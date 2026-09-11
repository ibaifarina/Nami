import SwiftUI

struct DiscoverView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: DiscoverViewModel

    init(environment: AppEnvironment) {
        _model = State(initialValue: DiscoverViewModel(environment: environment))
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                searchAndFilters
                if model.query.isEmpty, !model.recentSearches.isEmpty {
                    recentSearches
                }
                content
            }
            .contentPadding()
            .padding(.vertical, Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .topBarScrim()
        .background(AppColor.background)
        .navigationTitle("Discover")
        .onChange(of: model.query) { model.queryDidChange() }
        .onChange(of: model.filters) { model.filtersDidChange() }
        .task { await model.loadInitial() }
    }

    private var searchAndFilters: some View {
        HStack(spacing: Spacing.md) {
            searchBar
            filterBar
        }
    }

    private var searchBar: some View {
        @Bindable var model = model
        return HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search anime", text: $model.query)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .onSubmit { Task { await model.recordCurrentQuery() } }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 7)
        .frame(width: 280)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(AppColor.stroke))
    }

    private var filterBar: some View {
        @Bindable var model = model
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                FilterMenu(
                    label: "Genre",
                    anyLabel: "All Genres",
                    systemImage: "theatermasks",
                    selection: $model.filters.genre,
                    options: DiscoverFilters.genres.map { ($0.slug, $0.title) }
                )
                FilterMenu(
                    label: "Season",
                    anyLabel: "Any Season",
                    systemImage: "leaf",
                    selection: $model.filters.season,
                    options: AnimeSeason.allCases.map { ($0, $0.displayName) }
                )
                FilterMenu(
                    label: "Year",
                    anyLabel: "Any Year",
                    systemImage: "calendar",
                    selection: $model.filters.year,
                    options: DiscoverFilters.years.map { ($0, String($0)) }
                )
                FilterMenu(
                    label: "Format",
                    anyLabel: "Any Format",
                    systemImage: "rectangle.stack",
                    selection: $model.filters.subtype,
                    options: AnimeSubtype.allCases.map { ($0, $0.displayName) }
                )
                FilterMenu(
                    label: "Status",
                    anyLabel: "Any Status",
                    systemImage: "dot.radiowaves.left.and.right",
                    selection: $model.filters.status,
                    options: AnimeStatus.allCases.map { ($0, $0.displayName) }
                )
                FilterDropdown(
                    title: "Sort: \(model.filters.sort.displayName)",
                    systemImage: "arrow.up.arrow.down",
                    isActive: model.filters.sort != .popularity,
                    rows: DiscoverSort.allCases.map { sort in
                        FilterDropdownPanel<DiscoverSort>.Item(
                            id: sort.id,
                            label: sort.displayName,
                            value: sort,
                            isSelected: sort == model.filters.sort
                        )
                    },
                    onSelect: { model.filters.sort = $0 ?? .popularity }
                )
            }
            .padding(.vertical, Spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .defaultScrollAnchor(.trailing)
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Recent Searches")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    Task { await model.clearRecentSearches() }
                }
                .buttonStyle(.plain)
                .font(AppFont.cardMeta)
                .foregroundStyle(AppColor.brand)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(model.recentSearches, id: \.self) { value in
                        Button {
                            model.useRecentSearch(value)
                        } label: {
                            Text(value)
                                .font(AppFont.cardMeta)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .hoverFeedback(scale: 1.03)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Spacing.lg) {
                ForEach(0..<12, id: \.self) { _ in
                    PosterSkeleton()
                }
            }
        case .loaded(let items) where items.isEmpty:
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "No results",
                message: "Try a different search or clear some filters.",
                actionTitle: "Clear Filters",
                action: { model.clearFilters() }
            )
        case .loaded(let items):
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Spacing.lg) {
                ForEach(items) { anime in
                    AnimePosterCard(anime: anime) {
                        environment.router.push(.anime(id: anime.id), in: .discover)
                    }
                    .task {
                        await model.loadMoreIfNeeded(currentItem: anime)
                    }
                }
            }
            if model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, Spacing.md)
            }
        case .failed(let error):
            ErrorStateView(
                title: error.errorDescription ?? "Something went wrong",
                message: error.recoverySuggestion,
                technicalDetail: error.technicalDetail,
                onRetry: { Task { await model.retry() } }
            )
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: Layout.posterCardMinWidth,
                    maximum: Layout.posterCardMaxWidth
                ),
                spacing: Spacing.lg,
                alignment: .top
            )
        ]
    }
}

private struct FilterDropdown<Value: Hashable>: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var panelWidth: CGFloat = 200
    let rows: [FilterDropdownPanel<Value>.Item]
    let onSelect: (Value?) -> Void

    @State private var isExpanded = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            FilterChipLabel(
                text: title,
                systemImage: systemImage,
                isActive: isActive,
                isExpanded: isExpanded
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isExpanded, arrowEdge: .top) {
            FilterDropdownPanel(rows: rows) { value in
                onSelect(value)
                isExpanded = false
            }
            .frame(width: panelWidth)
        }
    }
}

