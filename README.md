# OpenResty + Brotli + Zstd

Drop-in OpenResty base image with Brotli and Zstandard compression modules prebuilt and loaded.

This repository builds and publishes a container image that is intended to be used as a base image for your own apps while adding:

- `ngx_http_brotli_filter_module`
- `ngx_http_brotli_static_module`
- `ngx_http_zstd_filter_module`
- `ngx_http_zstd_static_module`

## What you get

- Multi-stage Docker build that compiles dynamic modules against the matching nginx version inside OpenResty.
- Runtime image based on `openresty/openresty:<version>-alpine`.
- Sensible default compression settings in `container/nginx/conf.d/10-compression-defaults.conf`.

## Use as a base image

```dockerfile
FROM ghcr.io/<owner>/<repo>:latest

# Add your own host/app config
COPY ./nginx/conf.d/ /etc/nginx/conf.d/
```

If you replace the full `nginx.conf`, keep the `load_module ...` lines from `container/nginx/nginx.conf`, otherwise Brotli/Zstd modules are not loaded.

## Default compression settings

Sensible defaults for static and dynamic compression are included in `container/nginx/conf.d/10-compression-defaults.conf`.  
Dynamic compression is disabled by default. Pre-Compressed files (`.gz`, `.br`, `.zst`) are served when they exist.

If you want on-the-fly dynamic compression, explicitly enable `gzip on`, `brotli on`, and/or `zstd on` in your own config.

Note: Particulary Brotli is very resource intensive, so falling back to Gzip when Zstd is not supported by the client is recommended for best performance.

## License

This project is licensed under the GNU AFFERO GENERAL PUBLIC LICENSE, see [LICENSE](LICENSE) for details.
