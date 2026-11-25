import Sparkle

@MainActor
final class AppUpdateController {
    static let shared = AppUpdateController()

    private let updaterController: SPUStandardUpdaterController
    private var hasStarted = false

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updaterController.startUpdater()
    }

    func checkForUpdates() {
        start()
        updaterController.checkForUpdates(nil)
    }
}
