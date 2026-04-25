import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import os.log

// MARK: - 日志记录器
extension os.Logger {
    static let app = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "App")
    static let siri = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "Siri")
    static let audioPlayer = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "AudioPlayer")
    static let camera = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "Camera")
    static let makeView = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "MakeView")
    static let appPages = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "AppPages")
    static let ttsService = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "TTSService")
    static let networkService = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "NetworkService")
    static let settingsManager = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "SettingsManager")
    static let ocrService = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "OCRService")
    static let coordinator = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "Coordinator")
    static let debugLog = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "DebugLog")
    static let sessionRecord = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "SessionRecord")
    static let playHistory = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "PlayHistory")
    static let backgroundMake = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "BackgroundMake")
    static let makeHistory = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "MakeHistory")
    static let llmService = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "LLMService")
    static let peerTransfer = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "PeerTransfer")
}

// MARK: - AppDelegate
class AppDelegate: NSObject, UIApplicationDelegate {}

struct HomePageStartupPreloadSnapshot {
    let items: [SessionRecordMetadata]
    let totalCount: Int
    let playStatsMap: [String: PlayStatInfo]
    let seriesOptions: [String]
    let sortMode: HomeSessionSortMode
}

// MARK: - 应用状态管理
class AppState: ObservableObject {
    @Published var loadingProgress: Double = 0.0
    @Published var loadingMessage = "正在初始化..."

    /// 当前全屏页：nil = 主界面，.loading = 启动页，.imageViewer / .camera = 全屏大图/相机
    @Published var fullScreenKind: FullScreenPageKind? = .loading

    @Published var fullScreenCoverImages: [UIImage] = []
    @Published var fullScreenCoverIndex: Int = 0
    @Published var cameraOverlayImages: [UIImage] = []

    @Published var selectedTab: Int = 0
    @Published var tab0ResetId: Int = 0
    @Published var tab2ResetId: Int = 0
    @Published var tab3ResetId: Int = 0
    @Published var openCameraOnNextRecordAppear: Bool = false
    @Published var openPhotoPickerOnNextRecordAppear: Bool = false
    /// 记录管理里「加载到制作」时写入，制作页 onAppear 消费后置 nil
    @Published var sessionIdToLoadIntoMake: String? = nil
    /// Siri 触发播放的会话记录，PlayView 消费后置 nil
    @Published var sessionRecordToPlay: SessionRecord? = nil
    /// 从记录列表点击制作中记录时写入，制作页消费后置 nil
    @Published var makeTaskIdToReconnect: String? = nil
    /// 播放互斥：当前是否有 PlayView 处于活跃状态，任意时刻只允许一个记录播放
    @Published var isPlayViewActive: Bool = false
    /// 制作完成后跳转到管理Tab编辑页的记录ID，SessionRecordListView 消费后置 nil
    @Published var recordIdToEditInManageTab: String? = nil
    /// 首页 Tab 重选触发器：same-tab tap 时自增，HomePageView 监听后重置到第1页
    @Published var tab0ReselectTrigger: Int = 0
    /// 管理 Tab 重选触发器：same-tab tap 时自增，SessionRecordListView 监听后重置到第1页
    @Published var tab2ReselectTrigger: Int = 0
    @Published private(set) var homePageStartupPreloadSnapshot: HomePageStartupPreloadSnapshot? = nil

    private var hasStartedHomePageStartupPreload = false

    init() {}

    func startHomePageStartupPreloadIfNeeded() {
        guard !hasStartedHomePageStartupPreload else { return }
        hasStartedHomePageStartupPreload = true

        let pageSize = Constants.Pagination.pageSize
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sortMode: HomeSessionSortMode = .list
            let result = SessionRecordManager.shared.getSessionMetadataPage(
                page: 1,
                pageSize: pageSize,
                completedOnly: true,
                sortMode: sortMode,
                caller: "启动预加载-首页首屏"
            )
            let playStatsMap = SessionRecordManager.shared.loadPlayStats(sessionIds: result.items.map(\.id))
            let uncategorized = Constants.GroupDisplay.uncategorizedLabel
            let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(caller: "启动预加载-首页系列")
                .filter { !$0.isMaking && !$0.isIncomplete }
            let seriesOptions = Array(Set(allMetadata.map(\.seriesName)).filter { $0 != uncategorized })
                .sorted { $0.localizedCompare($1) == .orderedAscending }

            for metadata in result.items {
                SessionRecordManager.shared.preloadHomeCardCover(
                    sessionId: metadata.id,
                    avatarImageIndex: metadata.avatarImageIndex,
                    totalImageCount: metadata.totalImageCount,
                    maxDimension: Constants.HomeCard.coverAvatarMaxDimension
                )
            }

            let snapshot = HomePageStartupPreloadSnapshot(
                items: result.items,
                totalCount: result.totalCount,
                playStatsMap: playStatsMap,
                seriesOptions: seriesOptions,
                sortMode: sortMode
            )

            DispatchQueue.main.async {
                self?.homePageStartupPreloadSnapshot = snapshot
            }
        }
    }

    func consumeHomePageStartupPreloadSnapshot() -> HomePageStartupPreloadSnapshot? {
        let snapshot = homePageStartupPreloadSnapshot
        homePageStartupPreloadSnapshot = nil
        return snapshot
    }
}

