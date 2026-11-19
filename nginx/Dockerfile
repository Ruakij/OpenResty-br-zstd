# nginx image with the profiles standard, unprivileged and hardened, selected with
# --target. The build context is the repository root:
#   docker build -f nginx/Dockerfile --target <profile> --build-arg NGINX_VERSION=<version> .

# nginx version from nginx/versions.json (.nginx). It has no default, so a build cannot
# use a stale version unnoticed.
ARG NGINX_VERSION
ARG NGINX_VARIANT=alpine

# Stage 1: Build Brotli/Zstd modules for the nginx version of the selected image.
FROM nginx:${NGINX_VERSION}-${NGINX_VARIANT} AS mod-builder

ARG NGINX_VERSION

RUN --mount=type=bind,source=common/build-modules.sh,target=/tmp/build-modules.sh \
    sh /tmp/build-modules.sh nginx "${NGINX_VERSION}"


# Stage 2: nginx with compression modules and configuration (profile "standard"
# is the alias at the end of this file)
FROM nginx:${NGINX_VERSION}-${NGINX_VARIANT} AS runtime

ARG NGINX_VARIANT

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
            echo "Unsupported runtime distribution for variant ${NGINX_VARIANT}"; \
            exit 1; \
        fi

# Copy compiled dynamic modules into runtime image
COPY --from=mod-builder /build/nginx/objs/ngx_http_brotli_filter_module.so /usr/lib/nginx/modules/
COPY --from=mod-builder /build/nginx/objs/ngx_http_brotli_static_module.so /usr/lib/nginx/modules/
COPY --from=mod-builder /build/nginx/objs/ngx_http_zstd_filter_module.so /usr/lib/nginx/modules/
COPY --from=mod-builder /build/nginx/objs/ngx_http_zstd_static_module.so /usr/lib/nginx/modules/

# Copy nginx configuration with sensible compression defaults
COPY ./nginx/conf/nginx.conf /etc/nginx/nginx.conf
COPY ./common/conf.d/ /etc/nginx/conf.d/


# Stage 3: Runs as nginx (uid/gid 101) on port 8080, without capabilities and with
# a read-only root filesystem. The pid file and temp paths are in /tmp.
FROM runtime AS unprivileged

ARG NGINX_VERSION
ARG NGINX_VARIANT
ARG VERSION=""
ARG REVISION=""
ARG CREATED=""

# The official image ships user and group nginx (101).
RUN test "$(id -u nginx)" = 101

# Overlays: main.d/ holds main-context drop-ins, conf.d/ http-context drop-ins.
COPY ./common/profiles/unprivileged/ /etc/nginx/
COPY ./nginx/profiles/unprivileged/ /etc/nginx/

USER 101:101
EXPOSE 8080

LABEL org.opencontainers.image.title="nginx-br-zstd (unprivileged)" \
      org.opencontainers.image.description="nginx with Brotli and Zstd dynamic compression modules, running as non-root user nginx (uid 101) on port 8080" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Ruakij/OpenResty-br-zstd" \
      org.opencontainers.image.base.name="nginx:${NGINX_VERSION}-${NGINX_VARIANT}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"


# Stage 4: Root filesystem of the hardened image
FROM unprivileged AS hardened-rootfs

COPY ./common/profiles/hardened/ /etc/nginx/

USER root
RUN --mount=type=bind,source=common/build-hardened-rootfs.sh,target=/tmp/build-hardened-rootfs.sh \
    sh /tmp/build-hardened-rootfs.sh \
        /usr/sbin/nginx \
        /usr/lib/nginx/modules \
        /etc/nginx \
        /usr/share/nginx \
        /var/log/nginx


# Stage 5: Hardened image without shell or package manager
FROM scratch AS hardened

ARG NGINX_VERSION
ARG NGINX_VARIANT
ARG VERSION=""
ARG REVISION=""
ARG CREATED=""

COPY --from=hardened-rootfs /rootfs/ /

USER 101:101
EXPOSE 8080
STOPSIGNAL SIGQUIT
ENTRYPOINT ["/usr/sbin/nginx"]
CMD ["-g", "daemon off;"]

LABEL org.opencontainers.image.title="nginx-br-zstd (hardened)" \
      org.opencontainers.image.description="nginx with Brotli and Zstd dynamic compression modules, running as non-root user nginx (uid 101) on port 8080 without shell or package manager" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Ruakij/OpenResty-br-zstd" \
      org.opencontainers.image.base.name="nginx:${NGINX_VERSION}-${NGINX_VARIANT}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"


# Stage 6: Profile "standard". It comes last so that a build without --target produces it.
FROM runtime AS standard

ARG NGINX_VERSION
ARG NGINX_VARIANT
ARG VERSION=""
ARG REVISION=""
ARG CREATED=""

LABEL org.opencontainers.image.title="nginx-br-zstd" \
      org.opencontainers.image.description="nginx with Brotli and Zstd dynamic compression modules" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/Ruakij/OpenResty-br-zstd" \
      org.opencontainers.image.base.name="nginx:${NGINX_VERSION}-${NGINX_VARIANT}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
