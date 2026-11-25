# OpenResty image with the profiles standard, unprivileged and hardened, selected with
# --target. The build context is the repository root:
#   docker build -f openresty/Dockerfile --target <profile> .
ARG OPENRESTY_BASE_TAG=1.31.9.1-1
ARG OPENRESTY_VARIANT=alpine

# Stage 1: Build Brotli/Zstd modules compatible with the nginx version
# embedded in the selected OpenResty image.
FROM openresty/openresty:${OPENRESTY_BASE_TAG}-${OPENRESTY_VARIANT} AS mod-builder

ARG OPENRESTY_BASE_TAG

# Match OpenResty's embedded nginx major.minor.patch to keep modules binary-compatible.
# The release version is the tag without the revision (1.31.8.1-0 -> 1.31.8.1).
RUN --mount=type=bind,source=common/build-modules.sh,target=/tmp/build-modules.sh \
    sh /tmp/build-modules.sh openresty "${OPENRESTY_BASE_TAG%%-*}"


# Stage 2: OpenResty with compression modules and configuration (profile "standard"
# is the alias at the end of this file)
FROM openresty/openresty:${OPENRESTY_BASE_TAG}-${OPENRESTY_VARIANT} AS runtime

ARG OPENRESTY_VARIANT

# Runtime libs required by dynamic modules
RUN set -eux; \
        if [ -f /etc/alpine-release ]; then \
            apk add --no-cache brotli-libs zstd-libs; \
        elif [ -f /etc/debian_version ]; then \
            apt-get update; \
            apt-get install -y --no-install-recommends \
                libbrotli1 \
                libzstd1 \
                ca-certificates; \
            rm -rf /var/lib/apt/lists/*; \
        else \
            echo "Unsupported runtime distribution for variant ${OPENRESTY_VARIANT}"; \
            exit 1; \
        fi

# Copy compiled dynamic modules into runtime image
COPY --from=mod-builder /build/nginx/objs/ngx_http_brotli_filter_module.so /usr/local/openresty/nginx/modules/
COPY --from=mod-builder /build/nginx/objs/ngx_http_brotli_static_module.so /usr/local/openresty/nginx/modules/
COPY --from=mod-builder /build/nginx/objs/ngx_http_zstd_filter_module.so /usr/local/openresty/nginx/modules/
COPY --from=mod-builder /build/nginx/objs/ngx_http_zstd_static_module.so /usr/local/openresty/nginx/modules/

# Copy OpenResty/nginx configuration with sensible compression defaults
COPY ./openresty/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./common/conf.d/ /etc/nginx/conf.d/


# Stage 3: Runs as nginx (uid/gid 101) on port 8080, without capabilities and with
# a read-only root filesystem. The pid file and temp paths are in /tmp.
FROM runtime AS unprivileged

ARG OPENRESTY_BASE_TAG
ARG OPENRESTY_VARIANT
ARG VERSION=""
ARG REVISION=""
ARG CREATED=""

RUN set -eux; \
        if ! getent passwd 101 >/dev/null; then \
            if [ -f /etc/alpine-release ]; then \
                addgroup -g 101 -S nginx; \
                adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx; \
            elif [ -f /etc/debian_version ]; then \
                groupadd --system --gid 101 nginx; \
                useradd --system --gid nginx --no-create-home --home /nonexistent \
                    --comment "nginx user" --shell /bin/false --uid 101 nginx; \
            else \
                echo "Unsupported distribution for variant ${OPENRESTY_VARIANT}"; \
                exit 1; \
            fi; \
        fi

# Overlays: main.d/ holds main-context drop-ins, conf.d/ http-context drop-ins.
COPY ./common/profiles/unprivileged/ /etc/nginx/
COPY ./openresty/profiles/unprivileged/ /etc/nginx/

USER 101:101
EXPOSE 8080

LABEL org.opencontainers.image.title="OpenResty-br-zstd (unprivileged)" \
      org.opencontainers.image.description="OpenResty with Brotli and Zstd dynamic compression modules, running as non-root user nginx (uid 101) on port 8080" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Ruakij/OpenResty-br-zstd" \
      org.opencontainers.image.base.name="openresty/openresty:${OPENRESTY_BASE_TAG}-${OPENRESTY_VARIANT}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"


# Stage 4: Root filesystem of the hardened image
FROM unprivileged AS hardened-rootfs

COPY ./common/profiles/hardened/ /etc/nginx/
COPY ./openresty/profiles/hardened/ /etc/nginx/

USER root
RUN --mount=type=bind,source=common/build-hardened-rootfs.sh,target=/tmp/build-hardened-rootfs.sh \
    sh /tmp/build-hardened-rootfs.sh \
        /usr/local/openresty/nginx/sbin/nginx \
        /usr/local/openresty/nginx/modules \
        /usr/local/openresty \
        /etc/nginx


# Stage 5: Hardened image without shell or package manager
FROM scratch AS hardened

ARG OPENRESTY_BASE_TAG
ARG OPENRESTY_VARIANT
ARG VERSION=""
ARG REVISION=""
ARG CREATED=""

COPY --from=hardened-rootfs /rootfs/ /

USER 101:101
EXPOSE 8080
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]

LABEL org.opencontainers.image.title="OpenResty-br-zstd (hardened)" \
      org.opencontainers.image.description="OpenResty with Brotli and Zstd dynamic compression modules, running as non-root user nginx (uid 101) on port 8080 without shell or package manager" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Ruakij/OpenResty-br-zstd" \
      org.opencontainers.image.base.name="openresty/openresty:${OPENRESTY_BASE_TAG}-${OPENRESTY_VARIANT}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"


# Stage 6: Profile "standard". It comes last so that a build without --target produces it.
FROM runtime AS standard

ARG OPENRESTY_BASE_TAG
ARG OPENRESTY_VARIANT
ARG VERSION=""
ARG REVISION=""
ARG CREATED=""

# Scripts of derived images read the pid file from /var/run/nginx.pid.
COPY ./openresty/profiles/standard/ /etc/nginx/

LABEL org.opencontainers.image.title="OpenResty-br-zstd" \
      org.opencontainers.image.description="OpenResty with Brotli and Zstd dynamic compression modules" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Ruakij/OpenResty-br-zstd" \
      org.opencontainers.image.base.name="openresty/openresty:${OPENRESTY_BASE_TAG}-${OPENRESTY_VARIANT}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
