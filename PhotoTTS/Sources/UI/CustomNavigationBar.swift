import SwiftUI

// MARK: - 顶部导航栏（左 / 中标题 / 右 布局）
struct CustomNavigationBar<Leading: View, Trailing: View>: View {
    var showShadow: Bool = false
    let title: String
    let leading: Leading
    let trailing: Trailing

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    init(
        showShadow: Bool = false,
        title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.showShadow = showShadow
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    init(showShadow: Bool = false, title: String, @ViewBuilder trailing: () -> Trailing)
    where Leading == EmptyView {
        self.showShadow = showShadow
        self.title = title
        self.leading = EmptyView()
        self.trailing = trailing()
    }

    init(showShadow: Bool = false, title: String, @ViewBuilder leading: () -> Leading)
    where Trailing == EmptyView {
        self.showShadow = showShadow
        self.title = title
        self.leading = leading()
        self.trailing = EmptyView()
    }

    init(showShadow: Bool = false, title: String)
    where Leading == EmptyView, Trailing == EmptyView {
        self.showShadow = showShadow
        self.title = title
        self.leading = EmptyView()
        self.trailing = EmptyView()
    }

    var body: some View {
        ZStack {
            HStack {
                leading
                Spacer(minLength: 0)
                trailing
            }
            Text(title)
                .font(Constants.Fonts.navTitle)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 45)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(showShadow ? 0.1 : 0), radius: showShadow ? 2 : 0, x: 0, y: showShadow ? 2 : 0)
    }
}

// MARK: - 顶导 + 左边缘滑动手势（合为一个组件）
struct TopAndLeftSideNavigationBar<Leading: View, Trailing: View>: View {
    var showShadow: Bool = false
    let title: String
    let leading: Leading
    let trailing: Trailing
    var onSwipeBack: (() -> Void)? = nil
    var onLeftAreaTap: (() -> Void)? = nil

    init(
        showShadow: Bool = false,
        title: String,
        onSwipeBack: (() -> Void)? = nil,
        onLeftAreaTap: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.showShadow = showShadow
        self.title = title
        self.onSwipeBack = onSwipeBack
        self.onLeftAreaTap = onLeftAreaTap
        self.leading = leading()
        self.trailing = trailing()
    }

    init(showShadow: Bool = false, title: String, onSwipeBack: (() -> Void)? = nil, onLeftAreaTap: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing)
    where Leading == EmptyView {
        self.showShadow = showShadow
        self.title = title
        self.onSwipeBack = onSwipeBack
        self.onLeftAreaTap = onLeftAreaTap
        self.leading = EmptyView()
        self.trailing = trailing()
    }

    init(showShadow: Bool = false, title: String, onSwipeBack: (() -> Void)? = nil, onLeftAreaTap: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading)
    where Trailing == EmptyView {
        self.showShadow = showShadow
        self.title = title
        self.onSwipeBack = onSwipeBack
        self.onLeftAreaTap = onLeftAreaTap
        self.leading = leading()
        self.trailing = EmptyView()
    }

    init(showShadow: Bool = false, title: String, onSwipeBack: (() -> Void)? = nil, onLeftAreaTap: (() -> Void)? = nil)
    where Leading == EmptyView, Trailing == EmptyView {
        self.showShadow = showShadow
        self.title = title
        self.onSwipeBack = onSwipeBack
        self.onLeftAreaTap = onLeftAreaTap
        self.leading = EmptyView()
        self.trailing = EmptyView()
    }

    var body: some View {
        VStack(spacing: 0) {
            CustomNavigationBar(showShadow: showShadow, title: title, leading: { leading }, trailing: { trailing })
            HStack(spacing: 0) {
                leftGestureStrip
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var leftGestureStrip: some View {
        let strip = Rectangle()
            .fill(Color.clear)
            .frame(width: Constants.Gesture.gestureThreshold)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture()
                    .onEnded { value in
                        let startX = value.startLocation.x
                        let translationX = value.translation.width
                        if startX < Constants.Gesture.leftEdgeStartZoneWidth,
                           translationX > Constants.Gesture.swipeBackMinTranslation {
                            onSwipeBack?()
                        }
                    }
            )
        if let tap = onLeftAreaTap {
            strip.simultaneousGesture(TapGesture().onEnded { _ in tap() })
        } else {
            strip
        }
    }
}