private struct FilterDropdownPanel<Value: Hashable>: View {
    struct Item: Identifiable {
        let id: String
        let label: String
        let value: Value?
        let isSelected: Bool
    }

    let rows: [Item]
    let onSelect: (Value?) -> Void

    @State private var hoveredID: String?

    var body: some View {
        Group {
            if rows.count > 8 {
                ScrollView {
                    rowList
                }
                .frame(height: 300)
            } else {
                rowList
            }
        }
    }

    private var rowList: some View {
        VStack(spacing: 2) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                Button {
                    onSelect(row.value)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(row.label)
                            .font(AppFont.cardTitle)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.sm)
                        if row.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColor.brand)
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        highlightShape(isFirst: index == 0, isLast: index == rows.count - 1)
                            .fill(rowBackground(for: row))
                    }
                    .contentShape(highlightShape(isFirst: index == 0, isLast: index == rows.count - 1))
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        hoveredID = row.id
                    } else if hoveredID == row.id {
                        hoveredID = nil
                    }
                }
                .accessibilityAddTraits(row.isSelected ? .isSelected : [])
            }
        }
        .padding(Spacing.xxs)
    }

    /// Matches the corner curvature of the enclosing popover so the first and
    /// last row highlights nest concentrically inside the dropdown container.
    private func highlightShape(isFirst: Bool, isLast: Bool) -> UnevenRoundedRectangle {
        let inner = Radius.control - 2
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? Self.containerRadius - Spacing.xxs : inner,
            bottomLeadingRadius: isLast ? Self.containerRadius - Spacing.xxs : inner,
            bottomTrailingRadius: isLast ? Self.containerRadius - Spacing.xxs : inner,
            topTrailingRadius: isFirst ? Self.containerRadius - Spacing.xxs : inner,
            style: .circular
        )
    }

    private static var containerRadius: CGFloat { 18 }

    private func rowBackground(for row: Item) -> Color {
        if row.isSelected { return AppColor.brand.opacity(0.12) }
        if hoveredID == row.id { return Color.primary.opacity(0.05) }
        return .clear
    }
}

private struct FilterMenu<Value: Hashable>: View {
    let label: String
    let anyLabel: String
    let systemImage: String
    @Binding var selection: Value?
    let options: [(value: Value, label: String)]

    var body: some View {
        FilterDropdown(
            title: selectionTitle,
            systemImage: systemImage,
            isActive: selection != nil,
            rows: rows,
            onSelect: { selection = $0 }
        )
    }

    private var rows: [FilterDropdownPanel<Value>.Item] {
        [FilterDropdownPanel<Value>.Item(
            id: "any",
            label: anyLabel,
            value: nil,
            isSelected: selection == nil
        )] + options.map { option in
            FilterDropdownPanel<Value>.Item(
                id: "\(option.value)",
                label: option.label,
                value: option.value,
                isSelected: option.value == selection
            )
        }
    }

    private var selectionTitle: String {
        options.first { $0.value == selection }?.label ?? label
    }
}

private struct FilterChipLabel: View {
    let text: String
    var systemImage: String?
    let isActive: Bool
    var isExpanded = false

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Spacing.xxs + 2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(text)
                .font(AppFont.cardTitle)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(chevronColor)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .animation(.easeOut(duration: Motion.hover), value: isExpanded)
        }
        .foregroundStyle(isActive ? AppColor.buttonLabel : Color.primary)
        .padding(.leading, Spacing.sm)
        .padding(.trailing, Spacing.sm - 2)
        .padding(.vertical, 6)
        .background(Capsule().fill(background))
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        .scaleEffect(isHovering && !isActive ? 1.03 : 1)
        .animation(.easeOut(duration: Motion.hover), value: isHovering)
        .animation(.easeOut(duration: Motion.hover), value: isActive)
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isActive { return AppColor.buttonFill }
        return isHovering ? AppColor.surfaceElevated : AppColor.surface
    }

    private var border: Color {
        if isActive { return .clear }
        return isHovering ? Color.primary.opacity(0.18) : AppColor.stroke
    }

    private var iconColor: Color {
        guard !isActive else { return AppColor.buttonLabel.opacity(0.7) }
        return (isHovering ? AppColor.brand : Color.secondary).opacity(0.7)
    }

    private var chevronColor: Color {
        isActive ? AppColor.buttonLabel.opacity(0.7) : Color.secondary.opacity(0.8)
    }

    private var shadowOpacity: Double {
        if isActive { return 0.18 }
        return isHovering ? 0.10 : 0.03
    }

    private var shadowRadius: CGFloat {
        isActive ? 6 : (isHovering ? 5 : 2)
    }

    private var shadowY: CGFloat {
        isActive ? 3 : 1
    }
}

#if DEBUG
#Preview("Discover") {
    let environment = AppEnvironment.preview()
    DiscoverView(environment: environment)
        .environment(environment)
        .frame(width: 1100, height: 820)
}
#endif
