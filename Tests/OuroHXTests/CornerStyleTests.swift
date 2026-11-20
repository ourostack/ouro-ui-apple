import Foundation
@testable import OuroHX
import SwiftUI
import Testing

/// Every Ouro corner is a squircle (`.continuous`), capsules included: Ari, 2026-11-20, "ABSOLUTELY NO ROUNDED CORNERS /
/// squircle ONLY … absolutely NO regressions". SwiftUI's `Capsule()`, `RoundedRectangle(cornerRadius:)`, `.rect(cornerRadius:)`,
/// `UnevenRoundedRectangle(…)` and `.cornerRadius(_:)` all default to circular corners, so each must name `.continuous`.
/// True circles (`Circle()`, a spinner's `.progressViewStyle(.circular)`) stay round, as in Ouro's base.
@Suite("Corner style")
struct CornerStyleTests {
    /// What draws Ouro's components and the gallery that shows them. The Ouro Feel fixture is test scaffolding with its
    /// own rules (AGENTS.md), so it is not here.
    static let folders = ["Sources/OuroHX", "Sources/OuroA2UI", "Examples/OuroHXGallery"]

    static let circularCorners: [(name: String, pattern: String)] = [
        ("Capsule without .continuous", #"\bCapsule\((?![^)]*\.continuous)[^)]*\)"#),
        ("style: .circular", #"style:\s*\.circular"#),
        (".cornerRadius(_:)", #"\.cornerRadius\("#),
        ("RoundedRectangle without a style", #"\bRoundedRectangle\(corner(Radius|Size):(?![^\n]*style:)"#),
        ("UnevenRoundedRectangle without a style", #"\bUnevenRoundedRectangle\((?![^\n]*style:)"#),
        (".rect(cornerRadius:) without a style", #"\.rect\((cornerRadius|topLeadingRadius|topTrailingRadius|bottomLeadingRadius|bottomTrailingRadius):(?![^\n]*style:)"#),
        (".capsule shorthand", #"(?<![\w.])\.capsule\b(?!\(style)"#),
    ]

    @Test("no component or gallery page draws a circular corner")
    func noCircularCorners() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let patterns = try Self.circularCorners.map { ($0.name, try NSRegularExpression(pattern: $0.pattern)) }
        var found: [String] = []
        var scanned = 0
        for folder in Self.folders {
            let files = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            for file in files {
                scanned += 1
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    let range = NSRange(line.startIndex..., in: line)
                    for (name, regex) in patterns where regex.firstMatch(in: line, range: range) != nil {
                        found.append("\(file.path.replacingOccurrences(of: root.path + "/", with: "")):\(index + 1): \(name)")
                    }
                }
            }
        }
        #expect(scanned > 20, "the scan found only \(scanned) Swift files; are the folders still \(Self.folders)?")
        #expect(found.isEmpty, "Circular corners; use style: .continuous:\n\(found.joined(separator: "\n"))")
    }

    @Test("the scan catches each circular corner and passes its continuous form")
    func scanCatchesEachForm() throws {
        let patterns = try Self.circularCorners.map { try NSRegularExpression(pattern: $0.pattern) }
        func flagged(_ line: String) -> Bool {
            patterns.contains { $0.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
        }
        for circular in ["Capsule().fill(.red)", "Capsule(style: .circular)", "RoundedRectangle(cornerRadius: 8)",
                         ".background(.red, in: .rect(cornerRadius: 12))", "UnevenRoundedRectangle(topLeadingRadius: 4)",
                         ".clipShape(.capsule)", "view.cornerRadius(6)", "RoundedRectangle(cornerSize: size)"] {
            #expect(flagged(circular), "\(circular)")
        }
        for continuous in ["Capsule(style: .continuous).fill(.red)", "RoundedRectangle(cornerRadius: 8, style: .continuous)",
                           ".background(.red, in: .rect(cornerRadius: 12, style: .continuous))",
                           "UnevenRoundedRectangle(topLeadingRadius: 4, style: .continuous)", ".clipShape(.capsule(style: .continuous))",
                           "Circle().fill(.red)", ".progressViewStyle(.circular)"] {
            #expect(!flagged(continuous), "\(continuous)")
        }
    }

    @Test("a pill button's capsule is a squircle")
    func pillIsContinuous() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 50)
        let continuous = RoundedRectangle(cornerRadius: OuroButtonMetrics.pillRadius(height: 50), style: .continuous).path(in: rect)
        let circular = RoundedRectangle(cornerRadius: OuroButtonMetrics.pillRadius(height: 50), style: .circular).path(in: rect)
        #expect(PillShape().path(in: rect).description == continuous.description)
        #expect(PillShape().path(in: rect).description != circular.description)
    }
}
