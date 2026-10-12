# Development progress

[English](../README.md) · [简体中文](../README.zh-CN.md) · [日本語](../README.ja.md)

Updated: 2026-10-12 (Asia/Taipei)

Status: local MVP and safe interactive preview. The network-guard implementation is experimental and has not been validated against a live VPN.

## Completed

- Native SwiftUI/AppKit menu-bar application for macOS 14+, using Swift 6 and no remote package dependencies.
- Compact 280 × 290 pt interface with English, Simplified Chinese, and Japanese localization.
- System sans-serif typography throughout, adaptive macOS light/dark appearance, standard controls, system-accent Start and red Stop buttons, and a left-aligned Choose apps action. Decorative hero graphics and oversized page headings have been removed.
- Keep Mac Awake through a process-owned power assertion: while Mamori runs or for a custom 1–10,080 minute duration. Normal Quit cancels it; display sleep and screen locking remain available.
- Searchable installed-application catalog, including stopped applications. Selection does not launch an app. Automatic quit is optional and off by default, with optional delayed force quit and process-identity rechecks.
- Read-only GlobalProtect observation and a pure session reducer covering lifecycle, stale callbacks, restoration, power leases, and application-quit tickets.
- Narrow privileged helper implementation using authenticated XPC, owned PF resources, a recovery journal, and restoration acknowledgment. Its activation and compatibility remain unvalidated on a real connection.
- A separate `Mamori Preview.app` bundle that always uses simulated VPN, power, firewall, and quit effects. Its only real application interaction is reading the installed-app catalog and icons.
- Local build, safe preview, screenshot capture, and isolated test scripts; documentation of behavior, installation, removal, and network limitations.
- Reproducible development-download packaging with separate normal and preview apps, a drag-to-Applications disk image, Quick Start guides, and SHA-256 checksums. The initial app downloads target Apple silicon and remain ad-hoc signed and non-notarized.

## Verification performed

The recorded core suite passed **34 tests with 0 failures**: 20 session tests, 8 guard-policy tests, and 6 VPN-observation tests. These use synthetic inputs and exercise pure logic; they do not establish live network enforcement.

The app and helper compile. Preview checks cover English, Chinese, and Japanese home screens; connected and blocked simulations; installed-app selection and search; awake duration; settings; and normal Quit. The final native-style presentation revision was rebuilt and checked visually without repeating the complete suite.

No real VPN was disconnected, no helper was registered, no PF rules were activated, no power assertion was acquired, and no user work app was terminated during development verification. Raw local logs, desktop reference captures, installed-app inventory screenshots, build products, and temporary work files are excluded from the public repository.

## Remaining before a usable network-protection release

1. Configure Developer ID signing and distribution, including the bundled background service and notarization.
2. Validate registration, authorization, recovery, normal Quit, and removal on a controlled test Mac.
3. Validate actual network enforcement in a separately authorized environment: existing connections, IPv4/IPv6, DNS, UDP/QUIC, gateway/SSO behavior, tunnel replacement, network transitions, and process failures.
4. Confirm compatibility with specific GlobalProtect versions and strengthen VPN evidence where needed. Two sampled external IPv4 routes do not prove a full tunnel.
5. Review the unsupported PF integration assumption and choose an appropriate long-term enforcement approach before wider distribution.

Universal VPN support, automatic reconnection, launch at login, telemetry, and erasure of macOS or terminal history are outside this MVP.

## 简体中文

当前已完成原生 macOS 最小版本和安全交互预览，支持中英日界面、全系统无衬线字体、自定义保持唤醒时长、已安装应用选择，以及模拟 VPN 断线后的自动退出流程。34 项核心测试通过；最新字体修改已重新构建并检查界面。验证期间没有断开真实 VPN、启用防火墙规则、安装后台服务或退出用户正在使用的应用。

真实断网保护仍处于实验阶段，需要完成 Developer ID 签名、后台服务授权、恢复与卸载验证，以及在单独授权的测试环境中进行网络测试。当前不承诺支持所有 VPN，也不包含自动重连。详见[中文项目说明](../README.zh-CN.md)。

## 日本語

ネイティブ macOS アプリの最小構成と、安全な操作プレビューを実装済みです。英語・簡体字中国語・日本語の UI、システムのサンセリフ書体、時間指定のスリープ抑止、インストール済みアプリの選択、VPN 切断時の自動終了シミュレーションに対応しています。コアテスト 34 件が成功し、最新の書体変更は再ビルドと画面確認で検証しました。検証中に実際の VPN の切断、ファイアウォール設定の適用、バックグラウンドサービスの登録、作業中のアプリの終了は行っていません。

実際のネットワーク遮断は未検証の実験的機能です。Developer ID 署名、サービスの承認、復元・削除手順、別途許可された環境でのネットワーク検証が必要です。すべての VPN への対応や自動再接続は含みません。[日本語のプロジェクト説明](../README.ja.md)も参照してください。
