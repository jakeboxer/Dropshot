import Foundation
import Testing
@testable import Dropshot

@Suite(.serialized)
struct DroppedInputTests {
    @Test
    func directInputIsReadableWithoutTakingOwnershipOfTheFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("input.heic")
        try Data("direct".utf8).write(to: file)

        let contents = try await DroppedInput(fileURL: file).withReadableFile {
            try Data(contentsOf: $0)
        }

        #expect(contents == Data("direct".utf8))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func directInputBalancesSecurityScopedAccessWhenReadingSucceedsOrFails() async {
        let file = URL(fileURLWithPath: "/selected.heic")
        let access = SecurityScopeRecorder()
        let successful = DroppedInput(
            fileURL: file,
            startAccessingSecurityScopedResource: access.start,
            stopAccessingSecurityScopedResource: access.stop
        )

        _ = try? await successful.withReadableFile { _ in true }
        #expect(access.calls == [.start(file), .stop(file)])

        let failedAccess = SecurityScopeRecorder()
        let failing = DroppedInput(
            fileURL: file,
            startAccessingSecurityScopedResource: failedAccess.start,
            stopAccessingSecurityScopedResource: failedAccess.stop
        )
        _ = try? await failing.withReadableFile { _ -> Bool in
            throw TestFailure.expected
        }
        #expect(failedAccess.calls == [.start(file), .stop(file)])
    }

    @Test
    func promisedInputIsReadableOnlyWhileItsOwnedDirectoryExists() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = promisedInput(root: root, contents: "promised")

        let contents = try await input.withReadableFile { file in
            #expect(FileManager.default.fileExists(atPath: file.path))
            return try Data(contentsOf: file)
        }

        #expect(contents == Data("promised".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test
    func promisedInputCleansUpAfterBodyOrReceiptFailure() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bodyFailure = promisedInput(root: root, contents: "temporary")

        await #expect(throws: TestFailure.self) {
            try await bodyFailure.withReadableFile { _ -> Bool in
                throw TestFailure.expected
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)

        let receiptFailure = DroppedInput(
            receivePromisedFile: { _, completion in completion(.failure(TestFailure.expected)) },
            ephemeralInputsRoot: root
        )
        await #expect(throws: TestFailure.self) {
            try await receiptFailure.withReadableFile { _ in true }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test
    func cancellationCleansUpAgainWhenAPromiseCallbackArrivesLate() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let receipt = ReceiptProbe()
        let input = DroppedInput(
            receivePromisedFile: { destination, completion in
                Task { await receipt.capture(destination: destination, completion: completion) }
            },
            ephemeralInputsRoot: root
        )
        let operation = Task {
            try await input.withReadableFile { _ in true }
        }
        let pendingReceipt = await receipt.waitForReceipt()

        operation.cancel()
        await #expect(throws: CancellationError.self) {
            try await operation.value
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)

        try FileManager.default.createDirectory(
            at: pendingReceipt.destination,
            withIntermediateDirectories: true
        )
        let resurrected = pendingReceipt.destination.appendingPathComponent("late.heic")
        try Data("late".utf8).write(to: resurrected)
        pendingReceipt.completion(.success(resurrected))
        await Task.yield()

        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test
    func promisedInputRejectsFilesOutsideItsOwnedDirectoryAndSymlinks() async throws {
        let root = temporaryRoot()
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data("outside".utf8).write(to: outside)
        let outsideInput = DroppedInput(
            receivePromisedFile: { _, completion in completion(.success(outside)) },
            ephemeralInputsRoot: root
        )
        await #expect(throws: DroppedInputError.receivedFileOutsideOwnedDirectory) {
            try await outsideInput.withReadableFile { _ in true }
        }

        let symlinkInput = DroppedInput(
            receivePromisedFile: { destination, completion in
                let link = destination.appendingPathComponent("link.heic")
                do {
                    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
                    completion(.success(link))
                } catch {
                    completion(.failure(error))
                }
            },
            ephemeralInputsRoot: root
        )
        await #expect(throws: DroppedInputError.receivedFileOutsideOwnedDirectory) {
            try await symlinkInput.withReadableFile { _ in true }
        }
    }

    @Test
    func launchCleanupRemovesOnlyChildrenOfARealOwnedRoot() throws {
        let container = temporaryRoot()
        let root = container.appendingPathComponent("owned", isDirectory: true)
        let unrelated = container.appendingPathComponent("unrelated")
        let symlinkTarget = container.appendingPathComponent("symlink-target", isDirectory: true)
        let targetMarker = symlinkTarget.appendingPathComponent("keep")
        defer { try? FileManager.default.removeItem(at: container) }
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("abandoned", isDirectory: true),
            withIntermediateDirectories: false
        )
        try Data("keep".utf8).write(to: unrelated)

        try DroppedInput.cleanupAbandonedInputs(ephemeralInputsRoot: root)

        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: unrelated.path))

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: targetMarker)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: symlinkTarget)
        #expect(throws: DroppedInputError.unsafeEphemeralInputsRoot) {
            try DroppedInput.cleanupAbandonedInputs(ephemeralInputsRoot: root)
        }
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(FileManager.default.fileExists(atPath: targetMarker.path))
    }

    @Test
    func secondReadCannotConsumeOrDeleteAnActivePromise() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let enteredBody = TestGate()
        let releaseBody = TestGate()
        let input = promisedInput(root: root, contents: "active")
        let firstRead = Task {
            try await input.withReadableFile { file in
                await enteredBody.open()
                await releaseBody.wait()
                return try Data(contentsOf: file)
            }
        }
        await enteredBody.wait()

        await #expect(throws: DroppedInputError.alreadyConsumed) {
            try await input.withReadableFile { _ in true }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)

        await releaseBody.open()
        #expect(try await firstRead.value == Data("active".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dropshot18-input-\(UUID().uuidString)", isDirectory: true)
    }

    private func promisedInput(root: URL, contents: String) -> DroppedInput {
        DroppedInput(
            receivePromisedFile: { destination, completion in
                let file = destination.appendingPathComponent("input.heic")
                do {
                    try Data(contents.utf8).write(to: file)
                    completion(.success(file))
                } catch {
                    completion(.failure(error))
                }
            },
            ephemeralInputsRoot: root
        )
    }
}

nonisolated private enum TestFailure: Error {
    case expected
}

nonisolated private final class SecurityScopeRecorder: @unchecked Sendable {
    enum Call: Equatable {
        case start(URL)
        case stop(URL)
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    var calls: [Call] { lock.withLock { recordedCalls } }

    func start(_ url: URL) -> Bool {
        lock.withLock { recordedCalls.append(.start(url)) }
        return true
    }

    func stop(_ url: URL) {
        lock.withLock { recordedCalls.append(.stop(url)) }
    }
}

private actor ReceiptProbe {
    typealias Receipt = (
        destination: URL,
        completion: @Sendable (Result<URL, any Error>) -> Void
    )

    private var receipt: Receipt?
    private var waiter: CheckedContinuation<Receipt, Never>?

    func capture(
        destination: URL,
        completion: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) {
        let receipt = Receipt(destination, completion)
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: receipt)
        } else {
            self.receipt = receipt
        }
    }

    func waitForReceipt() async -> Receipt {
        if let receipt {
            self.receipt = nil
            return receipt
        }
        return await withCheckedContinuation { waiter = $0 }
    }
}

private actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
