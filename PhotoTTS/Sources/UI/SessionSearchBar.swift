import SwiftUI

struct SessionSearchBar: View {
    @Binding var searchText: String
    @Binding var selectedSeries: String?
    @Binding var selectedReadStatus: SessionReadStatusFilter?
    let seriesOptions: [String]
    let onSearchSubmit: (() -> Void)?

    init(
        searchText: Binding<String>,
        selectedSeries: Binding<String?>,
        selectedReadStatus: Binding<SessionReadStatusFilter?>,
        seriesOptions: [String],
        onSearchSubmit: (() -> Void)? = nil
    ) {
        self._searchText = searchText
        self._selectedSeries = selectedSeries
        self._selectedReadStatus = selectedReadStatus
        self.seriesOptions = seriesOptions
        self.onSearchSubmit = onSearchSubmit
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    private func filterMenuLabel(title: String, isSelected _: Bool, width: CGFloat) -> some View {
        Text(title)
            .font(Constants.Fonts.searchInput)
            .foregroundColor(.gray)
            .lineLimit(1)
        .frame(width: scaled(width), height: Constants.SearchBar.rowMinHeight, alignment: .center)
        .padding(.horizontal, scaled(6))
        .contentShape(Rectangle())
    }

    var body: some View {
        HStack(spacing: 0) {
            // 系列筛选（左侧）
            Menu {
                Button(action: { selectedSeries = nil }) {
                    HStack {
                        Text("不限")
                        if selectedSeries == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                ForEach(seriesOptions, id: \.self) { series in
                    Button(action: { selectedSeries = series }) {
                        HStack {
                            Text(series)
                            if selectedSeries == series {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                filterMenuLabel(title: selectedSeries ?? "系列", isSelected: selectedSeries != nil, width: 34)
            }
            .buttonStyle(.plain)

            // 分隔线
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 0.5)
                .padding(.vertical, 8)

            // 状态筛选（中间）
            Menu {
                Button(action: { selectedReadStatus = nil }) {
                    HStack {
                        Text("不限")
                        if selectedReadStatus == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                ForEach(SessionReadStatusFilter.allCases, id: \.rawValue) { filter in
                    Button(action: { selectedReadStatus = filter }) {
                        HStack {
                            Text(filter.label)
                            if selectedReadStatus == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                filterMenuLabel(title: selectedReadStatus?.label ?? "状态", isSelected: selectedReadStatus != nil, width: 34)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: 0.5)
                .padding(.vertical, 8)

            // 搜索输入框（右侧）
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(Constants.Fonts.searchIcon)
                    .foregroundColor(.gray)
                TextField(Constants.UI.searchPlaceholder, text: $searchText)
                    .font(Constants.Fonts.searchInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        onSearchSubmit?()
                    }
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Constants.Fonts.searchIcon)
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Constants.SearchBar.innerHorizontalPadding)
            .padding(.vertical, Constants.SearchBar.innerVerticalPadding)
        }
        .frame(minHeight: Constants.SearchBar.rowMinHeight)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: Constants.SearchBar.cornerRadius))
    }
}
