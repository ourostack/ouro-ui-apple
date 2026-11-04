import OuroHX
import SwiftUI

/// Launch arguments pick what to show, so screenshots need no taps: `-theme abyss -page pairs`.
@main
struct GalleryApp: App {
    var body: some Scene {
        WindowGroup {
            GalleryScreen(
                theme: OuroThemeName(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .pearl,
                page: GalleryPage(rawValue: UserDefaults.standard.string(forKey: "page") ?? "") ?? .colors
            )
        }
    }
}

enum GalleryPage: String, CaseIterable, Identifiable {
    case colors = "Colours", pairs = "Pairs", feel = "Feel"
    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "colors", "colours": self = .colors
        case "pairs": self = .pairs
        case "feel": self = .feel
        default: return nil
        }
    }
}

struct GalleryScreen: View {
    @State var theme: OuroThemeName
    @State var page: GalleryPage

    var body: some View {
        ThemedPage(theme: theme, page: $page, pickTheme: { theme = $0 })
            .ouroTheme(theme)
    }
}

private struct ThemedPage: View {
    let theme: OuroThemeName
    @Binding var page: GalleryPage
    let pickTheme: (OuroThemeName) -> Void
    @Environment(\.ouroColors) private var colors
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Picker("Page", selection: $page) {
                    ForEach(GalleryPage.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch page {
                case .colors: ColorGrid()
                case .pairs: PairList()
                case .feel: FeelPage()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(colors.background.ignoresSafeArea())
        .foregroundStyle(colors.foreground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(OuroThemeName.allCases, id: \.self) { name in
                    Button(name.rawValue.capitalized) { pickTheme(name) }
                }
            } label: {
                Text(theme.rawValue.capitalized)
                    .font(.largeTitle.bold())
                    .foregroundStyle(colors.foreground)
            }
            Text("\(scheme == .dark ? "Dark" : "Light")\(contrast == .increased ? ", increased contrast" : "") · ouro-ui-core v0.3.0")
                .font(.subheadline)
                .foregroundStyle(colors.mutedForeground)
        }
        .padding(.top, 8)
    }
}

/// Every colour token, as a chip with its name.
private struct ColorGrid: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Tokens.all(colors), id: \.name) { token in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: theme.radius(.sm))
                        .fill(token.color)
                        .overlay(RoundedRectangle(cornerRadius: theme.radius(.sm)).strokeBorder(colors.border, lineWidth: 1))
                        .frame(height: 30)
                    Text(token.name)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(colors.mutedForeground)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Text on its surface, with the WCAG ratio, plus the radius scale.
private struct PairList: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Tokens.pairs(colors), id: \.name) { pair in
                let ratio = OuroColor.contrastRatio(pair.text, pair.surface)
                HStack {
                    Text(pair.name).font(.callout.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f:1", ratio)).font(.callout.monospacedDigit())
                }
                .foregroundStyle(pair.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(pair.surface, in: .rect(cornerRadius: theme.radius(.md)))
            }
            Text("Radii").font(.headline).padding(.top, 8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(OuroRadius.allCases, id: \.self) { step in
                    VStack(spacing: 3) {
                        UnevenRoundedRectangle(topLeadingRadius: theme.radius(step))
                            .fill(colors.primary)
                            .frame(width: 38, height: 38)
                        Text(step.rawValue).font(.caption2.monospaced()).foregroundStyle(colors.mutedForeground)
                    }
                }
            }
        }
    }
}

/// Motion and haptics: tap things.
private struct FeelPage: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme
    @State private var lit = false
    @State private var checked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                lit.toggle()
            } label: {
                Text(lit ? "Boing, but politely" : "Press me")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(colors.primaryForeground)
                    .background(colors.primary, in: .rect(cornerRadius: theme.radius(.lg)))
            }
            .buttonStyle(.ouroPress)
            .ouroHaptic(.turned, trigger: lit)
            Circle()
                .fill(colors.accentForeground)
                .frame(width: 24, height: 24)
                .offset(x: lit ? 280 : 0)
                .ouroAnimation(.spring, value: lit)
            Text("Moments").font(.headline)
            ForEach(OuroHaptics.table, id: \.name) { moment in
                Button {
                    if checked.contains(moment.name) { checked.remove(moment.name) } else { checked.insert(moment.name) }
                    OuroHaptics.play(moment)
                } label: {
                    HStack {
                        Image(systemName: checked.contains(moment.name) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(colors.primary)
                        Text(moment.name)
                        Spacer()
                        Text(moment.feedback.label).font(.caption).foregroundStyle(colors.mutedForeground)
                    }
                }
                .buttonStyle(.ouroPress)
            }
        }
    }
}

enum Tokens {
    struct Token { let name: String; let color: Color }
    struct Pair { let name: String; let text: Color; let surface: Color }

    static func all(_ c: OuroColors) -> [Token] {
        Mirror(reflecting: c).children.compactMap { child in
            (child.value as? Color).map { Token(name: child.label ?? "?", color: $0) }
        }
    }

    static func pairs(_ c: OuroColors) -> [Pair] {
        [
            Pair(name: "foreground", text: c.foreground, surface: c.background),
            Pair(name: "mutedForeground", text: c.mutedForeground, surface: c.background),
            Pair(name: "cardForeground", text: c.cardForeground, surface: c.card),
            Pair(name: "primaryForeground", text: c.primaryForeground, surface: c.primary),
            Pair(name: "secondaryForeground", text: c.secondaryForeground, surface: c.secondary),
            Pair(name: "accentForeground", text: c.accentForeground, surface: c.accent),
            Pair(name: "destructiveForeground", text: c.destructiveForeground, surface: c.destructive),
            Pair(name: "successForeground", text: c.successForeground, surface: c.success),
            Pair(name: "warningForeground", text: c.warningForeground, surface: c.warning),
            Pair(name: "sidebarForeground", text: c.sidebarForeground, surface: c.sidebar),
            Pair(name: "sidebarPrimaryForeground", text: c.sidebarPrimaryForeground, surface: c.sidebarPrimary),
        ]
    }
}
