import OuroHX
import SwiftUI

final class TextFieldsGalleryPage: GalleryComponentPage {
    override class var page: String { "textfields" }
    override class var title: String { "Text fields" }
    override class var aliases: [String] { ["textfield", "text-field"] }
    @MainActor override class var content: AnyView { AnyView(TextFieldsPage()) }
}

/// Text fields as an app's sign-in and editor screens use them: an email with a description, a password, a field
/// with an error, a search with a clear button, a large field, a plain one in the app's own frame and a disabled one.
struct TextFieldsPage: View {
    @State private var email = "cook@example.com"
    @State private var password = "lemon-orzo"
    @State private var title = ""
    @State private var query = "orzo"
    @State private var servings = "6"
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OuroTextField("Email", text: $email, placeholder: "you@example.com", description: "We send your recipes here.", type: .email, required: true)
            OuroTextField("Password", text: $password, type: .password)
            OuroTextField("Recipe title", text: $title, placeholder: "Lemon orzo with peas", error: title.isEmpty ? "Give the recipe a title." : nil, required: true)
            OuroTextField("Search recipes", text: $query, placeholder: "Search recipes", type: .search, hideLabel: true, clearable: true)
            OuroTextField("Servings", text: $servings, size: .lg)
            HStack(spacing: 8) {
                OuroTextField("Note to self", text: $note, placeholder: "Oven runs hot", variant: .plain, hideLabel: true)
                OuroButton("Add", variant: .soft, size: .sm) { note = "" }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary))
            OuroTextField("Kitchen name", text: .constant("Ari's kitchen"), description: "Set by your household.")
                .disabled(true)
        }
    }
}
