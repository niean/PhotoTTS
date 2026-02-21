import SwiftUI
import PhotosUI

// MARK: - APP 介绍页头像（与介绍页同源，供「我的」等复用）
enum IntroAvatarImage {
    static func load() -> UIImage? {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("custom_background.jpg")
        if FileManager.default.fileExists(atPath: path.path),
           let image = UIImage(contentsOfFile: path.path) {
            return image
        }
        return UIImage(named: "home")
    }
}

// MARK: - 统一页面视图（加载页和介绍页）
struct AppPageView: View {
    @State private var rotationAngle: Double = 0
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @ObservedObject var appState: AppState
    let pageType: PageType
    var onDismiss: (() -> Void)? = nil
    
    enum PageType {
        case loading
        case intro
    }
    
    // MARK: - 图片保存和加载方法
    private func saveBackgroundImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagePath = documentsPath.appendingPathComponent("custom_background.jpg")
        
        do {
            try data.write(to: imagePath)
            print("✅ 背景图片已保存到: \(imagePath)")
        } catch {
            print("❌ 保存背景图片失败: \(error)")
        }
    }
    
    private func loadBackgroundImage() -> UIImage? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagePath = documentsPath.appendingPathComponent("custom_background.jpg")
        
        if FileManager.default.fileExists(atPath: imagePath.path) {
            return UIImage(contentsOfFile: imagePath.path)
        }
        return nil
    }
    
    private func getBackgroundImage() -> UIImage? {
        return IntroAvatarImage.load()
    }
    
    // MARK: - 相机图标视图
    private var cameraIconView: some View {
        // TODO: 使用 CustomZStack 替代(当前CustomZStack有点样式问题)
        ZStack {
            // 圆形背景（根据页面类型选择）
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 120, height: 120)
                .overlay(backgroundImageView)
            
            Image(systemName: "camera.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
                .opacity(pageType == .intro ? 0.2 : 1.0) 
                .rotationEffect(.degrees(rotationAngle))
                .animation(
                    Animation.linear(duration: 2.0)
                        .repeatForever(autoreverses: false),
                    value: rotationAngle
                )
                .onTapGesture {
                    if pageType == .intro {
                        print("📷 点击相机图标，打开图片选择器")
                        showingImagePicker = true
                    }
                }
        }
    }
    
    // MARK: - 背景图片视图
    private var backgroundImageView: some View {
        Group {
            if pageType == .intro {
                // 介绍页: 使用动态背景图片
                if let backgroundImage = getBackgroundImage() {
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else {
                    Image("home")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                }
            }
            // 加载页: 只使用纯色背景，不添加图片
        }
    }
    
    var body: some View {
        GeometryReader { _ in
            CustomZStack {
                pageContent
                    .padding(.top, (pageType == .intro && onDismiss != nil) ? 0 : 45) // push 时由外层提供导航栏，不占位
                    
                VStack(spacing: 0) {
                    if pageType == .intro {
                        // 顶部导航栏
                        // TODO
                    }
                }
            }
        }
    }
    
    private var pageContent: some View {
        CustomZStack {
            HStack {
                Spacer()

                VStack(spacing: 40) {
                    Spacer()
                    
                    // 应用图标和动画
                    VStack(spacing: 20) {
                        // 旋转的相机图标
                        cameraIconView
                        
                        // 应用名称
                        Text("Photo TTS")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        // 应用描述
                        Text("拍照阅读，让绘本更精彩")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                            .multilineTextAlignment(.center)
                    }
                    
                    // 加载进度（仅在加载页面显示）
                    if pageType == .loading {
                        VStack(spacing: 16) {
                            // 进度条
                            ProgressView(value: appState.loadingProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                .frame(width: 200)
                                .scaleEffect(y: 2.0)
                            
                            // 加载消息
                            Text(appState.loadingMessage)
                                .font(.headline)
                                .foregroundColor(.blue)
                                .animation(.easeInOut(duration: 0.3), value: appState.loadingMessage)
                            
                            // 进度百分比
                            Text("\(Int(appState.loadingProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 底部版权信息
                    VStack(spacing: 8) {
                        Text("Author: NieAn")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Powered by AGI")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 30)
                }
                .padding()
                Spacer()
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                let maxP = Int(Constants.ImageDisplay.saveImageMaxPixel)
                let capped = SessionRecordManager.downsampleImageToMaxPixel(image, maxPixelLength: maxP) ?? image
                print("📷 用户选择了新图片，保存为背景")
                saveBackgroundImage(capped)
                selectedImage = nil
            }
        }
    }
}

// MARK: - 加载页面视图（使用统一页面，加载节奏在此执行）
struct AppLoadingView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        AppPageView(appState: appState, pageType: .loading)
            .onAppear {
                runLoadingSequence()
            }
    }
    
    private func runLoadingSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            appState.loadingMessage = "配置音频服务..."
            appState.loadingProgress = 0.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            appState.loadingMessage = "初始化OCR服务..."
            appState.loadingProgress = 0.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            appState.loadingMessage = "加载用户设置..."
            appState.loadingProgress = 0.8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            appState.loadingMessage = "准备就绪"
            appState.loadingProgress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                appState.fullScreenKind = nil
            }
        }
    }
}

// MARK: - APP介绍页视图（使用统一页面）
struct AppIntroView: View {
    @ObservedObject var appState: AppState
    /// 非 nil 时由调用方控制关闭（如 sheet 内弹出）
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        AppPageView(appState: appState, pageType: .intro, onDismiss: onDismiss)
    }
}

