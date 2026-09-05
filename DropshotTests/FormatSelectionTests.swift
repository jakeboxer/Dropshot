import Testing
@testable import Dropshot

struct FormatSelectionTests {
    @Test
    func optionSelectsPNGUntilReleased() {
        #expect(FormatSelection.resolve(optionHeld: false) == .jpeg)
        #expect(FormatSelection.resolve(optionHeld: true) == .png)
        #expect(FormatSelection.resolve(optionHeld: false) == .jpeg)
    }
}
