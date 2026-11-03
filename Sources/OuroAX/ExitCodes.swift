extension OuroAX {
    /// One exit code in a tool's table. Codes 0, 1 and 2 mean the same thing in every Ouro AX tool.
    public struct ExitCode: Sendable, Hashable, Codable {
        public var code: Int
        /// A slug an error names its exit by, such as `usage`.
        public var name: String
        /// A few words for the one-line summary.
        public var short: String
        /// The full meaning, for `help exit-codes`.
        public var meaning: String

        public init(code: Int, name: String, short: String, meaning: String) {
            self.code = code
            self.name = name
            self.short = short
            self.meaning = meaning
        }

        /// 0 ok, 1 error, 2 usage: the base every Ouro AX tool starts from.
        public static let base: [ExitCode] = [
            .init(code: 0, name: "ok", short: "ok", meaning: "ok"),
            .init(code: 1, name: "error", short: "error", meaning: "error: the message says what to do"),
            .init(code: 2, name: "usage", short: "usage", meaning: "usage: a missing or wrong argument; nothing was done"),
        ]

        /// The code a check or lint tool adds: its checks ran and found a problem, with a fix beside it. A check that
        /// couldn't run exits 1 instead, so an agent tells "found something" from "broke" by the code alone.
        public static let findings = ExitCode(code: 3, name: "findings", short: "findings", meaning: "findings: a check found a problem; its fix says what to do")
    }

    /// A tool's exit codes as one table: the base codes, then its own, numbered from 3 with no gaps.
    public struct ExitTable: Sendable, Hashable {
        public let codes: [ExitCode]

        public init(_ codes: [ExitCode] = ExitCode.base) throws {
            for (i, entry) in codes.enumerated() {
                if entry.code != i {
                    throw Problem(code: "exit-gap", exit: 1, thing: "exit codes", problem: "code \(entry.code) is at position \(i)", fix: "number the codes 0, 1, 2, ... with no gaps")
                }
                if i < ExitCode.base.count, entry.name != ExitCode.base[i].name {
                    throw Problem(code: "exit-base-renamed", exit: 1, thing: "exit codes", problem: "code \(i) is named \"\(entry.name)\"", fix: "name it \"\(ExitCode.base[i].name)\", as every Ouro AX tool does")
                }
            }
            if codes.count < ExitCode.base.count {
                throw Problem(code: "exit-short", exit: 1, thing: "exit codes", problem: "the table needs 0 ok, 1 error and 2 usage", fix: "start from OuroAX.ExitCode.base")
            }
            if Set(codes.map(\.name)).count != codes.count {
                throw Problem(code: "exit-duplicate", exit: 1, thing: "exit codes", problem: "two codes share a name", fix: "give each code its own name")
            }
            self.codes = codes
        }

        /// The number for a name; throws for a name the table does not have, so a typo fails in tests.
        public func code(_ name: String) throws -> Int {
            guard let found = codes.first(where: { $0.name == name }) else {
                throw Problem(code: "exit-unknown", exit: 1, thing: "exit codes", problem: "no code named \"\(name)\"", fix: "one of \(codes.map(\.name).joined(separator: ", "))")
            }
            return found.code
        }

        public func has(_ name: String) -> Bool { codes.contains { $0.name == name } }

        /// `Exit codes: 0 ok, 1 error, 2 usage, ...`
        public func line() -> String {
            "Exit codes: " + codes.map { "\($0.code) \($0.short)" }.joined(separator: ", ") + "."
        }
    }
}
