# daed 容器镜像 — 复用本仓库 release 的 v3_avx2 二进制（A1 方案）
# 注意: 构建上下文 (image-context/) 必须包含 daed 二进制, 由 workflow 自动下载
#       不要手动 docker build (本地无该二进制时会失败)
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source=https://github.com/guochan2019/onekey-daed

# GEO 数据源与官方 Dockerfile 一致 (v2rayA dist)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /usr/local/share/daed /etc/daed \
 && wget -qO /usr/local/share/daed/geoip.dat https://github.com/v2rayA/dist-v2ray-rules-dat/raw/master/geoip.dat \
 && wget -qO /usr/local/share/daed/geosite.dat https://github.com/v2rayA/dist-v2ray-rules-dat/raw/master/geosite.dat

COPY daed /usr/local/bin/daed

EXPOSE 2023

CMD ["daed", "run", "-c", "/etc/daed"]
