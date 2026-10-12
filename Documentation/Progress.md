# Development progress

[English](../README.md) · [简体中文](../README.zh-CN.md) · [日本語](../README.ja.md)

Updated: 2026-10-12 (Asia/Taipei)

Status: **0.2.0 local development build**. The real guard and complete-uninstall paths are implemented, but live network protection and privileged installation have not been exercised. The published `v0.1.0-preview` downloads remain the older, limited ad-hoc builds.

## Implemented

- Native SwiftUI/AppKit menu-bar app for macOS 14+, using Swift 6 and no remote package dependencies. The compact interface uses system typography, standard controls, adaptive appearance, and English, Simplified Chinese, and Japanese localization.
- Independent Keep Mac Awake control, either while Mamori runs or for a custom duration. Display sleep and screen locking remain available. Normal Quit releases the assertion.
- Searchable installed-app selection and optional automatic quit after a **confirmed** VPN loss. The option is off by default; delayed force quit is separate. Unreadable VPN evidence does not trigger application termination.
- Apple-signed privileged helper with authenticated XPC, narrow operations, owned PF resources, recovery journaling, and restoration acknowledgment. A local Apple Development build can use this path after explicit macOS approval; an ad-hoc build cannot.
- Read-only GlobalProtect gateway and tunnel discovery after helper setup. Helper-reported evidence drives the active guard status. Default-deny rules remain in place after a manual VPN disconnection.
- GlobalProtect client recognition includes the exact `com.paloaltonetworks.globalprotect.client` identifier. Starting a configured guard now delegates VPN validation to the authenticated helper instead of redundantly requiring a positive advisory UI observation; this removes a false startup rejection without bypassing helper checks.
- Ordered PF readback, policy journaling before changes, interruption recovery, and boot-aware handling of PF enable references. Two sampled external IPv4 routes still do not prove a full tunnel.
- Complete Uninstall, after power release, firewall restoration, and service unregistration: permanently remove the running validated production app and the current user's exact owned data paths. Protected, read-only, or translocated installs report incomplete removal. Other copies, downloads, source, other users' data, and system logs are outside its scope.
- A separate `Mamori Preview.app` with simulated power, VPN, firewall, application-quit, and uninstall effects. It contains no privileged helper; its app catalog and icons are read from the Mac.
- Explicit `auto`, `dev`, `developerID`, and `adhoc` build modes; inside-out signing; static bundle validation; isolated preview output; and public packaging that refuses Apple Development builds. Developer ID notarization is an explicit optional workflow.

## Verification performed

The aggregate Swift suite passed **78 tests with 0 failures**: 19 guard-engine, 2 helper-evidence, 9 guard-policy, 20 session, 6 pure VPN-observation, 4 observer-identifier, 10 uninstall, and 8 app-model tests. Synthetic inputs, fake command runners, and temporary files cover behavior without registering the helper or changing live networking.

Six additional synthetic bundle checks passed: valid bundles, code tampering, a wrong daemon executable path, unwanted automatic startup, a helper in the preview, and a wrong helper identifier. App and helper compilation, an Apple Development signed local bundle, and an isolated ad-hoc preview bundle passed static validation. Ad-hoc ZIP packaging passed, and the public packager rejected the local Apple Development build as intended. A non-activating `pfctl -n -v` fixture parse also passed; this checks syntax, not enforcement.

Native preview checks covered English, Chinese, and Japanese settings, the complete-uninstall confirmation and no-removal simulation, a retained blocked state after simulated VPN loss, and Restore & Quit. Earlier checks also covered app selection and awake duration. Preview UI review is separate from live guard verification.

The earlier 0.2.0 build 2 development app was installed from the clean ZIP into `/Applications/Mamori.app`. Deep and strict signature verification passed, and a running process from that exact installed path was confirmed. The UI automation tool could not attach to the menu-bar app, so visual inspection of the installed real app was not verified; the safe-preview UI checks above still stand. Real helper setup, live network enforcement, and complete-uninstall integration remain untested.

No real VPN was disconnected, no helper was registered, no PF rules were activated, and no user work app was terminated during these checks. Raw logs, app inventories, build products, and temporary work files are excluded from the public repository. No Developer ID identity is available for this build, so the public notarization path has not been exercised.

