import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", chinese = "zh-Hans", japanese = "ja"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .english: "English"
        case .chinese: "简体中文"
        case .japanese: "日本語"
        }
    }
}

enum Copy: CaseIterable {
    case tagline, ready, inactive, protected, blocked, working, attention
    case vpnDetected, vpnUnconfirmed, vpnDisconnected, vpnConnection
    case keepAwake, always, customDuration, minutes, untilQuit, remaining, awakeOff
    case autoQuit, off, on, chooseApps, selectedApps, noApps, appsExplanation
    case start, stop, settings, restoreQuit, back, done, language
    case preview, previewNotice, simulation, simulateLoss, simulateRecovery, resetDemo
    case networkProtection, installHelper, removeHelper, helperNeeded, helperReady
    case tunnel, gateways, gatewayHelp, refresh, details, noEvidence
    case wakeHelp, expired, forceQuit, forceHelp, normalQuit, quitHelp
    case monitoring, connectionDetails, build, readyToTest, blockedDetail, protectedDetail
    case shuttingDown, error, retry, notRunning, gracefulOnly, quitRequested, forceRequested
    case noSelection, pending, configure, safetyNotice, platformNotice, durationLabel, searchApps
    case completeUninstall, uninstallConfirm, uninstallExplanation, uninstalling, uninstallFailed, uninstallPreview, cancel
    case approveHelper, detectConnection, manualDisconnectProtection
    case tunnelHelp, gatewayRequired, gatewayInvalid