// MARK: - 应用入口
@main
struct PhotoTTSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // 在应用启动时直接配置音频会话
        configureAudioSession()
        
        // 设置顶部状态栏
        configureStatusBar()
        
        // 设置屏幕保持唤醒状态，防止息屏
        UIApplication.shared.isIdleTimerDisabled = true
        
        // 初始化会话记录管理器，确保目录被创建
        _ = SessionRecordManager.shared

        // 初始化调试日志管理器，开始捕获日志
        _ = DebugLogManager.shared
        
        // 一次性回溯任务：补齐缺失的制作历史事件
        DispatchQueue.global(qos: .utility).async {
            MakeHistoryManager.shared.backfillMakeEventsIfNeeded()
        }

        // 一次性修复任务：修正存量记录的音频时长（使用错误公式计算的旧数据）
        DispatchQueue.global(qos: .utility).async {
            SessionRecordManager.shared.fixAudioDurationForAllSessionsIfNeeded()
        }

        // 一次性补数任务：为老未读绘本补齐缺失的 history.json / makeEvents / playEvents
        DispatchQueue.global(qos: .utility).async {
            SessionRecordManager.shared.backfillLegacyUnreadHistoryIfNeeded()
        }
        
        // Siri App Shortcuts 注册由 scenePhase == .active 统一处理，
        // 首次启动和每次回到前台都会触发，无需在 init() 中重复注册
    }
    
    var body: some Scene {
        WindowGroup {
            CustomZStack {
                // 底部导航Tab
                if appState.fullScreenKind != .loading {
                    MainTabView(appState: appState)
                }
                // 全屏容器：启动页、大图、相机
                if let kind = appState.fullScreenKind {
                    FullScreenPageContainer(appState: appState, kind: kind)
                }
            }
            .statusBarHidden(appState.fullScreenKind != nil)
            // Siri 触发播放：根级 PlayView（PlayView 例外，允许 fullScreenCover）
            .fullScreenCover(item: $appState.sessionRecordToPlay) { record in
                PlayView(recordId: record.id, onDismiss: {
                    appState.sessionRecordToPlay = nil
                    appState.isPlayViewActive = false
                })
            }
            // 监听 App 进入前台（包含 Siri 拉起场景）
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // 防息屏：每次回前台重新设置，防止系统重置
                    UIApplication.shared.isIdleTimerDisabled = true
                    // 每次回到前台重新注册 Siri Shortcuts，防止系统索引丢失
                    Self.registerAppShortcuts(caller: "foreground")
                    loadPendingSiriSession()
                    // 设备传输：前台时开始广播，可被附近设备发现
                    PeerTransferManager.shared.startAdvertising()
                    // 性能监控：前台且非启动页时启动监控
                    if appState.fullScreenKind != .loading {
                        PerformanceMonitorManager.shared.startMonitoring()
                    }
                }
                if phase == .background || phase == .inactive {
                    // 设备传输：进入后台时停止广播
                    PeerTransferManager.shared.stopAdvertising()
                    // 性能监控：后台时停止监控
                    PerformanceMonitorManager.shared.stopMonitoring()
                }
            }
            // 性能监控：启动页结束时启动监控
            .onChange(of: appState.fullScreenKind) { oldKind, newKind in
                if oldKind == .loading && newKind == nil && scenePhase == .active {
                    PerformanceMonitorManager.shared.startMonitoring()
                }
            }
            // 设备传输：接收方公共 UI（PlayView 活跃时由 PlayView 实例展示）
            .transferReceiver(isActive: !appState.isPlayViewActive)
        }
    }

    // MARK: - Siri Shortcuts 注册

    /// 向系统注册 App Shortcuts，供 Siri 发现和调用
    /// - Parameter caller: 调用来源标识（init / foreground / manual），用于日志区分
    static func registerAppShortcuts(caller: String) {
        PhotoTTSShortcuts.updateAppShortcutParameters()
        os.Logger.siri.info("App Shortcuts 注册成功 (caller=\(caller))")
    }

    // Siri 待播放：App 激活时检查 UserDefaults，有则加载并触发 PlayView
    private func loadPendingSiriSession() {
        guard let sessionId = UserDefaults.standard.string(forKey: kSiriPendingSessionId) else { return }
        // 立即清除，防止重复触发
        UserDefaults.standard.removeObject(forKey: kSiriPendingSessionId)

        let tryLoad = {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let record = SessionRecordManager.shared.loadSession(id: sessionId) else {
                    os.Logger.siri.warning("播放: 未找到会话 \(sessionId)")
                    return
                }
                DispatchQueue.main.async {
                    guard !appState.isPlayViewActive else {
                        os.Logger.audioPlayer.warning("播放互斥: 已有播放中，拒绝Siri触发播放 sessionId=\(sessionId)")
                        return
                    }
                    appState.isPlayViewActive = true
                    appState.sessionRecordToPlay = record
                }
            }
        }

        if appState.fullScreenKind == .loading {
            // 启动页还未结束，延迟等待
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { tryLoad() }
        } else {
            tryLoad()
        }
    }
    
    private func configureAudioSession() {
        // 在后台线程配置音频会话，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                // 先停用当前会话，避免冲突
                try audioSession.setActive(false, options: [])
                
                // 使用 .playback：忽略静音开关，扬声器始终可出声；后台暂停由 willResignActiveNotification 控制
                try audioSession.setCategory(.playback, mode: .default)
                
                // 激活音频会话
                try audioSession.setActive(true)
                
                DispatchQueue.main.async {
                    os.Logger.audioPlayer.info("音频会话配置成功")
                }
                
            } catch {
                DispatchQueue.main.async {
                    os.Logger.audioPlayer.error("音频会话配置失败: \(error.localizedDescription)")
                }
                // 尝试更简单的配置
                configureSimpleAudioSession()
            }
        }
    }
    
    private func configureSimpleAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用 .playback：忽略静音开关；后台暂停由 willResignActiveNotification 控制
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
            os.Logger.audioPlayer.info("简化音频会话配置成功")
        } catch {
            os.Logger.audioPlayer.error("简化音频会话配置也失败: \(error.localizedDescription)")
            // 最后尝试: 只设置category，不激活
            configureMinimalAudioSession()
        }
    }
    
    private func configureMinimalAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback)
            os.Logger.audioPlayer.info("最小音频会话配置成功（仅设置category）")
        } catch {
            os.Logger.audioPlayer.error("最小音频会话配置也失败: \(error.localizedDescription)")
        }
    }
    
    private func configureStatusBar() {
        // 状态栏
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                
                let statusBarView = UIView()
                statusBarView.backgroundColor = UIColor.clear // 状态栏背景色，保持透明
                statusBarView.tag = Constants.UI.statusBarViewTag
                
                window.viewWithTag(Constants.UI.statusBarViewTag)?.removeFromSuperview()
                window.addSubview(statusBarView)
                statusBarView.translatesAutoresizingMaskIntoConstraints = false
                
                let statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0
                
                NSLayoutConstraint.activate([
                    statusBarView.topAnchor.constraint(equalTo: window.topAnchor),
                    statusBarView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                    statusBarView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                    statusBarView.heightAnchor.constraint(equalToConstant: statusBarHeight)
                ])
                
                os.Logger.app.info("状态栏已设置, 高度: \(statusBarHeight)")
            }
        }
    }
}

