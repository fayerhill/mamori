<p align="center">
  <img src="Resources/MamoriIcon.png" alt="Mamori 图标" width="72">
</p>

<h1 align="center">Mamori · 守 · お守り</h1>

<p align="center">让 Mac 保持唤醒，把注意力留给手上的事。</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文 · <a href="README.ja.md">日本語</a>
</p>

Mamori 是一个轻巧的原生 macOS 菜单栏工具。开始一段 AI 工作、等待构建，或整理需要较长时间的研究资料时，打开保醒，选好时长，然后继续做你的事。

它留在菜单栏里。你需要时，点开一个小面板；工作结束时，明确地停止或退出。

> **当前源码版本为 0.2.0。** 使用有效 Apple 签名的本地构建已包含真实后台服务设置、网络守护、可选应用退出和完整卸载，仍待受控环境中的真实验证。下方公开下载的 **v0.1.0-preview** 是旧版 ad-hoc 构建，仅提供实际保醒、只读观察和模拟守护。面向公众的正式签名分发仍需要 Developer ID 与公证。

<p align="center">
  <img src="Artifacts/home-zh-Hans.png" alt="Mamori 简体中文界面，展示保醒与模拟守护选项" width="280">
</p>

## 适合这些时候

- **让 AI 继续工作。** 给较长的编程、分析或资料整理任务留出时间，减少因 Mac 自动睡眠而中断本地运行的情况。
- **等待构建或导出。** 设定一段保醒时间，不必为了一个任务改动系统的长期电源设置。
- **离开桌面一会儿。** 屏幕可以熄灭，Mac 也可以锁屏；保醒不要求你一直亮着屏幕。

Mamori 防止的是自动空闲睡眠。它不保证阻止合盖、主动睡眠、关机或低电量睡眠，也不能保证远端 AI 服务或任务持续运行。

## 小，但把控制交给你

**只保醒你需要的时间。** 选择在 Mamori 运行期间持续保醒，或设定自定义时长。计时结束会停止，退出应用也会释放保醒。关闭小面板则不会退出菜单栏应用。

**熟悉的 Mac 界面。** 原生控件、紧凑布局和浅色／深色外观；支持英语、简体中文和日语。日常操作不需要打开终端。

**看得见当前状态。** 应用只读观察 GlobalProtect；启用签名后台服务后，守护状态以服务的实际验证结果为准。设置服务后可只读探测网关与隧道，再由你决定开始。检测到 VPN 本身并不代表已有防火墙保护。

**先体验，再决定。** 单独的 Mamori Preview 始终模拟 VPN、保醒、防火墙和应用退出。签名本地版则可在守护开启后，按明确确认的断线事件退出已选且正在运行的应用；无法读取连接证据时不会误当作确认断线。应用选择器也支持尚未运行的应用，选中本身不会启动或退出它们。

**退出与卸载都有明确结果。** 设置中的「完整卸载」需要确认：先释放保醒、确认网络还原并注销服务，再永久删除当前运行的应用副本和本用户的自有偏好、缓存、支持文件及保存状态。它不移入废纸篓，也不删除源码、其他副本、其他用户数据或系统日志。失败会显示未完成；预览版只模拟。

## 安静，是一种选择

Mamori 围绕一段由你开始、由你结束的工作时间设计。保醒与网络守护各自独立，不会因为切换一个功能，就悄悄改变另一个功能的状态。

它不自动重连 VPN，不自动重开已退出的应用，也不在登录时自行启动。没有账号、遥测或后台数据上传；不改动你的 DNS、代理、GlobalProtect 设置或 Shell 配置。

我们希望保留的是明确的状态、直接的操作和可靠的退出路径。更多开关，只有在确实有用时才加入。

## 下载并开始

**[下载 macOS DMG](https://github.com/fayerhill/mamori/releases/download/v0.1.0-preview/Mamori-macOS-arm64.dmg)** · [v0.1.0-preview 发布说明与校验文件](https://github.com/fayerhill/mamori/releases/tag/v0.1.0-preview)

下方下载是旧版 **v0.1.0-preview**，适用于 **Apple Silicon、macOS 14 或更新版本**，采用 **ad-hoc 签名且尚未公证**。它不包含当前 0.2.0 本地签名构建的完整功能，也不应当作已验证的网络防护产品。当前版本见[本地签名构建说明](Documentation/Signing.md)。

1. 下载并打开 DMG，将需要的应用拖入 **Applications**。
2. 打开 **Mamori**，点击菜单栏的盾牌，开启保醒并选择时长。想先试界面，可以打开 **Mamori Preview**。
3. 工作结束后关闭保醒，或选择 **还原并退出**。

DMG 包含两个应用：

| 应用 | 用途 |
| --- | --- |
| **Mamori** | 实际保醒与只读 GlobalProtect 观察；保醒默认关闭。 |
| **Mamori Preview** | 模拟守护流程；不改变真实 VPN、防火墙、电源断言或其他应用。 |

安装无需 Xcode、Homebrew 或命令行配置。如果 macOS 阻止打开，请先阅读[下载说明](Documentation/Download.md)，再自行判断是否信任此开发构建；无需关闭 Gatekeeper。

## 正在走向哪里

当前源码已实现后台服务设置、断线时保留默认拒绝策略、可选应用退出和完整卸载。本地 Apple Development 签名可以用于开发验证；面向公众的签名分发仍待 Developer ID 与公证。实际安装、断网行为、恢复与卸载需要在单独授权的测试环境中验证，不能用编译或签名通过代替。

自动退出只处理明确选中的应用，不会自动恢复它们。选择浏览器或终端意味着整个应用及其所有窗口；关键系统组件、Mamori 自身和 VPN 控制组件不在可退出名单中。当前不承诺支持所有 VPN、代理或网络配置，也不承诺零泄漏。

[查看开发进度与里程碑](Documentation/Progress.md)

<details>
<summary>开发者：本地构建与技术文档</summary>

需要 Xcode 和 Swift 6。项目使用 Swift Package Manager，没有第三方软件包依赖。

```sh
git clone https://github.com/fayerhill/mamori.git
cd mamori
./Scripts/build.sh
./Scripts/preview.sh
```

构建默认自动选择可用的 Developer ID、Apple Development 或 ad-hoc 签名。使用 `SIGNING_MODE=dev` 构建带真实服务的本地开发版，使用 `SIGNING_MODE=adhoc` 构建功能受限的预览版；公开打包脚本拒绝 Apple Development 构建。详见[签名说明](Documentation/Signing.md)。预览不要求断开真实 VPN；隔离测试通过也不等于真实网络阻断已获验证。

- [构建、安装与移除](Documentation/Installation.md)
- [生命周期与行为约定](Documentation/Behavior.md)
- [网络守护的架构、前提与限制](Documentation/NetworkGuard.md)

代码与代码注释使用英语。若将来安装了真实后台服务，移除应用前必须先确认网络资源已还原，再移除服务；不要删除尚待恢复的记录。

</details>
