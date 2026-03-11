import SwiftUI
import os.log
import UIKit
import AVFoundation
import PhotosUI

// MARK: - 相机相关协议和委托
protocol CustomCameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
    func didCancel()
    func updateImageCount(_ count: Int)
    func setPhotoCount(_ count: Int)
}

// 自定义相机视图 - 使用AVFoundation
struct CustomCameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var selectedImages: [UIImage]
    let onImagesSelected: (([UIImage]) -> Void)?
    let onPhotoCountUpdate: ((Int) -> Void)?
    /// 用户点击取消时调用，用于同步主页面 showingCamera 状态（避免选图导致重绘时误触发 onDisappear 关闭相机）
    let onDismiss: (() -> Void)?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> CustomCameraViewController {
        let cameraVC = CustomCameraViewController()
        cameraVC.delegate = context.coordinator
        cameraVC.setPhotoCount(selectedImages.count)
        return cameraVC
    }
    
    func updateUIViewController(_ uiViewController: CustomCameraViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CustomCameraViewControllerDelegate {
        let parent: CustomCameraView
        
        init(_ parent: CustomCameraView) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            // 满足 saveImageMaxPixel 限制后加入
            let maxP = Int(Constants.ImageDisplay.saveImageMaxPixel)
            let capped = SessionRecordManager.downsampleImageToMaxPixel(image, maxPixelLength: maxP) ?? image
            parent.selectedImages.append(capped)
            parent.onImagesSelected?([capped])
            os.Logger.camera.debug("照片已添加, 继续拍摄。当前已拍摄 \(self.parent.selectedImages.count) 张")
            
            // 更新相机界面的状态显示
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let newCount = self.parent.selectedImages.count
                self.parent.onPhotoCountUpdate?(newCount)
            }
        }
        
        func didCancel() {
            parent.onDismiss?()
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func updateImageCount(_ count: Int) {
            // 这个方法在CustomCameraViewController中实现
            // 这里不需要实现，因为delegate会直接调用CustomCameraViewController的方法
        }
        
        func setPhotoCount(_ count: Int) {
            // 这个方法在CustomCameraViewController中实现
            // 这里不需要实现，因为delegate会直接调用CustomCameraViewController的方法
        }
    }
}

// 自定义相机视图控制器
class CustomCameraViewController: UIViewController {
    weak var delegate: CustomCameraViewControllerDelegate?
    
    private var currentPhotoCount: Int = 0
    
    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var isConfiguring = false
    
    private let captureButton = UIButton()
    private let cancelButton = UIButton()
    private let flipCameraButton = UIButton()
    private let statusLabel = UILabel()
    
    // 遮罩层视图
    private let bottomOverlay = UIView()
    
