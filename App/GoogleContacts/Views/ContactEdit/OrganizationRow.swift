import SwiftUI

struct OrganizationRow: View {
    @Binding var name: String
    @Binding var title: String
    @Binding var department: String
    @Binding var isCurrent: Bool
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Company", text: $name)
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.plain)
            }
            TextField("Title", text: $title)
            TextField("Department", text: $department)
            Toggle("Current", isOn: $isCurrent)
        }
    }
}
