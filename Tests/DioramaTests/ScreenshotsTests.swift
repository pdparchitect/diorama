import AppKit
import Testing
@testable import Diorama

@Suite @MainActor
struct ScreenshotsTests {
    @Test func sameSecondScreenshotsNeverOverwriteAnExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        let first = try Screenshots.save(image, date: date, directory: directory)
        let sentinel = Data("existing screenshot".utf8)
        try sentinel.write(to: first)
        let second = try Screenshots.save(image, date: date, directory: directory)
        let third = try Screenshots.save(image, date: date, directory: directory)
        #expect(Set([first, second, third]).count == 3)
        #expect(try Data(contentsOf: first) == sentinel)
        #expect(NSImage(contentsOf: second) != nil)
        #expect(NSImage(contentsOf: third) != nil)
    }
}
