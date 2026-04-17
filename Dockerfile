ARG OPENRESTY_VERSION=1.29.2.3

# Stage 1: Build Brotli/Zstd modules compatible with the nginx version
# embedded in the selected OpenResty image.
FROM openresty/openresty:${OPENRESTY_VERSION}-alpine-fat AS openresty-mod-builder

ARG OPENRESTY_VERSION

RUN apk add --no-cache \
    git \
    build-base \
    pcre-dev \
    zlib-dev \
    openssl-dev \
    linux-headers \
    cmake \
    brotli-dev \
    zstd-dev \
    wget

WORKDIR /build

# Clone module sources (with submodules where required)
RUN git clone --depth=1 --recursive https://github.com/google/ngx_brotli.git && \
    git clone --depth=1 --recursive https://github.com/tokers/zstd-nginx-module.git

# Match OpenResty's embedded nginx major.minor.patch to keep modules binary-compatible.
# OpenResty tags use four numeric segments; nginx uses the first three.
RUN NGINX_VERSION="$(echo "${OPENRESTY_VERSION}" | cut -d. -f1-3)" && \
    test -n "${NGINX_VERSION}" && \
    echo "Using nginx version: ${NGINX_VERSION}" && \
    wget -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    tar -xzf "nginx-${NGINX_VERSION}.tar.gz" && \
    mv "nginx-${NGINX_VERSION}" nginx

WORKDIR /build/nginx

# Build dynamic modules only (not nginx/openresty itself)
RUN ./configure \
    --with-compat \
    --with-cc-opt='-O2' \
    --add-dynamic-module=/build/ngx_brotli \
    --add-dynamic-module=/build/zstd-nginx-module && \
    make modules


# Stage 2: OpenResty runtime with compression modules
FROM openresty/openresty:${OPENRESTY_VERSION}-alpine AS runtime

# Runtime libs required by dynamic modules
RUN apk add --no-cache brotli-libs zstd-libs

# Copy compiled dynamic modules into runtime image
COPY --from=openresty-mod-builder /build/nginx/objs/ngx_http_brotli_filter_module.so /usr/local/openresty/nginx/modules/
COPY --from=openresty-mod-builder /build/nginx/objs/ngx_http_brotli_static_module.so /usr/local/openresty/nginx/modules/
COPY --from=openresty-mod-builder /build/nginx/objs/ngx_http_zstd_filter_module.so /usr/local/openresty/nginx/modules/
COPY --from=openresty-mod-builder /build/nginx/objs/ngx_http_zstd_static_module.so /usr/local/openresty/nginx/modules/

# Copy OpenResty/nginx configuration with sensible compression defaults
COPY ./container/nginx/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY ./container/nginx/conf.d/ /etc/nginx/conf.d/

EXPOSE 80

CMD ["openresty", "-g", "daemon off;"]
