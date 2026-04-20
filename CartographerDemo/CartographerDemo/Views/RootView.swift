import SwiftUI
import MapKit
import Cartographer

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var visibleRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
    )
    @State private var showDebugMenu = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                DemoMapView(
                    annotations: container.annotations,
                    tileSource: container.selectedTileSource.source,
                    onLongPress: { coord in
                        Task { await container.addPin(at: coord) }
                    },
                    visibleRegion: $visibleRegion
                )
                .ignoresSafeArea(edges: .bottom)

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