// MARK: - 底导：四个功能簇（首页、制作、管理、我的）
struct MainTabView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { newTab in
                if newTab == 0 && appState.selectedTab == 0 {
                    appState.tab0ReselectTrigger = (appState.tab0ReselectTrigger + 1) % 1024
                    return // 不重复写 selectedTab，避免触发 @Published 重渲染干扰 UIKit scroll-to-top
                }
                if newTab == 2 && appState.selectedTab == 2 {
                    appState.tab2ReselectTrigger = (appState.tab2ReselectTrigger + 1) % 1024
                    return
                }
                appState.selectedTab = newTab
            }
        )) {
            NavigationStack {
                HomePageView(appState: appState)
            }
            .id(appState.tab0ResetId)
            .tabItem {
                Label("首页", systemImage: "play.house")
            }
            .tag(0)

            MakeView(appState: appState)
                .tabItem {
                    Label("制作", systemImage: "book.fill")
                }
                .tag(1)

            NavigationStack {
                SessionRecordListView(
                    appState: appState,
                    onLoadSession: { _ in },
                    onLoadToMake: { id in
                        if BackgroundMakeManager.shared.activeTask(for: id) != nil {
                            appState.makeTaskIdToReconnect = id
                        } else {
                            appState.sessionIdToLoadIntoMake = id
                        }
                        appState.selectedTab = 1
                    },
                    mode: .manage,
                    isRootTab: true
                )
            }
            .id(appState.tab2ResetId)
            .tabItem {
                Label("管理", systemImage: "books.vertical.circle")
            }
            .tag(2)

            MeTabView(appState: appState)
                .id(appState.tab3ResetId)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
                .tag(3)
        }
        .environment(\.horizontalSizeClass, .compact) // iPad适配，保持底导在底部
        .onChange(of: appState.selectedTab) { old, new in
            if old == 0 && new != 0 { appState.tab0ResetId = (appState.tab0ResetId + 1) % 1024 }
            if old == 2 && new != 2 { appState.tab2ResetId = (appState.tab2ResetId + 1) % 1024 }
            if old == 3 && new != 3 { appState.tab3ResetId = (appState.tab3ResetId + 1) % 1024 }
        }
    }
}