    func text(_ language: AppLanguage) -> String {
        let value: (String, String, String)
        switch self {
        case .tagline: value = ("QUIETLY KEEPS YOU SAFE", "安心守候", "そっと、見守る")
        case .ready: value = ("Ready to guard", "准备守护", "守る準備ができました")
        case .inactive: value = ("Protection inactive", "保护尚未开启", "保護はオフです")
        case .protected: value = ("Guarding", "守护中", "保護中")
        case .blocked: value = ("Network blocked", "网络已阻断", "通信を遮断中")
        case .working: value = ("Preparing protection", "正在准备保护", "保護を準備しています")
        case .attention: value = ("Needs attention", "需要处理", "確認が必要です")
        case .vpnDetected: value = ("VPN detected", "已检测到 VPN", "VPN を検出しました")
        case .vpnUnconfirmed: value = ("Connection not verified", "连接尚未确认", "接続を確認できません")
        case .vpnDisconnected: value = ("VPN disconnected", "VPN 已断开", "VPN が切断されました")
        case .vpnConnection: value = ("VPN connection", "VPN 连接", "VPN 接続")
        case .keepAwake: value = ("Keep Mac awake", "保持 Mac 唤醒", "Mac のスリープを防ぐ")
        case .always: value = ("Always", "一直保持", "常時")
        case .customDuration: value = ("Custom duration", "自定义时长", "時間を指定")
        case .minutes: value = ("minutes", "分钟", "分")
        case .untilQuit: value = ("Until you quit Mamori", "直到退出 Mamori", "Mamori を終了するまで")
        case .remaining: value = ("remaining", "后结束", "後に終了")
        case .awakeOff: value = ("Mac can sleep normally", "Mac 可正常休眠", "通常どおりスリープします")
        case .autoQuit: value = ("Auto-quit apps", "自动退出应用", "アプリを自動終了")
        case .off: value = ("Off", "关闭", "オフ")
        case .on: value = ("On · while guarding", "开启 · 守护期间生效", "オン · 保護中のみ")
        case .chooseApps: value = ("Choose apps", "选择应用", "アプリを選ぶ")
        case .selectedApps: value = ("Selected apps", "已选应用", "選択したアプリ")
        case .noApps: value = ("No matching apps", "没有匹配的应用", "該当するアプリはありません")
        case .appsExplanation: value = ("Quit selected apps if the VPN drops while guarding. Only running apps are affected. Browsers and terminals close their windows and sessions; unsaved work may be lost.", "守护期间 VPN 断开时退出所选应用，仅影响当时运行的应用。浏览器和终端会关闭窗口及会话，未保存的内容可能丢失。", "保護中に VPN が切断されたら、選択した起動中のアプリを終了します。ブラウザとターミナルのウインドウやセッションが閉じ、未保存の内容が失われる場合があります。")
        case .start: value = ("Start guarding", "开始守护", "保護を開始")
        case .stop: value = ("Stop guarding", "停止守护", "保護を停止")
        case .settings: value = ("Settings", "设置", "設定")
        case .restoreQuit: value = ("Restore & Quit", "还原并退出", "復元して終了")
        case .back: value = ("Back", "返回", "戻る")
        case .done: value = ("Done", "完成", "完了")
        case .language: value = ("Language", "语言", "言語")
        case .preview: value = ("PREVIEW", "预览", "プレビュー")
        case .previewNotice: value = ("Simulation only. Your VPN, network, power settings, and apps are untouched.", "仅为模拟，不会更改你的 VPN、网络、电源设置或退出真实应用。", "シミュレーションです。VPN、ネットワーク、電源設定、実際のアプリには影響しません。")
        case .simulation: value = ("Safe simulation", "安全模拟", "安全なシミュレーション")
        case .simulateLoss: value = ("Simulate VPN loss", "模拟 VPN 断开", "VPN 切断をシミュレート")
        case .simulateRecovery: value = ("Simulate VPN recovery", "模拟 VPN 恢复", "VPN 復旧をシミュレート")
        case .resetDemo: value = ("Reset preview", "重置预览", "プレビューをリセット")
        case .networkProtection: value = ("Network protection", "网络保护", "ネットワーク保護")
        case .installHelper: value = ("Set up protection", "设置保护服务", "保護を設定")
        case .removeHelper: value = ("Remove background service", "移除后台服务", "バックグラウンドサービスを削除")
        case .helperNeeded: value = ("Background service required", "需要后台服务", "バックグラウンドサービスが必要です")
        case .helperReady: value = ("Background service available", "后台服务可用", "バックグラウンドサービスが利用可能です")
        case .tunnel: value = ("VPN tunnel interface", "VPN 隧道接口", "VPN トンネルインターフェイス")
        case .gateways: value = ("VPN gateway addresses", "VPN 网关地址", "VPN ゲートウェイアドレス")
        case .gatewayHelp: value = ("Enter the exact public IP addresses of your VPN gateway, separated by commas. Only these endpoints are allowed outside the tunnel.", "输入 VPN 网关的公网 IP 地址，以逗号分隔。隧道外仅允许访问这些端点。", "VPN ゲートウェイの正確な公開 IP アドレスをカンマで区切って入力してください。トンネル外ではこの接続先のみ許可されます。")
        case .tunnelHelp: value = ("Use Detect connection to find the active VPN tunnel, or enter its utun interface.", "点击「探测连接」查找当前 VPN 隧道，或填写其 utun 接口。", "「接続を検出」で現在の VPN トンネルを調べるか、utun インターフェイスを入力してください。")
        case .gatewayRequired: value = ("Use Detect connection, or enter 1–8 VPN gateway IPv4 addresses.", "点击「探测连接」，或填写 1–8 个 VPN 网关 IPv4 地址。", "「接続を検出」を使うか、VPN ゲートウェイの IPv4 アドレスを 1～8 個入力してください。")
        case .gatewayInvalid: value = ("Enter the VPN gateway's public IPv4 addresses, separated by commas. Hostnames and private addresses are not supported.", "请填写 VPN 网关的公网 IPv4 地址，以逗号分隔。当前不支持域名或私有地址。", "VPN ゲートウェイの公開 IPv4 アドレスをカンマで区切って入力してください。ホスト名とプライベートアドレスには対応していません。")
        case .refresh: value = ("Refresh", "刷新", "更新")
        case .details: value = ("Technical details", "技术信息", "技術情報")
        case .noEvidence: value = ("No connection evidence is available.", "暂无连接信息。", "接続情報を取得できません。")
        case .wakeHelp: value = ("The display can turn off and your Mac can lock. This prevents idle sleep, not lid-close or a manual sleep command.", "屏幕可以关闭，Mac 可以锁定。此功能阻止空闲休眠，不阻止合盖或手动休眠。", "画面の消灯とロックは可能です。アイドル時のスリープのみを防ぎます。ふたを閉じた場合や手動のスリープは対象外です。")
        case .expired: value = ("Keep-awake timer finished", "保醒计时已结束", "スリープ防止の時間が終了しました")
        case .forceQuit: value = ("Force quit after 5 seconds", "5 秒后强制退出", "5 秒後に強制終了")
        case .forceHelp: value = ("Optional. Use only for apps you are willing to close without saving.", "可选，仅对可接受丢失未保存内容的应用启用。", "任意です。未保存の内容を失ってもよいアプリにのみ使用してください。")
        case .normalQuit: value = ("When Mamori quits", "退出 Mamori 时", "Mamori の終了時")
        case .quitHelp: value = ("Stop auto-quit, release keep-awake, and restore Mamori's network rules before exiting. Closing this panel keeps Mamori running.", "停止自动退出应用、取消保醒并还原 Mamori 的网络规则后退出。关闭此面板不会退出 Mamori。", "アプリの自動終了とスリープ防止を停止し、Mamori のネットワークルールを復元してから終了します。このパネルを閉じても Mamori は動作を続けます。")
        case .monitoring: value = ("Waiting for the next VPN drop", "等待下一次 VPN 断开", "次の VPN 切断を待っています")
        case .connectionDetails: value = ("Connection details", "连接信息", "接続の詳細")
        case .build: value = ("Mamori 0.2", "Mamori 0.2", "Mamori 0.2")
        case .readyToTest: value = ("Ready for a safe test", "可以开始安全测试", "安全なテストを開始できます")
        case .blockedDetail: value = ("VPN lost · Network blocked", "VPN 已断开 · 网络已阻断", "VPN 切断 · ネットワークを遮断中")
        case .protectedDetail: value = ("Traffic stays inside your VPN", "流量仅通过 VPN 传输", "通信は VPN 内に限定されています")
        case .shuttingDown: value = ("Restoring your Mac…", "正在还原 Mac…", "Mac を復元しています…")
        case .error: value = ("Could not complete the action", "操作未完成", "操作を完了できませんでした")
        case .retry: value = ("Try again", "重试", "再試行")
        case .notRunning: value = ("Not running", "未运行", "停止中")
        case .gracefulOnly: value = ("Ask apps to quit normally", "请求应用正常退出", "通常の終了を要求")
        case .quitRequested: value = ("Quit requested", "已请求退出", "終了を要求しました")
        case .forceRequested: value = ("Force quit requested", "已请求强制退出", "強制終了を要求しました")
        case .noSelection: value = ("No apps selected", "尚未选择应用", "アプリが未選択です")
        case .pending: value = ("Please wait…", "请稍候…", "お待ちください…")
        case .configure: value = ("Configure protection", "配置保护", "保護を構成")
        case .safetyNotice: value = ("Protection starts only after the background service verifies its rules. Setup may require administrator approval.", "后台服务验证规则生效后才会开始保护。设置可能需要管理员授权。", "バックグラウンドサービスがルールを検証してから保護を開始します。設定には管理者の承認が必要な場合があります。")
        case .platformNotice: value = ("Use an Apple-signed Mamori build to set up network protection. Keep-awake remains available in this build.", "请使用 Apple 证书签名的 Mamori 版本设置网络保护。当前版本仍可使用保醒。", "ネットワーク保護には Apple 証明書で署名された Mamori が必要です。このビルドでもスリープ防止は利用できます。")
        case .durationLabel: value = ("Duration (1–10,080 minutes)", "时长（1–10,080 分钟）", "時間（1〜10,080 分）")
        case .searchApps: value = ("Search installed apps", "搜索已安装应用", "インストール済みアプリを検索")
        case .completeUninstall: value = ("Complete Uninstall…", "完整卸载…", "完全にアンインストール…")
        case .uninstallConfirm: value = ("Uninstall Mamori", "卸载 Mamori", "Mamori をアンインストール")
        case .uninstallExplanation: value = ("Restore networking, stop keep-awake and auto-quit, then permanently delete this copy of Mamori, its background service, and its settings and caches for your account. This cannot be undone. macOS-managed logs and other copies are not removed.", "还原网络，停止保醒与自动退出应用，然后永久删除当前 Mamori、后台服务及当前账户下的设置和缓存。此操作无法撤销。不会删除 macOS 管理的系统日志或其他 App 副本。", "ネットワークを復元し、スリープ防止とアプリの自動終了を停止して、この Mamori とバックグラウンドサービス、現在のアカウントの設定とキャッシュを完全に削除します。この操作は取り消せません。macOS のシステムログや別のコピーは削除しません。")
        case .uninstalling: value = ("Uninstalling…", "正在卸载…", "アンインストール中…")
        case .uninstallFailed: value = ("Uninstall could not finish. Mamori is still open so you can retry.", "卸载未完成。Mamori 保持打开，你可以重试。", "アンインストールを完了できませんでした。再試行できるよう Mamori を開いたままにしています。")
        case .uninstallPreview: value = ("Preview only: no app, settings, or background service was removed.", "仅为预览：未删除任何 App、设置或后台服务。", "プレビューのため、アプリ、設定、バックグラウンドサービスは削除していません。")
        case .cancel: value = ("Cancel", "取消", "キャンセル")
        case .approveHelper: value = ("Open macOS Approval Settings", "打开 macOS 授权设置", "macOS の承認設定を開く")
        case .detectConnection: value = ("Detect VPN connection", "检测 VPN 连接", "VPN 接続を検出")
        case .manualDisconnectProtection: value = ("While guarding, manual disconnects also block direct traffic. Stop guarding or Restore & Quit to allow normal networking.", "守护期间，手动断开 VPN 也会阻断直连。停止守护或还原并退出后恢复正常网络。", "保護中は手動で VPN を切断した場合も直接通信を遮断します。保護の停止、または復元して終了すると通常の通信に戻ります。")
        }
        switch language {
        case .english: return value.0
        case .chinese: return value.1
        case .japanese: return value.2
        }
    }
}
