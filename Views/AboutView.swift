import SwiftUI

@MainActor
final class AboutViewModel: ObservableObject {
    enum LegalInfo: Identifiable {
        case privacy
        case license

        var id: Self { self }
    }

    @Published var presentedLegalInfo: LegalInfo?
    @Published var isShowingUpdateInfo = false

    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var architecture: String {
#if arch(arm64)
        "Apple Silicon"
#elseif arch(x86_64)
        "Intel"
#else
        "Unknown"
#endif
    }

    func checkForUpdates() {
        isShowingUpdateInfo = true
    }
}

struct AboutView: View {
    @StateObject private var model = AboutViewModel()
    let onFeedback: () -> Void

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: 1120) {
            PageHeaderView(
                title: "关于 NookFlow",
                subtitle: "查看应用版本、运行信息与支持入口。",
                icon: "info.circle.fill"
            )
        } content: {
            brandCard
            supportCard
            legalCard
            footer
        }
        .alert("当前版本 \(model.version)", isPresented: $model.isShowingUpdateInfo) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("自动更新服务尚未接入。当前构建为 \(model.build)，后续接入更新源后会在这里检查新版本。")
        }
        .sheet(item: $model.presentedLegalInfo) { info in
            AboutLegalDocumentView(info: info)
        }
    }

    private var brandCard: some View {
        SettingsSectionCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xxl) {
                    brandIdentity
                    Spacer(minLength: AppSpacing.xl)
                    brandFacts
                }

                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    brandIdentity
                    brandFacts
                }
            }
            .padding(AppSpacing.sm)
        }
    }

    private var brandIdentity: some View {
        HStack(spacing: AppSpacing.xl) {
            AppBrandIconView(size: 82)
                .appShadow(AppShadowStyle.floating)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("NookFlow")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                Text("让 Mac 顶部区域更聪明，也更安静。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColor.textSecondary)

                HStack(spacing: AppSpacing.sm) {
                    AboutTag(text: "Version \(model.version)")
                    AboutTag(text: "Build \(model.build)")
                }
            }
        }
    }

    private var brandFacts: some View {
        HStack(spacing: AppSpacing.md) {
            AboutMetric(value: model.architecture, label: "运行架构", icon: "cpu")
            AboutMetric(value: "macOS", label: "原生应用", icon: "macwindow")
        }
    }

    private var supportCard: some View {
        SettingsSectionCard(
            title: "支持与维护",
            subtitle: "遇到问题时，可以从这里快速收集信息。"
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: AppSpacing.sm, alignment: .top),
                    GridItem(.flexible(), spacing: AppSpacing.sm, alignment: .top)
                ],
                spacing: AppSpacing.sm
            ) {
                AboutSupportTile(
                    icon: "arrow.triangle.2.circlepath",
                    title: "检查更新",
                    subtitle: "查看当前版本状态",
                    actionTitle: "检查",
                    action: model.checkForUpdates
                )
                AboutSupportTile(
                    icon: "bubble.left.and.text.bubble.right",
                    title: "发送反馈",
                    subtitle: "告诉我们你的想法或遇到的问题",
                    actionTitle: "反馈",
                    action: onFeedback
                )
            }
        }
    }

    private var legalCard: some View {
        SettingsSectionCard(
            title: "隐私与许可",
            subtitle: "了解应用使用系统能力时遵循的原则。"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: AppSpacing.sm)],
                spacing: AppSpacing.sm
            ) {
                AboutLinkTile(
                    icon: "hand.raised",
                    title: "隐私说明",
                    subtitle: "查看权限与本地数据说明"
                ) {
                    model.presentedLegalInfo = .privacy
                }

                AboutLinkTile(
                    icon: "doc.text",
                    title: "许可信息",
                    subtitle: "查看系统框架与服务说明"
                ) {
                    model.presentedLegalInfo = .license
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "heart")
            Text("感谢每一位愿意尝试 NookFlow 的用户。")
            Spacer(minLength: AppSpacing.md)
            Text("Made for macOS")
            Text("·")
            Text("© 2026 NookFlow")
        }
        .font(AppTypography.supporting)
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, AppSpacing.xs)
    }

}