// MARK: - 全屏页面类型
enum FullScreenPageKind: Equatable {
    case loading       // 启动页
    case imageViewer   // 全屏大图
    case camera        // 摄像机
}

// MARK: - 全屏页面容器
struct FullScreenPageContainer: View {
    @ObservedObject var appState: AppState
    let kind: FullScreenPageKind
    
    var body: some View {
        Group {
            switch kind {
            case .imageViewer:
                FullScreenImageOverlay(appState: appState)
            case .camera:
                FullScreenCameraOverlay(appState: appState)
            case .loading:
                AppLoadingView(appState: appState)
            }
        }
        .ignoresSafeArea(.all)
        .transition(.opacity)
        .zIndex(100)
    }
}


// MARK: - 全屏大图
struct FullScreenImageOverlay: View {
    @ObservedObject var appState: AppState
    
    private var images: [UIImage] { appState.fullScreenCoverImages }
    private var indexBinding: Binding<Int> {
        Binding(
            get: { appState.fullScreenCoverIndex },
            set: { appState.fullScreenCoverIndex = $0 }
        )
    }
    
    var body: some View {
        FullScreenImageContent(
            images: images,
            currentIndex: indexBinding,
            onTapBackground: { appState.fullScreenKind = nil },
            overlayContent: { EmptyView() }
        )
        .statusBarHidden(true)
    }
}

// MARK: - 全屏相机
struct FullScreenCameraOverlay: View {
    @ObservedObject var appState: AppState
    @State private var capturedImage: UIImage?
    @State private var showLandscapeTip: Bool = !UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.landscapeTipDismissed)
    
    private var selectedImagesBinding: Binding<[UIImage]> {
        Binding(
            get: { appState.cameraOverlayImages },
            set: { appState.cameraOverlayImages = $0 }
        )
    }
    
    var body: some View {
        ZStack {
            CustomCameraView(
                image: $capturedImage,
                selectedImages: selectedImagesBinding,
                onImagesSelected: { images in
                    if !images.isEmpty {
                        NotificationCenter.default.post(name: Constants.NotificationNames.updateImageCount, object: nil, userInfo: ["count": appState.cameraOverlayImages.count])
                    }
                },
                onPhotoCountUpdate: { count in
                    NotificationCenter.default.post(name: Constants.NotificationNames.updateImageCount, object: nil, userInfo: ["count": count])
                },
                onDismiss: {
                    appState.fullScreenKind = nil
                }
            )

            // 横拍提示覆盖层
            LandscapeTipOverlay(isVisible: $showLandscapeTip)
        }
        .onChange(of: capturedImage) { _, newImage in
            if let newImage = newImage {
                appState.cameraOverlayImages.append(newImage)
                capturedImage = nil
            }
        }
    }
}
