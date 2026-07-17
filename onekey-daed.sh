#!/bin/bash
# ============================================================
# onekey-daed — daed 一键安装/升级/卸载脚本
# 适用环境: Debian 13 (fresh LXC)
# 功能: 安装 daed（dae 现代化 Web 管理面板）
# 项目: https://github.com/daeuniverse/daed
# ============================================================
set -e

trap 'echo -e "\033[0;31m[ERROR] 脚本执行失败，请检查:\033[0m
  - 网络连接（能否访问 github.com 或 ghcr.io）
  - 是否以 root 运行" >&2' ERR

# ---------- 配置 ----------
FALLBACK_VER="v1.28.0"
# 可通过 DAED_VER 环境变量指定版本，如: DAED_VER=v1.28.0 bash onekey-daed.sh
# 或 DAED_SRC=docker 使用 Docker 镜像提取最新版（推荐，获取 main 分支新功能）
if [ -n "$DAED_VER" ]; then
  FORCE_VER="$DAED_VER"
  warn "使用指定版本: ${FORCE_VER}"
else
  FORCE_VER=""
fi
INSTALL_DIR="/opt/daed"
BIN="/usr/local/bin/daed"
CONF_DIR="/opt/daed"

# ---------- 彩色输出 ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------- 检测 root ----------
if [ "$(id -u)" -ne 0 ]; then
  err "请以 root 用户运行 (当前非 root)"
fi

# ---------- 检测架构 ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      if grep -q avx2 /proc/cpuinfo 2>/dev/null; then
        echo "x86_64_v3_avx2"
      elif grep -q sse /proc/cpuinfo 2>/dev/null; then
        echo "x86_64_v2_sse"
      else
        echo "x86_64"
      fi
      ;;
    aarch64|arm64) echo "arm64"       ;;
    i386|i686)     echo "x86_32"      ;;
    mips)          echo "mips32"      ;;
    mipsel)        echo "mips32le"    ;;
    mips64)        echo "mips64"      ;;
    mips64el)      echo "mips64le"    ;;
    riscv64)       echo "riscv64"     ;;
    *)             echo ""            ;;
  esac
}

# ---------- 获取最新版本 ----------
fetch_latest_ver() {
  # 该仓库有多个子项目 tag（dae-lang-core-v*、dae-lsp-v* 等），
  # 需过滤出 daed 本身的 release（纯 v 开头版本号）
  curl -s --connect-timeout 5 \
    https://api.github.com/repos/daeuniverse/daed/releases \
    | grep -o '"tag_name": *"v[0-9]*\.[0-9]*\.[0-9]*"' \
    | head -1 | grep -o 'v[^\"]*' 2>/dev/null || echo ""
}

# ---------- 获取当前版本 ----------
get_current_ver() {
  if [ ! -f "$BIN" ]; then
    echo ""; return
  fi
  # daed version 输出格式: "daed version v1.27.0"
  "$BIN" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
}

# ---------- 检测 kernel 是否满足 eBPF 要求 ----------
check_kernel() {
  local major minor
  major=$(uname -r | cut -d. -f1)
  minor=$(uname -r | cut -d. -f2)
  if [ "$major" -lt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -lt 17 ]; }; then
    err "内核版本过低 ($(uname -r))，daed 需要 Linux 5.17+"
  fi

  # 关键 eBPF 内核配置检查（仅当可读取内核配置时）
  local missing=""
  for cfg in CONFIG_BPF CONFIG_BPF_SYSCALL CONFIG_DEBUG_INFO_BTF; do
    if zgrep -q "${cfg}=y" /proc/config.gz 2>/dev/null || \
       grep -q "${cfg}=y" /boot/config-$(uname -r) 2>/dev/null; then
      :  # 配置已启用
    else
      missing="$missing $cfg"
    fi
  done
  if [ -n "$missing" ]; then
    if [ -f /proc/config.gz ] || [ -f "/boot/config-$(uname -r)" ]; then
      # 配置文件存在但缺少选项 → 硬错误
      err "内核缺少必要 eBPF 配置:$missing\n  请确认内核编译时启用了这些选项"
    else
      # 配置文件不可读（如 LXC 容器），仅警告
      warn "无法读取内核配置（LXC 容器常见），跳过 eBPF 配置检查"
      warn "  如果 daed 启动失败，请确认宿主机内核启用了上述 eBPF 选项"
    fi
  fi
}

