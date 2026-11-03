import Foundation
import PackagePlugin

/// Lints every `*.skillsbundle` in a target at build time with `ouro-ax-skills`. Errors fail the build and point at
/// the line in SKILL.md; warnings show in the issue navigator.
///
/// Add it to a package target with `plugins: [.plugin(name: "OuroAXSkillsLintPlugin", package: "ouro-ui-apple")]`,
/// or to an Xcode app target under Build Phases > Run Build Tool Plug-ins.
@main
struct OuroAXSkillsLintPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: any Target) async throws -> [Command] {
        guard let target = target as? any SourceModuleTarget else { return [] }
        return try commands(
            bundles: Self.bundles(in: target.sourceFiles.map(\.url) + [target.directoryURL]),
            tool: context.tool(named: "ouro-ax-skills").url,
            work: context.pluginWorkDirectoryURL,
            name: target.name
        )
    }

    func commands(bundles: [URL], tool: URL, work: URL, name: String) throws -> [Command] {
        guard !bundles.isEmpty else { return [] }
        let stamp = work.appendingPathComponent("\(name)-skills-lint.stamp")
        let inputs = bundles.flatMap(Self.files(in:))
        return [.buildCommand(
            displayName: "Lint app skills for \(name)",
            executable: tool,
            arguments: ["lint"] + bundles.map(\.path) + ["--format", "xcode", "--stamp", stamp.path],
            inputFiles: inputs,
            outputFiles: [stamp]
        )]
    }

    /// The `.skillsbundle` folders among these files, or under these folders.
    static func bundles(in urls: [URL]) -> [URL] {
        var found = Set<String>()
        for url in urls {
            if let bundle = enclosingBundle(url) { found.insert(bundle.path); continue }
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { continue }
            for case let child as URL in walker where child.pathExtension == "skillsbundle" {
                found.insert(child.path)
                walker.skipDescendants()
            }
        }
        return found.sorted().map { URL(fileURLWithPath: $0) }
    }

    static func enclosingBundle(_ url: URL) -> URL? {
        var current = url
        while current.pathComponents.count > 1 {
            if current.pathExtension == "skillsbundle" { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }

    static func files(in bundle: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension OuroAXSkillsLintPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try commands(
            bundles: Self.bundles(in: target.inputFiles.map(\.url)),
            tool: context.tool(named: "ouro-ax-skills").url,
            work: context.pluginWorkDirectoryURL,
            name: target.displayName
        )
    }
}
#endif
