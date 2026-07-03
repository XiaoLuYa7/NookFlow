import SwiftUI

@MainActor
final class AboutViewModel: ObservableObject {
    enum PresentedInfo: Identifiable {
        case update
        case privacy
        case license

        var id: Self { self }
    }

    @Published var presentedInfo: PresentedInfo?

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
        presentedInfo = .update
    }
}

struct AboutView: View {
    @StateObject private var model = AboutViewModel()
    let onFeedback: () -> Void

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: 980) {
            PageHeaderView(
                title: "关于 L-Nook",
                subtitle: "查看应用版本、运行信息与支持入口。",
                icon: "info.circle.fill"
            )
        } content: {
            brandCard
            supportCard
            legalCard
            footer
        }
        .alert(item: $model.presentedInfo) { info in
            switch info {
            case .update:
                Alert(
                    title: Text("当前版本 \(model.version)"),
                    message: Text("自动更新服务尚未接入。当前构建为 \(model.build)，后续接入更新源后会在这里检查新版本。"),
                    dismissButton: .default(Text("知道了"))
                )
            case .privacy:
                Alert(
                    title: Text("隐私说明"),
                    message: Text("L-Nook 的天气、日历、提醒事项和音乐能力仅在获得系统授权后工作。相关权限可随时在 macOS 系统设置中关闭。"),
                    dismissButton: .default(Text("完成"))
                )
            case .license:
                Alert(
                    title: Text("许可信息"),
                    message: Text("L-Nook 使用 Apple 提供的系统框架。第三方服务与内容仍受各自条款和许可约束。"),
                    dismissButton: .default(Text("完成"))
                )
            }
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
            Image(nsImage: AppBrandAsset.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 82, height: 82)
                .appShadow(AppShadowStyle.floating)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("L-Nook")
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
                    model.presentedInfo = .privacy
                }

                AboutLinkTile(
                    icon: "doc.text",
                    title: "许可信息",
                    subtitle: "查看系统框架与服务说明"
                ) {
                    model.presentedInfo = .license
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "heart")
            Text("感谢每一位愿意尝试 L-Nook 的用户。")
            Spacer(minLength: AppSpacing.md)
            Text("Made for macOS")
            Text("·")
            Text("© 2026 L-Nook")
        }
        .font(AppTypography.supporting)
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, AppSpacing.xs)
    }

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
