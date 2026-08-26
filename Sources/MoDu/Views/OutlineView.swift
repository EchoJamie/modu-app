import SwiftUI

struct OutlineView: View {
    @EnvironmentObject private var model: ReaderViewModel
    let items: [OutlineItem]
    let pane: ReaderPaneID

    private var theme: ResolvedReaderTheme { model.resolvedTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("大纲")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.divider.opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 15)
            .frame(height: 38)

            Divider().overlay(theme.divider.opacity(0.75))

            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 21, weight: .light))
                    Text("这篇文档没有标题")
                        .font(.system(size: 14))
                }
                .foregroundStyle(theme.secondary.opacity(0.8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(items) { item in
                                outlineRow(item)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: model.selectedOutlineID(for: pane)) { selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(theme.chrome.opacity(theme.isDark ? 0.72 : 0.62))
    }

    private func outlineRow(_ item: OutlineItem) -> some View {
        let isSelected = model.selectedOutlineID(for: pane) == item.id
        return Button {
            model.scroll(to: item, in: pane)
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? theme.accent : .clear)
                    .frame(width: 3, height: 20)
                Text(item.title)
                    .font(.system(
                        size: item.level == 1 ? 15.5 : 14.5,
                        weight: item.level <= 2 ? .medium : .regular
                    ))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected
                ? theme.foreground
                : theme.secondary)
            .padding(.leading, CGFloat(max(0, item.level - 1)) * 11)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                        ? theme.accent.opacity(theme.isDark ? 0.2 : 0.1)
                        : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
    }
}
