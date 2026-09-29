import SwiftUI
import SwiftData
import GoogleContactsKit

struct SyncStatusBannerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Query(sort: \PendingMutation.createdAt) private var mutations: [PendingMutation]
    @State private var isRetrying = false

    private var failed: [PendingMutation] { mutations.filter { $0.lastError != nil } }

    var body: some View {
        if !failed.isEmpty {
            HStack {
                Text(failed.count == 1 ? "1 change couldn't sync" : "\(failed.count) changes couldn't sync")
                Spacer()
                Button(isRetrying ? "Retrying…" : "Retry") { retry() }
                    .disabled(isRetrying)
            }
            .font(.footnote)
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(.orange.opacity(0.3))
        } else if !mutations.isEmpty {
            Text(mutations.count == 1 ? "1 change pending sync" : "\(mutations.count) changes pending sync")
                .font(.footnote)
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(.gray.opacity(0.2))
        }
    }

    private func retry() {
        isRetrying = true
        Task {
            try? await environment.syncEngine.drainOutbox()
            isRetrying = false
        }
    }
}
