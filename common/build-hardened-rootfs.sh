#!/bin/sh
# Assembles /rootfs for an image without shell and package manager.
# Usage: build-hardened-rootfs.sh <nginx-binary> <modules-dir> <dir>...
# Copies the directories completely, except that the modules directory keeps only the
# Brotli and Zstd modules: the other base modules need libraries (gd, xslt, geoip)
# that the image lacks. Also links the binary as /usr/sbin/nginx, the fixed
# entrypoint path.
set -eu

# glibc loads nss libraries at runtime, which the ldd-based library copy cannot find;
# musl has none.
if [ ! -f /etc/alpine-release ]; then
    echo "The hardened profile supports alpine variants only"
    exit 1
fi

nginx_bin="$1"
modules_dir="$2"
shift 2

root=/rootfs
mkdir -p "${root}/etc/ssl/certs" "${root}/usr/sbin" "${root}/tmp"
chmod 1777 "${root}/tmp"

for d in "$@"; do
    mkdir -p "${root}$(dirname "${d}")"
    cp -a "${d}" "${root}$(dirname "${d}")/"
done

rm -rf "${root}${modules_dir}"
mkdir -p "${root}${modules_dir}"
cp "${modules_dir}"/ngx_http_brotli_*.so "${modules_dir}"/ngx_http_zstd_*.so "${root}${modules_dir}/"

mkdir -p "${root}$(dirname "${nginx_bin}")"
cp -a "${nginx_bin}" "${root}${nginx_bin}"
[ "${nginx_bin}" = /usr/sbin/nginx ] || ln -s "${nginx_bin}" "${root}/usr/sbin/nginx"

# Collect the shared libraries of the binary, the modules and the copied directories.
{
    echo "${nginx_bin}"
    ls "${modules_dir}"/ngx_http_brotli_*.so "${modules_dir}"/ngx_http_zstd_*.so
    find "$@" -type f -name '*.so*' -not -path "${modules_dir}/*"
} | sort -u > /tmp/elf-files
while read -r f; do ldd "${f}" 2>&1 || true; done < /tmp/elf-files > /tmp/ldd.out
# ldd lists the nginx symbols of a module as not found, because only the binary
# provides them; a missing library produces a different message.
if grep -E '=> not found|Error loading shared library' /tmp/ldd.out; then
    echo "Unresolved shared libraries"
    exit 1
fi
awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^\/[^:]*$/) print $i }' /tmp/ldd.out | sort -u | while read -r lib; do
    [ -e "${root}${lib}" ] && continue
    mkdir -p "${root}$(dirname "${lib}")"
    cp -L "${lib}" "${root}${lib}"
done

cp -L /etc/ssl/certs/ca-certificates.crt "${root}/etc/ssl/certs/"
printf 'root:x:0:0:root:/root:/sbin/nologin\nnginx:x:101:101:nginx:/var/cache/nginx:/sbin/nologin\n' > "${root}/etc/passwd"
printf 'root:x:0:\nnginx:x:101:\n' > "${root}/etc/group"
