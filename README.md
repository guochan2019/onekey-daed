# onekey-daed

一键在 Debian LXC 上部署 [daed](https://github.com/daeuniverse/daed) — dae 的现代化 Web 管理面板。

> 依赖 [onekey-mosdns](https://github.com/guochan2019/onekey-mosdns) 提供的 GEO 数据（`/usr/share/v2ray/`）。

## 快速开始

> ⚠️ 需要 root 权限。内核需 **Linux 5.17+** 且启用 eBPF。

```bash
# 方式一：gh CLI（推荐）
gh repo clone guochan2019/onekey-daed
cd onekey-daed
bash onekey-daed.sh

# 方式二：git clone（需配置 SSH 密钥）
git clone git@github.com:guochan2019/onekey-daed.git
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

### 指定版本安装

官方 release 可能滞后于主线代码，可通过 `DAED_VER` 环境变量指定版本：

```bash
DAED_VER=v1.28.0 bash onekey-daed.sh
```

> 版本号需与 [GitHub Releases](https://github.com/daeuniverse/daed/releases) 的 tag 名一致，
> 或使用 wkccd 等第三方构建的版本号。如果下载失败请自行寻找对应二进制文件。

## 安装流程

| 步骤 | 说明 |
|------|------|
| 检测 | 内核版本 ≥ 5.17 + eBPF 配置检查 |
| 检测 | 确认 mosdns GEO 数据存在 |
| 1/5 | 安装依赖（wget、unzip、curl） |
| 2/5 | 下载 daed，自动匹配 CPU 优化版 |
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

脚本自动检测 CPU 指令集，下载对应的优化版二进制：

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
