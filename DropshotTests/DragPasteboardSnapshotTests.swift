import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Dropshot

@MainActor
struct DragPasteboardSnapshotTests {
    @Test
    func snapshotPreservesMultipleDestinationItemsForAuthoritativeRejection() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let heicURL = URL(fileURLWithPath: "/image.heic")
        let textURL = URL(fileURLWithPath: "/notes.txt")
        let heicItem = NSPasteboardItem()
        heicItem.setString(heicURL.absoluteString, forType: .fileURL)
        heicItem.setData(Data(), forType: .init(UTType.heic.identifier))
        let textItem = NSPasteboardItem()
        textItem.setString(textURL.absoluteString, forType: .fileURL)
        textItem.setData(Data(), forType: .init(UTType.plainText.identifier))
        pasteboard.writeObjects([heicItem, textItem])

        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)

        #expect(descriptor.items?.count == 2)
        #expect(DragClassifier.classify(descriptor) == .ineligible)
        #expect(DragPasteboardSnapshot.singleFileInput(from: pasteboard) == nil)
    }

    @Test
    func dragObserverPublishesAPasteboardSnapshotWithoutRequestingPermissions() {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let url = URL(fileURLWithPath: "/observed-image.heic")
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(Data(), forType: .init(UTType.heic.identifier))
        pasteboard.writeObjects([item])
        var observations: [DragDescriptor] = []
        let observer = AppKitDragObserver(pasteboard: pasteboard) { observations.append($0) }

        observer.sampleDragPasteboard()

        #expect(observations == [DragDescriptor(items: [.fileURL(url, contentType: .heic)])])
    }

    @Test
    func explicitHEICFileURLBecomesAnEligibleDragObservation() throws {
        let pasteboard = NSPasteboard(name: .init("DropshotTests.\(UUID().uuidString)"))
        defer { pasteboard.clearContents() }
        let url = URL(fileURLWithPath: "/observed-image.heic")
        let item = NSPasteboardItem()
        #expect(item.setString(url.absoluteString, forType: .fileURL))
        #expect(item.setData(Data(), forType: .init(UTType.heic.identifier)))
        #expect(pasteboard.writeObjects([item]))

        let descriptor = DragPasteboardSnapshot.descriptor(from: pasteboard)

        #expect(descriptor == DragDescriptor(items: [.fileURL(url, contentType: .heic)]))
        #expect(DragClassifier.classify(descriptor) == .eligible)
    }
}
