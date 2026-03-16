import SwiftUI

/// 相机横拍提示覆盖层
/// 打开相机时展示，引导用户将手机旋转至横屏拍摄，displayDuration 秒后自动淡出消失
struct LandscapeTipOverlay: View {
    @Binding var isVisible: Bool
    @State private var arrowRotation: Double = Constants.CameraTip.rotationStartAngle

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        if isVisible {
            ZStack {
                // 半透明遮罩
                Color.black.opacity(Constants.CameraTip.overlayOpacity)

                // 提示内容
                VStack(spacing: scaled(20)) {
                    // 手机图标 + 旋转箭头
                    ZStack {
                        // 手机图标
                        Image(systemName: "iphone")
                            .font(Constants.Fonts.emptyStateIcon)
                            .foregroundColor(.white)

                        // 旋转箭头（垂直翻转实现 turn down 效果）
                        Image(systemName: "arrowshape.down.fill")
                            .font(Constants.Fonts.tipArrowIcon)
                            .foregroundColor(.yellow)
                            .scaleEffect(x: 1, y: 1)
                            .offset(x: scaled(55), y: scaled(-10))
                            .rotationEffect(.degrees(arrowRotation))
                    }

                    // 文案
                    Text("横拍效果更佳")
                        .font(Constants.Fonts.tipBackIcon)
                        .foregroundColor(.white)
                }
                .padding(scaled(30))
            }
            .allowsHitTesting(false)
            .onAppear {
                startArrowAnimation()
                scheduleAutoDismiss()
            }
        }
    }

    // MARK: - 箭头顺时针旋转动画（左上角 -> 右上角，120度，3次）
    private func startArrowAnimation() {
        withAnimation(
            .easeInOut(duration: Constants.CameraTip.animationDuration)
            .repeatCount(Constants.CameraTip.rotationRepeatCount, autoreverses: false)
        ) {
            arrowRotation = Constants.CameraTip.rotationEndAngle
        }
    }

    // MARK: - 定时自动消失
    private func scheduleAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.CameraTip.displayDuration) {
            withAnimation(.easeOut(duration: Constants.CameraTip.fadeOutDuration)) {
                isVisible = false
            }
        }
    }
}
