# nginx and OpenResty + Brotli + Zstd

Drop-in nginx and OpenResty base images with Brotli and Zstandard compression modules prebuilt and loaded.

This repository builds and publishes two image families, each in three profiles, for use as base images of applications. Every image carries:

- `ngx_http_brotli_filter_module`
- `ngx_http_brotli_static_module`
- `ngx_http_zstd_filter_module`
- `ngx_http_zstd_static_module`

## Contents
- [Images](#images)
- [Profiles](#profiles)
- [Published tags](#published-tags)
- [Use as a base image](#use-as-a-base-image)
- [Default compression settings](#default-compression-settings)
- [Security defaults (hardened)](#security-defaults-hardened)
- [Repository layout](#repository-layout)
- [License](#license)

## Images

| Image | Base | Variants |
| --- | --- | --- |
| `ghcr.io/ruakij/openresty-br-zstd` | `openresty/openresty` | `alpine`, `alpine-slim`, `alpine-fat` |
| `ghcr.io/ruakij/nginx-br-zstd` | official `nginx` | `alpine`, `alpine-slim` |

The modules are compiled against the nginx version embedded in the base image (derived from the OpenResty tag, or the nginx version itself) and loaded by the `nginx.conf` of the image. The OpenResty images build them against the nginx sources bundled in the OpenResty release, because OpenResty patches the `ngx_http_request_t` layout.

## Profiles

| Profile | User | Port | Filesystem | Tag suffix |
| --- | --- | --- | --- | --- |
| `standard` | root (as the base image) | 80 | writable | none |
| `unprivileged` | `nginx`, uid/gid 101 | 8080 | works read-only | `-unprivileged` |
| `hardened` | `nginx`, uid/gid 101 | 8080 | works read-only | `-hardened` |

`unprivileged` and `hardened` keep the pid file and all temp paths in `/tmp` and run with

```sh
docker run --read-only --cap-drop ALL --user 101:101 --tmpfs /tmp -p 8080:8080 ghcr.io/ruakij/nginx-br-zstd:alpine-unprivileged
```

`hardened` builds on `unprivileged` and adds:

- An image from `scratch` without shell and package manager. It contains the nginx binary, the four compression modules, the shared libraries they need (found with `ldd`), a minimal `passwd`/`group` with uid 101, the CA bundle, the configuration and `/tmp` (mode 1777). The OpenResty image also carries `/usr/local/openresty` with the Lua libraries; its other dynamic modules (geoip, image filter, xslt) are left out.
- The entrypoint `/usr/sbin/nginx` with `CMD ["-g", "daemon off;"]`. The `/docker-entrypoint.d` steps of the official nginx image do not run.
- Security defaults, listed under [Security defaults (hardened)](#security-defaults-hardened).
- Alpine variants only (musl needs no nss). A build of a non-alpine variant fails with a clear message.

Check the configuration of a hardened image through the entrypoint, as there is no shell:

```sh
docker run --rm --entrypoint /usr/sbin/nginx ghcr.io/ruakij/openresty-br-zstd:alpine-hardened -t
```

## Published tags

Tags are published when a release tag is pushed: `v<openresty-tag>` publishes the OpenResty images, `nginx-v<nginx-version>` the nginx images. The release tag must equal the version in the `versions.json` of its flavor at the tagged commit. Every tag exists per profile with the suffix from the table above (`<tag>`, `<tag>-unprivileged`, `<tag>-hardened`); the examples show the `standard` form.

| Tag | OpenResty image | nginx image |
| --- | --- | --- |
| `<version>-<variant>` | `1.31.8.1-0-alpine`, `1.31.8.1-alpine`, `1.31.8-alpine`, `1.31-alpine` | `1.31.9-alpine`, `1.31-alpine` |
| `<version>-<variant>--rev-<short sha>` | `1.31.8.1-0-alpine--rev-abc1234` | `1.31.9-alpine--rev-abc1234` |
| `<variant>` | `alpine`, `alpine-slim`, `alpine-fat` | `alpine`, `alpine-slim` |
| `latest` | `alpine` standard | `alpine` standard |
| `<profile>` | `unprivileged`, `hardened` (variant `alpine`) | `unprivileged`, `hardened` (variant `alpine`) |

## Use as a base image

```dockerfile
FROM ghcr.io/ruakij/nginx-br-zstd:alpine

# Add your own host/app config
COPY ./nginx/conf.d/ /etc/nginx/conf.d/
```

Both flavors read `/etc/nginx/conf.d/*.conf`. The main configuration lives in `/etc/nginx/nginx.conf` (nginx) and `/usr/local/openresty/nginx/conf/nginx.conf` (OpenResty). If a derived image replaces the full `nginx.conf`, it keeps the `load_module ...` lines and the `include` of `main.d`, otherwise the Brotli/Zstd modules or the profile settings are not loaded.

The `hardened` profile has no shell, so a derived image cannot use `RUN`. Add files with `COPY`, and run build steps in an earlier stage of a multi-stage build:

```dockerfile
FROM node:alpine AS build
# ... build the site ...

FROM ghcr.io/ruakij/nginx-br-zstd:alpine-hardened
COPY --from=build /app/dist/ /usr/share/nginx/html/
```

The `unprivileged` and `hardened` profiles listen on 8080 with a default server in `/etc/nginx/conf.d/default.conf`. Derived images that ship their own server block on another port replace that file.

## Default compression settings

Sensible defaults for static and dynamic compression are in `common/conf.d/10-compression-defaults.conf`.
Dynamic compression is disabled by default. Pre-compressed files (`.gz`, `.br`, `.zst`) are served when they exist.

To enable on-the-fly dynamic compression, set `gzip on`, `brotli on`, and/or `zstd on` in the site configuration.

Brotli is very resource intensive, so falling back to Gzip when Zstd is not supported by the client is recommended for best performance.

## Security defaults (hardened)

Set in `common/profiles/hardened`:

- Limits: 10 s header and body timeouts, `reset_timedout_connection`, `disable_symlinks if_not_owner`.
- No version disclosure: `server_tokens off`; `X-Powered-By`, `X-AspNet-Version` and `X-AspNetMvc-Version` are hidden from proxied, FastCGI, uwsgi and SCGI responses. The OpenResty image also removes the `Server` header (headers-more); the nginx image still sends `Server: nginx`.
- Headers (`always`) unless the upstream response sets them: `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Permitted-Cross-Domain-Policies: none`.
- TLS settings that apply once TLS is configured: `ssl_session_tickets off`, a 1 day session timeout and a 10 MB session cache.
- The default server answers 403 for dotfiles (except `/.well-known/`) and for `~`, `.bak` and `.swp` files.

The headers use `add_header_inherit merge`, so a server or location with its own `add_header` keeps them. Setting the same header name again sends it twice. The `*_hide_header` lists are not merged: a server or location with its own `proxy_hide_header` (or FastCGI, uwsgi, SCGI equivalent) loses the inherited entries and has to repeat them. A derived server block gets the file rule with `include /etc/nginx/server.d/10-deny-hidden.conf;`.

## Repository layout

```
openresty/Dockerfile     targets: standard, unprivileged, hardened
openresty/versions.json  tracked OpenResty tag and variants
openresty/conf/          nginx.conf of the OpenResty flavor
openresty/profiles/      flavor-specific overlay per profile
nginx/Dockerfile         targets: standard, unprivileged, hardened
nginx/versions.json      tracked nginx version and variants
nginx/conf/              nginx.conf of the nginx flavor
nginx/profiles/          flavor-specific overlay per profile
common/conf.d/           compression defaults of all images
common/profiles/         overlays shared by both flavors
common/*.sh              module build, hardened root filesystem, smoke test
```

A profile overlay is a directory copied over `/etc/nginx` by the Dockerfile stage of the profile:

- `main.d/*.conf` is included at the top of `nginx.conf` (main context), for example the pid file path.
- `conf.d/*.conf` is included in the `http` context, for example the temp paths and the default server.
- `server.d/*.conf` is included in the default server on port 8080, for example the file rules of `hardened`.

`unprivileged` applies `common/profiles/unprivileged` and the flavor overlay, `hardened` adds `common/profiles/hardened` on top.

Build context is the repository root:

```sh
docker build -f openresty/Dockerfile --target unprivileged .
docker build -f nginx/Dockerfile --target hardened --build-arg NGINX_VERSION="$(jq -r .nginx nginx/versions.json)" .
bash common/smoke-test.sh start <image> <openresty|nginx> <standard|unprivileged|hardened>
```

The workflow `upstream-sync` tracks the newest `X.Y.Z.W-alpine-fat` OpenResty tag and the newest `X.Y.Z-alpine` nginx tag, tests each bump in its own pull request, merges it and releases `v<openresty-tag>` or `nginx-v<nginx-version>`. The two bumps are independent job chains; each edits only the `versions.json` of its flavor, builds only its flavor and waits until every configured variant of a version is published.

## License

This project is licensed under the GNU AFFERO GENERAL PUBLIC LICENSE, see [LICENSE](LICENSE) for details.
