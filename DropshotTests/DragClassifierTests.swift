import Foundation
import Testing
@testable import Dropshot

struct DragClassifierTests {
    @Test
    func onlyEligibleDestinationEvidenceCreatesAnAcceptedDropForTheMatchingInput() throws {
        let input = DroppedInput(fileURL: URL(fileURLWithPath: "/image.heic"))
        let eligible = DragDescriptor(items: [.fileURL(input.fileURL, contentType: .heic)])
        #expect(DragClassifier.classify(eligible) == .eligible)
        for rejected in [DragDescriptor(items: nil), DragDescriptor(items: [.other]),
                         DragDescriptor(items: [.filePromise(contentTypes: [.unknown])])] {
            #expect(DragClassifier.acceptDrop(atDestination: rejected, input: input) == nil)
        }
        let accepted = try #require(DragClassifier.acceptDrop(atDestination: eligible, input: input, optionHeld: true))
        #expect(accepted.input == input)
        #expect(accepted.optionHeld)
        let differentInput = DroppedInput(fileURL: URL(fileURLWithPath: "/different.heic"))
        #expect(DragClassifier.acceptDrop(atDestination: eligible, input: differentInput) == nil)
        let promise = DragDescriptor(items: [.filePromise(contentTypes: [.heic])])
        #expect(DragClassifier.acceptDrop(atDestination: promise, input: input)?.input == input)
        #expect(DragClassifier.acceptDrop(atDestination: promise,
            input: DroppedInput(fileURL: URL(string: "https://example.com/image.heic")!)) == nil)
    }

    @Test(arguments: [
        DragDescriptor(items: nil),
        DragDescriptor(items: [.fileURL(URL(fileURLWithPath: "/extensionless"), contentType: .unknown)]),
        DragDescriptor(items: [.filePromise(contentTypes: [])]),
        DragDescriptor(items: [.filePromise(contentTypes: [.unknown])])
    ])
    func ambiguousEvidenceRemainsIndeterminate(descriptor: DragDescriptor) {
        #expect(DragClassifier.classify(descriptor) == .indeterminate)
    }

    @Test(arguments: [
        DragDescriptor(items: []),
        DragDescriptor(items: [.other]),
        DragDescriptor(items: [.fileURL(URL(string: "https://example.com/image.heic")!, contentType: .heic)]),
        DragDescriptor(items: [.fileURL(URL(fileURLWithPath: "/image.jpg"), contentType: .unknown)]),
        DragDescriptor(items: [.fileURL(URL(fileURLWithPath: "/image.heic"), contentType: .other)]),
        DragDescriptor(items: [.fileURL(URL(fileURLWithPath: "/image.jpg"), contentType: .heic)]),
        DragDescriptor(items: [.filePromise(contentTypes: [.other])]),
        DragDescriptor(items: [.filePromise(contentTypes: [.heic, .heic])]),
        DragDescriptor(items: [.filePromise(contentTypes: [.heic, .other])]),
        DragDescriptor(items: [.filePromise(contentTypes: [.heic]), .other]),
        DragDescriptor(items: [.fileURL(URL(fileURLWithPath: "/image.heic"), contentType: .heic),
                               .fileURL(URL(fileURLWithPath: "/second.heic"), contentType: .heic)])
    ])
    func rejectsMultipleMixedNonHEICAndContradictoryItems(descriptor: DragDescriptor) {
        #expect(DragClassifier.classify(descriptor) == .ineligible)
    }

    @Test(arguments: [
        DragDescriptor(items: [.filePromise(contentTypes: [.heic])]),
        DragDescriptor(items: [.fileURL(URL(fileURLWithPath: "/extensionless"), contentType: .heic)])
    ])
    func explicitHEICTypeIsEligible(descriptor: DragDescriptor) {
        #expect(DragClassifier.classify(descriptor) == .eligible)
    }

    @Test
    func singleExplicitHEICFileURLIsEligible() {
        let descriptor = DragDescriptor(items: [.fileURL(
            URL(fileURLWithPath: "/not-read/IMAGE.HEIC"), contentType: .unknown
        )])
        #expect(DragClassifier.classify(descriptor) == .eligible)
    }
}
