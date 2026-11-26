import SwiftUI

struct ShortcutsCardView: View {

    @ObservedObject private var store = ShortcutsStore.shared
    @EnvironmentObject private var settings: IslandSettings

    private var configuredShortcutCount: Int {
        store.slots.compactMap { $0 }.count
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 7) {
                header

                ForEach(0..<ShortcutsStore.slotCount, id: \.self) { index in
                    shortcutRow(slot: index)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let notice = store.notice {
                noticeView(notice)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(width: 13)

            Text("快捷指令")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.66))

            Spacer(minLength: 4)
        }
        .frame(height: 15)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("快捷指令，已配置 \(configuredShortcutCount) 个")
    }

    @ViewBuilder
    private func shortcutRow(slot: Int) -> some View {
        if let item = store.slots.indices.contains(slot) ? store.slots[slot] : nil {
            configuredShortcutRow(item)
        } else {
            addShortcutRow
        }
    }

    private func configuredShortcutRow(_ item: ShortcutItem) -> some View {
        let isRunning = store.isRunning(item)

        return Button {
            store.run(item)
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.07))

                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.62)
                    } else {
                        Image(systemName: shortcutSymbol(for: item.name))
                            .font(.system(size: 10, weight: .medium))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color.white.opacity(0.76))
                    }
                }
                .frame(width: 22, height: 22)

                Text(item.name)
                    .font(.system(size: 10.2, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isRunning ? "ellipsis" : "play.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(isRunning ? 0.38 : 0.86))
                    .frame(width: 12, height: 20)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ShortcutCardRowButtonStyle())
        .handCursor()
        .disabled(isRunning)
        .help("运行“\(item.name)”")
        .accessibilityLabel("运行快捷指令 \(item.name)")
        .accessibilityValue(isRunning ? "正在运行" : "未运行")
    }

    private var addShortcutRow: some View {
        Button {
            settings.shortcutsSettingsTrigger = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white.opacity(0.52))

                Text("添加快捷指令")
                    .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                Color.white.opacity(0.18),
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(ShortcutCardRowButtonStyle())
        .handCursor()
        .help("打开快捷指令设置")
        .accessibilityLabel("添加快捷指令")
    }

    private func shortcutSymbol(for name: String) -> String {
        let normalizedName = name.lowercased()
        let rules: [([String], String)] = [
            (["音乐", "识别"], "waveform"),
            (["歌曲", "听歌", "shazam"], "music.note"),
            (["图片", "照片", "截图", "相机"], "photo.fill.on.rectangle.fill"),
            (["翻译", "translate"], "character.bubble.fill"),
            (["文件", "文档", "folder", "file"], "folder.fill"),
            (["提醒", "待办", "闹钟"], "bell.fill"),
            (["链接", "网页", "url"], "link"),
            (["剪贴板", "复制"], "doc.on.clipboard.fill"),
            (["天气"], "cloud.sun.fill")
        ]

        for (keywords, symbol) in rules
        where keywords.contains(where: normalizedName.contains) {
            return symbol
        }

        return "bolt.fill"
    }

    private func noticeView(_ notice: ShortcutNotice) -> some View {
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
                .fill(Color.black.opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct ShortcutCardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
