import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import os.log

// MARK: - 日志记录器
extension os.Logger {
    static let audioPlayer = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "AudioPlayer")
}

// MARK: - AppDelegate：锁定竖屏，拦截横屏
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Info.plist 声明支持全部方向以满足审核要求，运行时仅允许竖屏，保持竖屏布局
        return .portrait
    }
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

    init() {}
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
        
        // 向系统注册 Siri App Shortcuts，确保 Siri 能识别语音指令
        PhotoTTSShortcuts.updateAppShortcutParameters()
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
                })
            }
            // 监听 App 进入前台（包含 Siri 拉起场景）
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    loadPendingSiriSession()
                }
            }
        }
    }

    // Siri 待播放：App 激活时检查 UserDefaults，有则加载并触发 PlayView
    private func loadPendingSiriSession() {
        guard let sessionId = UserDefaults.standard.string(forKey: kSiriPendingSessionId) else { return }
        // 立即清除，防止重复触发
        UserDefaults.standard.removeObject(forKey: kSiriPendingSessionId)

        let tryLoad = {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let record = SessionRecordManager.shared.loadSession(id: sessionId) else {
                    print("Siri 播放：未找到会话 \(sessionId)")
                    return
                }
                DispatchQueue.main.async {
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
                
                // 使用最基本的配置
                try audioSession.setCategory(.playback, mode: .default)
                
                // 激活音频会话
                try audioSession.setActive(true)
                
                DispatchQueue.main.async {
                    os.Logger.audioPlayer.info("✅ 音频会话配置成功")
                }
                
            } catch {
                DispatchQueue.main.async {
                    os.Logger.audioPlayer.error("❌ 音频会话配置失败: \(error.localizedDescription)")
                }
                // 尝试更简单的配置
                configureSimpleAudioSession()
            }
        }
    }
    
    private func configureSimpleAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用最基本的配置，不设置mode和options
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
            os.Logger.audioPlayer.info("✅ 简化音频会话配置成功")
        } catch {
            os.Logger.audioPlayer.error("❌ 简化音频会话配置也失败: \(error.localizedDescription)")
            // 最后尝试: 只设置category，不激活
            configureMinimalAudioSession()
        }
    }
    
    private func configureMinimalAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback)
            os.Logger.audioPlayer.info("✅ 最小音频会话配置成功（仅设置category）")
        } catch {
            os.Logger.audioPlayer.error("❌ 最小音频会话配置也失败: \(error.localizedDescription)")
        }
    }
    
    private func configureStatusBar() {
        // 状态栏
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                
                let statusBarView = UIView()
                statusBarView.backgroundColor = UIColor.clear // 状态栏背景色，保持透明
                statusBarView.tag = 999 // 用于识别和移除
                
                window.viewWithTag(999)?.removeFromSuperview()
                window.addSubview(statusBarView)
                statusBarView.translatesAutoresizingMaskIntoConstraints = false
                
                let statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0
                
                NSLayoutConstraint.activate([
                    statusBarView.topAnchor.constraint(equalTo: window.topAnchor),
                    statusBarView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                    statusBarView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                    statusBarView.heightAnchor.constraint(equalToConstant: statusBarHeight)
                ])
                
                print("✅ 状态栏已设置，高度: \(statusBarHeight)")
            }
        }
    }
}

// MARK: - 底导：四个功能簇（首页、制作、消息、我的）
struct MainTabView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                HomePageView(appState: appState)
            }
            .id(appState.tab0ResetId)
            .tabItem {
                Label("首页", systemImage: "house")
            }
            .tag(0)
            
            MakeView(appState: appState)
                .tabItem {
                    Label("制作", systemImage: "book")
                }
                .tag(1)
            
            MessageTabView()
                .id(appState.tab2ResetId)
                .tabItem {
                    Label("消息", systemImage: "message.fill")
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
    
    private var selectedImagesBinding: Binding<[UIImage]> {
        Binding(
            get: { appState.cameraOverlayImages },
            set: { appState.cameraOverlayImages = $0 }
        )
    }
    
    var body: some View {
        CustomCameraView(
            image: $capturedImage,
            selectedImages: selectedImagesBinding,
            onImagesSelected: { images in
                if !images.isEmpty {
                    NotificationCenter.default.post(name: NSNotification.Name("UpdatePhotoCount"), object: nil, userInfo: ["count": appState.cameraOverlayImages.count])
                }
            },
            onPhotoCountUpdate: { count in
                NotificationCenter.default.post(name: NSNotification.Name("UpdatePhotoCount"), object: nil, userInfo: ["count": count])
            },
            onDismiss: {
                appState.fullScreenKind = nil
            }
        )
        .onChange(of: capturedImage) { _, newImage in
            if let newImage = newImage {
                appState.cameraOverlayImages.append(newImage)
                capturedImage = nil
            }
        }
    }
}


