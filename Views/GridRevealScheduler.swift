import SwiftUI

@MainActor
final class GridRevealScheduler: ObservableObject {
    @Published private(set) var revealedIDs = Set<String>()

    private var task: Task<Void, Never>?
    private var generation = 0

    deinit {
        task?.cancel()
    }

    func schedule(
        ids: [String],
        staggered: Bool,
        revealAnimation: Animation,
        exitAnimation: Animation,
        staggerDelay: TimeInterval,
        maximumDelay: TimeInterval
    ) {
        task?.cancel()
        task = nil
        generation &+= 1
        let currentGeneration = generation
        let visibleIDs = Set(ids)

        withAnimation(exitAnimation) {
            revealedIDs.formIntersection(visibleIDs)
        }

        guard staggered else {
            withAnimation(revealAnimation) {
                revealedIDs.formUnion(visibleIDs)
            }
            return
        }

        let pendingIDs = ids.enumerated().compactMap { index, id -> (String, TimeInterval)? in
            guard !revealedIDs.contains(id) else { return nil }
            return (id, min(Double(index) * staggerDelay, maximumDelay))
        }

        task = Task { @MainActor [weak self] in
            var previousDelay: TimeInterval = 0

            for (id, delay) in pendingIDs {
                let wait = delay - previousDelay
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                }
                guard let self, !Task.isCancelled, self.generation == currentGeneration else { return }

                _ = withAnimation(revealAnimation) {
                    self.revealedIDs.insert(id)
                }
                previousDelay = delay
            }

            guard let self, self.generation == currentGeneration else { return }
            self.task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation &+= 1
    }
}
