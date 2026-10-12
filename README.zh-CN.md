# Mamori

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

**Mamori · 守 · お守り** 是一个小巧的原生 macOS 菜单栏工具：让 Mac 保持唤醒，选择在确认 VPN 断开时退出的应用，并提供一个范围明确的网络保护原型。

界面遵循简洁的 macOS 原生风格，采用系统无衬线字体、标准控件和自适应浅色／深色外观。面板尺寸为 280 × 290 pt；开始守护使用系统强调色（默认蓝色），停止使用红色，「选择应用」位于自动退出标题下方并左对齐。

**当前状态：本地最小可用版本（MVP），需要 macOS 14 或更新版本。** 默认构建使用临时签名（ad-hoc），可使用保持唤醒和独立安全预览。网络保护仍是未经真实连接验证的实验功能，需要 Developer ID 签名的应用、后台服务及单独的受控验证。当前预览不提供实际防火墙保护。

<img src="Artifacts/home-zh-Hans.png" alt="Mamori 简体中文安全预览，采用系统无衬线字体" width="280">

## 功能

- **保持唤醒**：在 Mamori 运行期间持续启用，或设置 1–10,080 分钟的时长；仍允许熄屏和锁屏。
- **选择应用**：搜索已安装的应用，也可选择尚未运行的应用。确认断线时，仅处理当时正在运行的已选应用。
- **可选自动退出**：默认关闭；可另行启用等待五秒后的强制退出。操作前重新检查进程身份，避免误操作。
- **VPN 观察**：保守地只读观察 GlobalProtect；不会把任意 `utun` 接口当成已验证的 VPN。
- **还原并退出**：取消待执行的应用退出操作、释放保醒，并等待网络资源还原确认。失败时保留重试入口。
- **三种界面语言**：英语、简体中文和日语，可在设置中切换。

保醒与网络守护独立：停止守护不会取消保醒计时，退出 Mamori 才会结束两者。关闭面板不会退出菜单栏应用。VPN 恢复后不会自动重连 VPN，也不会重新打开已退出的应用。

## 下载

在 [v0.1.0-preview 发布页](https://github.com/fayerhill/mamori/releases/tag/v0.1.0-preview) 下载开发预览版。首个版本仅提供 **Apple Silicon（arm64）、macOS 14+** 构建，两个应用分别打包为 ZIP：

- **Mamori-macOS-arm64.zip**：包含普通版 `Mamori.app`，可使用保醒及只读 VPN 观察；默认不启用保醒。
- **Mamori-Preview-macOS-arm64.zip**：包含始终使用安全模拟模式的 `Mamori Preview.app`，适合先体验界面与断线流程，不操作真实 VPN、防火墙、电源断言或其他应用。

每个 ZIP 附有快速入门说明；发布页另提供 `SHA256SUMS` 用于校验下载文件。

这些是 **ad-hoc 签名、尚未公证的开发构建**，并非可直接依赖的网络防护产品。自动退出应用依赖已启用的网络守护，因此当前下载版也只能在安全预览中演示这一流程。真实网络保护仍需 Developer ID 签名的应用和 `SMAppService` 后台服务，以及单独受控环境中的验证。安装方式见[下载说明](Documentation/Download.md)，移除方式见[安装说明](Documentation/Installation.md)。

## 构建与预览

需要 macOS 14+、Xcode 和 Swift 6。项目使用 Swift Package Manager，没有第三方软件包依赖。

```sh
git clone https://github.com/fayerhill/mamori.git
cd mamori
./Scripts/build.sh
./Scripts/preview.sh
```

构建产物为 `build/Mamori.app` 和 `build/Mamori Preview.app`；预编译 ZIP 通过 Releases 分发，不提交到源代码目录。预览应用即使从 Finder 直接打开，也始终使用模拟模式：读取已安装应用列表与图标，但模拟 VPN、电源、防火墙和退出应用的操作，不改变真实 VPN，也不退出其他应用。

运行隔离测试或生成预览截图：

```sh
./Scripts/test.sh
./Scripts/preview.sh --capture /private/tmp/mamori-preview
```

截图仅允许在模拟模式下运行；普通应用需要 `--demo`，预览应用自动启用该模式。使用 `/private/tmp` 可避免 Documents 文件夹访问权限阻止截图。

## 架构

| 模块 | 职责 |
| --- | --- |
| `Sources/Mamori` | SwiftUI/AppKit 界面、本地化与操作协调 |
| `Sources/MamoriCore` | 纯状态机、VPN 证据分类和网络策略 |
| `Sources/MamoriSystem` | 电源、应用、VPN 与 XPC 系统适配 |
| `Sources/MamoriGuard` | 通过 `SMAppService` 管理的特权后台服务、PF 原型和恢复记录 |

代码及代码注释保持英语。后台接口仅提供限定操作；还原只处理 Mamori 自己拥有的网络资源。

## 限制与验证范围

- 首版只针对有限的 GlobalProtect 配置，不承诺支持所有 VPN、代理或分流模式。需要已确认的 IPv4 网关地址和指定的全隧道接口。
- 对两个外部 IPv4 地址的路由采样**不能证明全隧道覆盖**；全隧道仍是部署前提，需要针对实际环境验证。
- PF 原型要求系统原有过滤入口可用，且不存在冲突规则或已有状态表。它不会清空其他软件的连接状态来强行启用。
- 网关与最小 DHCP 流量有例外；共享允许网关 IP 的应用无法完全区分。不支持 IPv6 VPN 网关传输，也不承诺零泄漏。PF 不是 Apple 支持的产品 API。
- 保醒不保证阻止合盖、主动睡眠、关机、重启或低电量睡眠，也不保证远端 AI 任务持续执行。
- 没有自动重连、开机自动启动或遥测；不会修改 Shell 配置、PATH、DNS、代理或 GlobalProtect 设置。卸载不会清除系统日志、授权记录、无关终端历史或备份。

已记录的核心测试为 **34 项通过、0 失败**；最新字体调整已重新构建并检查界面。这些验证不等于真实网络防护验证。开发验证期间没有断开真实 VPN、注册后台服务、启用 PF 规则、取得电源断言或退出用户工作应用。

## 后续计划与文档

下一步是完成 Developer ID 签名与公证，在受控测试 Mac 上验证服务授权、恢复与移除，再单独验证实际网络阻断、GlobalProtect 兼容性及故障行为。更广泛分发前还需评估长期网络过滤方案。

- [开发进度与里程碑](Documentation/Progress.md)
- [构建、安装与移除](Documentation/Installation.md)
- [生命周期与行为约定](Documentation/Behavior.md)
- [网络保护的前提、策略与限制](Documentation/NetworkGuard.md)

正常退出会还原活动功能，但保留应用和偏好。移除真实后台服务前必须先确认还原成功；不要在恢复失败时先删除应用或恢复记录。
