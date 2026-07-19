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
FALLBACK_VER="daed_build_20260718"
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

# 支持使用本地预制二进制（如 OpenWrt 编译的），跳过 GitHub 下载
# 用法: DAED_BIN=/path/to/daed bash onekey-daed.sh
LOCAL_BIN="${DAED_BIN:-}"
[ -n "$LOCAL_BIN" ] && warn "使用本地二进制: ${LOCAL_BIN}"

# ---------- 检测架构 ----------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "x86_64"  ;;
    aarch64|arm64) echo "arm64"    ;;
    *)             echo ""         ;;
  esac
}

# ---------- 获取最新版本 ----------
fetch_latest_ver() {
  curl -s --connect-timeout 5 \
    https://api.github.com/repos/guochan2019/onekey-daed/releases/latest \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"' 2>/dev/null || echo ""
}

# ---------- 获取当前版本 ----------
get_current_ver() {
  if [ ! -f "$BIN" ]; then
    echo ""; return
  fi
  "$BIN" version 2>/dev/null | head -1 || echo ""
}

# ---------- 检测 kernel 是否满足 eBPF 要求 ----------
check_kernel() {
  local major minor
  major=$(uname -r | cut -d. -f1)
  minor=$(uname -r | cut -d. -f2)
  if [ "$major" -lt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -lt 17 ]; }; then
    err "内核版本过低 ($(uname -r))，daed 需要 Linux 5.17+"
  fi

  local missing=""
  for cfg in CONFIG_BPF CONFIG_BPF_SYSCALL CONFIG_DEBUG_INFO_BTF; do
    if zgrep -q "${cfg}=y" /proc/config.gz 2>/dev/null || \
       grep -q "${cfg}=y" /boot/config-$(uname -r) 2>/dev/null; then
      :
    else
      missing="$missing $cfg"
    fi
  done
  if [ -n "$missing" ]; then
    if [ -f /proc/config.gz ] || [ -f "/boot/config-$(uname -r)" ]; then
      err "内核缺少必要 eBPF 配置:$missing\n  请确认内核编译时启用了这些选项"
    else
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

