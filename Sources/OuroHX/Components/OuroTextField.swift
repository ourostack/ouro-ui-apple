public import SwiftUI

/// What kind of text a field holds, as web's `type`: each sets the keyboard, autofill and capitalisation for you.
/// `password` hides the text and adds a show and hide button. A date or a time is SwiftUI's `DatePicker`, not a text
/// field, so neither is a type here.
public enum OuroTextFieldType: String, CaseIterable, Sendable { case text, email, password, tel, url, search }

/// A field's frame, as on web: `outline` is the bordered box, `plain` draws none, for a field inside a frame your app
/// draws (a search row with its own rules).
public enum OuroTextFieldVariant: String, CaseIterable, Sendable { case outline, plain }

/// A field's size, as on web: `md` is 44 points tall at the default text size, `lg` 56 with larger text, for a page's
/// main search.
public enum OuroTextFieldSize: String, CaseIterable, Sendable { case md, lg }

/// The resolved colours of a text field as seen: its label, description, text and error read at 5:1 on the page
/// (7:1 under increased contrast), core claim `contrast.text`; its edge reads at 3:1, so the box can be found (WCAG
/// 1.4.11), and turns the destructive colour when the field has an error.
public struct OuroTextFieldPalette: Sendable {
    public var label: Color.Resolved
    public var description: Color.Resolved
    public var text: Color.Resolved
    /// The placeholder: an example, not a label, so it reads at the same 5:1 as the description.
    public var placeholder: Color.Resolved
    public var error: Color.Resolved
    public var edge: Color.Resolved
    public var invalidEdge: Color.Resolved
    /// The ring drawn while the field has focus.
    public var focus: Color.Resolved
    /// What the words sit on: the page.
    public var surface: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        surface = page
        label = OuroInk.readable(OuroInk.r(c.foreground), on: page, style)
        text = label
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: page, style)
        placeholder = description
        error = OuroInk.readable(OuroInk.r(c.destructive), on: page, style)
        let line = style.contrast == .increased ? OuroColor.increasedLineContrast + 1 : OuroColor.increasedLineContrast
        edge = OuroColor.push(OuroInk.r(c.input), against: page, to: line)
        invalidEdge = OuroColor.push(OuroInk.r(c.destructive), against: page, to: line)
        focus = OuroColor.push(OuroInk.r(c.ring), against: page, to: line)
    }
}

/// Metrics every ``OuroTextField`` shares, as data.
public enum OuroTextFieldMetrics {
    public static let defaultType = OuroTextFieldType.text
    public static let defaultVariant = OuroTextFieldVariant.outline
    public static let defaultSize = OuroTextFieldSize.md
    /// Web's `h-11` and `h-14`: 44 and 56 points at the default text size, taller as the text grows (core claim
    /// `target.touch`).
    public static func minimumHeight(_ size: OuroTextFieldSize) -> CGFloat { size == .md ? 44 : 56 }
    /// Web's `px-3` inside an `outline` field.
    public static let horizontalPadding: CGFloat = 12
    /// Web's `rounded-lg`, from the theme.
    public static let radius = OuroRadius.lg
    /// The edge's width; the focus ring is twice it.
    public static let edgeWidth: CGFloat = 1
    /// Web's clear button name.
    public static let clearLabel = "Clear"
    /// Web's password button name. It stays the same while the password shows; its value says whether it does.
    public static let showPasswordLabel = "Show password"

    /// The text style for each size: `body` (web's 16px), `title3` for `lg` (web's 20px).
    public static func font(_ size: OuroTextFieldSize) -> Font { size == .md ? .body : .title3 }

