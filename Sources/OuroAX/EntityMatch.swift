import Foundation

extension OuroAX {
    /// How well a person's or agent's words match an entity's text, for `EntityStringQuery` answers.
    public enum EntityMatch {
        /// A rank for `query` against `fields`, lower is better, or nil when nothing matches. Case and accents are
        /// ignored ("cafe" finds "Café"). 0: a field starts with the query; 1: a word in a field does; 2: a field
        /// contains it anywhere.
        public static func score(_ query: String, in fields: [String]) -> Int? {
            let q = fold(query)
            guard !q.isEmpty else { return nil }
            var best: Int?
            for field in fields.map(fold) {
                let rank: Int?
                if field.hasPrefix(q) { rank = 0 }
                else if field.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { rank = 1 }
                else if field.contains(q) { rank = 2 }
                else { rank = nil }
                if let rank, rank < (best ?? .max) { best = rank }
            }
            return best
        }

        static func fold(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

extension OuroAX.Problem {
    /// An entity that is gone or never existed, with the way to find the right one.
    public static func notFound(kind: String, id: String, fix: String?) -> OuroAX.Problem {
        .init(code: "not-found", exit: 1, thing: "\(kind) \(id)", problem: "not found", fix: fix)
    }
}