## Remaining before a validated network-protection release

1. Exercise signed helper approval, recovery, normal Quit, and complete uninstall on a controlled test Mac.
2. Validate packet behavior in a separately authorized environment: existing connections, IPv4/IPv6, DNS, UDP/QUIC, narrow gateway and authentication exceptions, tunnel replacement, network transitions, and process failures.
3. Confirm compatibility with specific GlobalProtect versions and strengthen VPN evidence where needed. Do not infer universal VPN support from the generic tunnel interface.
4. Obtain Developer ID signing and validate the notarization and public distribution workflow.
5. Review the unsupported PF integration assumption before wider distribution and choose a suitable long-term enforcement approach.

Automatic VPN reconnection, launch at login, telemetry, erasure of system or terminal history, and guarantees about remote AI job uptime are outside this version.

See [Signing](Signing.md), [Network guard](NetworkGuard.md), [Behavior](Behavior.md), and [Installation and removal](Installation.md) for the implementation boundaries.

## 简体中文

此前的 0.2.0 build 2 本地开发版已从干净 ZIP 安装到 `/Applications/Mamori.app`，通过完整、严格的签名校验，并确认从该路径启动。界面自动化工具未能连接菜单栏应用，因此未完成已安装真实应用的视觉检查；此前安全预览的界面检查仍有效。真实后台服务设置、网络阻断及完整卸载的集成验证仍未进行。

0.2.0 已实现真实后台服务、断线阻断、可选退出应用和完整卸载流程；本机 Apple Development 签名构建已通过静态校验。78 项 Swift 测试通过：19 项守护引擎、2 项后台连接证据、9 项网络策略、20 项会话、6 项纯 VPN 观察、4 项观察器标识匹配、10 项卸载及 8 项应用模型；另有 6 项合成应用包检查通过。真实服务安装、VPN 断线后的网络效果及系统卸载仍需单独授权的实机验证；开发期间没有断开用户 VPN、启用 PF 规则或退出工作应用。公开的 `v0.1.0-preview` 仍是旧版受限预览，不能作为新版防护效果的证明。详见[中文项目说明](../README.zh-CN.md)。

已补充对准确的 `com.paloaltonetworks.globalprotect.client` 标识的识别。已配置守护的启动校验交给经过身份认证的后台服务，不再因菜单栏的辅助观察未确认连接而提前拒绝；后台验证仍然保留。

## 日本語

先の 0.2.0 build 2 ローカル開発版をクリーンな ZIP から `/Applications/Mamori.app` にインストールし、再帰的かつ厳密な署名検証と、そのパスからの起動を確認しました。UI 自動化ツールはメニューバーアプリに接続できず、インストール済み実アプリの画面確認は未検証です。安全なプレビューの画面確認結果は有効ですが、実ヘルパーの設定、通信制限、完全アンインストールの統合検証は未実施です。

0.2.0 では実際のヘルパー、切断時の通信制限、任意のアプリ終了、完全アンインストール処理を実装しました。ローカルの Apple Development 署名ビルドは静的検証を通過しました。Swift テストは 78 件成功し、内訳はガードエンジン 19 件、ヘルパーの接続判定 2 件、通信ポリシー 9 件、セッション 20 件、純粋な VPN 観測 6 件、オブザーバーの識別子判定 4 件、アンインストール 10 件、アプリモデル 8 件です。別途、合成アプリバンドル検査 6 件も成功しています。サービスの登録、実際の VPN 切断時の通信、システム上の削除は、別途許可された環境での検証が必要です。開発確認中にユーザーの VPN を切断したり、PF ルールを有効化したり、作業用アプリを終了したりしていません。公開中の `v0.1.0-preview` は制限のある旧プレビューです。[日本語のプロジェクト説明](../README.ja.md)も参照してください。

正確な `com.paloaltonetworks.globalprotect.client` 識別子の認識を追加しました。設定済みの保護を開始するときは認証済みヘルパーが接続を検証し、UI の補助的な観測だけで開始を拒否しないよう修正しています。ヘルパーの検証は省略しません。