    /// What VoiceOver reads after the field's name: its description, then its error, so a person hears why it is
    /// invalid before they type (web's `aria-describedby`).
    public static func hint(description: String?, error: String?) -> String? {
        func sentence(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s.last.map { ".!?".contains($0) } == true ? s : s + "."
        }
        let parts = [sentence(error).map { "Error: \($0)" }, sentence(description)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    #if os(iOS) || os(visionOS)
    /// The keyboard each type opens, as web's `inputMode`.
    public static func keyboard(_ type: OuroTextFieldType) -> UIKeyboardType {
        switch type {
        case .text, .password: .default
        case .email: .emailAddress
        case .tel: .phonePad
        case .url: .URL
        case .search: .webSearch
        }
    }
    #endif

    /// What autofill offers for each type, as web's `autoComplete`.
    public static func contentType(_ type: OuroTextFieldType) -> OuroTextContentType? {
        switch type {
        case .text, .search: nil
        case .email: .emailAddress
        case .password: .password
        case .tel: .telephoneNumber
        case .url: .url
        }
    }

    /// Whether the type turns off capitalisation and autocorrection, as web does for `email`, `url` and `password`.
    public static func isLiteral(_ type: OuroTextFieldType) -> Bool { type == .email || type == .url || type == .password || type == .tel }
}

/// The autofill kinds ``OuroTextFieldMetrics/contentType(_:)`` names, so it reads the same on every platform.
public enum OuroTextContentType: String, Sendable { case emailAddress, password, telephoneNumber, url }

/// Ouro HX's text field: a label above that stays, a description under it, an error that says what is wrong, and the
/// keyboard and autofill for its type, web's `TextField`.
///
/// ```swift
/// OuroTextField("Email", text: $email, type: .email, description: "We send the recipe here.")
/// OuroTextField("Password", text: $password, type: .password, error: passwordError)
/// OuroTextField("Search recipes", text: $query, type: .search, hideLabel: true, clearable: true)
/// ```
///
/// VoiceOver names it by its label (kept even with `hideLabel`), then reads its error and description. A placeholder
/// is an example of what to type, never its name.
public struct OuroTextField: View {
    let label: String
    @Binding var text: String
    let placeholder: String?
    let description: String?
    let error: String?
    let type: OuroTextFieldType
    let variant: OuroTextFieldVariant
    let size: OuroTextFieldSize
    let required: Bool
    let hideLabel: Bool
    let clearable: Bool
    let onSubmit: (() -> Void)?
    @State private var revealed = false
    @FocusState private var focused: Bool
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String? = nil,
        description: String? = nil,
        error: String? = nil,
        type: OuroTextFieldType = OuroTextFieldMetrics.defaultType,
        variant: OuroTextFieldVariant = OuroTextFieldMetrics.defaultVariant,
        size: OuroTextFieldSize = OuroTextFieldMetrics.defaultSize,
        required: Bool = false,
        hideLabel: Bool = false,
        clearable: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.description = description
        self.error = error
        self.type = type
        self.variant = variant
        self.size = size
        self.required = required
        self.hideLabel = hideLabel
        self.clearable = clearable
        self.onSubmit = onSubmit
    }

    private var invalid: Bool { !(error ?? "").isEmpty }

    public var body: some View {
        let palette = OuroTextFieldPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        VStack(alignment: .leading, spacing: 6) {
            if !hideLabel {
                (Text(label) + Text(required ? " *" : "").foregroundStyle(Color(palette.error)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(palette.label))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            if let description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(Color(palette.description))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            box(palette)
            if invalid, let error {
                Label { Text(error) } icon: { Image(systemName: "exclamationmark.circle") }
                    .font(.footnote)
                    .foregroundStyle(Color(palette.error))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    private func box(_ palette: OuroTextFieldPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius(OuroTextFieldMetrics.radius), style: .continuous)
        let edge = invalid ? palette.invalidEdge : (focused ? palette.focus : palette.edge)
        return HStack(spacing: 8) {
            if type == .search {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(palette.description))
                    .accessibilityHidden(true)
            }
            input(palette)
            if clearable, !text.isEmpty, isEnabled {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(palette.description))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(OuroTextFieldMetrics.clearLabel))
            }
            if type == .password {
                Button {
                    revealed.toggle()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .foregroundStyle(Color(palette.description))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(OuroTextFieldMetrics.showPasswordLabel))
                .accessibilityValue(Text(revealed ? "Shown" : "Hidden"))
            }
        }
        .font(OuroTextFieldMetrics.font(size))
        .padding(.horizontal, variant == .outline ? OuroTextFieldMetrics.horizontalPadding : 0)
        .frame(minHeight: OuroTextFieldMetrics.minimumHeight(size))
        .background {
            if variant == .outline { shape.fill(Color(palette.surface)) }
        }
        .overlay {
            if variant == .outline {
                shape.strokeBorder(Color(edge), lineWidth: focused || invalid ? OuroTextFieldMetrics.edgeWidth * 2 : OuroTextFieldMetrics.edgeWidth)
            } else if focused {
                shape.strokeBorder(Color(palette.focus), lineWidth: OuroTextFieldMetrics.edgeWidth * 2).padding(-4)
            }
        }
        .contentShape(shape)
        .onTapGesture { focused = true }
        .animation(OuroMotion.animation(.fast, reduceMotion: reduceMotion), value: focused)
    }

    @ViewBuilder private func input(_ palette: OuroTextFieldPalette) -> some View {
        let prompt = placeholder.map { Text($0).foregroundStyle(Color(palette.placeholder)) }
        Group {
            if type == .password && !revealed {
                SecureField(label, text: $text, prompt: prompt)
            } else {
                TextField(label, text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .foregroundStyle(Color(palette.text))
        .focused($focused)
        .literalInput(type)
        .submitLabel(type == .search ? .search : .done)
        .onSubmit { onSubmit?() }
        .accessibilityLabel(Text(required ? "\(label), required" : label))
        .accessibilityHint(OuroTextFieldMetrics.hint(description: description, error: error).map { Text($0) } ?? Text(""))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// The type's keyboard and autofill, and no capitalisation or autocorrection for what must be typed exactly.
    @ViewBuilder func literalInput(_ type: OuroTextFieldType) -> some View {
        let literal = OuroTextFieldMetrics.isLiteral(type)
        #if os(iOS) || os(visionOS)
        self
            .keyboardType(OuroTextFieldMetrics.keyboard(type))
            .textContentType(OuroTextFieldMetrics.contentType(type).map(\.uiKit))
            .textInputAutocapitalization(literal ? .never : nil)
            .autocorrectionDisabled(literal)
        #else
        self
            .textContentType(OuroTextFieldMetrics.contentType(type).map(\.appKit))
            .autocorrectionDisabled(literal)
        #endif
    }
}

extension OuroTextContentType {
    #if os(iOS) || os(visionOS)
    var uiKit: UITextContentType {
        switch self {
        case .emailAddress: .emailAddress
        case .password: .password
        case .telephoneNumber: .telephoneNumber
        case .url: .URL
        }
    }
    #else
    var appKit: NSTextContentType {
        switch self {
        case .emailAddress: .emailAddress
        case .password: .password
        case .telephoneNumber: .telephoneNumber
        case .url: .URL
        }
    }
    #endif
}
