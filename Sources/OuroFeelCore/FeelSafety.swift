/// Words a walk must never tap: a control whose identifier or label holds one would delete, sign out, pay or send.
/// Identifiers are split at case changes and punctuation first, so `account.signOut` reads as "account sign out".
public enum FeelSafety {
    public static let dangerous = [
        "delete", "remove", "sign out", "log out", "logout", "signout", "erase", "reset", "clear", "trash", "discard",
        "buy", "purchase", "pay", "checkout", "order", "subscribe", "send", "share", "publish", "post", "report", "block",
    ]

    /// `text` split into lowercase words, at case changes and at anything not a letter or digit.
    public static func words(_ text: String) -> String {
        var out = ""
        var previous: Character?
        for c in text {
            if let p = previous, c.isUppercase, p.isLowercase { out.append(" ") }
            out.append(c.isLetter || c.isNumber ? Character(c.lowercased()) : " ")
            previous = c
        }
        return " " + out.split(separator: " ").joined(separator: " ") + " "
    }

    public static func isDangerous(_ texts: String..., avoid: [String] = dangerous) -> Bool {
        let all = texts.map(words).joined()
        return avoid.contains { all.contains(" \($0) ") || all.contains(" \($0)") && $0.count >= 5 }
    }
}
