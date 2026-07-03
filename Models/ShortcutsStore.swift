import AppKit
import Foundation

struct ShortcutNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct ShortcutListError: Error, Equatable {
    let message: String
}

@MainActor
final class ShortcutsStore: ObservableObject {

    static let shared = ShortcutsStore()
    static let slotCount = 2

    @Published private(set) var slots: [ShortcutItem?] = [nil, nil]
    @Published private(set) var runningShortcutIDs: Set<UUID> = []
    @Published var notice: ShortcutNotice?

    private let defaults = UserDefaults.standard
    private let storageKey = "settings.shortcuts"
    private var noticeDismissalTask: Task<Void, Never>?

    private init() {
        load()
    }

    // MARK: - Slot Management

    func setShortcut(_ item: ShortcutItem?, at slot: Int) {
        guard slot >= 0, slot < Self.slotCount else { return }
        slots[slot] = item
        save()
    }

    func clearSlot(_ slot: Int) {
        setShortcut(nil, at: slot)
    }

    // MARK: - Execution

    func run(_ item: ShortcutItem) {
        guard !runningShortcutIDs.contains(item.id) else { return }
        runningShortcutIDs.insert(item.id)

        Task {
            let result = await Self.runShortcut(identifier: item.id)

            if !result.succeeded {
                let detail = result.message.isEmpty ? "请确认该快捷指令仍存在并允许被执行。" : result.message
                showNotice("“\(item.name)”执行失败。\(detail)")
                NSLog("ShortcutsStore: failed to run shortcut '\(item.name)': \(detail)")
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            runningShortcutIDs.remove(item.id)
        }
    }

    func isRunning(_ item: ShortcutItem) -> Bool {
        runningShortcutIDs.contains(item.id)
    }

    // MARK: - Fetch Available Shortcuts

    func fetchAvailableShortcuts() async -> Result<[ShortcutItem], ShortcutListError> {
        let result = await Self.listShortcuts()
        if case .failure(let error) = result {
            NSLog("ShortcutsStore: failed to list shortcuts: \(error.message)")
        }
        return result
    }

    // MARK: - Refresh Names

    /// Re-syncs display names for saved slots against a list explicitly loaded by the settings page.
    @discardableResult
    func reconcileSlots(with available: [ShortcutItem]) -> [ShortcutItem] {
        var missing: [ShortcutItem] = []
        var didChange = false

        for i in slots.indices {
            guard let saved = slots[i] else { continue }
            if let match = available.first(where: { $0.id == saved.id }) {
                if match.name != saved.name {
                    slots[i] = match
                    didChange = true
                }
            } else {
                missing.append(saved)
            }
        }

        if didChange {
            save()
        }

        return missing
    }

    // MARK: - Process Helpers

    private nonisolated static func runShortcut(identifier: UUID) async -> ProcessResult {
        await Task.detached(priority: .userInitiated) {
            await runShortcutsCommand(arguments: ["run", identifier.uuidString])
        }.value
    }

    private nonisolated static func listShortcuts() async -> Result<[ShortcutItem], ShortcutListError> {
        await Task.detached(priority: .userInitiated) {
            let result = await runShortcutsCommand(arguments: ["list", "--show-identifiers"])
            guard result.succeeded else {
                let message = result.message.isEmpty ? "无法读取快捷指令列表。" : result.message
                return .failure(ShortcutListError(message: message))
            }

            let items = result.output
                .split(separator: "\n")
                .compactMap { parseShortcutLine(String($0)) }

            return .success(items)
        }.value
    }

    private nonisolated static func runShortcutsCommand(arguments: [String]) async -> ProcessResult {
        guard !Task.isCancelled else {
            return ProcessResult(status: ProcessResult.cancelledStatus, output: "", errorOutput: "操作已取消")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let state = ProcessExecutionState()

        do {
            return try await withTaskCancellationHandler {
                try process.run()
                state.setRunning(process)
                if Task.isCancelled {
                    state.terminate()
                }

                async let outputData = readData(from: outputPipe.fileHandleForReading)
                async let errorData = readData(from: errorPipe.fileHandleForReading)
                async let status = waitForProcess(process)

                let terminationStatus = await status
                state.markFinished()

                let output = String(data: await outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: await errorData, encoding: .utf8) ?? ""

                if Task.isCancelled {
                    return ProcessResult(
                        status: ProcessResult.cancelledStatus,
                        output: output,
                        errorOutput: errorOutput.isEmpty ? "操作已取消" : errorOutput
                    )
                }

                return ProcessResult(status: terminationStatus, output: output, errorOutput: errorOutput)
            } onCancel: {
                state.terminate()
            }
        } catch {
            return ProcessResult(status: -1, output: "", errorOutput: error.localizedDescription)
        }
    }

    private nonisolated static func readData(from handle: FileHandle) async -> Data {
        await Task.detached(priority: .utility) {
            handle.readDataToEndOfFile()
        }.value
    }

    private nonisolated static func waitForProcess(_ process: Process) async -> Int32 {
        await Task.detached(priority: .utility) {
            process.waitUntilExit()
            return process.terminationStatus
        }.value
    }

    /// Parses a line like "Name (BFAB2667-A8BF-4FB5-A79C-1F48B446B906)"
    private nonisolated static func parseShortcutLine(_ line: String) -> ShortcutItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let openParen = trimmed.lastIndex(of: "("),
              let closeParen = trimmed.lastIndex(of: ")"),
              openParen < closeParen else {
            return nil
        }

        let name = trimmed[trimmed.startIndex..<openParen]
            .trimmingCharacters(in: .whitespaces)
        let idString = trimmed[trimmed.index(after: openParen)..<closeParen]
            .trimmingCharacters(in: .whitespaces)

        guard let uuid = UUID(uuidString: idString) else { return nil }
        guard !name.isEmpty else { return nil }

        return ShortcutItem(id: uuid, name: name)
    }

    private func showNotice(_ message: String) {
        noticeDismissalTask?.cancel()
        notice = ShortcutNotice(message: message)
        noticeDismissalTask = Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            if !Task.isCancelled {
                notice = nil
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ShortcutItem?].self, from: data) else {
            return
        }
        var loaded = decoded
        if loaded.count < Self.slotCount {
            loaded.append(contentsOf: repeatElement(nil, count: Self.slotCount - loaded.count))
        }
        slots = Array(loaded.prefix(Self.slotCount))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

private struct ProcessResult {
    static let cancelledStatus: Int32 = -999

    let status: Int32
    let output: String
    let errorOutput: String

    var succeeded: Bool {
        status == 0
    }

    var message: String {
        errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class ProcessExecutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isFinished = false

    func setRunning(_ process: Process) {
        lock.lock()
        if isFinished {
            lock.unlock()
            if process.isRunning {
                process.terminate()
            }
            return
        }

        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let process = isFinished ? nil : process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func markFinished() {
        lock.lock()
        isFinished = true
        process = nil
        lock.unlock()
    }
}
