import SwiftUI

/// 通用翻页控件（首页、管理Tab 共用）
struct PaginationControl: View {
    let currentPage: Int
    let totalPages: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        HStack(spacing: scaled(16)) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(Constants.Fonts.listAction)
                    .foregroundColor(currentPage > 1 ? .blue : .gray.opacity(0.4))
            }
            .disabled(currentPage <= 1)
            .buttonStyle(.plain)

            Text("\(currentPage) / \(totalPages)")
                .font(Constants.Fonts.recordMeta)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(Constants.Fonts.listAction)
                    .foregroundColor(currentPage < totalPages ? .blue : .gray.opacity(0.4))
            }
            .disabled(currentPage >= totalPages)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: scaled(Constants.Pagination.controlHeight))
    }
}
