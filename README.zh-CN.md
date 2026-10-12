<p align="center">
  <img src="Resources/MamoriIcon.png" alt="Mamori 图标" width="72">
</p>

<h1 align="center">Mamori · 守 · お守り</h1>

<p align="center">让 Mac 保持唤醒，把注意力留给手上的事。</p>

<p align="center">
  <a href="README.md">English</a> · 简体中文 · <a href="README.ja.md">日本語</a>
</p>

Mamori 是一个轻巧的原生菜单栏工具，陪你完成较长的 AI 任务、构建和研究。选好保醒时长，主动开启 VPN 守护，再决定断线后哪些应用需要退出。操作集中在一个小面板里，结束时也有明确的退出路径。

**[开始使用 0.2.0](Documentation/Signing.md)** · [安装与移除](Documentation/Installation.md) · [开发进度](Documentation/Progress.md)

macOS 14+ · Apple Silicon 本地构建 · 英语、简体中文、日语

> **0.2.0 是本地开发版本。** 已实现真实后台服务设置、网络守护、可选应用退出和完整卸载；本机已确认服务安装及后台进程运行；真实网络阻断和完整卸载仍待验证。目前没有公开且已公证的 0.2.0 安装包，下方另附旧版预览下载。

<p align="center">
  <img src="Artifacts/home-zh-Hans.png" alt="Mamori 简体中文安全预览界面" width="280">
</p>

## 让需要时间的工作，少一件要操心的事

| 操作 | 功能 |
| --- | --- |
| **保持 Mac 唤醒** | 在 Mamori 运行期间或指定时长内保醒。屏幕仍可熄灭，也可以锁屏。 |
| **守护 GlobalProtect** | 守护开启后，无论主动断开还是意外掉线，实现都会保留默认拒绝策略，由后台服务验证规则并报告状态。 |
| **退出所选应用** | 确认 VPN 断线后，可退出已选且正在运行的应用。默认关闭；证据不明时不会触发退出，延时强退需单独选择。 |
| **还原并退出** | 取消待执行的应用操作、释放保醒，并等待自有网络资源还原后退出。偏好设置留待下次使用。 |
| **完整卸载** | 确认后还原自有网络资源、注销服务，再永久删除当前运行的应用及本用户的 Mamori 数据。清理失败会明确显示。 |

保醒和网络守护各自独立。Mamori 不自动重连 VPN，也不重开已退出的应用。选择浏览器或终端，意味着整个应用及其所有窗口和会话。

## 从当前版本开始

1. 按[签名指南](Documentation/Signing.md)**构建并签名 0.2.0**。本地 Apple Development 身份可启用真实服务；ad-hoc 构建无法启用。
2. 将干净的 `build/Mamori.zip` 解压到 **Applications**，再打开 Mamori。构建脚本不会安装或启动后台服务。
3. 连接 GlobalProtect，在 Mamori 中选择**设置保护服务**，按提示在 macOS 中批准后台服务。
4. 选择**检测 VPN 连接**，检查识别出的隧道和网关，再点击**开始守护**。启动校验由经过身份认证的后台服务负责，不能仅凭菜单栏的观察结果放行。
5. 按需开启保醒和自动退出。工作结束时选择**还原并退出**；需要移除应用时，选择**设置 → 完整卸载**。

这是一条用于受控本地评估的流程。签名有效、检测到隧道或测试通过，都不能代替真实的数据包验证。

## 小，是一种选择

**熟悉而安静。** 系统字体、原生控件、浅色／深色外观和三种语言。关闭面板只是收起界面，不会结束会话。

**由你决定。** 保醒和自动退出默认关闭；不自动登录启动、重连 VPN 或重开应用。Mamori 自身、VPN 控制组件和关键系统组件不在可退出名单中。

**只管理自己的东西。** 没有遥测；不改 Shell 配置、PATH、DNS、代理、GlobalProtect 设置或全局电源偏好。完整卸载只移除自有资源，不删除其他副本、源码、其他用户数据或 macOS 日志与授权记录；应用直接删除，不移入废纸篓。

## 已经验证了什么

**守护修复的 89 项 Swift 测试通过。** 此前的 6 项合成应用包检查也已通过。build 5 已安装到 Applications 并通过严格签名校验；在原生安全预览中确认应用名称统一左对齐、复选框垂直居中，点击复选框或名称均可切换选择。此前也检查了真实主页、设置页及三种语言的安全预览。PF 读取器已通过本机只读核对，另行执行的非启用式语法检查也已通过。具体范围见[验证记录](Documentation/Progress.md)。

真实 VPN 断线、PF 有效阻断及真实完整卸载集成仍**未经验证**。更新前，用户通过「还原并退出」清理了启用 PF 前失败的会话；这不代表已验证启用 PF 后的还原流程。当前守护针对有限的 GlobalProtect 配置，不涵盖分流、纯代理或所有 VPN。两条抽样路由不能证明全隧道覆盖。保醒也不会阻止合盖或主动睡眠，更不能保证远端 AI 任务持续运行。评估前请阅读[网络边界](Documentation/NetworkGuard.md)。

## 旧版预览下载

公开的 **[v0.1.0-preview](https://github.com/fayerhill/mamori/releases/tag/v0.1.0-preview)** 是面向 Apple Silicon 的旧版 ad-hoc 签名、未公证构建。普通版提供实际保醒和只读观察，不能启用真实守护或自动退出，也不包含当前 0.2.0 的完整功能。

旧版安装方式见[下载说明](Documentation/Download.md)。想安全体验当前界面，可构建独立的 **Mamori Preview**：它模拟 VPN、防火墙、保醒、应用退出和卸载，只读取已安装应用目录。评估真实守护时，请使用上方的签名本地构建。

<details>
<summary><strong>开发、探索与参与</strong></summary>

需要支持 Swift 6 的 Xcode。项目使用 SwiftUI、AppKit 和 Swift Package Manager，没有远程软件包依赖。

```sh
git clone https://github.com/fayerhill/mamori.git
cd mamori
SIGNING_MODE=dev ./Scripts/build.sh
./Scripts/preview.sh
./Scripts/test.sh
```

没有签名身份时，可用 `SIGNING_MODE=adhoc` 构建功能受限版本。`auto` 依次选择 Developer ID、Apple Development 和 ad-hoc；公开打包流程拒绝 Apple Development 构建。详见[签名说明](Documentation/Signing.md)。

`Mamori` 负责界面，`MamoriCore` 负责会话和策略，`MamoriSystem` 负责系统适配，`MamoriGuard` 负责特权服务。下一步是受控集成验证，以及 Developer ID 签名和公证。欢迎[反馈问题](https://github.com/fayerhill/mamori/issues)，请勿公开私有 VPN 地址或凭证。

</details>

[行为约定](Documentation/Behavior.md) · [网络设计](Documentation/NetworkGuard.md) · [安装与移除](Documentation/Installation.md) · [开发进度](Documentation/Progress.md)
