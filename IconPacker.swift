import Foundation

guard CommandLine.arguments.count == 9 else {
    fputs("Usage: IconPacker <output.icns> <16> <32> <64> <128> <256> <512> <1024>\n", stderr)
    exit(2)
}

let chunkTypes = ["icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10"]
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
var chunks = Data()

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

for (index, type) in chunkTypes.enumerated() {
    let pngURL = URL(fileURLWithPath: CommandLine.arguments[index + 2])
    let pngData: Data
    do {
        pngData = try Data(contentsOf: pngURL)
    } catch {
        fputs("Could not read \(pngURL.path): \(error)\n", stderr)
        exit(3)
    }
    chunks.append(type.data(using: .ascii)!)
    appendUInt32(UInt32(pngData.count + 8), to: &chunks)
    chunks.append(pngData)
}

var container = Data("icns".utf8)
appendUInt32(UInt32(chunks.count + 8), to: &container)
container.append(chunks)

do {
    try container.write(to: outputURL)
} catch {
    fputs("Could not write ICNS: \(error)\n", stderr)
    exit(4)
}

