import SwiftUI

// MARK: - ZStack 容器
struct CustomZStack<Content: View>: View {
    var alignment: Alignment = .center
    var backgroundColor: Color
    var ignoresSafeArea: Bool
    @ViewBuilder let content: () -> Content

    init(
        alignment: Alignment = .center,
        backgroundColor: Color = Color(uiColor: .systemGroupedBackground),
        ignoresSafeArea: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.ignoresSafeArea = ignoresSafeArea
        self.content = content
    }

    var body: some View {
        ZStack(alignment: alignment) {
            backgroundColor
                .ignoresSafeArea(edges: ignoresSafeArea ? .all : [])
            content()
        }
    }
}
