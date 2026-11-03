public import Foundation
import CryptoKit

extension AXXray {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// What an app's App Intents metadata says it offers: the inventory the system registers from the bundle's
    /// `Metadata.appintents/extract.actionsdata`. The format is undocumented, so this reads only the fields the
    /// checks need and treats every one as optional.
    public struct Inventory: Codable, Sendable, Hashable {
        public struct Parameter: Codable, Sendable, Hashable {
            public var name: String
            public var title: String
            public var description: String?
            public var isOptional: Bool
            /// The entity type the parameter takes, when it takes one.
            public var entityType: String?
        }

        public struct Intent: Codable, Sendable, Hashable {
            public var identifier: String
            public var title: String
            public var description: String?
            public var parameters: [Parameter]
            /// The Siri schemas it adopts (`assistantDefinedSchemas`).
            public var schemas: [String]
            /// Whether it is a tool intent; nil when the metadata cannot say (built before the 27.3 SDK).
            public var isTool: Bool?
            public var openAppWhenRun: Bool
        }

        public struct Property: Codable, Sendable, Hashable {
            public var identifier: String
            public var title: String
            public var description: String?
            public var isOptional: Bool
        }

        public struct Entity: Codable, Sendable, Hashable {
            public var typeName: String
            public var displayName: String
            public var properties: [Property]
            /// It conforms to `IndexedEntity`.
            public var indexed: Bool
            /// The content types it exports as a `Transferable`.
            public var exportableTypes: [String]
            /// The content types it can be made from, which reading an export back needs.
            public var importableTypes: [String] = []
            public var transient: Bool
            /// The capabilities bitmask of its default query, when the metadata names one.
            public var queryCapabilities: Int?
            public var queryIdentifier: String?

            /// The default query lists every entity (`EnumerableEntityQuery`).
            public var enumerable: Bool { (queryCapabilities ?? 0) & 1 != 0 }
            /// The default query answers string searches (`EntityStringQuery`).
            public var stringSearchable: Bool { (queryCapabilities ?? 0) & 4 != 0 }
        }

        public struct Shortcut: Codable, Sendable, Hashable {
            public var intent: String
            public var title: String
            public var phrases: [String]
        }

        /// The Xcode tools that wrote the metadata, such as "27B52".
        public var generator: String?
        public var intents: [Intent]
        public var entities: [Entity]
        public var shortcuts: [Shortcut]
        public var enums: [String]
        /// True when the metadata has a field that marks tool intents, so `isTool` is known.
        public var marksTools: Bool

