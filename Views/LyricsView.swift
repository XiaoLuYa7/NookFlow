import SwiftUI

struct LyricsView: View {

    let lyrics: [LyricLine]
    let currentIndex: Int?
    let showTranslation: Bool
    let isLoading: Bool
    let statusText: String

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if lyrics.isEmpty {
                emptyView
            } else {
                lyricsScrollView
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("加载歌词...")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        Text(statusText.isEmpty ? "暂无歌词" : statusText)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lyrics Scroll

    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Top spacer for centering current line
                    Spacer(minLength: 24)

                    ForEach(Array(lyrics.enumerated()), id: \.element.id) { index, line in
                        lyricLineView(line: line, index: index)
                            .id(index)
                    }

                    // Bottom spacer
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: currentIndex) { _, newIndex in
                guard let newIndex else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Lyric Line

    @ViewBuilder
    private func lyricLineView(line: LyricLine, index: Int) -> some View {
        let isCurrent = index == currentIndex
        let isPast = currentIndex != nil && index < currentIndex!
        let isNear = currentIndex != nil && abs(index - currentIndex!) <= 1

        VStack(alignment: .leading, spacing: 2) {
            Text(line.words)
                .font(.system(
                    size: isCurrent ? 13 : 11,
                    weight: isCurrent ? .semibold : .medium,
                    design: .rounded
                ))
                .foregroundStyle(
                    isCurrent ? Color.white.opacity(0.95) :
                    isPast ? Color.white.opacity(0.30) :
                    isNear ? Color.white.opacity(0.55) :
                    Color.white.opacity(0.40)
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if showTranslation, let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: isCurrent ? 10 : 9, weight: .regular, design: .rounded))
                    .foregroundStyle(
                        isCurrent ? Color.white.opacity(0.60) :
                        isPast ? Color.white.opacity(0.20) :
                        Color.white.opacity(0.28)
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, isCurrent ? 4 : 2)
        .animation(.easeOut(duration: 0.20), value: isCurrent)
    }
}
