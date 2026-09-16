import Foundation
import Darwin

nonisolated enum DroppedInputError: Error, Equatable, Sendable {
    case alreadyConsumed
    case unsafeEphemeralInputsRoot
    case receivedFileOutsideOwnedDirectory
    case receivedFileIsNotRegular
}

nonisolated private struct SecurityScopedFileAccess: Sendable {
    let start: @Sendable (URL) -> Bool
    let stop: @Sendable (URL) -> Void

    static let system = SecurityScopedFileAccess(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

nonisolated struct DroppedInput: Equatable, Sendable {
    typealias PromiseReceiver = @Sendable (
        _ destinationDirectory: URL,
        _ completion: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) -> Void

    private static let defaultEphemeralInputsRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("Dropshot-EphemeralInputs", isDirectory: true)

    private enum Source: Sendable {
        case direct(URL, SecurityScopedFileAccess)
        case promise(PromiseStorage)
    }

    private let source: Source

    init(fileURL: URL) {
        source = .direct(fileURL, .system)
    }

    init(
        fileURL: URL,
        startAccessingSecurityScopedResource: @escaping @Sendable (URL) -> Bool,
        stopAccessingSecurityScopedResource: @escaping @Sendable (URL) -> Void
    ) {
        source = .direct(fileURL, SecurityScopedFileAccess(
            start: startAccessingSecurityScopedResource,
            stop: stopAccessingSecurityScopedResource
        ))
    }

    init(
        receivePromisedFile: @escaping PromiseReceiver,
        ephemeralInputsRoot: URL = DroppedInput.defaultEphemeralInputsRoot
    ) {
        source = .promise(PromiseStorage(
            operationDirectory: ephemeralInputsRoot.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            ),
            receivePromisedFile: receivePromisedFile
        ))
    }

    var fileURL: URL {
        switch source {
        case .direct(let fileURL, _):
            fileURL
        case .promise(let storage):
            storage.placeholderURL
        }
    }

    var isFilePromise: Bool {
        if case .promise = source { return true }
        return false
    }

    func withReadableFile<T: Sendable>(
        _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        switch source {
        case .direct(let fileURL, let access):
            try Task.checkCancellation()
            let didStartAccess = access.start(fileURL)
            defer {
                if didStartAccess {
                    access.stop(fileURL)
                }
            }
            let result = try await body(fileURL)
            try Task.checkCancellation()
            return result

        case .promise(let storage):
            try storage.claim()
            return try await withTaskCancellationHandler {
                do {
                    try Task.checkCancellation()
                    try Self.prepareRoot(storage.ephemeralInputsRoot)
                    try FileManager.default.createDirectory(
                        at: storage.operationDirectory,
                        withIntermediateDirectories: false
                    )
                    let receivedURL = try await storage.receive()
                    try Task.checkCancellation()
                    try Self.validate(receivedURL, inside: storage.operationDirectory)
                    let result = try await body(receivedURL)
                    try Task.checkCancellation()
                    try storage.finishAndRemove()
                    return result
                } catch {
                    storage.finish()
                    storage.removeOwnedDirectoryAfterTerminalEvent()
                    throw error
                }
            } onCancel: {
                storage.cancel()
            }
        }
    }

    static func cleanupAbandonedInputs(
        ephemeralInputsRoot: URL = DroppedInput.defaultEphemeralInputsRoot
    ) throws {
        guard !isSymbolicLink(ephemeralInputsRoot) else {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
        guard FileManager.default.fileExists(atPath: ephemeralInputsRoot.path) else { return }
        let rootValues: URLResourceValues
        do {
            rootValues = try ephemeralInputsRoot.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
        let abandonedInputs = try FileManager.default.contentsOfDirectory(
            at: ephemeralInputsRoot,
            includingPropertiesForKeys: nil
        )
        var firstCleanupError: (any Error)?
        for input in abandonedInputs {
            do {
                try FileManager.default.removeItem(at: input)
            } catch {
                if firstCleanupError == nil {
                    firstCleanupError = error
                }
            }
        }
        if let firstCleanupError {
            throw firstCleanupError
        }
    }

    static func == (lhs: DroppedInput, rhs: DroppedInput) -> Bool {
        switch (lhs.source, rhs.source) {
        case (.direct(let lhsURL, _), .direct(let rhsURL, _)):
            lhsURL == rhsURL
        case (.promise(let lhsStorage), .promise(let rhsStorage)):
            lhsStorage === rhsStorage
        default:
            false
        }
    }

    private static func prepareRoot(_ root: URL) throws {
        guard !isSymbolicLink(root) else {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard !isSymbolicLink(root) else {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
        let values: URLResourceValues
        do {
            values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DroppedInputError.unsafeEphemeralInputsRoot
        }
    }

    private static func validate(_ receivedURL: URL, inside operationDirectory: URL) throws {
        guard !isSymbolicLink(operationDirectory) else {
            throw DroppedInputError.receivedFileOutsideOwnedDirectory
        }
        let directoryValues = try operationDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw DroppedInputError.receivedFileOutsideOwnedDirectory
        }
        let lexicalOwnedDirectory = operationDirectory.standardizedFileURL
        let ownedDirectory = lexicalOwnedDirectory.resolvingSymlinksInPath()
        let candidate = receivedURL.standardizedFileURL
        let lexicalOwnedPrefix = lexicalOwnedDirectory.path.hasSuffix("/")
            ? lexicalOwnedDirectory.path
            : lexicalOwnedDirectory.path + "/"
        guard candidate.path.hasPrefix(lexicalOwnedPrefix) else {
            throw DroppedInputError.receivedFileOutsideOwnedDirectory
        }

        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let resolvedOwnedPrefix = ownedDirectory.path.hasSuffix("/")
            ? ownedDirectory.path
            : ownedDirectory.path + "/"
        guard resolvedCandidate.path.hasPrefix(resolvedOwnedPrefix) else {
            throw DroppedInputError.receivedFileOutsideOwnedDirectory
        }
        guard !isSymbolicLink(candidate), values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw DroppedInputError.receivedFileIsNotRegular
        }
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        var fileInfo = stat()
        let result = url.path.withCString { lstat($0, &fileInfo) }
        return result == 0 && (fileInfo.st_mode & S_IFMT) == S_IFLNK
    }
}

nonisolated private final class PromiseStorage: @unchecked Sendable {
    enum State {
        case ready
        case claimed
        case receiving(CheckedContinuation<URL, any Error>)
        case delivered
        case cancelled
        case finished
    }

    let ephemeralInputsRoot: URL
    let operationDirectory: URL
    var placeholderURL: URL {
        operationDirectory.appendingPathComponent("pending.heic")
    }

    private let receivePromisedFile: DroppedInput.PromiseReceiver
    private let lock = NSLock()
    private var state = State.ready

    init(operationDirectory: URL, receivePromisedFile: @escaping DroppedInput.PromiseReceiver) {
        ephemeralInputsRoot = operationDirectory.deletingLastPathComponent()
        self.operationDirectory = operationDirectory
        self.receivePromisedFile = receivePromisedFile
    }

    func claim() throws {
        try lock.withLock {
            guard case .ready = state else { throw DroppedInputError.alreadyConsumed }
            state = .claimed
        }
    }

    func receive() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldStart: Bool
                lock.lock()
                switch state {
                case .claimed:
                    state = .receiving(continuation)
                    shouldStart = true
                case .cancelled:
                    shouldStart = false
                case .ready, .receiving, .delivered, .finished:
                    shouldStart = false
                }
                let currentState = state
                lock.unlock()

                if shouldStart {
                    receivePromisedFile(operationDirectory) { [self] result in
                        complete(with: result)
                    }
                } else {
                    switch currentState {
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .ready, .claimed, .receiving, .delivered, .finished:
                        continuation.resume(throwing: DroppedInputError.alreadyConsumed)
                    }
                }
            }
        } onCancel: { cancel() }
    }

    func finishAndRemove() throws {
        finish()
        if FileManager.default.fileExists(atPath: operationDirectory.path) {
            try FileManager.default.removeItem(at: operationDirectory)
        }
    }

    func finish() {
        lock.withLock { state = .finished }
    }

    func removeOwnedDirectoryAfterTerminalEvent() {
        try? FileManager.default.removeItem(at: operationDirectory)
    }

    private func complete(with result: Result<URL, any Error>) {
        let continuation: CheckedContinuation<URL, any Error>?
        let cleanupAfterLateCompletion: Bool
        lock.lock()
        switch state {
        case .receiving(let pending):
            state = .delivered
            continuation = pending
            cleanupAfterLateCompletion = false
        case .cancelled, .finished:
            continuation = nil
            cleanupAfterLateCompletion = true
        case .delivered:
            continuation = nil
            cleanupAfterLateCompletion = true
        case .ready, .claimed:
            continuation = nil
            cleanupAfterLateCompletion = false
        }
        lock.unlock()

        if cleanupAfterLateCompletion {
            removeOwnedDirectoryAfterTerminalEvent()
        }
        continuation?.resume(with: result)
    }

    func cancel() {
        let continuation: CheckedContinuation<URL, any Error>?
        lock.lock()
        switch state {
        case .ready, .claimed:
            state = .cancelled
            continuation = nil
        case .receiving(let pending):
            state = .cancelled
            continuation = pending
        case .delivered:
            state = .cancelled
            continuation = nil
        case .finished, .cancelled:
            continuation = nil
        }
        lock.unlock()

        removeOwnedDirectoryAfterTerminalEvent()
        continuation?.resume(throwing: CancellationError())
    }
}