        /// Parses `extract.actionsdata`.
        public init(actionsData data: Data) throws {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "extract.actionsdata is not a JSON object"])
            }
            generator = (root["generator"] as? [String: Any])?["version"] as? String
            let queries = Self.objects(root["queries"])
            func queryFor(_ entity: [String: Any], typeName: String) -> [String: Any]? {
                if let id = entity["defaultQueryIdentifier"] as? String,
                   let q = queries.first(where: { ($0["fullyQualifiedIdentifier"] as? String) == id || ($0["identifier"] as? String) == id }) { return q }
                return queries.first { ($0["entityType"] as? String) == typeName && ($0["defaultQueryForEntity"] as? Bool) == true }
            }
            let actions = Self.objects(root["actions"])
            marksTools = actions.contains { $0.keys.contains { $0.range(of: "tool", options: .caseInsensitive) != nil } }
            intents = actions.map { a in
                let parameters = Self.objects(a["parameters"]).map { p in
                    Parameter(
                        name: p["name"] as? String ?? "",
                        title: Self.text(p["title"]) ?? "",
                        description: Self.text(p["parameterDescription"]),
                        isOptional: p["isOptional"] as? Bool ?? false,
                        entityType: ((p["valueType"] as? [String: Any])?["entity"] as? [String: Any]).flatMap { ($0["wrapper"] as? [String: Any])?["typeName"] as? String }
                    )
                }
                let toolKeys = a.keys.filter { $0.range(of: "tool", options: .caseInsensitive) != nil }
                return Intent(
                    identifier: a["identifier"] as? String ?? "",
                    title: Self.text(a["title"]) ?? "",
                    description: Self.text((a["descriptionMetadata"] as? [String: Any])?["descriptionText"]),
                    parameters: parameters,
                    schemas: (a["assistantDefinedSchemas"] as? [Any] ?? []).map { Self.text($0) ?? String(describing: $0) },
                    isTool: toolKeys.isEmpty ? nil : toolKeys.contains { Self.truthy(a[$0]) },
                    openAppWhenRun: a["openAppWhenRun"] as? Bool ?? false
                )
            }.sorted { $0.identifier < $1.identifier }
            entities = Self.objects(root["entities"]).map { e in
                let typeName = e["typeName"] as? String ?? ""
                let query = queryFor(e, typeName: typeName)
                let protocols = (e["systemProtocolMetadata"] as? [Any] ?? []).compactMap { $0 as? String }
                return Entity(
                    typeName: typeName,
                    displayName: Self.text(e["displayTypeName"]) ?? "",
                    properties: Self.objects(e["properties"]).map { p in
                        Property(
                            identifier: p["identifier"] as? String ?? "",
                            title: Self.text(p["title"]) ?? "",
                            description: Self.text(p["propertyDescription"]) ?? Self.text(p["description"]),
                            isOptional: p["isOptional"] as? Bool ?? false
                        )
                    },
                    indexed: protocols.contains("com.apple.appintents.entity.Indexed"),
                    exportableTypes: Self.objects((e["transferableContentTypes"] as? [String: Any])?["exportableTypes"]).compactMap { $0["contentType"] as? String },
                    importableTypes: Self.objects((e["transferableContentTypes"] as? [String: Any])?["importableTypes"]).compactMap { $0["contentType"] as? String },
                    transient: e["transient"] as? Bool ?? false,
                    queryCapabilities: query?["capabilities"] as? Int,
                    queryIdentifier: query?["identifier"] as? String
                )
            }.sorted { $0.typeName < $1.typeName }
            shortcuts = Self.objects(root["autoShortcuts"]).map { s in
                Shortcut(
                    intent: s["actionIdentifier"] as? String ?? "",
                    title: Self.text(s["shortTitle"]) ?? "",
                    phrases: Self.objects(s["phraseTemplates"]).compactMap { $0["key"] as? String }
                )
            }
            enums = Self.objects(root["enums"]).compactMap { $0["identifier"] as? String }.sorted()
        }

        /// Finds `Metadata.appintents/extract.actionsdata` in a built `.app` (iOS or macOS layout).
        public static func metadataURL(inApp app: URL) -> URL? {
            for base in ["Metadata.appintents", "Contents/Resources/Metadata.appintents"] {
                let url = app.appendingPathComponent(base).appendingPathComponent("extract.actionsdata")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
            return nil
        }

        /// True when the generator is the 27.3 SDK or later, whose metadata can carry tool marks and property
        /// descriptions. Inferred from Xcode's build numbers: 27.0 and 27.1 are 27A (27A266a, 27A9275), 27.2 is 27B (27B52).
        public var isSiriAISDK: Bool {
            guard let g = generator, g.count >= 3 else { return false }
            let major = Int(g.prefix(2)) ?? 0
            let letter = g[g.index(g.startIndex, offsetBy: 2)]
            return major > 27 || (major == 27 && letter >= "C")
        }

        // A dictionary keyed by identifier, or an array, as an array of objects.
        static func objects(_ value: Any?) -> [[String: Any]] {
            if let a = value as? [[String: Any]] { return a }
            if let d = value as? [String: Any] { return d.keys.sorted().compactMap { d[$0] as? [String: Any] } }
            if let a = value as? [Any] { return a.compactMap { $0 as? [String: Any] } }
            return []
        }

        // A localized string resource as written: `{ key, alternatives }`; nil when absent or blank.
        static func text(_ value: Any?) -> String? {
            let s = (value as? [String: Any])?["key"] as? String ?? value as? String
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return s
        }

        static func truthy(_ value: Any?) -> Bool {
            switch value {
            case let b as Bool: b
            case let n as NSNumber: n.intValue != 0
            case let a as [Any]: !a.isEmpty
            case let d as [String: Any]: !d.isEmpty
            case let s as String: !s.isEmpty
            default: false
            }
        }
    }
}
