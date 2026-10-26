import Foundation

/// Moving through the playlist. Each move pauses, points at the new item and loads it, and the
/// completion answers once that item can be played or it is known that it cannot -- see
/// NativeAudioPlayerLoading.swift.
extension NativeAudioPlayer {

    /// Moves to the item with the given id. Answers false straight away for an id nothing
    /// carries, which leaves the playlist where it was -- see select() in definitions.ts --
    /// and otherwise answers through the completion once the item has loaded or failed to.
    @discardableResult
    func select(_ id: String, _ completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard let index = playerItems.firstIndex(where: { $0.id == id }) else {
            completion(false)
            return false
        }

        pause()
        currentIndex = index
        load(completion)
        return true
    }

    @discardableResult
    func next(_ completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard !playerItems.isEmpty else {
            completion(false)
            return false
        }

        pause()

        if currentIndex < (playerItems.count - 1) {
            currentIndex += 1
        } else {
            currentIndex = 0
        }

        load(completion)
        return true
    }

    @discardableResult
    func previous(_ completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        guard !playerItems.isEmpty else {
            completion(false)
            return false
        }

        pause()

        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = playerItems.count - 1
        }

        load(completion)
        return true
    }
}
