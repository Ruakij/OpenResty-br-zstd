#!/usr/bin/env bash
# Smoke tests for a built image.
# Usage: smoke-test.sh <config|start> <image> <flavor> <profile>
#   config  runs the configuration test of the image
#   start   starts a container and checks its state, user, logs, HTTP and compression
set -Eeuo pipefail

mode="${1:?mode}"
image="${2:?image}"
flavor="${3:?flavor (openresty|nginx)}"
profile="${4:?profile (standard|unprivileged|hardened)}"

container="br-zstd-smoke-${flavor}-${profile}-$$"
port=80
run_flags=()
if [ "${profile}" != standard ]; then
  port=8080
  # Runtime flags the unprivileged and hardened profiles must support.
  run_flags=(--read-only --cap-drop ALL --security-opt no-new-privileges --user 101:101 --tmpfs /tmp)
fi

# Prints the nginx invocation for the image. The hardened image has no shell and no
# base entrypoint, so it needs --entrypoint.
nginx_cmd() {
  if [ "${profile}" = hardened ]; then
    docker run --rm ${run_flags[@]+"${run_flags[@]}"} --entrypoint /usr/sbin/nginx "${image}" "$@"
  elif [ "${flavor}" = openresty ]; then
    docker run --rm ${run_flags[@]+"${run_flags[@]}"} "${image}" openresty "$@"
  else
    docker run --rm ${run_flags[@]+"${run_flags[@]}"} "${image}" nginx "$@"
  fi
}

if [ "${mode}" = config ]; then
  nginx_cmd -t
  if [ "${profile}" = hardened ]; then
    config="$(nginx_cmd -T 2>&1)"
    if ! grep -q 'add_header_inherit merge;' <<<"${config}"; then
      echo "nginx -T does not show the hardened configuration."
      exit 1
    fi
    if docker run --rm --entrypoint /bin/sh "${image}" -c true 2>/dev/null; then
      echo "The hardened image contains a shell."
      exit 1
    fi
  fi
  exit 0
fi

workdir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/br-zstd-smoke.XXXXXX")"

cleanup() {
  exit_code=$?
  if [ "${exit_code}" -ne 0 ] && docker container inspect "${container}" >/dev/null 2>&1; then
    echo "Container logs:"
    docker logs "${container}" || true
    echo "Container state:"
    docker inspect --format '{{json .State}}' "${container}" || true
  fi
  docker rm --force "${container}" >/dev/null 2>&1 || true
  rm -rf "${workdir}"
  exit "${exit_code}"
}
trap cleanup EXIT

# Test content: the static modules serve precompressed files byte for byte, so the
# content of the .br and .zst files does not matter.
mkdir "${workdir}/content"
head -c 8192 /dev/zero | tr '\0' 'a' > "${workdir}/content/plain.txt"
cp "${workdir}/content/plain.txt" "${workdir}/content/static.txt"
printf 'br' > "${workdir}/content/static.txt.br"
printf 'zstd' > "${workdir}/content/static.txt.zst"
cat > "${workdir}/smoke.conf" <<'CONF'
server {
    listen 8081;
    root /smoke;

    location /upstream/ {
        proxy_pass http://127.0.0.1:8082/;
    }

    location /own-header/ {
        add_header X-Own "1" always;
        return 200 "ok";
    }

    location /dynamic/ {
        alias /smoke/;
        brotli on;
        brotli_min_length 1;
        brotli_types text/plain;
        zstd on;
        zstd_min_length 1;
        zstd_types text/plain;
    }
}

server {
    listen 127.0.0.1:8082;
    add_header_inherit off;
    add_header X-Powered-By "PHP" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-AspNet-Version "4.0" always;
    return 200 "ok";
}
CONF
chmod -R a+rX "${workdir}"

docker run --detach \
  --name "${container}" \
  ${run_flags[@]+"${run_flags[@]}"} \
  --publish "127.0.0.1::${port}" \
  --publish "127.0.0.1::8081" \
  --volume "${workdir}/content:/smoke:ro" \
  --volume "${workdir}/smoke.conf:/etc/nginx/conf.d/99-smoke.conf:ro" \
  "${image}" >/dev/null

host_port() {
  docker port "${container}" "$1/tcp" | head -n1 | sed 's/.*://'
}
site="http://127.0.0.1:$(host_port "${port}")"
smoke="http://127.0.0.1:$(host_port 8081)"

