import SwiftUI
import SwiftData
import GoogleContactsKit

struct LabelsManagementView: View {
    @Query(filter: #Predicate<ContactGroup> { $0.groupType == "USER_CONTACT_GROUP" }, sort: \ContactGroup.name)
    private var labels: [ContactGroup]
    @EnvironmentObject private var environment: AppEnvironment
    @State private var newLabelName = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New label name", text: $newLabelName)
                    Button("Add") { Task { await addLabel() } }.disabled(newLabelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            Section("Labels") {
                ForEach(labels) { group in
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.members.count)").foregroundStyle(.secondary)
                    }
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet { try? await environment.repository.deleteLabel(labels[index]) }
                    }
                }
            }
        }
        .navigationTitle("Labels")
    }

    private func addLabel() async {
        let name = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            _ = try await environment.repository.createLabel(name: name)
            newLabelName = ""
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't create the label. Check your connection and try again."
        }
    }
}