# ---------- 卸载 ----------
uninstall_daed() {
  echo ""
  warn "========== 卸载 daed =========="
  echo ""
  systemctl stop daed 2>/dev/null || true
  systemctl disable daed 2>/dev/null || true
  rm -f /etc/systemd/system/daed.service
  systemctl daemon-reload

  rm -f "$BIN"
  rm -rf "$INSTALL_DIR"
  rm -rf "$CONF_DIR"
  rm -rf /var/log/daed

  info "✓ daed 已卸载"
  info "  安装目录 ${INSTALL_DIR} 已删除"
  info "  配置目录 ${CONF_DIR} 已删除"
  echo ""
  exit 0
}

do_install_from_docker() {
  info "从 Docker 镜像提取 daed（ghcr.io/daeuniverse/daed:latest）..."
  if ! command -v docker &>/dev/null; then
    warn "Docker 未安装，尝试自动安装..."
    apt install -y -qq docker.io || apt install -y -qq docker-ce || {
      err "Docker 安装失败，请手动安装后再试\n  curl -fsSL https://get.docker.com | bash"
    }
  fi
  docker pull ghcr.io/daeuniverse/daed:latest
  local cid
  cid=$(docker create ghcr.io/daeuniverse/daed:latest)
  docker cp "$cid":/usr/local/bin/daed "$BIN"
  docker rm "$cid" >/dev/null
  chmod +x "$BIN"
  # 获取实际版本号
  DAED_VER=$("$BIN" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$DAED_VER" ] && DAED_VER="(Docker)"
  info "  ✓ daed ${DAED_VER} 已从 Docker 提取"
}

# ---------- 安装 ----------
do_install() {
  DAED_VER="${1}"
  DAED_ARCH="${2}"
  FROM_DOCKER="${3:-false}"

  # 检查内核是否满足 eBPF 要求
  check_kernel

  # 检查依赖：GEO 数据由 mosdns 提供
  if [ ! -f "/usr/share/v2ray/geoip.dat" ] || [ ! -f "/usr/share/v2ray/geosite.dat" ]; then
    err "未检测到 mosdns 的 GEO 数据 (/usr/share/v2ray/geoip.dat)\n  daed 需要依赖 mosdns，请先安装 onekey-mosdns"
  fi

  info "=== 1/5 安装系统依赖 ==="
  apt update -qq
  apt install -y -qq wget unzip curl

  if [ "$FROM_DOCKER" != "true" ]; then
    info "=== 2/5 下载 daed ${DAED_VER} (${DAED_ARCH}) ==="
    DOWNLOAD_URL="https://github.com/daeuniverse/daed/releases/download/${DAED_VER}/daed-linux-${DAED_ARCH}.zip"
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    wget -q "$DOWNLOAD_URL" -O daed.zip
    unzip -q daed.zip
    # zip 内带一层目录，二进制文件名 = daed-linux-{arch}
    BINARY_PATH=$(find . -type f \( -name "daed-linux-*" -o -name "daed" \) ! -name "*.zip" ! -name "*.service" ! -name "*.desktop" ! -name "*.conf" ! -name "*.yaml" 2>/dev/null | head -1)
    if [ -z "$BINARY_PATH" ]; then
      err "未找到 daed 二进制文件\n  $(ls -la 2>/dev/null | head -10)"
    fi
    install -m 755 "$BINARY_PATH" "$BIN"
    chmod +x "$BIN"
    rm -rf "$TMPDIR"
    "$BIN" version 2>/dev/null | head -1 || info "  ✓ daed 已安装"
  fi

  info "=== 3/5 创建目录结构 ==="
  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONF_DIR"
  mkdir -p /var/log/daed

  info "=== 4/5 创建 systemd 服务 ==="
  cat > /etc/systemd/system/daed.service << 'SERVICEEOF'
[Unit]
Description=daed - Modern web dashboard for dae
Documentation=https://github.com/daeuniverse/daed
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

# 资源限制
MemoryHigh=512M
LimitNPROC=4096
LimitNOFILE=1048576
OOMScoreAdjust=-100

# 启动命令：挂载 BPF 文件系统（LXC 中需先创建目录） + 清理残留网络命名空间
ExecStartPre=/bin/sh -c 'mkdir -p /sys/fs/bpf && mount -t bpf bpf /sys/fs/bpf 2>/dev/null || true'
ExecStartPre=/bin/sh -c 'ip netns delete daens 2>/dev/null; rm -f /run/netns/daens'
ExecStart=/usr/local/bin/daed run -c /opt/daed

# 环境变量：GEO 数据路径
Environment=DAED_GEOIP_DAT=/usr/share/v2ray/geoip.dat
Environment=DAED_GEOSITE_DAT=/usr/share/v2ray/geosite.dat

# 重启策略
Restart=on-failure
RestartSec=5

# 超时（eBPF 加载可能需要较长时间）
TimeoutStartSec=120
TimeoutStopSec=30

StandardOutput=append:/var/log/daed/daed.log
StandardError=append:/var/log/daed/daed.log

[Install]
WantedBy=multi-user.target
SERVICEEOF
  systemctl daemon-reload
  systemctl enable daed

  info "=== 5/5 启动 daed 服务 ==="
  systemctl start daed
  sleep 2
  if systemctl is-active daed &>/dev/null; then
    info "  ✓ daed 服务已启动"
  else
    warn "  ⚠ daed 启动异常，检查日志: journalctl -u daed -n 50 --no-pager"
    systemctl status daed --no-pager --lines=10
    exit 1
  fi

  LOCAL_IP=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
  info ""
  info "========== 安装完成 =========="
  info " daed 版本:    ${DAED_VER}"
  info " 安装目录:     ${INSTALL_DIR}"
  info " 配置目录:     ${CONF_DIR}"
  info " GEO 数据:     共享 mosdns (/usr/share/v2ray/)"
  info " 日志文件:     /var/log/daed/daed.log"
  info ""
  info "========== 访问面板 =========="
  info " 地址: http://${LOCAL_IP}:2023"
  info ""
  info "========== 服务管理 =========="
  info " systemctl restart daed   # 重启"
  info " systemctl status daed    # 状态"
  info " journalctl -u daed -f    # 实时日志"
  info ""
}

# ---------- 升级 ----------
do_upgrade() {
  DAED_VER="$1"
  DAED_ARCH="$2"
  CURRENT_VER="$3"

  info "=== 升级 daed: ${CURRENT_VER:-未知} → ${DAED_VER} ==="
  DOWNLOAD_URL="https://github.com/daeuniverse/daed/releases/download/${DAED_VER}/daed-linux-${DAED_ARCH}.zip"
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  wget -q "$DOWNLOAD_URL" -O daed.zip
  unzip -q daed.zip
  # zip 内带一层目录，二进制文件名 = daed-linux-{arch}
  BINARY_PATH=$(find . -type f \( -name "daed-linux-*" -o -name "daed" \) ! -name "*.zip" ! -name "*.service" ! -name "*.desktop" ! -name "*.conf" ! -name "*.yaml" 2>/dev/null | head -1)
  if [ -z "$BINARY_PATH" ]; then
    err "未找到 daed 二进制文件\n  $(ls -la 2>/dev/null | head -10)"
  fi
  install -m 755 "$BINARY_PATH" "$BIN"
  chmod +x "$BIN"
  rm -rf "$TMPDIR"

  systemctl restart daed
  info "  ✓ daed 已升级到 ${DAED_VER} 并重启"
}

# =================== 主菜单 ===================
echo ""
echo "========================================"
echo "  daed 一键安装/升级/卸载脚本"
echo "  https://github.com/daeuniverse/daed"
echo "========================================"
echo ""

DAED_ARCH=$(detect_arch)
[ -z "$DAED_ARCH" ] && err "不支持的架构: $(uname -m)"

INSTALLED=false
CURRENT_VER=$(get_current_ver)
if [ -f "$BIN" ]; then
  INSTALLED=true
  if [ -n "$CURRENT_VER" ]; then
    info "检测到 daed ${CURRENT_VER} 已安装"
  else
    info "检测到 daed 已安装（版本未知）"
  fi
else
  info "daed 未安装"
fi

echo ""
echo "请选择操作："
echo "  1. 安装 / 升级 daed"
echo "  2. 卸载 daed"
echo "  0. 退出"
echo ""
read -p "请输入选项 (0-2): " ACTION
echo ""

case "$ACTION" in
  2)
    uninstall_daed
    ;;
  0)
    info "已退出"
    exit 0
    ;;
  1|"")
    if [ "$DAED_SRC" = "docker" ]; then
      # 从 Docker 提取二进制，然后继续安装流程
      do_install_from_docker
      do_install "" "" "true"
    elif [ -n "$FORCE_VER" ]; then
      LATEST_VER="$FORCE_VER"
    else
      LATEST_VER=$(fetch_latest_ver)
      if [ -z "$LATEST_VER" ]; then
        LATEST_VER="$FALLBACK_VER"
        warn "GitHub API 不可用，使用后备版本 ${FALLBACK_VER}"
      fi
    fi

    if [ "$INSTALLED" = true ]; then
      if [ -n "$CURRENT_VER" ] && [ "$CURRENT_VER" = "$LATEST_VER" ]; then
        info "当前版本: ${CURRENT_VER}"
        info "✓ 已是最新版本"
        exit 0
      fi
      do_upgrade "$LATEST_VER" "$DAED_ARCH" "$CURRENT_VER"
    else
      do_install "$LATEST_VER" "$DAED_ARCH"
    fi
    ;;
  *)
    err "无效选项: ${ACTION}"
    ;;
esac