private struct AboutLegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss

    let info: AboutViewModel.LegalInfo

    private var document: AboutLegalDocument {
        switch info {
        case .privacy: .privacy
        case .license: .license
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(AppColor.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    Text(document.introduction)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AppSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                                .fill(AppColor.accentSoft.opacity(0.56))
                        }

                    ForEach(document.sections) { section in
                        AboutLegalSectionView(section: section)
                    }

                    if !document.references.isEmpty {
                        referenceSection
                    }

                    Text(document.footer)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.xxl)
            }
            .scrollIndicators(.automatic)

            Divider()
                .overlay(AppColor.divider)

            HStack {
                Text("NookFlow · 更新于 2026 年 7 月 13 日")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textTertiary)

                Spacer()

                Button("完成") {
                    dismiss()
                }
                .buttonStyle(AppButtonStyle(role: .primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.md)
        }
        .frame(width: 640, height: 680)
        .background(AppColor.pageBackground)
    }

    private var header: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: document.icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 42, height: 42)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(AppColor.accentSoft)
                }

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(document.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(document.subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: AppControlStyle.iconButtonSize, height: AppControlStyle.iconButtonSize)
            }
            .buttonStyle(AppButtonStyle(role: .quiet))
            .help("关闭")
        }
        .padding(AppSpacing.xxl)
    }

    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("相关条款与来源", systemImage: "link")
                .font(AppTypography.rowTitle)
                .foregroundStyle(AppColor.textPrimary)

            ForEach(document.references) { reference in
                Link(destination: reference.url) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(reference.title)
                            .font(AppTypography.supporting)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.accent)
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
        .padding(.top, AppSpacing.sm)
    }
}

