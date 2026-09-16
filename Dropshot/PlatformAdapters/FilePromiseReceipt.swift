import AppKit

nonisolated enum FilePromiseReceiptError: Error, Equatable, Sendable {
    case unexpectedFileCount(Int)
    case unexpectedFileName
}

nonisolated final class FilePromiseReceipt: @unchecked Sendable {
    private let receiver: NSFilePromiseReceiver
    private let operationQueue: OperationQueue

    init(receiver: NSFilePromiseReceiver) {
        self.receiver = receiver
        operationQueue = OperationQueue()
        operationQueue.name = "Dropshot.FilePromiseReceipt"
        operationQueue.qualityOfService = .userInitiated
        operationQueue.maxConcurrentOperationCount = 1
    }

    func receive(
        at destinationDirectory: URL,
        completion: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) {
        receiver.receivePromisedFiles(
            atDestination: destinationDirectory,
            options: [:],
            operationQueue: operationQueue
        ) { [receiver] fileURL, error in
            completion(Self.result(
                fileNames: receiver.fileNames,
                fileURL: fileURL,
                error: error
            ))
        }
    }

    private static func result(
        fileNames: [String],
        fileURL: URL,
        error: (any Error)?
    ) -> Result<URL, any Error> {
        guard fileNames.count == 1 else {
            return .failure(FilePromiseReceiptError.unexpectedFileCount(fileNames.count))
        }
        let promisedExtension = URL(fileURLWithPath: fileNames[0]).pathExtension.lowercased()
        let receivedExtension = fileURL.pathExtension.lowercased()
        guard (promisedExtension.isEmpty || promisedExtension == "heic"),
              (receivedExtension.isEmpty || receivedExtension == "heic") else {
            return .failure(FilePromiseReceiptError.unexpectedFileName)
        }
        if let error {
            return .failure(error)
        }
        return .success(fileURL)
    }
}
