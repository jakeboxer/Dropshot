import CoreGraphics
import Foundation

/// Validates the color declarations that ImageIO may otherwise repair while
/// decoding. This intentionally reads only the ISO-BMFF metadata needed to
/// connect the primary image item to its `colr` properties.
nonisolated enum HEICColorInformation {
    static func validate(_ data: Data) throws {
        try Parser(data: data).validate()
    }
}

private nonisolated struct Parser {
    private static let meta = fourCC("meta")
    private static let pitm = fourCC("pitm")
    private static let iprp = fourCC("iprp")
    private static let ipco = fourCC("ipco")
    private static let ipma = fourCC("ipma")
    private static let iref = fourCC("iref")
    private static let dimg = fourCC("dimg")
    private static let colr = fourCC("colr")
    private static let nclx = fourCC("nclx")
    private static let nclc = fourCC("nclc")
    private static let prof = fourCC("prof")
    private static let rICC = fourCC("rICC")

    let data: Data

    func validate() throws {
        let topLevel = try boxes(in: data.indices)
        let metadataBoxes = topLevel.filter { $0.type == Self.meta }
        guard metadataBoxes.count == 1, let meta = metadataBoxes.first else {
            throw ParseError.invalid
        }
        let metaChildren = try fullBoxChildren(of: meta)
        let primaryBoxes = metaChildren.filter { $0.type == Self.pitm }
        guard primaryBoxes.count == 1, let primaryBox = primaryBoxes.first else {
            throw ParseError.invalid
        }
        let primaryID = try primaryItemID(in: primaryBox)

        var relevantItemIDs: Set<UInt32> = [primaryID]
        let referenceBoxes = metaChildren.filter { $0.type == Self.iref }
        guard referenceBoxes.count <= 1 else { throw ParseError.invalid }
        if let references = referenceBoxes.first {
            relevantItemIDs.formUnion(try derivedImageSources(of: primaryID, in: references))
        }

        let itemPropertyBoxes = metaChildren.filter { $0.type == Self.iprp }
        guard itemPropertyBoxes.count <= 1 else { throw ParseError.invalid }
        guard let itemProperties = itemPropertyBoxes.first else {
            return // A missing color declaration uses the system HEIC interpretation.
        }
        let propertyChildren = try boxes(in: itemProperties.content)
        let propertyContainers = propertyChildren.filter { $0.type == Self.ipco }
        guard propertyContainers.count <= 1 else { throw ParseError.invalid }
        guard let propertyContainer = propertyContainers.first else {
            return
        }
        let properties = try boxes(in: propertyContainer.content)

        var associatedPropertyIndexes: [UInt32: Set<Int>] = [:]
        for associations in propertyChildren where associations.type == Self.ipma {
            for (itemID, indexes) in try propertyIndexes(for: relevantItemIDs, in: associations) {
                associatedPropertyIndexes[itemID, default: []].formUnion(indexes)
            }
        }

        for itemID in associatedPropertyIndexes.keys.sorted() {
            // ICC and CICP may legally coexist, so compare declarations only
            // within the same interpretation family.
            var declarations: [ColorFamily: Data] = [:]
            for index in associatedPropertyIndexes[itemID, default: []].sorted() {
                guard index <= properties.count else { throw ParseError.invalid }
                let property = properties[index - 1]
                if property.type == Self.colr {
                    let family = try validateColorProperty(property)
                    let declaration = data.subdata(in: property.content)
                    if let existing = declarations[family], existing != declaration {
                        throw ParseError.invalid
                    }
                    declarations[family] = declaration
                }
            }
        }
    }

    private func primaryItemID(in box: Box) throws -> UInt32 {
        var reader = Reader(data: data, range: box.content)
        let version = try reader.readUInt8()
        guard version <= 1 else { throw ParseError.invalid }
        guard try reader.readUInt24() == 0 else { throw ParseError.invalid }
        let itemID = version == 0 ? UInt32(try reader.readUInt16()) : try reader.readUInt32()
        guard reader.isAtEnd else { throw ParseError.invalid }
        return itemID
    }

    private func derivedImageSources(of primaryID: UInt32, in box: Box) throws -> Set<UInt32> {
        var reader = Reader(data: data, range: box.content)
        let version = try reader.readUInt8()
        guard version <= 1 else { throw ParseError.invalid }
        guard try reader.readUInt24() == 0 else { throw ParseError.invalid }
        let references = try boxes(in: reader.remainingRange)
        var referencesBySource: [UInt32: [Box]] = [:]
        for reference in references where reference.type == Self.dimg {
            var referenceReader = Reader(data: data, range: reference.content)
            let fromID = version == 0
                ? UInt32(try referenceReader.readUInt16())
                : try referenceReader.readUInt32()
            referencesBySource[fromID, default: []].append(reference)
        }

        var visited = Set<UInt32>()
        var pending = [primaryID]
        while let sourceID = pending.popLast() {
            guard visited.insert(sourceID).inserted else { continue }
            for reference in referencesBySource[sourceID, default: []] {
                var referenceReader = Reader(data: data, range: reference.content)
                try referenceReader.skip(version == 0 ? 2 : 4)
                let count = Int(try referenceReader.readUInt16())
                for _ in 0..<count {
                    let referencedID = version == 0
                        ? UInt32(try referenceReader.readUInt16())
                        : try referenceReader.readUInt32()
                    if !visited.contains(referencedID) {
                        pending.append(referencedID)
                    }
                }
                guard referenceReader.isAtEnd else { throw ParseError.invalid }
            }
        }
        visited.remove(primaryID)
        return visited
    }

    private func propertyIndexes(
        for itemIDs: Set<UInt32>,
        in box: Box
    ) throws -> [UInt32: Set<Int>] {
        var reader = Reader(data: data, range: box.content)
        let version = try reader.readUInt8()
        guard version <= 1 else { throw ParseError.invalid }
        let flags = try reader.readUInt24()
        guard flags & ~1 == 0 else { throw ParseError.invalid }
        let wideAssociations = flags & 1 != 0
        let entryCount = Int(try reader.readUInt32())
        var result: [UInt32: Set<Int>] = [:]

        for _ in 0..<entryCount {
            let itemID = version < 1
                ? UInt32(try reader.readUInt16())
                : try reader.readUInt32()
            let associationCount = Int(try reader.readUInt8())
            for _ in 0..<associationCount {
                let association = wideAssociations
                    ? UInt16(try reader.readUInt16())
                    : UInt16(try reader.readUInt8())
                if itemIDs.contains(itemID) {
                    let mask: UInt16 = wideAssociations ? 0x7fff : 0x007f
                    let propertyIndex = Int(association & mask)
                    if propertyIndex != 0 {
                        result[itemID, default: []].insert(propertyIndex)
                    }
                }
            }
        }
        guard reader.isAtEnd else { throw ParseError.invalid }
        return result
    }

    private func validateColorProperty(_ box: Box) throws -> ColorFamily {
        var reader = Reader(data: data, range: box.content)
        let colorType = try reader.readUInt32()
        let family: ColorFamily
        switch colorType {
        case Self.nclx:
            try validateCICP(reader: &reader, includesRangeFlag: true)
            family = .cicp
        case Self.nclc:
            try validateCICP(reader: &reader, includesRangeFlag: false)
            family = .cicp
        case Self.prof, Self.rICC:
            try validateICC(reader: &reader)
            family = .icc
        default:
            // ImageIO can silently fall back for an unknown primary color type.
            throw ParseError.invalid
        }
        guard reader.isAtEnd else { throw ParseError.invalid }
        return family
    }

    private func validateCICP(reader: inout Reader, includesRangeFlag: Bool) throws {
        let primaries = try reader.readUInt16()
        let transfer = try reader.readUInt16()
        let matrix = try reader.readUInt16()
        guard Self.colorPrimaries.contains(primaries),
              Self.transferCharacteristics.contains(transfer),
              Self.matrixCoefficients.contains(matrix) else {
            throw ParseError.invalid
        }
        if includesRangeFlag {
            let range = try reader.readUInt8()
            guard range & 0x7f == 0 else { throw ParseError.invalid }
        }
    }

    private func validateICC(reader: inout Reader) throws {
        let profileData = reader.readRemainingData()
        guard profileData.count >= 128,
              UInt64(uint32(in: profileData, at: 0)) == UInt64(profileData.count),
              uint32(in: profileData, at: 36) == fourCC("acsp"),
              let colorSpace = CGColorSpace(iccData: profileData as CFData),
              colorSpace.model == .rgb || colorSpace.model == .monochrome else {
            throw ParseError.invalid
        }
    }

    private func fullBoxChildren(of box: Box) throws -> [Box] {
        var reader = Reader(data: data, range: box.content)
        let version = try reader.readUInt8()
        guard version == 0 else { throw ParseError.invalid }
        guard try reader.readUInt24() == 0 else { throw ParseError.invalid }
        return try boxes(in: reader.remainingRange)
    }

    private func boxes(in range: Range<Int>) throws -> [Box] {
        var reader = Reader(data: data, range: range)
        var result: [Box] = []
        while !reader.isAtEnd {
            let start = reader.offset
            let size32 = try reader.readUInt32()
            let type = try reader.readUInt32()
            var headerSize = 8
            let size: Int
            if size32 == 1 {
                headerSize = 16
                let size64 = try reader.readUInt64()
                guard size64 <= UInt64(Int.max) else { throw ParseError.invalid }
                size = Int(size64)
            } else if size32 == 0 {
                size = range.upperBound - start
            } else {
                size = Int(size32)
            }
            guard size >= headerSize,
                  size <= range.upperBound - start else { throw ParseError.invalid }
            let end = start + size
            result.append(Box(type: type, content: (start + headerSize)..<end))
            reader.offset = end
        }
        return result
    }

    // Assigned values in ITU-T H.273 (07/2024), Tables 2 through 4.
    // https://www.itu.int/rec/T-REC-H.273-202407-I/en
    private static let colorPrimaries: Set<UInt16> = [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 22]
    private static let transferCharacteristics: Set<UInt16> = [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
    private static let matrixCoefficients: Set<UInt16> = [0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
}

private nonisolated enum ColorFamily: Hashable {
    case cicp
    case icc
}

private nonisolated struct Box {
    let type: UInt32
    let content: Range<Int>
}

private nonisolated struct Reader {
    let data: Data
    let range: Range<Int>
    var offset: Int

    init(data: Data, range: Range<Int>) {
        self.data = data
        self.range = range
        self.offset = range.lowerBound
    }

    var isAtEnd: Bool { offset == range.upperBound }
    var remainingRange: Range<Int> { offset..<range.upperBound }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < range.upperBound else { throw ParseError.invalid }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        guard range.upperBound - offset >= 2 else { throw ParseError.invalid }
        defer { offset += 2 }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    mutating func readUInt24() throws -> UInt32 {
        guard range.upperBound - offset >= 3 else { throw ParseError.invalid }
        defer { offset += 3 }
        return UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
    }

    mutating func readUInt32() throws -> UInt32 {
        guard range.upperBound - offset >= 4 else { throw ParseError.invalid }
        defer { offset += 4 }
        return uint32(in: data, at: offset)
    }

    mutating func readUInt64() throws -> UInt64 {
        guard range.upperBound - offset >= 8 else { throw ParseError.invalid }
        defer { offset += 8 }
        return (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(data[offset + $1]) }
    }

    mutating func readRemainingData() -> Data {
        defer { offset = range.upperBound }
        return data.subdata(in: offset..<range.upperBound)
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, count <= range.upperBound - offset else { throw ParseError.invalid }
        offset += count
    }
}

private nonisolated enum ParseError: Error {
    case invalid
}

nonisolated private func fourCC(_ value: String) -> UInt32 {
    value.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
}

nonisolated private func uint32(in data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) << 24
        | UInt32(data[offset + 1]) << 16
        | UInt32(data[offset + 2]) << 8
        | UInt32(data[offset + 3])
}
