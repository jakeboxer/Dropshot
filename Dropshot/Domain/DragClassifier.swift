import Foundation

// Value snapshots only: constructing/classifying descriptors never opens a file or
// fulfills a promise. Adapters must preserve every item and promised file.
nonisolated struct DragDescriptor: Equatable, Sendable {
    enum ContentType: Equatable, Sendable {
        // Explicit advertised HEIC content (public.heic), not generic HEIF/image content.
        case heic
        case other
        // Missing or generic advertised types (such as public.image).
        case unknown
    }

    enum Item: Equatable, Sendable {
        case fileURL(URL, contentType: ContentType)
        // Metadata-only observation of a file URL. It intentionally carries no
        // URL and can never authorize an Accepted Drop.
        case fileReference(contentType: ContentType)
        // One content type per promised file, not alternate representations of one file.
        case filePromise(contentTypes: [ContentType])
        case other
    }

    // nil means the item inventory is unavailable; [] means a known empty inventory.
    // Multiple advertised representations of one item belong in that single item.
    let items: [Item]?
}

nonisolated enum DragEligibility: Equatable, Sendable {
    case eligible
    case ineligible
    case indeterminate
}

nonisolated enum DragClassifier {
    // Call only on release at the Drop Zone with a fresh destination snapshot.
    // Promise inputs retain receipt ownership and materialize only during conversion.
    static func acceptDrop(
        atDestination descriptor: DragDescriptor,
        input: DroppedInput,
        optionHeld: Bool = false
    ) -> AcceptedDrop? {
        guard classify(descriptor) == .eligible, let item = descriptor.items?.first else { return nil }
        switch item {
        case .fileURL(let url, _):
            guard !input.isFilePromise, input.fileURL == url else { return nil }
        case .fileReference:
            return nil
        case .filePromise:
            if input.isFilePromise {
                return AcceptedDrop(input: input, optionHeld: optionHeld)
            }
            let received = DragDescriptor(items: [.fileURL(input.fileURL, contentType: .heic)])
            guard classify(received) == .eligible else { return nil }
        case .other:
            return nil
        }
        return AcceptedDrop(input: input, optionHeld: optionHeld)
    }

    static func classify(_ descriptor: DragDescriptor) -> DragEligibility {
        guard let items = descriptor.items else { return .indeterminate }
        guard items.count == 1 else { return .ineligible }
        switch items[0] {
        case .fileURL(let url, let contentType):
            guard url.isFileURL, contentType != .other else { return .ineligible }
            let extensionName = url.pathExtension.lowercased()
            guard extensionName.isEmpty || extensionName == "heic" else { return .ineligible }
            return extensionName == "heic" || contentType == .heic ? .eligible : .indeterminate
        case .fileReference(let contentType):
            switch contentType {
            case .heic: return .eligible
            case .other: return .ineligible
            case .unknown: return .indeterminate
            }
        case .filePromise(let contentTypes):
            guard !contentTypes.isEmpty else { return .indeterminate }
            guard contentTypes.count == 1, contentTypes[0] != .other else { return .ineligible }
            return contentTypes[0] == .heic ? .eligible : .indeterminate
        case .other:
            return .ineligible
        }
    }
}

// Only destination classification in this file can construct conversion authority.
nonisolated struct AcceptedDrop: Equatable, Sendable {
    let input: DroppedInput
    let optionHeld: Bool

    fileprivate init(input: DroppedInput, optionHeld: Bool) {
        self.input = input
        self.optionHeld = optionHeld
    }
}
