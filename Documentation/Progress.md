# Development progress

[English](../README.md) · [简体中文](../README.zh-CN.md) · [日本語](../README.ja.md)

Updated: 2026-10-14 (Asia/Taipei)

Status: **0.2.1 local development build, build 6**. The start/quit correction is installed at `/Applications/Mamori.app`, signed, and verified through a live guard cycle and normal macOS Quit. The published `v0.1.0-preview` downloads remain older, limited ad-hoc builds.

## Start and quit correction (build 6)

A live administrator read-only check confirmed PF was disabled with zero states, the owned anchor and recovery directory were absent, and querying that missing anchor returned `pfctl: DIOCGETRULES: Invalid argument`. Both fresh activation and no-journal restoration queried the missing anchor directly. The app requires a successful inactive acknowledgment before quitting, so the same defect caused both repeated start failures and the quit loop.

The helper now proves existence or absence through stable parent listings before reading its own anchor. Unknown diagnostics, changing topology, and unjournaled rules remain errors. Inspection failures report the exact command, exit status, and bounded diagnostic. The test fake now reproduces a missing anchor's failure instead of incorrectly returning empty success.

Validation: the two new start/quit regressions fail against unchanged main and pass with the fix. The final sources have 98 passing Swift tests (40 guard tests, 30 policy/session tests, 8 app-model tests, and 20 observation/uninstall tests). Release compilation, Apple Development signing with the installed app's team, and static bundle validation passed. The installed app matches the repaired signed build and passes deep, strict signature verification. Raw host diagnostics, private VPN configuration, signing material, and temporary verifier files are not part of the repository.

### Live verification on 2026-10-14

- Installed 0.2.1 (build 6) at `/Applications/Mamori.app` with the existing signing team and restarted its helper. The installed helper hash matches the verified build.
- A temporary same-team signed client exercised the existing authenticated XPC contract: inactive status, successful GlobalProtect discovery, `start → protected`, periodic `status → protected`, and `stop → inactive`. It automatically requested restoration on failure and did not control or disconnect the VPN.
- A subsequent administrator read-only inspection confirmed PF disabled, zero states, no PF starter references, and no recovery directory. PF retained the allocated owned anchor name after flushing; this is distinct from active rules or a retained enable reference.
- Launched the installed application. Its pending-restoration preference cleared after the helper's inactive acknowledgment. A main-thread sample showed the normal event loop rather than a hang.
- Sent a normal macOS application-termination request (not a signal or force quit). The installed app acknowledged restoration and exited; the helper then exited. The pending-restoration flag remained false.
- Native UI automation could launch the accessory app but timed out while obtaining its accessibility state. No new visual UI verification is claimed; normal termination was checked through the macOS application lifecycle API.

This verifies the reported start/quit failures and active-session cleanup on the local Mac. It does not claim exhaustive packet-leak protection, a tested deliberate VPN disconnection, full-tunnel proof, or real complete-uninstall integration. No work application was terminated and the connected VPN was left unchanged. The local development-signed binary is not published as a notarized download.

The sections below record earlier builds and their validation boundaries.

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

The aggregate Swift suite passed **89 tests with 0 failures**: 22 guard-engine, 2 helper-evidence, 3 policy-compiler, 4 PF-inspector, 10 guard-policy, 20 session, 6 pure VPN-observation, 4 observer-identifier, 10 uninstall, and 8 app-model tests. Synthetic inputs, fake command runners, and temporary files cover behavior without registering the helper or changing live networking.

Six earlier synthetic bundle checks passed and were not rerun for this reader fix: valid bundles, code tampering, a wrong daemon executable path, unwanted automatic startup, a helper in the preview, and a wrong helper identifier. Earlier app and helper builds, an Apple Development signed local bundle, and an isolated ad-hoc preview bundle passed static validation. Ad-hoc ZIP packaging passed, and the public packager rejected the local Apple Development build as intended. A non-activating `pfctl -n -v` fixture parse also passed; this checks syntax, not enforcement.

Native preview checks covered English, Chinese, and Japanese settings, the complete-uninstall confirmation and no-removal simulation, a retained blocked state after simulated VPN loss, and Restore & Quit. Earlier checks also covered app selection and awake duration. Preview UI review is separate from live guard verification.

Before updating, the user chose Restore & Quit for the failed pre-enable session. Both exact app/helper processes and the recovery directory were confirmed absent. Build 4 then replaced build 3 at `/Applications/Mamori.app` with the same signing team; deep and strict signature verification passed. This confirms cleanup of that failed session, not restoration after active PF enforcement.

Build 4 launched successfully through UI automation. The real home displayed “Protection inactive,” a detected GlobalProtect VPN, and the Start guarding control. Settings displayed “Background service available.” This is limited real home/settings observation; no guard session was started. Safe-preview UI checks still stand. Successful enforcement and complete-uninstall integration remain unverified.