ready=false
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "${site}/" 2>/dev/null && curl -fsS -o /dev/null "${smoke}/static.txt" 2>/dev/null; then
    ready=true
    break
  fi
  sleep 0.5
done
if [ "${ready}" != true ]; then
  echo "Container does not serve HTTP on port ${port} and 8081."
  exit 1
fi

state="$(docker inspect --format '{{.State.Status}}' "${container}")"
if [ "${state}" != "running" ]; then
  echo "Container is not running: ${state}"
  exit 1
fi

if [ "${profile}" != standard ]; then
  uids="$(docker top "${container}" -eo pid,uid | awk 'NR > 1 { print $2 }' | sort -u)"
  if [ "${uids}" != 101 ]; then
    echo "Container processes do not all run as uid 101: ${uids}"
    exit 1
  fi
fi

# Prints the Content-Encoding response header for a request.
content_encoding() {
  curl -fsS -o /dev/null -D - -H "Accept-Encoding: $2" "$1" \
    | tr -d '\r' | awk -F': ' 'tolower($1) == "content-encoding" { print tolower($2) }'
}
for encoding in br zstd; do
  for path in dynamic/plain.txt static.txt; do
    got="$(content_encoding "${smoke}/${path}" "${encoding}")"
    if [ "${got}" != "${encoding}" ]; then
      echo "Expected Content-Encoding ${encoding} for /${path}, got '${got}'."
      exit 1
    fi
  done
done

# Before the hardened probes, which provoke error log lines on purpose.
logs="$(docker logs "${container}" 2>&1)"
printf '%s\n' "${logs}"
if printf '%s\n' "${logs}" | grep -Eiq '\[(warn|error|crit|alert|emerg)\]'; then
  echo "The container logs contain nginx warnings or errors."
  exit 1
fi

if [ "${profile}" = hardened ]; then
  status_of() {
    curl -sS -o /dev/null -w '%{http_code}' "$1"
  }
  headers_of() {
    curl -fsS -o /dev/null -D - "$1" | tr -d '\r'
  }
  expect_header() {
    if ! printf '%s\n' "$2" | grep -iqx "$3"; then
      echo "Hardened response from $1 lacks the header: $3"
      exit 1
    fi
  }
  expect_no_header() {
    if printf '%s\n' "$2" | grep -iq "^$3:"; then
      echo "Hardened response from $1 contains the header: $3"
      exit 1
    fi
  }
  for url in "${site}/" "${smoke}/upstream/" "${smoke}/own-header/"; do
    headers="$(headers_of "${url}")"
    expect_header "${url}" "${headers}" 'X-Content-Type-Options: nosniff'
    expect_header "${url}" "${headers}" 'X-Frame-Options: SAMEORIGIN'
    expect_header "${url}" "${headers}" 'X-Permitted-Cross-Domain-Policies: none'
    expect_no_header "${url}" "${headers}" 'X-Powered-By'
    expect_no_header "${url}" "${headers}" 'X-AspNet-Version'
  done
  expect_header "${site}/" "$(headers_of "${site}/")" 'Referrer-Policy: strict-origin-when-cross-origin'
  headers="$(headers_of "${smoke}/own-header/")"
  expect_header "${smoke}/own-header/" "${headers}" 'X-Own: 1'
  expect_header "${smoke}/own-header/" "${headers}" 'Referrer-Policy: strict-origin-when-cross-origin'
  # A header the upstream sends replaces the hardened default instead of being appended.
  headers="$(headers_of "${smoke}/upstream/")"
  if [ "$(printf '%s\n' "${headers}" | grep -ic '^Referrer-Policy:')" != 1 ]; then
    echo "Hardened response from ${smoke}/upstream/ does not carry exactly one Referrer-Policy."
    exit 1
  fi
  expect_header "${smoke}/upstream/" "${headers}" 'Referrer-Policy: no-referrer'
  headers="$(headers_of "${site}/")"
  if [ "${flavor}" = openresty ]; then
    expect_no_header "${site}/" "${headers}" 'Server'
  else
    expect_header "${site}/" "${headers}" 'Server: nginx'
  fi
  for path in .env .git/config sub/.htpasswd index.html~ backup.bak .x.swp; do
    code="$(status_of "${site}/${path}")"
    if [ "${code}" != 403 ]; then
      echo "Expected 403 for /${path}, got ${code}."
      exit 1
    fi
  done
  code="$(status_of "${site}/.well-known/missing")"
  if [ "${code}" != 404 ]; then
    echo "Expected 404 for /.well-known/missing, got ${code}."
    exit 1
  fi
fi
