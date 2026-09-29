import SwiftUI

struct AddressRow: View {
    @Binding var label: String
    @Binding var street: String
    @Binding var city: String
    @Binding var region: String
    @Binding var postalCode: String
    @Binding var country: String
    var onDelete: () -> Void

    private let commonLabels = ["home", "work", "other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker("", selection: $label) {
                    ForEach(commonLabels, id: \.self) { Text($0.capitalized).tag($0) }
                    Text("Custom").tag(label)
                }
                .labelsHidden()
                .frame(width: 100)
                Spacer()
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "minus.circle.fill") }
                    .buttonStyle(.plain)
            }
            TextField("Street", text: $street)
            HStack {
                TextField("City", text: $city)
                TextField("State/Region", text: $region)
            }
            HStack {
                TextField("Postal code", text: $postalCode)
                TextField("Country", text: $country)
            }
        }
    }
}