Automated and preview checks did not register the helper or exercise live networking. Separately, the user installed the service and manually attempted to start guarding. Read-only diagnostics confirmed a running helper and installed owned rules, but no recorded PF enable request or token from Mamori. No live VPN disconnection or successful activation test was performed by the development agents, and no user work app was terminated. Raw logs, app inventories, build products, and temporary work files are excluded from the public repository. No Developer ID identity is available for this build, so the public notarization path has not been exercised.

## PF rule-reader correction

A user-initiated guard start reported “Another firewall policy changed.” Redacted read-only diagnostics showed that the root and owned installed rules matched the recovery journal; Mamori had not yet recorded an enable request or obtained an enable token. macOS wildcard recursive rule reads could return incomplete output and a `DIOCGETRULES` error on stderr while still exiting with status 0.

The source fix enumerates concrete anchors instead of relying on the wildcard read and rejects stderr errors even when the command reports success. Exact rule comparisons and existing safety checks remain in place. The new reader passed a read-only probe on the real Mac: four anchors and nine owned rules were read, root/owned/full-tree comparisons matched, PF was disabled, and the journal recorded neither an enable request nor a token.

That probe also exposed an overly strict syntax diagnostic check. The dedicated policy compiler now accepts only the exact known generic `-f` notice and still rejects errors. Connected (nine-rule) and blocked (eight-rule) fixtures passed unprivileged syntax checks that require `-n`, so PF was not activated. The journal's syntax was not rechecked by the host probe after this correction. These are rule-reading and syntax results, not an enforcement test.

The 89-test aggregate covers both corrections. Build 4 has completed release compilation, Apple Development signing, and static bundle validation following the user's macOS approval. The signed build is now installed as build 4; its initial home and Settings were observed without starting protection.

## App picker alignment (build 5)

App rows now fill the available width and align to the leading edge. Native checkboxes sit in a centered row beside the icon and text, including two-line status labels. Clicking either the checkbox or the app label updates the same selection; VoiceOver retains the app name, checked state, and status hint.

The signed release build and static bundle validation passed. Native safe-preview inspection confirmed left alignment, vertical centering, and selection by checkbox and label. Build 5 replaced the stopped build 4 with a matching signing team and passed deep, strict signature verification. This small UI change did not rerun the earlier 89-test backend suite.

中文：build 5 调整应用列表左对齐和复选框垂直居中，保留点击名称选择及无障碍状态提示。原生安全预览、编译和签名检查通过，更新版已安装。

日本語：build 5 でアプリ行を左揃えにし、チェックボックスを垂直中央に配置しました。名前のクリックとアクセシビリティの状態通知も維持しています。安全なネイティブプレビュー、ビルド、署名検証を通過し、更新版をインストールしました。

## Remaining before a validated network-protection release

1. Extend the verified local start/restore/quit cycle to interrupted-session recovery and complete uninstall on a controlled test Mac.
2. Validate packet behavior in a separately authorized environment: existing connections, IPv4/IPv6, DNS, UDP/QUIC, narrow gateway and authentication exceptions, tunnel replacement, network transitions, and process failures.
3. Confirm compatibility with specific GlobalProtect versions and strengthen VPN evidence where needed. Do not infer universal VPN support from the generic tunnel interface.
4. Obtain Developer ID signing and validate the notarization and public distribution workflow.
5. Review the unsupported PF integration assumption before wider distribution and choose a suitable long-term enforcement approach.

Automatic VPN reconnection, launch at login, telemetry, erasure of system or terminal history, and guarantees about remote AI job uptime are outside this version.

See [Signing](Signing.md), [Network guard](NetworkGuard.md), [Behavior](Behavior.md), and [Installation and removal](Installation.md) for the implementation boundaries.

## 简体中文

更新前，用户选择「还原并退出」，已确认此前失败会话的应用和后台进程均结束、恢复目录已移除。随后将相同签名团队的 build 4 安装到 `/Applications/Mamori.app`，替换 build 3，并通过完整、严格的签名校验。这验证的是启用 PF 前失败会话的清理，不是启用 PF 后的还原。

build 4 已经由界面自动化成功启动，真实主页显示「Protection inactive」、检测到 GlobalProtect VPN 及开始守护按钮；设置页显示「Background service available」。这次只观察了真实主页和设置，没有开启守护；安全预览检查仍有效。有效阻断和完整卸载仍未获验证。

