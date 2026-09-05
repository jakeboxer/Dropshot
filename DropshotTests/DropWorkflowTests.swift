import Foundation
import Testing
@testable import Dropshot

struct DropWorkflowTests {
    @Test(arguments: [false, true])
    func authoritativeDropOverridesEarlierModifierObservation(optionHeld: Bool) throws {
        var workflow = DropWorkflow()
        _ = workflow.handle(.modifiersChanged(optionHeld: !optionHeld))
        let input = DroppedInput(fileURL: URL(fileURLWithPath: "/unused.heic"))
        let effects = workflow.handle(.acceptedDrop(AcceptedDrop(input: input, optionHeld: optionHeld)))
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
