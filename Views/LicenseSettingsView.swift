import SwiftUI

struct LicenseSettingsView: View {
    @ObservedObject var manager: LicenseManager
    @State private var activationCode = ""
    @State private var isShowingDeactivateConfirmation = false
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        SettingsPageScaffold(contentMaxWidth: 920) {
            PageHeaderView(
                title: "许可",
                subtitle: "激活 NookFlow Pro，或管理这台 Mac 的设备许可。",
                icon: "key.fill"
            )
        } content: {
            statusCard
            activationCard
            devicePolicyCard
        }
        .task {
            await manager.refreshIfNeeded()
        }
        .confirmationDialog(
            "要停用这台 Mac 吗？",
            isPresented: $isShowingDeactivateConfirmation
        ) {
            Button("停用并释放激活码", role: .destructive) {
                Task { await manager.deactivate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("停用后，Pro 功能会关闭，激活码可以在另一台 Mac 上使用。")
        }
    }

    private var statusCard: some View {
        SettingsSectionCard {
            HStack(spacing: AppSpacing.xl) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(manager.isProUnlocked ? Color.green.opacity(0.12) : AppColor.controlFill)
                    Image(systemName: manager.isProUnlocked ? "checkmark.seal.fill" : "lock.open")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(manager.isProUnlocked ? Color.green : AppColor.textTertiary)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(manager.isProUnlocked ? "NookFlow Pro 已激活" : "当前使用免费版本")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(statusDescription)
                        .font(AppTypography.supporting)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: AppSpacing.lg)

                if manager.isProUnlocked {
                    Button("停用设备") {
                        isShowingDeactivateConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(AppSpacing.sm)
        }
    }

    private var activationCard: some View {
        SettingsSectionCard(
            title: manager.isProUnlocked ? "设备许可" : "激活 NookFlow Pro",
            subtitle: manager.isProUnlocked
                ? "一个激活码同时只能绑定一台设备。"
                : "输入购买后收到的激活码，无需重新下载安装。"
        ) {
            if manager.isProUnlocked {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    licenseDetails
                    if manager.needsDeviceKeyAuthorization {
                        storedLicenseRecovery
                    }
                }
            } else if manager.canResumeStoredLicense {
                storedLicenseRecovery
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.sm) {
                        TextField("NF-XXXXX-XXXXX-XXXXX", text: $activationCode)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .focused($isCodeFocused)
                            .onChange(of: activationCode) { _, newValue in
                                activationCode = LicenseManager.formattedActivationCode(newValue)
                                manager.resetError()
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .frame(height: 46)
                            .background(AppColor.controlFill, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                    .stroke(isCodeFocused ? AppColor.accent.opacity(0.7) : AppColor.border, lineWidth: 1)
                            }

                        Button {
                            isCodeFocused = false
                            Task { await manager.activate(code: activationCode) }
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                if manager.state == .activating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "key.fill")
                                }
                                Text(manager.state == .activating ? "正在激活" : "激活")
                            }
                            .frame(minWidth: 112)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(activationCode.count < 18 || manager.state == .activating)
                    }

                    if case let .error(message) = manager.state {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(AppTypography.supporting)
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
    }

    private var licenseDetails: some View {
        HStack(spacing: 0) {
            licenseFact(title: "版本", value: "Pro")
            Divider().frame(height: 42)
            licenseFact(title: "授权方式", value: "单设备")
            Divider().frame(height: 42)
            licenseFact(title: "离线使用", value: "最长 30 天")
        }
        .padding(.vertical, AppSpacing.sm)
    }

    private var storedLicenseRecovery: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 38, height: 38)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("已找到这台 Mac 的许可证")
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("无需重新输入激活码。由你主动确认一次钥匙串访问即可继续使用。")
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer(minLength: AppSpacing.md)

            Button(manager.state == .activating ? "正在恢复" : "继续使用 Pro") {
                Task { await manager.resumeStoredLicense() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.state == .activating)
        }
        .padding(AppSpacing.md)
        .background(AppColor.accentSoft.opacity(0.62), in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    }

    private var devicePolicyCard: some View {
        SettingsSectionCard(
            title: "一码一机",
            subtitle: "设备绑定以本机密钥为依据，不读取硬件序列号。"
        ) {
            VStack(spacing: 0) {
                policyRow(
                    icon: "key.horizontal",
                    title: "本机设备密钥",
                    subtitle: "首次激活时创建，并以仅限本机方式保存在钥匙串。"
                )
                Divider().padding(.leading, 48)
                policyRow(
                    icon: "lock.shield",
                    title: "服务器签名许可",
                    subtitle: "App 只保存服务器签名结果，无法在本地伪造 Pro 状态。"
                )
                Divider().padding(.leading, 48)
                policyRow(
                    icon: "arrow.left.arrow.right",
                    title: "支持设备转移",
                    subtitle: "在旧设备停用后，可用同一激活码绑定新设备。"
                )
            }
        }
    }

    private func licenseFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppTypography.caption).foregroundStyle(AppColor.textTertiary)
            Text(value).font(AppTypography.rowTitle).foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
    }

    private func policyRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 34, height: 34)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AppTypography.rowTitle).foregroundStyle(AppColor.textPrimary)
                Text(subtitle).font(AppTypography.supporting).foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.md)
    }

    private var statusDescription: String {
        if manager.isProUnlocked {
            return "此设备已获得 Pro 功能使用许可。"
        }
        if case let .error(message) = manager.state {
            return message
        }
        return "免费功能可持续使用，Pro 功能需要激活码。"
    }

}
