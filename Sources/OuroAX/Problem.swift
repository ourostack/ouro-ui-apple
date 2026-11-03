public import Foundation

extension OuroAX {
    /// One error shape for every agent surface: a one-line message plus its fix.
    ///
    /// The line is `<tool>: <thing>: <problem>. Fix: <exact code>.`, the same as Ouro AX for web's `ax-problem`, and its
    /// JSON is `{ code, exit, thing, problem, fix, message }`. Throw it from an App Intent and Siri and Shortcuts show the
    /// message; encode it and an agent reads the same fields it reads from a CLI's `--json`.
    public struct Problem: Error, Codable, Sendable, Hashable, CustomStringConvertible, LocalizedError {
        /// A stable slug an agent can branch on, such as `unknown-flag`, `missing-arg` or `not-found`.
        public var code: String
        /// The process exit code (see ``OuroAX/ExitCode``).
        public var exit: Int
        /// What the error is about: a command, a flag, an intent, a file.
        public var thing: String
        /// What's wrong, in the reader's words.
        public var problem: String
        /// The exact thing to run or do instead, or nil when nothing the reader does can fix it.
        public var fix: String?

        public init(code: String, exit: Int, thing: String, problem: String, fix: String?) {
            self.code = code
            self.exit = exit
            self.thing = thing
            self.problem = problem
            self.fix = fix
        }

        /// `<thing>: <problem>. Fix: <fix>.`, without a tool's prefix.
        public var message: String {
            let head = "\(thing): \(Self.sentence(problem))."
            guard let fix else { return head }
            return "\(head) Fix: \(Self.sentence(fix))."
        }

        /// The one stderr line: `<tool>: <thing>: <problem>. Fix: <fix>.` Line breaks in any part become spaces.
        public func line(tool: String) -> String {
            "\(tool): \(message)".replacing(/\s*[\r\n]+\s*/, with: " ")
        }

        /// The `--json` and MCP form: `{ "error": { code, exit, thing, problem, fix, message } }`.
        public func errorJSON() throws -> Data {
            try JSONEncoder().encode(["error": self])
        }

        public var description: String { message }
        public var errorDescription: String? { message }

        static func sentence(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/[.\s]+$/, with: "")
        }

        private enum CodingKeys: String, CodingKey { case code, exit, thing, problem, fix, message }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            exit = try c.decode(Int.self, forKey: .exit)
            thing = try c.decode(String.self, forKey: .thing)
            problem = try c.decode(String.self, forKey: .problem)
            fix = try c.decodeIfPresent(String.self, forKey: .fix)
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(code, forKey: .code)
            try c.encode(exit, forKey: .exit)
            try c.encode(thing, forKey: .thing)
            try c.encode(problem, forKey: .problem)
            if let fix { try c.encode(fix, forKey: .fix) } else { try c.encodeNil(forKey: .fix) }
            try c.encode(message, forKey: .message)
        }

        /// The candidate a reader most likely meant: a unique prefix, or the nearest within two edits; nil when none is
        /// close. Use it to name the fix for a mistyped value.
        public static func didYouMean(_ word: String, in candidates: [String]) -> String? {
            guard !word.isEmpty else { return nil }
            let prefixed = candidates.filter { $0.hasPrefix(word) || word.hasPrefix($0) }
            if prefixed.count == 1 { return prefixed[0] }
            var best: String?
            var bestDistance = min(3, max(2, word.count / 2) + 1)
            for candidate in candidates {
                let d = distance(Array(word), Array(candidate))
                if d < bestDistance {
                    best = candidate
                    bestDistance = d
                }
            }
            return best
        }

        private static func distance(_ a: [Character], _ b: [Character]) -> Int {
            var row = Array(0...b.count)
            for i in 1...max(a.count, 1) where !a.isEmpty {
                var diagonal = row[0]
                row[0] = i
                for j in stride(from: 1, through: b.count, by: 1) {
                    let above = row[j]
                    row[j] = Swift.min(above + 1, row[j - 1] + 1, diagonal + (a[i - 1] == b[j - 1] ? 0 : 1))
                    diagonal = above
                }
            }
            return row[b.count]
        }
    }

    /// Quotes a word for a POSIX shell only when it needs it, so a fix copies and runs as printed.
    public static func shellWord(_ word: String) -> String {
        if word.wholeMatch(of: /<[^>\s]+>/) != nil || word.wholeMatch(of: /[A-Za-z0-9_.\/:@#,=+\-]+/) != nil { return word }
        return "\"" + word.replacing(/(["\\$`])/) { "\\" + $0.output.1 } + "\""
    }

    /// A command line from words, each quoted only when it needs it.
    public static func commandLine(_ words: [String]) -> String {
        words.map(shellWord).joined(separator: " ")
    }
}