# ---------- 安装 ----------
do_install() {
  DAED_VER="$1"
  DAED_ARCH="$2"

  check_kernel

  if [ ! -f "/usr/share/v2ray/geoip.dat" ] || [ ! -f "/usr/share/v2ray/geosite.dat" ]; then
    err "未检测到 mosdns 的 GEO 数据 (/usr/share/v2ray/geoip.dat)\n  daed 需要依赖 mosdns，请先安装 onekey-mosdns"
  fi

  info "=== 1/5 安装系统依赖 ==="
  apt update -qq
  apt install -y -qq wget curl

  info "=== 2/5 获取 daed ==="
  if [ -n "$LOCAL_BIN" ]; then
    info "  → 使用本地二进制: ${LOCAL_BIN}"
    TMP_FILE=$(mktemp)
    cp "$LOCAL_BIN" "$TMP_FILE"
    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$BIN"
    DAED_VER=$("$BIN" --version 2>/dev/null || "$BIN" version 2>/dev/null || echo "自定义")
  else
    info "  → 从本仓库 release 下载: ${DAED_VER} (${DAED_ARCH})"
    TMP_FILE=$(mktemp)
    wget -q "https://github.com/guochan2019/onekey-daed/releases/download/${DAED_VER}/daed-linux-${DAED_ARCH}" -O "$TMP_FILE"
    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$BIN"
    DAED_VER=$("$BIN" --version 2>/dev/null | head -1 || echo "$DAED_VER")
  fi

  info "=== 3/5 创建目录结构 ==="
  mkdir -p "$INSTALL_DIR"
  mkdir -p "$CONF_DIR"
  mkdir -p /var/log/daed

  # 将 GEO 数据链接到 daed 默认搜索路径（对齐 QiuSimons 做法）
  mkdir -p /usr/share/daed
  if [ -f /usr/share/v2ray/geoip.dat ] && [ -f /usr/share/v2ray/geosite.dat ]; then
    ln -sf /usr/share/v2ray/geoip.dat /usr/share/daed/geoip.dat
    ln -sf /usr/share/v2ray/geosite.dat /usr/share/daed/geosite.dat
    info "  ✓ GEO 数据已链接到 /usr/share/daed/"
  else
    warn "  ⚠ /usr/share/v2ray/ 下未找到 GEO 数据"
    warn "  请先安装 onekey-mosdns 或手动下载 geoip.dat / geosite.dat"
  fi

  info "=== 4/5 创建 systemd 服务 ==="
  # 启动延迟（由用户通过 systemd drop-in 自主决定是否需要）

  cat > /etc/systemd/system/daed.service << 'SERVICEEOF'
[Unit]
Description=daed - A modern dashboard for dae
Documentation=https://github.com/QiuSimons/luci-app-daed

[Service]
Type=simple

# 对齐 QiuSimons + 硬上限防止 OOM 崩溃
LimitCORE=infinity
LimitNOFILE=infinity
MemoryMax=1G

ExecStartPre=/bin/sh -c 'mkdir -p /sys/fs/bpf && mount -t bpf bpf /sys/fs/bpf 2>/dev/null; exit 0'
ExecStartPre=/bin/sh -c 'ip netns delete daens 2>/dev/null; rm -f /run/netns/daens; exit 0'
ExecStopPost=/bin/sh -c 'ip netns delete daens 2>/dev/null; rm -f /run/netns/daens; exit 0'
ExecStart=/usr/local/bin/daed run -c /opt/daed

# Debian 特有：GEO 数据路径（OpenWrt 由包管理器处理）
Environment=DAED_GEOIP_DAT=/usr/share/v2ray/geoip.dat
Environment=DAED_GEOSITE_DAT=/usr/share/v2ray/geosite.dat

# 对齐 QiuSimons：procd respawn → 任何退出都重启
Restart=always
RestartSec=2

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
  if [ -n "$LOCAL_BIN" ]; then
    info "  → 使用本地二进制: ${LOCAL_BIN}"
    TMP_FILE=$(mktemp)
    cp "$LOCAL_BIN" "$TMP_FILE"
    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$BIN"
    DAED_VER=$("$BIN" --version 2>/dev/null || "$BIN" version 2>/dev/null || echo "自定义")
  else
    info "  → 从本仓库 release 下载: ${DAED_VER} (${DAED_ARCH})"
    TMP_FILE=$(mktemp)
    wget -q "https://github.com/guochan2019/onekey-daed/releases/download/${DAED_VER}/daed-linux-${DAED_ARCH}" -O "$TMP_FILE"
    chmod +x "$TMP_FILE"
    mv "$TMP_FILE" "$BIN"
    DAED_VER=$("$BIN" --version 2>/dev/null | head -1 || echo "$DAED_VER")
  fi

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
echo "  1. 安装 / 升级 daed（云编译版）"
echo "  2. 安装 / 升级 daed（本地二进制文件）"
echo "  3. 卸载 daed"
echo "  0. 退出"
echo ""
read -p "请输入选项 (0-3): " ACTION </dev/tty
echo ""

case "$ACTION" in
  3)
    uninstall_daed
    ;;
  0)
    info "已退出"
    exit 0
    ;;
  2)
    # 本地二进制模式：用户输入路径
    read -p "请输入本地 daed 二进制文件路径: " LOCAL_PATH </dev/tty
    if [ ! -f "$LOCAL_PATH" ]; then
      err "文件不存在: ${LOCAL_PATH}"
    fi
    LOCAL_BIN="$LOCAL_PATH"
    LATEST_VER="local"
    if [ "$INSTALLED" = true ]; then
      do_upgrade "$LATEST_VER" "$DAED_ARCH" "$CURRENT_VER"
    else
      do_install "$LATEST_VER" "$DAED_ARCH"
    fi
    ;;
  1|"")
    LATEST_VER=$(fetch_latest_ver)
    if [ -z "$LATEST_VER" ]; then
      LATEST_VER="$FALLBACK_VER"
      warn "GitHub API 不可用，使用后备版本 ${FALLBACK_VER}"
    fi

    if [ "$INSTALLED" = true ]; then
      do_upgrade "$LATEST_VER" "$DAED_ARCH" "$CURRENT_VER"
    else
      do_install "$LATEST_VER" "$DAED_ARCH"
    fi
    ;;
  *)
    err "无效选项: ${ACTION}"
    ;;
esac
