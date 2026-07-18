# onekey-daed

一键在 Debian LXC 上部署 [daed](https://github.com/daeuniverse/daed) — dae 的现代化 Web 管理面板。

> 依赖 [onekey-mosdns](https://github.com/guochan2019/onekey-mosdns) 提供的 GEO 数据（`/usr/share/v2ray/`）。

## 快速开始

> ⚠️ 需要 root 权限。内核需 **Linux 5.17+** 且启用 eBPF。

```bash
gh repo clone guochan2019/onekey-daed
cd onekey-daed
bash onekey-daed.sh
```

## 前置依赖

| 项目 | 说明 |
|------|------|
| [onekey-mosdns](https://github.com/guochan2019/onekey-mosdns) | 提供 GEO 数据（geoip.dat + geosite.dat） |
| Linux 5.17+ | dae 要求的最小内核版本 |
| eBPF 内核配置 | `CONFIG_BPF=y`、`CONFIG_BPF_SYSCALL=y`、`CONFIG_DEBUG_INFO_BTF=y` |

脚本安装前会自动检测内核版本和 eBPF 配置。

## 使用方式

运行脚本后显示菜单：

```
========================================
  daed 一键安装/升级/卸载脚本
  https://github.com/daeuniverse/daed
========================================

[INFO] daed 未安装

请选择操作：
  1. 安装 / 升级 daed
  2. 卸载 daed
  0. 退出
```

| 选项 | 功能 |
|------|------|
| **1** | 未安装 → 5 步完整安装；已安装 → 检测版本并升级 |
| **2** | 卸载：停止服务、删除二进制/配置/日志 |
| **0** | 退出 |

## 下载源模式

脚本支持三种获取 daed 二进制的方式：

### 1. 官方 release（默认）

从 `daeuniverse/daed` GitHub release 拉取最新稳定版，自动匹配 CPU 指令集：

```bash
bash onekey-daed.sh
```

### 2. CI 云编译版（推荐）

使用 GitHub Actions 从 [QiuSimons/luci-app-daed](https://github.com/QiuSimons/luci-app-daed) 锁定的源码编译，与 OpenWrt 编译版完全一致。编译完成后自动发布到本仓库 release：

```bash
DAED_SRC=self bash onekey-daed.sh
```

触发编译：`Actions` → `Build daed binary` → `Run workflow`

### 3. 本地二进制文件

支持直接使用预编译的二进制（如从 OpenWrt 编译环境中提取）：

```bash
DAED_BIN=/path/to/daed bash onekey-daed.sh
```

## 安装流程

| 步骤 | 说明 |
|------|------|
| 检测 | 内核版本 ≥ 5.17 + eBPF 配置检查 |
| 检测 | 确认 mosdns GEO 数据存在 |
| 1/5 | 安装依赖（wget、unzip、curl） |
| 2/5 | 下载/使用 daed 二进制 |
| 3/5 | 创建目录结构 |
| 4/5 | 创建 systemd 服务（对齐官方配置） |
| 5/5 | 启动 daed 服务 |

## 目录结构

```
/opt/daed/                   # 安装目录 + 配置目录
/usr/local/bin/daed          # daed 二进制
/var/log/daed/daed.log       # 运行日志
/usr/share/v2ray/
├── geoip.dat                # GEO 数据（由 mosdns 提供）
└── geosite.dat
```

## CPU 优化

脚本自动检测 CPU 指令集，从官方 release 下载对应的优化版二进制（仅官方源模式）：

| CPU 特性 | 下载版本 |
|----------|---------|
| 支持 AVX2 | `x86_64_v3_avx2` |
| 仅 SSE  | `x86_64_v2_sse` |
| 通用 x86_64 | `x86_64` |

> ARM64、MIPS、RISC-V 等架构同样支持。

## 面板访问

| 项目 | 值 |
|------|-----|
| 地址 | `http://{IP}:2023` |
| 首次启动 | 按照页面引导完成初始化配置 |

## 服务管理

```bash
systemctl status daed       # 查看状态
systemctl restart daed      # 重启
systemctl stop daed         # 停止
journalctl -u daed -f       # 实时日志
```

### 升级 / 卸载

再次运行脚本选择对应选项即可：

```bash
bash onekey-daed.sh
# 选 1 → 升级；选 2 → 卸载
```

## 架构支持

x86_64（含 AVX2/SSE 优化）/ arm64 / x86_32 / mips32 / mips32le / mips64 / mips64le / riscv64

## 许可证

本项目基于 [GPL-3.0](LICENSE) 协议。daed 本身采用 MIT + AGPL-3.0 双许可证。
