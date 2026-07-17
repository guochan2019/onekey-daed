#!/bin/bash
# ============================================================
# onekey-daed — daed 一键安装/升级/卸载脚本
# 适用环境: Debian 13 (fresh LXC)
# 功能: 安装 daed（dae 现代化 Web 管理面板）
# 项目: https://github.com/daeuniverse/daed
# ============================================================
set -e

trap 'echo -e "\033[0;31m[ERROR] 脚本执行失败，请检查:\033[0m
  - 网络连接（能否访问 github.com）
  - 是否以 root 运行" >&2' ERR

# ---------- 配置 ----------
FALLBACK_VER="v1.27.0"
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
  curl -s --connect-timeout 5 \
    https://api.github.com/repos/daeuniverse/daed/releases/latest \
    | grep -o '"tag_name": *"[^"]*"' | grep -o 'v[^\"]*' 2>/dev/null || echo ""
}

# ---------- 获取当前版本 ----------
get_current_ver() {
  if [ ! -f "$BIN" ]; then
    echo ""; return
  fi
  # daed version 输出格式: "daed version v1.27.0"
  "$BIN" version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
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

# ---------- 安装 ----------
do_install() {
  DAED_VER="$1"
  DAED_ARCH="$2"

  # 检查依赖：GEO 数据由 mosdns 提供
  if [ ! -f "/usr/share/v2ray/geoip.dat" ] || [ ! -f "/usr/share/v2ray/geosite.dat" ]; then
    err "未检测到 mosdns 的 GEO 数据 (/usr/share/v2ray/geoip.dat)\n  daed 需要依赖 mosdns，请先安装 onekey-mosdns"
  fi

  info "=== 1/5 安装系统依赖 ==="
  apt update -qq
  apt install -y -qq wget unzip curl

  info "=== 2/5 下载 daed ${DAED_VER} (${DAED_ARCH}) ==="
  DOWNLOAD_URL="https://github.com/daeuniverse/daed/releases/download/${DAED_VER}/daed-linux-${DAED_ARCH}.zip"
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  wget -q "$DOWNLOAD_URL" -O daed.zip
  unzip -q daed.zip
  install -m 755 daed "$BIN"
  chmod +x "$BIN"
  rm -rf "$TMPDIR"
  "$BIN" version 2>/dev/null | head -1 || info "  ✓ daed 已安装"

  info "=== 3/5 创建目录结构 ==="
  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONF_DIR"
  mkdir -p /var/log/daed

  info "=== 4/5 创建 systemd 服务 ==="
  cat > /etc/systemd/system/daed.service << 'SERVICEEOF'
[Unit]
Description=daed - Modern web dashboard for dae
Documentation=https://github.com/daeuniverse/daed
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/daed
ExecStart=/usr/local/bin/daed run -c /opt/daed
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

Environment=DAED_GEOIP_DAT=/usr/share/v2ray/geoip.dat
Environment=DAED_GEOSITE_DAT=/usr/share/v2ray/geosite.dat

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
  info "⚠ daed 在 LXC 中可能无法使用 eBPF 内核功能"
  info "  Web 管理面板和 API 正常工作不受影响"
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
  install -m 755 daed "$BIN"
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
    LATEST_VER=$(fetch_latest_ver)
    if [ -z "$LATEST_VER" ]; then
      LATEST_VER="$FALLBACK_VER"
      warn "GitHub API 不可用，使用后备版本 ${FALLBACK_VER}"
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