    /// 左边缘右滑返回：是否从左侧边缘开始滑动
    private var leftEdgeSwipeStarted = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        setupLeftEdgeSwipeBackGesture()
        // 监听照片数量更新通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePhotoCountUpdate(_:)),
            name: Constants.NotificationNames.updateImageCount,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handlePhotoCountUpdate(_ notification: Notification) {
        if let userInfo = notification.userInfo,
           let count = userInfo["count"] as? Int {
            setPhotoCount(count)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        os.Logger.camera.debug("相机视图即将出现")
        
        // 异步执行初始化，避免阻塞主线程
        DispatchQueue.main.async { [weak self] in
            self?.startSession()
            self?.ensureButtonsVisible()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 更新预览层frame，向上移动30像素
        updatePreviewLayerFrame()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if presentedViewController == nil {
            stopSession()
        }
    }
    
    // 手势识别
    private func setupLeftEdgeSwipeBackGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleLeftEdgePan(_:)))
        view.addGestureRecognizer(pan)
    }
    
    @objc private func handleLeftEdgePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            leftEdgeSwipeStarted = (location.x < Constants.Gesture.leftEdgeStartZoneWidth)
        case .ended:
            if leftEdgeSwipeStarted, translation.x > Constants.Gesture.swipeBackMinTranslation {
                os.Logger.camera.debug("相机页面：检测到左侧边缘向右滑动，返回主界面")
                delegate?.didCancel()
            }
            leftEdgeSwipeStarted = false
        case .cancelled:
            leftEdgeSwipeStarted = false
        default:
            break
        }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .photo
        
        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            os.Logger.camera.error("无法访问后置相机，尝试前置相机")
            setupFrontCamera()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if captureSession?.canAddOutput(photoOutput!) == true {
                captureSession?.addOutput(photoOutput!)
            }
            
            setupPreviewLayer()
            
        } catch {
            os.Logger.camera.error("相机设置失败: \(error.localizedDescription)")
            // 相机设置失败时显示错误状态
            showCameraError()
        }
    }
    
    private func setupFrontCamera() {
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            os.Logger.camera.error("无法访问前置相机")
            showCameraError()
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if captureSession?.canAddOutput(photoOutput!) == true {
                captureSession?.addOutput(photoOutput!)
            }
            
            setupPreviewLayer()
            
        } catch {
            os.Logger.camera.error("前置相机设置失败: \(error.localizedDescription)")
            showCameraError()
        }
    }
    
    private func showCameraError() {
        // 相机设置失败时显示错误状态
        statusLabel.text = "相机初始化失败\n请检查相机权限或重启应用"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .white
        statusLabel.font = UIFont.systemFont(ofSize: 16)
        statusLabel.backgroundColor = UIColor.red.withAlphaComponent(0.7)
        statusLabel.layer.cornerRadius = 12
        statusLabel.layer.masksToBounds = true
        view.addSubview(statusLabel)
        
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        // 禁用拍照按钮
        captureButton.isEnabled = false
    }
    
    private func updateStatusLabel() {
        statusLabel.text = "\(currentPhotoCount)"
        
        statusLabel.textAlignment = .right
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .white
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .light)
        statusLabel.backgroundColor = .clear
        
        if statusLabel.superview == nil {
            view.addSubview(statusLabel)
            statusLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
                statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
            ])
        }
    }
    
    func updateImageCount(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusLabel()
        }
    }
    
    func setPhotoCount(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.currentPhotoCount = count
            self?.updateStatusLabel()
        }
    }
    
    private func setupPreviewLayer() {
        guard let captureSession = captureSession else { return }
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspect  // 使用 resizeAspect 保持宽高比，预览与照片内容一致
        updatePreviewLayerFrame()
        
        if let previewLayer = videoPreviewLayer {
            // 将预览层插入到最底层，确保按钮显示在上方
            view.layer.insertSublayer(previewLayer, at: 0)
        }
    }
    
    // 更新预览层frame，向上移动30像素
    private func updatePreviewLayerFrame() {
        var frame = view.bounds
        frame.origin.y -= 30  // 向上移动30像素
        videoPreviewLayer?.frame = frame
    }
    
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // 添加底部遮罩层
        setupBottomOverlay()
        
        // 拍照按钮
        captureButton.setTitle("", for: .normal)
        captureButton.backgroundColor = .clear
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.layer.shadowColor = UIColor.black.cgColor
        captureButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        captureButton.layer.shadowOpacity = 0.3
        captureButton.layer.shadowRadius = 8
        captureButton.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        view.addSubview(captureButton)
        
        // 添加拍照按钮内圆
        let innerCircle = UIView()
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = 25
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.isUserInteractionEnabled = false
        captureButton.addSubview(innerCircle)
        
        NSLayoutConstraint.activate([
            innerCircle.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 50),
            innerCircle.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // 取消按钮（返回图标）
        cancelButton.setTitle(nil, for: .normal)
        let backImage = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        cancelButton.setImage(backImage, for: .normal)
        cancelButton.tintColor = .white
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        cancelButton.layer.cornerRadius = 25
        cancelButton.layer.borderWidth = 2
        cancelButton.layer.borderColor = UIColor.white.cgColor
        cancelButton.layer.shadowColor = UIColor.black.cgColor
        cancelButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        cancelButton.layer.shadowOpacity = 0.3
        cancelButton.layer.shadowRadius = 4
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        
        // 前后相机切换按钮
        flipCameraButton.setTitle("", for: .normal)
        flipCameraButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        flipCameraButton.layer.cornerRadius = 25
        flipCameraButton.layer.borderWidth = 2
        flipCameraButton.layer.borderColor = UIColor.white.cgColor
        flipCameraButton.layer.shadowColor = UIColor.black.cgColor
        flipCameraButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        flipCameraButton.layer.shadowOpacity = 0.3
        flipCameraButton.layer.shadowRadius = 4
        flipCameraButton.addTarget(self, action: #selector(flipCameraButtonTapped), for: .touchUpInside)
        view.addSubview(flipCameraButton)
        
        // 相机切换图标（与标准相机一致）
        let flipIcon = UIImageView()
        flipIcon.image = UIImage(systemName: "arrow.triangle.2.circlepath.camera", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        flipIcon.tintColor = .white
        flipIcon.translatesAutoresizingMaskIntoConstraints = false
        flipCameraButton.addSubview(flipIcon)
        
        NSLayoutConstraint.activate([
            flipIcon.centerXAnchor.constraint(equalTo: flipCameraButton.centerXAnchor),
            flipIcon.centerYAnchor.constraint(equalTo: flipCameraButton.centerYAnchor),
            flipIcon.widthAnchor.constraint(equalToConstant: 24),
            flipIcon.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        
        setupConstraints()
    }
    
    
    private func setupBottomOverlay() {
        bottomOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomOverlay)
        
        // 创建渐变层
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.3).cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor,
            UIColor.black.withAlphaComponent(0.8).cgColor
        ]
        gradientLayer.locations = [0.0, 0.3, 0.7, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        
        bottomOverlay.layer.addSublayer(gradientLayer)
        
        NSLayoutConstraint.activate([
            bottomOverlay.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -250),
            bottomOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 在布局完成后设置渐变层frame
        DispatchQueue.main.async {
            gradientLayer.frame = self.bottomOverlay.bounds
        }
    }
    
    private func setupConstraints() {
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        flipCameraButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // 拍照按钮 - 底部中心
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),
            
            // 取消按钮 - 底部左侧
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            cancelButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 50),
            cancelButton.heightAnchor.constraint(equalToConstant: 50),
            
            // 前后相机切换按钮 - 底部右侧
            flipCameraButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            flipCameraButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            flipCameraButton.widthAnchor.constraint(equalToConstant: 50),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc private func captureButtonTapped() {
        os.Logger.camera.debug("拍照按钮被点击，当前状态: isEnabled=\(self.captureButton.isEnabled), isHidden=\(self.captureButton.isHidden)")
        
        // 检查相机权限
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            os.Logger.camera.warning("相机权限未授权: \(String(describing: authStatus))")
            if authStatus == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.captureButtonTapped()
                        } else {
                            os.Logger.camera.warning("用户拒绝了相机权限")
                        }
                    }
                }
            }
        return
        }
        
        // 检查相机会话状态
        guard let captureSession = captureSession, captureSession.isRunning else {
            os.Logger.camera.warning("相机会话未运行")
            return
        }
        
        guard let photoOutput = photoOutput else {
            os.Logger.camera.warning("照片输出未初始化")
            return
        }
        
        // 禁用拍照按钮防止重复点击
        captureButton.isEnabled = false
        
        let settings = AVCapturePhotoSettings()
        
        // 设置照片格式 - 使用正确的API
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            // 在iOS 11+中，AVCapturePhotoSettings默认使用JPEG格式
            // 不需要显式设置format属性
        }
        
        // 异步拍照，避免阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let strongSelf = self else { return }
            photoOutput.capturePhoto(with: settings, delegate: strongSelf)
            
            // 设置超时机制，防止卡死
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                self?.captureButton.isEnabled = true
            }
        }
    }
    
    
    @objc private func cancelButtonTapped() {
        delegate?.didCancel()
    }
    
    @objc private func flipCameraButtonTapped() {
        guard let captureSession = captureSession else { return }
        guard let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput else { return }
        
        let currentPosition = currentInput.device.position
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
            os.Logger.camera.error("无法获取\(newPosition == .front ? "前置" : "后置")相机")
            return
        }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            
            captureSession.beginConfiguration()
            captureSession.removeInput(currentInput)
            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
            } else {
                // 回退到原来的输入
                captureSession.addInput(currentInput)
                os.Logger.camera.error("无法切换相机")
            }
            captureSession.commitConfiguration()
            
            os.Logger.camera.debug("相机已切换到\(newPosition == .front ? "前置" : "后置")")
        } catch {
            os.Logger.camera.error("切换相机失败: \(error.localizedDescription)")
        }
    }
    
    
    private func startSession() {
        guard let captureSession = captureSession, !isConfiguring else {
            os.Logger.camera.debug("相机会话未初始化或正在配置中")
            return
        }
        
        // 检查相机权限
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            os.Logger.camera.debug("相机权限未授权: \(String(describing: authStatus))")
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            os.Logger.camera.debug("开始启动相机会话...")
            captureSession.startRunning()
            
            DispatchQueue.main.async {
                if captureSession.isRunning {
                    os.Logger.camera.debug("相机会话启动成功")
                } else {
                    os.Logger.camera.debug("相机会话启动失败")
                }
            }
        }
    }
    
    private func stopSession() {
        guard let captureSession = captureSession, !isConfiguring else { return }
        
        captureSession.stopRunning()
    }
    
    private func ensureButtonsVisible() {
        os.Logger.camera.debug("确保按钮可见 - 拍照按钮状态: isEnabled=\(self.captureButton.isEnabled), isHidden=\(self.captureButton.isHidden)")
        
        // 只在必要时更新按钮状态，减少UI操作
        if captureButton.isHidden || !captureButton.isEnabled {
            captureButton.isHidden = false
            captureButton.isEnabled = true
        }
        
        if cancelButton.isHidden || !cancelButton.isEnabled {
            cancelButton.isHidden = false
            cancelButton.isEnabled = true
        }
        
        if flipCameraButton.isHidden || !flipCameraButton.isEnabled {
            flipCameraButton.isHidden = false
            flipCameraButton.isEnabled = true
        }
        
        os.Logger.camera.debug("按钮状态更新后 - 拍照按钮状态: isEnabled=\(self.captureButton.isEnabled), isHidden=\(self.captureButton.isHidden)")
        
        // 批量更新层级，减少UI操作
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.bringSubviewToFront(captureButton)
        view.bringSubviewToFront(cancelButton)
        view.bringSubviewToFront(flipCameraButton)
        view.bringSubviewToFront(statusLabel)
        CATransaction.commit()
        
        // 更新状态标签
        updateStatusLabel()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CustomCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // 重新启用拍照按钮
        DispatchQueue.main.async { [weak self] in
            os.Logger.camera.debug("拍照完成，重新启用拍照按钮")
            self?.captureButton.isEnabled = true
            os.Logger.camera.debug("拍照按钮状态: isEnabled=\(self?.captureButton.isEnabled ?? false)")
        }
        
        if let error = error {
            os.Logger.camera.debug("拍照失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                // 可以在这里显示错误提示
                os.Logger.camera.error("拍照错误，请重试")
            }
            return
        }
        
        os.Logger.camera.debug("开始处理照片数据...")
        
        guard let imageData = photo.fileDataRepresentation() else {
            os.Logger.camera.debug("无法获取照片数据")
            DispatchQueue.main.async {
                os.Logger.camera.error("照片数据获取失败")
            }
            return
        }
        
        guard let image = UIImage(data: imageData) else {
            os.Logger.camera.debug("无法创建UIImage，数据大小: \(imageData.count) 字节")
            DispatchQueue.main.async {
                os.Logger.camera.error("图片创建失败")
            }
            return
        }
        
        os.Logger.camera.debug("照片处理成功，图片大小: \(String(describing: image.size))")
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.didCaptureImage(image)
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        os.Logger.camera.debug("开始拍照...")
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        os.Logger.camera.debug("即将捕获照片...")
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        os.Logger.camera.debug("照片捕获完成，开始处理...")
    }
}