0.2.0 已实现真实后台服务、断线阻断、可选退出应用和完整卸载流程；本机 Apple Development 签名构建已通过静态校验。89 项 Swift 测试通过：22 项守护引擎、2 项后台连接证据、3 项策略编译器、4 项 PF 读取器、10 项网络策略、20 项会话、6 项纯 VPN 观察、4 项观察器标识匹配、10 项卸载及 8 项应用模型。另有此前通过的 6 项合成应用包检查，本次未重新运行。用户已安装真实服务；只读诊断确认已有自有规则，但 Mamori 尚无启用 PF 的请求记录或令牌。VPN 断线后的阻断效果及系统卸载仍需实机验证；开发代理没有执行真实断线或成功启用测试，也没有退出工作应用。公开的 `v0.1.0-preview` 仍是旧版受限预览，不能作为新版防护效果的证明。详见[中文项目说明](../README.zh-CN.md)。

已补充对准确的 `com.paloaltonetworks.globalprotect.client` 标识的识别。已配置守护的启动校验交给经过身份认证的后台服务，不再因菜单栏的辅助观察未确认连接而提前拒绝；后台验证仍然保留。

本次读取修复改为枚举具体 PF anchor，保留完整规则比对和错误检查。本机只读探测已读取 4 个 anchor、9 条自有规则，根规则、自有规则及完整规则树均匹配；当时 PF 未启用，日志中没有启用请求或令牌。

探测同时发现语法诊断检查过严，已修正为专用策略编译器只接受完全匹配的通用 `-f` 提示。连接态 9 条、阻断态 8 条规则均通过无特权、强制使用 `-n` 的语法检查，没有启用 PF；修正后未重新对主机恢复日志中的语法做探测，不能将这些结果当作阻断验证。89 项测试覆盖两处修复。用户已在 macOS 授权，build 4 已完成 release 编译、Apple Development 签名及静态应用包校验，并已安装；主页和设置页已在未开启守护的状态下观察。

## 日本語

更新前にユーザーが「復元して終了」を実行し、失敗したセッションのアプリとヘルパーのプロセス、および復旧ディレクトリが存在しないことを確認しました。同じ署名チームの build 4 で `/Applications/Mamori.app` の build 3 を置き換え、再帰的かつ厳密な署名検証を通過しました。これは PF 有効化前に失敗したセッションの整理であり、稼働中の PF からの復元検証ではありません。

build 4 は UI 自動化から正常に起動しました。実際のホームでは「Protection inactive」、GlobalProtect VPN の検出、保護開始ボタンを確認し、設定では「Background service available」を確認しました。ホームと設定の限定的な確認で、保護は開始していません。安全なプレビューの確認結果は有効ですが、実通信の制限と完全アンインストールは未検証です。

0.2.0 では実際のヘルパー、切断時の通信制限、任意のアプリ終了、完全アンインストール処理を実装しました。ローカルの Apple Development 署名ビルドは静的検証を通過しました。Swift テストは 89 件成功し、内訳はガードエンジン 22 件、ヘルパーの接続判定 2 件、ポリシーコンパイラー 3 件、PF 読み取り 4 件、通信ポリシー 10 件、セッション 20 件、純粋な VPN 観測 6 件、オブザーバーの識別子判定 4 件、アンインストール 10 件、アプリモデル 8 件です。以前の合成バンドル検査 6 件も成功していますが、今回は再実行していません。サービスはユーザーが登録済みです。読み取り専用の診断では自分のルールを確認しましたが、Mamori による PF 有効化の要求記録やトークンはありませんでした。VPN 切断時の通信制限と削除は実機検証が必要です。開発エージェントは実際の VPN 切断や有効化の成功試験を行わず、作業用アプリも終了していません。公開中の `v0.1.0-preview` は制限のある旧プレビューです。[日本語のプロジェクト説明](../README.ja.md)も参照してください。

正確な `com.paloaltonetworks.globalprotect.client` 識別子の認識を追加しました。設定済みの保護を開始するときは認証済みヘルパーが接続を検証し、UI の補助的な観測だけで開始を拒否しないよう修正しています。ヘルパーの検証は省略しません。

読み取り処理は具体的な PF anchor を列挙し、厳密なルール比較とエラー確認を維持します。実機上の読み取り専用プローブでは 4 個の anchor と 9 個の専用ルールを読み取り、ルート・専用ルール・ツリー全体が一致しました。PF は無効で、ジャーナルに有効化要求やトークンはありませんでした。

同時に見つかった構文診断の過剰な拒否を修正し、専用コンパイラーは既知の汎用 `-f` 通知と完全一致する場合だけ受け入れます。接続時 9 ルールと遮断時 8 ルールは、管理者権限なしで必ず `-n` を付ける構文検査を通過し、PF は有効化していません。修正後に実機のジャーナル内の構文を再検査したわけではなく、通信制限の検証でもありません。89 件のテストは両方の修正を含みます。ユーザーの macOS 承認後、build 4 の release ビルド、Apple Development 署名、静的バンドル検証が完了しました。build 4 はインストール済みで、保護を開始せずにホームと設定を確認しました。
