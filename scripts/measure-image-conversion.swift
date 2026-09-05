// Compile with the production domain, workflow, coordinator, and converter sources.
// Run: /usr/bin/time -l /tmp/measure-image-conversion DropshotTests/Fixtures/12-megapixel.heic [png]
import Foundation

@main
struct MeasureImageConversion {
    static func main() async throws {
        let format: OutputFormat = CommandLine.arguments.dropFirst(2).first == "png" ? .png : .jpeg
        let request = ConversionRequest(dropID: DropID(1),
            input: DroppedInput(fileURL: URL(fileURLWithPath: CommandLine.arguments[1])), format: format)
        for run in 0...5 {
            let start = ContinuousClock.now
            let output = try await ImageConversion().convert(request).get()
            print("\(run == 0 ? "warm-up" : "run \(run)"): \(start.duration(to: .now)); \(format) \(output.requestedFormatData.count), TIFF \(output.tiffData.count) bytes")
        }
    }
}