// 图片选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// 多选图片选择器
struct MultiImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.presentationMode) var presentationMode
    var onCompletion: (([UIImage]) -> Void)?
    var onCancel: (() -> Void)?
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = Constants.maxPhotoPickerSelectionCount
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker
        
        init(_ parent: MultiImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard !results.isEmpty else {
                os.Logger.camera.debug("用户取消了图片选择")
                DispatchQueue.main.async { self.parent.onCancel?() }
                return
            }
            
            os.Logger.camera.debug("开始加载 \(results.count) 张图片")
            
            // 处理选中的图片 - 保持选择顺序
            let group = DispatchGroup()
            var images: [UIImage] = Array(repeating: UIImage(), count: results.count) // 预分配数组，保持顺序
            var loadedCount = 0
            let processingQueue = DispatchQueue(label: "com.phototts.imageProcessing", qos: .userInitiated)
            let lock = NSLock()
            
            for (index, result) in results.enumerated() {
                group.enter()
                
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { (object, error) in
                        if let image = object as? UIImage {
                            processingQueue.async { [weak self] in
                                defer { group.leave() }
                                guard let self = self else { return }
                                
                                // 满足 saveImageMaxPixel 限制，超过则缩小
                                let maxP = Int(Constants.ImageDisplay.saveImageMaxPixel)
                                let cappedImage = SessionRecordManager.downsampleImageToMaxPixel(image, maxPixelLength: maxP) ?? image
                                
                                // 检查图片是否已经选择过
                                let isAlreadySelected = self.isImageAlreadySelected(cappedImage)
                                lock.lock()
                                if !isAlreadySelected {
                                    images[index] = cappedImage
                                    loadedCount += 1
                                    os.Logger.camera.info("图片 \(index) 加载成功")
                                } else {
                                    os.Logger.camera.debug("图片 \(index) 已存在，跳过")
                                    images[index] = UIImage()
                                }
                                lock.unlock()
                            }
                        } else {
                            group.leave()
                        }
                    }
                } else {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                // 过滤掉空图片，保持顺序
                let validImages = images.filter { !$0.size.equalTo(.zero) }
                
                os.Logger.camera.info("图片加载完成: 成功 \(validImages.count)/\(results.count)")
                
                // 批量添加图片，只触发一次UI更新
                if !validImages.isEmpty {
                    self.parent.selectedImages.append(contentsOf: validImages)
                    os.Logger.camera.debug("UI更新: 添加了 \(validImages.count) 张图片")
                }
                
                // 调用完成回调
                self.parent.onCompletion?(validImages)
            }
        }
        
        
        // 格式化字节大小显示
        private func formatBytes(_ bytes: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(bytes))
        }
        
        // 压缩图片以减少内存使用（使用 Image I/O 降采样，避免先解码全尺寸再缩放）
        private func compressImage(_ image: UIImage, maxSize: CGSize) -> UIImage {
            let maxPixel = Int(max(maxSize.width, maxSize.height))
            return SessionRecordManager.downsampleImageToMaxPixel(image, maxPixelLength: maxPixel) ?? image
        }
        
        // 检查图片是否已经选择过
        private func isImageAlreadySelected(_ newImage: UIImage) -> Bool {
            for selectedImage in parent.selectedImages {
                if imagesAreEqual(newImage, selectedImage) {
                    return true
                }
            }
            return false
        }
        
        // 比较两张图片是否相同
        private func imagesAreEqual(_ image1: UIImage, _ image2: UIImage) -> Bool {
            guard let data1 = image1.jpegData(compressionQuality: 1.0),
                  let data2 = image2.jpegData(compressionQuality: 1.0) else {
                return false
            }
            return data1 == data2
        }
    }
}
