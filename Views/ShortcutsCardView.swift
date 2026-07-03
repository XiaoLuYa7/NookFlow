import SwiftUI

struct ShortcutsCardView: View {

    @ObservedObject private var store = ShortcutsStore.shared
    @EnvironmentObject private var settings: IslandSettings

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .center, spacing: 8) {
                ForEach(0..<ShortcutsStore.slotCount, id: \.self) { index in
                    shortcutPill(slot: index)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if let notice = store.notice {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.85))

                    Text(notice.message)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.48))
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Pill

    @ViewBuilder
    private func shortcutPill(slot: Int) -> some View {
        let item = store.slots.indices.contains(slot) ? store.slots[slot] : nil
        let tint = item.map(shortcutTint)

        Button {
            if let item {
                store.run(item)
            } else {
                settings.shortcutsSettingsTrigger = true
            }
        } label: {
            let isRunning = item.map { store.isRunning($0) } ?? false

            HStack(spacing: 9) {
                ZStack {
                    if isRunning {
                        ProgressView()
                            .scaleEffect(0.45)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: item != nil ? "bolt.circle.fill" : "plus.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                item != nil
                                    ? Color.white.opacity(0.92)
                                    : Color.white.opacity(0.36)
                            )
                    }
                }
                .frame(width: 16, height: 16)

                Text(item?.name ?? "未设置快捷指令")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        item != nil
                            ? Color.white.opacity(0.86)
                            : Color.white.opacity(0.42)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            .background {
                if let tint {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.78),
                                    tint.opacity(0.58)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.07))
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .handCursor()
        .disabled(item.map { store.isRunning($0) } ?? false)
        .opacity(item == nil ? 0.6 : 1.0)
    }

    private func shortcutTint(_ item: ShortcutItem) -> Color {
        let palette: [Color] = [
            Color(red: 0.20, green: 0.76, blue: 0.34),
            Color(red: 0.06, green: 0.64, blue: 0.94),
            Color(red: 0.58, green: 0.32, blue: 0.86),
            Color(red: 1.00, green: 0.47, blue: 0.36),
            Color(red: 0.96, green: 0.36, blue: 0.76),
            Color(red: 0.95, green: 0.66, blue: 0.08),
            Color(red: 0.24, green: 0.45, blue: 0.86),
            Color(red: 0.16, green: 0.68, blue: 0.62)
        ]
        let stableValue = item.id.uuidString.unicodeScalars.reduce(UInt(0)) {
            ($0 &* 31) &+ UInt($1.value)
        }
        return palette[Int(stableValue % UInt(palette.count))]
    }
}
