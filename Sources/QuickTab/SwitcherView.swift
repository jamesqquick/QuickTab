import SwiftUI

struct SwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(QuickTabTheme.divider)
            results
            Divider().overlay(QuickTabTheme.divider)
            footer
        }
        .background(QuickTabTheme.panelGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 34, y: 18)
        .padding(18)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(QuickTabTheme.electric)
                    .frame(width: 39, height: 39)
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(QuickTabTheme.ink)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.modeLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.7)
                    .foregroundStyle(QuickTabTheme.electric)
                Text(viewModel.query.isEmpty ? "Where do you want to go?" : viewModel.query)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuickTabTheme.paper)
                    .lineLimit(1)
            }

            Spacer()
            Text("\(viewModel.results.count)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(QuickTabTheme.paperMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 19)
    }

    @ViewBuilder
    private var results: some View {
        if viewModel.results.isEmpty {
            VStack(spacing: 13) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(QuickTabTheme.violet)
                Text("No window found")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(QuickTabTheme.paper)
                Text("Try fewer characters or a different app name.")
                    .font(.system(size: 13))
                    .foregroundStyle(QuickTabTheme.paperMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                            SwitcherRow(
                                result: result,
                                isSelected: index == viewModel.selectedIndex,
                                onHover: {
                                    if settings.hoverSelects { viewModel.select(index) }
                                },
                                onSelect: {
                                    viewModel.select(index)
                                    viewModel.commit()
                                }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Keycap(label: "↑↓")
            Text("navigate")
            Keycap(label: "↩")
            Text("switch")
            Spacer()
            Keycap(label: "⌘W")
            Text("close")
            Keycap(label: "⌘Q")
            Text("quit")
            Keycap(label: "esc")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(QuickTabTheme.paperMuted)
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }
}

private struct SwitcherRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onHover: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 13) {
                Image(nsImage: result.item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    HighlightedText(
                        value: result.item.title,
                        highlighted: result.matchedTitleIndices,
                        baseColor: QuickTabTheme.paper,
                        highlightColor: QuickTabTheme.electric
                    )
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(result.item.subtitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if result.item.isMinimized { StatusPill(label: "MINIMIZED", color: QuickTabTheme.coral) }
                        if result.item.isHidden { StatusPill(label: "HIDDEN", color: QuickTabTheme.violet) }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(QuickTabTheme.paperMuted)
                }
                Spacer(minLength: 12)
                if isSelected {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(QuickTabTheme.ink)
                        .padding(8)
                        .background(QuickTabTheme.electric, in: Circle())
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.white.opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? QuickTabTheme.electric.opacity(0.46) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}

private struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct HighlightedText: View {
    let value: String
    let highlighted: IndexSet
    let baseColor: Color
    let highlightColor: Color

    var body: some View {
        value.enumerated().reduce(Text("")) { partial, pair in
            partial + Text(String(pair.element))
                .foregroundColor(highlighted.contains(pair.offset) ? highlightColor : baseColor)
                .fontWeight(highlighted.contains(pair.offset) ? .bold : .regular)
        }
    }
}
