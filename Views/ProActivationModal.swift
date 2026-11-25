import AppKit
import SwiftUI

struct ProActivationModal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var manager: LicenseManager
    let requestedFeatureName: String?
    let onActivated: () -> Void
    let onClose: () -> Void

    @State private var activationCode = ""
    @State private var activationTask: Task<Void, Never>?
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            modalContent
                .frame(width: 600)
                .padding(26)
                .background(AppColor.solidSurface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppColor.border.opacity(0.72), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.16), radius: 30, y: 16)
                .padding(28)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                )
        }
        .onAppear {
            if !manager.isProUnlocked {
                manager.resetError()
                isCodeFocused = !manager.canResumeStoredLicense
            }
        }
        .onDisappear {
            activationTask?.cancel()
            activationTask = nil
        }
        .onExitCommand(perform: close)
        .accessibilityAddTraits(.isModal)
    }

    private var modalContent: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                AppBrandIconView(size: 62)
                    .shadow(color: AppColor.accent.opacity(0.16), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 5) {
                    Text("NOOKFLOW PRO")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColor.accent)

                    Text(manager.isProUnlocked ? "NookFlow Pro 已激活" : "解锁 NookFlow Pro")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundStyle(AppColor.textPrimary)
                }

                Spacer(minLength: 12)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(introTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                Text(introDetail)
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                benefit(
                    icon: "music.note",
                    title: "音乐与歌词",
                    detail: "播放卡片、胶囊歌词与桌面歌词"
                )
                benefit(
                    icon: "checklist",
                    title: "待办与提醒",
                    detail: "在灵动岛管理任务并同步系统提醒"
                )
            }

            assuranceStrip

            if manager.isProUnlocked {
                activatedSection
            } else if manager.canResumeStoredLicense {
                storedLicenseRecoverySection
            } else {
                activationSection
            }
        }
    }

    private var activationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("输入激活码")
                .font(AppTypography.rowTitle)
                .foregroundStyle(AppColor.textPrimary)

            TextField("NF-XXXXX-XXXXX-XXXXX", text: $activationCode)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .focused($isCodeFocused)
                .onChange(of: activationCode) { _, newValue in
                    activationCode = LicenseManager.formattedActivationCode(newValue)
                    manager.resetError()
                }
                .onSubmit(activate)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isCodeFocused ? AppColor.accent.opacity(0.70) : AppColor.border, lineWidth: 1)
                }

            if case let .error(message) = manager.state {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Button(action: activate) {
                HStack(spacing: 9) {
                    if manager.state == .activating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "key.fill")
                    }
                    Text(manager.state == .activating ? "正在激活" : "激活 NookFlow Pro")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(AppColor.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(activationCode.count < 18 || manager.state == .activating)
            .opacity(activationCode.count < 18 ? 0.54 : 1)

            HStack(spacing: 6) {
                Text("还没有激活码？")
                    .foregroundStyle(AppColor.textSecondary)
                Button("前往官网购买") {
                    openPurchasePage()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accent)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.accent)
            }
            .font(AppTypography.control)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var activatedSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("此设备已获得 Pro 使用许可")
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text("音乐与待办功能已经解锁，可以直接返回继续使用。")
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 12)
            Button("完成", action: close)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(16)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var storedLicenseRecoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已找到这台 Mac 的许可证", systemImage: "checkmark.shield.fill")
                .font(AppTypography.rowTitle)
                .foregroundStyle(AppColor.textPrimary)

            Text("无需重新购买或输入激活码。点击下方按钮后，macOS 可能要求你确认一次钥匙串访问。NookFlow 不会在后台突然弹出该提示。")
                .font(AppTypography.supporting)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if case let .error(message) = manager.state {
                Text(message)
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                activationTask?.cancel()
                activationTask = Task { @MainActor in
                    await manager.resumeStoredLicense()
                    guard !Task.isCancelled, manager.isProUnlocked else { return }
                    onActivated()
                }
            } label: {
                HStack(spacing: 9) {
                    if manager.state == .activating {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "key.horizontal.fill")
                    }
                    Text(manager.state == .activating ? "正在恢复" : "继续使用 NookFlow Pro")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(AppColor.accentGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(manager.state == .activating)
        }
        .padding(16)
        .background(AppColor.accentSoft.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var assuranceStrip: some View {
        HStack(spacing: 0) {
            assurance(icon: "creditcard", title: "一次购买")
            Divider().frame(height: 22)
            assurance(icon: "desktopcomputer", title: "一码一机")
            Divider().frame(height: 22)
            assurance(icon: "arrow.left.arrow.right", title: "支持迁移")
        }
        .padding(.vertical, 10)
        .background(AppColor.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func assurance(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(AppTypography.caption)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity)
    }

    private var introTitle: String {
        if manager.isProUnlocked {
            return "完整的音乐与待办体验已在这台 Mac 上启用。"
        }
        if let requestedFeatureName, !requestedFeatureName.isEmpty {
            return "激活后即可在灵动岛中使用“\(requestedFeatureName)”。"
        }
        return "一个激活码即可解锁音乐与待办的完整体验。"
    }

    private var introDetail: String {
        manager.isProUnlocked
            ? "许可由服务器签名并安全绑定本机设备密钥。"
            : "付费功能仍可提前设置，激活后立即生效，无需重新下载安装。"
    }

    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColor.accent)
                .frame(width: 36, height: 36)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppTypography.rowTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 0.7)
        }
    }

    private func activate() {
        guard activationCode.count >= 18, manager.state != .activating else { return }
        isCodeFocused = false
        activationTask?.cancel()
        activationTask = Task { @MainActor in
            await manager.activate(code: activationCode)
            guard !Task.isCancelled, manager.isProUnlocked else { return }
            onActivated()
        }
    }

    private func openPurchasePage() {
        guard let url = LicenseManager.purchaseURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func close() {
        activationTask?.cancel()
        activationTask = nil
        manager.resetError()
        onClose()
    }
}
