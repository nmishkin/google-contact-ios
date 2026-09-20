import SwiftUI
import Network

@MainActor
final class NetworkStatusMonitor: ObservableObject {
    @Published var isOffline = false
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isOffline = path.status != .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkStatusMonitor"))
    }
}

struct OfflineBannerView: View {
    @ObservedObject var monitor: NetworkStatusMonitor

    var body: some View {
        if monitor.isOffline {
            Text("Offline — changes will sync later")
                .font(.footnote)
                .padding(6)
                .frame(maxWidth: .infinity)
                .background(.yellow.opacity(0.3))
        }
    }
}
