import SwiftUI

struct LabeledValueRow: View {
    @Binding var label: String
    @Binding var value: String
    let commonLabels: [String]
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Picker("", selection: $label) {
                ForEach(commonLabels, id: \.self) { Text($0.capitalized).tag($0) }
                Text("Custom").tag(label)
            }
            .labelsHidden()
            .frame(width: 100)
            TextField("Value", text: $value)
            Button(role: .destructive) { onDelete() } label: { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.plain)
        }
    }
}
