import SwiftUI
import Cartographer

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var showDebugMenu = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                if let store = container.mapStore {
                    Cartographer.MapView(store: store)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("Bootstrapping engine...")
                }

                statusBadge
                    .padding(12)
            }
            .navigationTitle("Cartographer Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDebugMenu = true
                    } label: {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                    .accessibilityLabel("Debug menu")
                }
            }
            .sheet(isPresented: $showDebugMenu) {
                DebugMenuView()
                    .environmentObject(container)
            }
        }
    }

    private var statusBadge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(container.annotations.count) annotations")
                .font(.caption)
            Text("sync: \(container.syncStatus)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let msg = container.lastActionMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
