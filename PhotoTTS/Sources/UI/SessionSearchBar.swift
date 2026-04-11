import SwiftUI

struct SessionSearchBar: View {
    @Binding var searchText: String
    @Binding var selectedSeries: String?
    let seriesOptions: [String]
    let unselectedButtonLabel: String
    let unselectedMenuLabel: String
    let onSearchSubmit: (() -> Void)?

    init(
        searchText: Binding<String>,
        selectedSeries: Binding<String?>,
        seriesOptions: [String],
        unselectedButtonLabel: String = "系列",
        unselectedMenuLabel: String = "不限",
        onSearchSubmit: (() -> Void)? = nil
    ) {
        self._searchText = searchText
        self._selectedSeries = selectedSeries
        self.seriesOptions = seriesOptions
        self.unselectedButtonLabel = unselectedButtonLabel
        self.unselectedMenuLabel = unselectedMenuLabel
        self.onSearchSubmit = onSearchSubmit
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        Constants.DeviceScale.adaptiveSize(iPhone: value)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 系列筛选（左侧）
            Menu {
                Button(action: { selectedSeries = nil }) {
                    HStack {
                        Text(unselectedMenuLabel)
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
                HStack(spacing: scaled(4)) {
                    Text(selectedSeries ?? unselectedButtonLabel)
                        .font(Constants.Fonts.searchInput)
                        .foregroundColor(selectedSeries == nil ? .primary : .blue)
                    Image(systemName: "chevron.down")
                        .font(Constants.Fonts.searchIcon)
                        .foregroundColor(selectedSeries == nil ? .gray : .blue)
                }
                .padding(.horizontal, scaled(10))
                .padding(.vertical, Constants.SearchBar.innerVerticalPadding)
            }
            .buttonStyle(.plain)

            // 分隔线
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
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: Constants.SearchBar.cornerRadius))
    }
}
