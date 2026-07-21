# onekey-daed

一键在 Debian LXC 上部署 [daed](https://github.com/daeuniverse/daed) — dae 的现代化 Web 管理面板。

> 依赖 [onekey-mosdns](https://github.com/guochan2019/onekey-mosdns) 提供的 GEO 数据（`/usr/share/v2ray/`）。

## 快速开始

> ⚠️ 需要 root 权限。内核需 **Linux 5.17+** 且启用 eBPF。

```bash
# 一键直达（推荐）
bash <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-daed/main/onekey-daed.sh)
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
  1. 安装 / 升级 daed（云编译版）
  2. 安装 / 升级 daed（本地二进制文件）
  3. 卸载 daed
  0. 退出
```

| 选项 | 功能 |
|------|------|
| **1** | 从 GitHub Actions 云编译版安装/升级（自动拉取本仓库最新 release） |
| **2** | 使用本地预编译二进制文件安装/升级（手动输入路径） |
| **3** | 卸载：停止服务、删除二进制/配置/日志 |
| **0** | 退出 |

## 下载来源说明

### 1. 云编译版（默认）

使用 GitHub Actions 从 [daeuniverse/daed](https://github.com/daeuniverse/daed) 官方仓库 main 分支编译，编译完成后自动发布到本仓库 release，脚本自动下载：

```bash
bash onekey-daed.sh
# 选 1
```

触发编译：`Actions` → `Build daed binary` → `Run workflow`（或每周日自动编译）

### 2. 本地二进制文件

支持从其它来源获取 daed 二进制：

```bash
bash onekey-daed.sh
# 选 2 → 输入文件路径
```

也支持通过环境变量直接指定（免交互）：

```bash
DAED_BIN=/path/to/daed bash onekey-daed.sh
```

## 安装流程

| 步骤 | 说明 |
|------|------|
| 检测 | 内核版本 ≥ 5.17 + eBPF 配置检查 |
| 检测 | 确认 mosdns GEO 数据存在 |
| 1/5 | 安装依赖（wget、curl） |
| 2/5 | 下载/使用 daed 二进制 |
| 3/5 | 创建目录结构 + GEO 数据链接 |
| 4/5 | 创建 systemd 服务 |
| 5/5 | 启动 daed 服务 |

## systemd 服务配置

采用官方推荐参数，已针对非 Docker 环境做适配：

| 参数 | 值 | 说明 |
|------|-----|------|
| `LimitNPROC` | 512 | 限制最大线程数，防止内存泄漏累积 |
| `LimitNOFILE` | 1048576 | 文件描述符上限 |
| `MemoryMax` | 2G | 内存硬上限，兜底防止系统 OOM |
| `Restart` | on-failure | 进程异常退出时自动拉起 |
| `ExecStartPre` | mountpoint -q \|\| mount | 自动挂载 BPF 文件系统（LXC 需要） |

## 目录结构

```
/opt/daed/                   # 安装目录 + 配置目录
/usr/local/bin/daed          # daed 二进制
/var/log/daed/daed.log       # 运行日志
/usr/share/v2ray/
├── geoip.dat                # GEO 数据（由 mosdns 提供）
└── geosite.dat
```

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
# 选 1 → 升级；选 3 → 卸载
```

## 架构支持

x86_64 / arm64

## 许可证

本项目基于 [GPL-3.0](LICENSE) 协议。daed 本身采用 MIT + AGPL-3.0 双许可证。