private struct AboutLegalSectionView: View {
    let section: AboutLegalSection

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: section.icon)
                .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: AppIconStyle.rowFrame, height: AppIconStyle.rowFrame)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(AppColor.accentSoft)
                }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(section.title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)

                Text(section.body)
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(section.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Circle()
                            .fill(AppColor.accent.opacity(0.72))
                            .frame(width: 5, height: 5)
                        Text(item)
                            .font(AppTypography.supporting)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AboutLegalDocument {
    let title: String
    let subtitle: String
    let icon: String
    let introduction: String
    let sections: [AboutLegalSection]
    let references: [AboutLegalReference]
    let footer: String

    static let privacy = AboutLegalDocument(
        title: "隐私说明",
        subtitle: "权限、本地数据与联网请求",
        icon: "hand.raised.fill",
        introduction: "NookFlow 采用本地优先与按需授权原则。NookFlow 不会出售你的个人信息，不包含广告追踪，也不会创建独立的云端用户账户或用户画像。",
        sections: [
            AboutLegalSection(
                title: "系统权限",
                icon: "checkmark.shield",
                body: "只有在相关功能需要时，NookFlow 才会请求 macOS 权限。拒绝权限不会影响无关功能。",
                items: [
                    "定位：用于显示本地天气，以及在创建待办时填写当前位置。天气功能会将近似经纬度发送至 Open-Meteo 获取预报。",
                    "提醒事项与日历：通过 EventKit 读取对应内容；只有在你执行新建、恢复、完成或删除等操作时才会修改提醒事项。",
                    "自动化：通过 Apple Events 读取已启用音乐应用的播放状态、歌曲名称、艺人、专辑、时长与播放进度，不读取账号密码。",
                    "通知：用于发送你主动启用的天气、设备状态和日常提醒，可随时在系统设置中关闭。"
                ]
            ),
            AboutLegalSection(
                title: "保存在本机的数据",
                icon: "internaldrive",
                body: "应用设置、模块顺序、快捷应用、快捷指令和歌词缓存保存在当前 Mac。NookFlow 不提供自有云同步服务。",
                items: [
                    "文件与应用入口只访问你选择或系统允许访问的位置。",
                    "歌词缓存包含歌曲名称、艺人和歌词文本，用于减少重复请求。",
                    "卸载应用前，你可以在设置中重置可重置的偏好；macOS 可能继续保留应用偏好数据，直至你手动移除。"
                ]
            ),
            AboutLegalSection(
                title: "联网请求",
                icon: "network",
                body: "联网功能开启后，以下信息会直接发送至对应服务。外部服务可能同时收到 IP 地址和常规请求信息，并按各自政策处理。",
                items: [
                    "天气：向 Open-Meteo 发送近似经纬度并接收天气数据。",
                    "歌词：向 QQ 音乐、酷狗音乐、LRCLIB 及第三方网易云音乐接口发送歌曲名称、艺人、专辑和时长，用于匹配歌词。",
                    "封面：向 Apple iTunes Search API 发送歌曲元数据，用于查找缺失的专辑封面。"
                ]
            ),
            AboutLegalSection(
                title: "你的控制权",
                icon: "slider.horizontal.3",
                body: "你可以在 NookFlow 设置中停用功能，也可以在“系统设置 - 隐私与安全性”中撤回定位、日历、提醒事项、自动化和通知权限。撤回后，对应功能将停止访问相关数据。",
                items: [
                    "如对隐私说明有疑问，请联系 lujunfeng.lucky@foxmail.com。"
                ]
            )
        ],
        references: [
            AboutLegalReference(title: "Open-Meteo 条款与隐私", url: URL(string: "https://open-meteo.com/en/terms")!),
            AboutLegalReference(title: "Apple 隐私政策", url: URL(string: "https://www.apple.com/legal/privacy/")!)
        ],
        footer: "本说明会随 NookFlow 的功能和数据处理方式更新。若未来加入账号、云同步、分析服务或新的数据来源，将在此处说明。"
    )

    static let license = AboutLegalDocument(
        title: "许可信息",
        subtitle: "应用、系统框架与外部服务",
        icon: "doc.text.fill",
        introduction: "NookFlow 由其开发者提供。应用中的系统能力、天气数据、音乐元数据、歌词和第三方商标分别受其权利人条款约束。",
        sections: [
            AboutLegalSection(
                title: "NookFlow 应用",
                icon: "app.badge",
                body: "© 2026 NookFlow。当前未发布开源许可证。除适用法律另有规定或获得书面授权外，不授予复制、修改、再分发或创建衍生作品的权利。",
                items: [
                    "应用按现状提供，具体授权范围以发布渠道展示的最终用户许可协议为准。"
                ]
            ),
            AboutLegalSection(
                title: "Apple 系统框架",
                icon: "apple.logo",
                body: "NookFlow 使用 SwiftUI、AppKit、Foundation、Core Location、EventKit、UserNotifications、Network、SwiftData、Quick Look 和其他 Apple SDK 能力。",
                items: [
                    "Apple、macOS、Apple Music 及相关名称和标志是 Apple Inc. 的商标。Apple 系统框架受 Apple 适用许可条款约束。"
                ]
            ),
            AboutLegalSection(
                title: "天气与音乐数据服务",
                icon: "cloud.sun",
                body: "天气数据由 Open-Meteo 提供，并按 CC BY 4.0 许可使用。免费 API 仅允许符合其条款的非商业用途；商业发布前应确认并使用适合的服务方案。",
                items: [
                    "专辑封面和音乐搜索结果可能来自 Apple iTunes Search API，使用受 Apple 对推广内容和媒体服务的相关条款约束。",
                    "歌词匹配可能使用 QQ 音乐、酷狗音乐、LRCLIB 及第三方网易云音乐接口；歌词及相关元数据的权利归原作者、发行方或服务提供者所有。"
                ]
            ),
            AboutLegalSection(
                title: "第三方名称与内容",
                icon: "building.2",
                body: "NookFlow 对第三方应用、服务或内容的提及仅用于说明兼容性。所有商标、图标、专辑封面、歌词和其他内容均归各自权利人所有。",
                items: [
                    "第三方服务的可用性、准确性和许可条款可能变化，NookFlow 不保证其持续可用。",
                    "许可问题可联系 lujunfeng.lucky@foxmail.com。"
                ]
            )
        ],
        references: [
            AboutLegalReference(title: "Open-Meteo 服务与 CC BY 4.0 说明", url: URL(string: "https://open-meteo.com/en/terms")!),
            AboutLegalReference(title: "Apple iTunes Search API", url: URL(string: "https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/")!),
            AboutLegalReference(title: "Apple 媒体服务条款", url: URL(string: "https://www.apple.com/legal/internet-services/")!)
        ],
        footer: "此页面用于说明 NookFlow 当前版本涉及的主要许可来源，不替代各服务提供者发布的完整条款。正式商业发布前应根据发行地区和业务模式完成合规审查。"
    )
}

private struct AboutLegalSection: Identifiable {
    let title: String
    let icon: String
    let body: String
    let items: [String]

    var id: String { title }
}

private struct AboutLegalReference: Identifiable {
    let title: String
    let url: URL

    var id: String { url.absoluteString }
}

private struct AboutTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.caption.monospacedDigit())
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(AppColor.controlFill)
            }
    }
}

private struct AboutMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.accent)
            Text(value)
                .font(AppTypography.rowTitle)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(AppSpacing.md)
        .frame(width: 116, height: 92, alignment: .leading)
        .appSurface(.inset, radius: AppRadius.row)
    }
}

private struct AboutSupportTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: AppIconStyle.rowFrame, height: AppIconStyle.rowFrame)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.accentSoft)
                    }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AppSpacing.md)

                Text(actionTitle)
                    .font(AppTypography.control)
                    .foregroundStyle(AppColor.accent)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
        .buttonStyle(AppButtonStyle(role: .secondary))
    }
}

private struct AboutLinkTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: AppIconStyle.rowSize, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: AppIconStyle.rowFrame, height: AppIconStyle.rowFrame)
                    .background {
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(AppColor.accentSoft)
                    }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.rowTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: AppSpacing.md)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        }
        .buttonStyle(AppButtonStyle(role: .quiet))
    }
}
