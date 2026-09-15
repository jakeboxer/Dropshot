import Foundation
import Testing
@testable import Dropshot

struct DropWorkflowTests {
    @Test
    func destinationLifecycleUpdatesGuidanceAndAbandonmentDismissesSilently() {
        var workflow = DropWorkflow()

        #expect(workflow.handle(.destinationEntered(optionHeld: false)).isEmpty)
        #expect(workflow.presentation == .guidance(.jpeg))
        #expect(workflow.handle(.destinationUpdated(optionHeld: true)).isEmpty)
        #expect(workflow.presentation == .guidance(.png))

        let abandonmentEvents: [DropWorkflow.Event] = [
            .destinationExited,
            .mouseReleased,
            .interrupted,
            .cancelled
        ]
        for event in abandonmentEvents {
            var abandonedWorkflow = DropWorkflow()
            _ = abandonedWorkflow.handle(.destinationEntered(optionHeld: false))

            #expect(abandonedWorkflow.handle(event).isEmpty)
            #expect(abandonedWorkflow.presentation == .hidden)
            #expect(abandonedWorkflow.activeDropID == nil)
        }
    }

    @Test
    func abandonmentSuppressesTheSamePhysicalDragUntilMouseRelease() {
        var workflow = DropWorkflow()
        let descriptor = DragDescriptor(items: [
            .fileURL(URL(fileURLWithPath: "/image.heic"), contentType: .heic)
        ])
        _ = workflow.handle(.destinationEntered(optionHeld: false))
        _ = workflow.handle(.destinationExited)

        #expect(workflow.handle(.dragObserved(descriptor)).isEmpty)
        #expect(workflow.presentation == .hidden)
        #expect(workflow.handle(.destinationEntered(optionHeld: true)).isEmpty)
        #expect(workflow.presentation == .hidden)
        #expect(workflow.handle(.destinationUpdated(optionHeld: true)).isEmpty)
        #expect(workflow.presentation == .hidden)
        #expect(workflow.handle(.pointerStateChanged(DragPointerState(
            leftMousePressed: false,
            optionHeld: false
        ))).isEmpty)
        #expect(workflow.handle(.dragObserved(descriptor)).isEmpty)
        #expect(workflow.presentation == .guidance(.jpeg))
    }

    @Test
    func successfulHandoffShowsTimedFeedbackThatANewDragReplaces() throws {
        var workflow = DropWorkflow()
        let input = DroppedInput(fileURL: URL(fileURLWithPath: "/image.heic"))
        let descriptor = DragDescriptor(items: [.fileURL(input.fileURL, contentType: .heic)])
        let request = ConversionRequest(dropID: DropID(1), input: input, format: .png)
        _ = workflow.handle(.acceptedDrop(try #require(DragClassifier.acceptDrop(
            atDestination: descriptor,
            input: input,
            optionHeld: true
        ))))

        #expect(workflow.handle(.clipboardHandoffCompleted(
            dropID: request.dropID,
            format: request.format
        )) == [.dismissSuccessFeedback(after: .milliseconds(800), dropID: request.dropID)])
        #expect(workflow.presentation == .success(.png, dropID: DropID(1)))
        #expect(workflow.handle(.successFeedbackElapsed(dropID: DropID(99))).isEmpty)
        #expect(workflow.presentation == .success(.png, dropID: DropID(1)))
        #expect(workflow.handle(.mouseReleased).isEmpty)
        #expect(workflow.presentation == .success(.png, dropID: DropID(1)))

        #expect(workflow.handle(.dragObserved(descriptor)).isEmpty)
        #expect(workflow.presentation == .guidance(.png))
        #expect(workflow.handle(.successFeedbackElapsed(dropID: DropID(1))).isEmpty)
        #expect(workflow.presentation == .guidance(.png))
    }

    @Test
    func earlyObservationRequestsPresentationWithoutAuthorizingOrReplacingConversion() throws {
        var workflow = DropWorkflow()
        let input = DroppedInput(fileURL: URL(fileURLWithPath: "/image.heic"))
        let descriptor = DragDescriptor(items: [.fileURL(input.fileURL, contentType: .heic)])
        #expect(workflow.handle(.dragObserved(descriptor)).isEmpty)
        #expect(workflow.isDropZoneRequested)
        #expect(workflow.activeDropID == nil)
        let accepted = try #require(DragClassifier.acceptDrop(atDestination: descriptor, input: input))
        let request = ConversionRequest(dropID: DropID(1), input: input, format: .jpeg)
        #expect(workflow.handle(.acceptedDrop(accepted)) == [.convert(request)])
        #expect(!workflow.isDropZoneRequested)
        for observation in [descriptor, DragDescriptor(items: nil), DragDescriptor(items: [.other])] {
            #expect(workflow.handle(.dragObserved(observation)).isEmpty)
            #expect(workflow.activeDropID == DropID(1))
        }
        #expect(!workflow.isDropZoneRequested)
        let image = ConvertedImage(requestedFormatData: Data([1]), tiffData: Data([2]))
        #expect(workflow.handle(.conversionCompleted(request: request, result: .success(image))) == [
            .performClipboardHandoff(ClipboardHandoff(dropID: DropID(1), format: .jpeg, convertedImage: image))
        ])
    }

    @Test(arguments: [false, true])
    func authoritativeDropOverridesEarlierModifierObservation(optionHeld: Bool) throws {
        var workflow = DropWorkflow()
        _ = workflow.handle(.modifiersChanged(optionHeld: !optionHeld))
        let input = DroppedInput(fileURL: URL(fileURLWithPath: "/unused.heic"))
        let effects = workflow.handle(.acceptedDrop(try #require(DragClassifier.acceptDrop(
            atDestination: DragDescriptor(items: [.fileURL(input.fileURL, contentType: .heic)]),
            input: input, optionHeld: optionHeld
        ))))
        let expectedFormat: OutputFormat = optionHeld ? .png : .jpeg
        let request = ConversionRequest(dropID: DropID(1), input: input, format: expectedFormat)
        #expect(effects == [.convert(request)])
        #expect(workflow.selectedFormat == expectedFormat)
        _ = workflow.handle(.modifiersChanged(optionHeld: !optionHeld))
        let image = ConvertedImage(requestedFormatData: Data([1]), tiffData: Data([2]))
        #expect(workflow.handle(.conversionCompleted(request: request, result: .success(image))) == [
            .performClipboardHandoff(ClipboardHandoff(dropID: DropID(1), format: expectedFormat, convertedImage: image))
        ])
    }

    @Test
    func modifierChangesImmediatelyUpdatePresentationFormat() {
        var workflow = DropWorkflow()
        #expect(workflow.selectedFormat == .jpeg)
        #expect(workflow.handle(.modifiersChanged(optionHeld: true)).isEmpty)
        #expect(workflow.selectedFormat == .png)
        #expect(workflow.handle(.modifiersChanged(optionHeld: false)).isEmpty)
        #expect(workflow.selectedFormat == .jpeg)
    }
}
