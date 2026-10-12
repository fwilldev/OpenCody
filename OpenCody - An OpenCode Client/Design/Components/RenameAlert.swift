import SwiftUI

/// A text-field alert for renaming whatever `item` holds; shown while it is non-nil.
private struct RenameAlert<Item: Identifiable>: ViewModifier {
    let title: String
    @Binding var item: Item?
    let currentName: (Item) -> String
    let message: (Item) -> String
    let onSave: (Item, String) -> Void

    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: isPresented, presenting: item) { item in
                TextField("Name", text: $text)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                Button("Cancel", role: .cancel) {}
                Button("Save") { onSave(item, text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: { item in
                Text(message(item))
            }
            .onChange(of: item?.id) {
                if let item { text = currentName(item) }
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { item != nil }, set: { if !$0 { item = nil } })
    }
}

extension View {
    /// Present a rename alert for `item`, prefilled with `currentName`.
    func renameAlert<Item: Identifiable>(
        _ title: String,
        item: Binding<Item?>,
        currentName: @escaping (Item) -> String,
        message: @escaping (Item) -> String = { _ in "" },
        onSave: @escaping (Item, String) -> Void
    ) -> some View {
        modifier(RenameAlert(title: title, item: item, currentName: currentName, message: message, onSave: onSave))
    }
}
