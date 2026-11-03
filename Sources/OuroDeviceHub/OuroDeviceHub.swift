public import CoreGraphics
#if os(macOS)
import AppKit
import ApplicationServices
#endif
import Foundation

/// Drives Xcode's Device Hub through accessibility, so a Mac job can fold, open and turn the iPhone Duo simulator.
/// The one copy of the `devicehub.swift` Spoonjoy and Gatefold each carry (byte-identical in both), with the same
/// `dump` and `press` output and exit codes, so their workflows switch by changing one path.
public enum OuroDeviceHub {
    /// One accessibility element of Device Hub's window.
    public struct Element: Equatable, Sendable {
        public var role: String
        public var description: String
        public var help: String
        public var frame: CGRect

        public init(role: String, description: String, help: String, frame: CGRect) {
            self.role = role
            self.description = description
            self.help = help
            self.frame = frame
        }
    }

    /// Why a command failed; each keeps the exit code the apps' scripts already check.
    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        case noProcess
        case notFound(String)
        case notTrusted
        case pressFailed(String, code: Int32)

        public var exitCode: Int32 {
            switch self {
            case .noProcess: 1
            case .notFound: 2
            case .notTrusted: 3
            case .pressFailed: 4
            }
        }

        public var description: String {
            switch self {
            case .noProcess: "no DeviceHub process"
            case let .notFound(query): "not found: \(query)"
            case .notTrusted: "not trusted for accessibility"
            case let .pressFailed(query, code): "pressed \(query): \(code)"
            }
        }
    }

    /// The first element whose description or help is exactly `query` ("Partially Open", "Rotate Right").
    public static func match(_ query: String, in elements: [Element]) -> Element? {
        elements.first { $0.description == query || $0.help == query }
    }

    /// `dump`'s lines: each button's description, help and frame.
    public static func dumpLines(_ elements: [Element]) -> [String] {
        elements.filter { $0.role == "AXButton" }.map {
            "\($0.description) | \($0.help) | \(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))"
        }
    }

    #if os(macOS)
    /// Device Hub's elements, read live. Needs the calling process trusted for accessibility.
    public static func elements() throws(Failure) -> (root: AXUIElement, all: [(element: AXUIElement, info: Element)]) {
        guard AXIsProcessTrusted() else { throw .notTrusted }
        guard let pid = deviceHubPID() else { throw .noProcess }
        let root = AXUIElementCreateApplication(pid)
        // SwiftUI and Catalyst apps build their accessibility tree only once an assistive client asks.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        usleep(1_500_000)
        var all: [(AXUIElement, Element)] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            all.append((e, Element(role: string(e, kAXRoleAttribute), description: string(e, kAXDescriptionAttribute), help: string(e, kAXHelpAttribute), frame: frame(e))))
            if depth < 40 { children(e).forEach { walk($0, depth + 1) } }
        }
        walk(root, 0)
        return (root, all)
    }

    /// Presses the first element matching `query`.
    public static func press(_ query: String) throws(Failure) {
        let all = try elements().all
        guard let hit = all.first(where: { $0.info.description == query || $0.info.help == query }) else { throw .notFound(query) }
        let result = AXUIElementPerformAction(hit.element, kAXPressAction as CFString)
        guard result == .success else { throw .pressFailed(query, code: result.rawValue) }
    }

    static func attribute(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(e, name as CFString, &value)
        return value
    }

    static func string(_ e: AXUIElement, _ name: String) -> String { (attribute(e, name) as? String) ?? "" }

    static func children(_ e: AXUIElement) -> [AXUIElement] { (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

    static func frame(_ e: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = attribute(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = attribute(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }

    /// Device Hub's NSRunningApplication reports pid -1, so the process is found by its executable path.
    static func deviceHubPID() -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "DeviceHub.app/Contents/MacOS"]
        let out = Pipe()
        p.standardOutput = out
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(separator: "\n").compactMap { pid_t($0) }.first
    }
    #endif
}
