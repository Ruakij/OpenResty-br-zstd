#!/bin/sh
# Builds the Brotli and Zstd dynamic modules against the nginx sources of a release.
# Usage: build-modules.sh nginx|openresty <version>
# OpenResty patches struct ngx_http_request_t (lua_subrequest), so modules must be built
# against the nginx sources bundled in the OpenResty release, not against vanilla nginx.
# The modules are written to /build/nginx/objs/.
set -eu

FLAVOR="${1:-}"
VERSION="${2:-}"
case "${FLAVOR}" in
    nginx | openresty) ;;
    *) FLAVOR="" ;;
esac
if [ -z "${FLAVOR}" ] || [ -z "${VERSION}" ]; then
    echo "Usage: build-modules.sh nginx|openresty <version>"
    exit 1
fi

if [ -f /etc/alpine-release ]; then
    apk add --no-cache \
        git \
        build-base \
        pcre-dev \
        zlib-dev \
        openssl-dev \
        linux-headers \
        cmake \
        brotli-dev \
        zstd-dev \
        wget \
        ca-certificates
elif [ -f /etc/debian_version ]; then
    apt-get update
    apt-get install -y --no-install-recommends \
        git \
        build-essential \
        libpcre3-dev \
        zlib1g-dev \
        libssl-dev \
        linux-libc-dev \
        cmake \
        libbrotli-dev \
        libzstd-dev \
        wget \
        ca-certificates
    rm -rf /var/lib/apt/lists/*
else
    echo "Unsupported build distribution"
    exit 1
fi

mkdir -p /build
cd /build

# Clone module sources (with submodules where required)
git clone --depth=1 --recursive https://github.com/google/ngx_brotli.git
git clone --depth=1 --recursive https://github.com/tokers/zstd-nginx-module.git

echo "Building against ${FLAVOR} ${VERSION}"
if [ "${FLAVOR}" = openresty ]; then
    wget -q "https://openresty.org/download/openresty-${VERSION}.tar.gz"
    tar -xzf "openresty-${VERSION}.tar.gz"
    mv "openresty-${VERSION}"/bundle/nginx-[0-9]* nginx
else
    wget -q "https://nginx.org/download/nginx-${VERSION}.tar.gz"
    tar -xzf "nginx-${VERSION}.tar.gz"
    mv "nginx-${VERSION}" nginx
fi

cd /build/nginx

# Build dynamic modules only (not nginx/openresty itself)
./configure \
    --with-compat \
    --with-cc-opt='-O2' \
    --add-dynamic-module=/build/ngx_brotli \
    --add-dynamic-module=/build/zstd-nginx-module
make modules
