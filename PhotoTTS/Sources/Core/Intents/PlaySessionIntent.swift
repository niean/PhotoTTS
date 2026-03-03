import AppIntents
import Foundation

// MARK: - Siri 待播放会话的 UserDefaults key
let kSiriPendingSessionId = Constants.UserDefaultsKeys.siriPendingSessionId

// MARK: - 播放绘本意图
struct PlaySessionIntent: AppIntent {
    static var title: LocalizedStringResource = "播放绘本"
    static var description = IntentDescription("用语音指令播放已保存的绘本会话")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "绘本")
    var session: SessionRecordEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 将待播放的 sessionId 写入 UserDefaults，App 激活后读取
        UserDefaults.standard.set(session.id, forKey: kSiriPendingSessionId)
        return .result(dialog: "正在打开《\(session.name)》")
    }
}

// MARK: - App Shortcuts（注册 Siri 短语）
struct PhotoTTSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySessionIntent(),
            phrases: [
                "用\(.applicationName) 播放绘本 \(\.$session)",
                "在\(.applicationName)中 播放绘本 \(\.$session)",
            ],
            shortTitle: "播放绘本",
            systemImageName: "book.fill"
        )
    }
}
