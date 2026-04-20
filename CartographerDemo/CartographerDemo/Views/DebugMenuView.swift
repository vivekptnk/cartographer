import SwiftUI
import MapKit
import Cartographer
import UniformTypeIdentifiers

struct DebugMenuView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var seedCount: Int = 25
    @State private var exportPayload: Data?
    @State private var showExport = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Annotations") {
                    Stepper("Seed count: \(seedCount)", value: $seedCount, in: 1...500, step: 25)
                    Button("Seed \(seedCount) synthetic annotations") {
                        Task { await container.seedSyntheticAnnotations(count: seedCount) }
                    }
                    Button("Clear all annotations", role: .destructive) {
                        Task { await container.clearAllAnnotations() }
                    }
                }

                Section("Sync") {
                    Toggle("CloudKit sync (in-memory stand-in)", isOn: syncBinding)
                    LabeledContent("Status") { Text(container.syncStatus) }
                    Button("Trigger sync now") {
                        Task { await container.performSync() }
                    }
                    .disabled(!container.syncEnabled)
                }

                Section("Tiles") {
                    Picker("Source", selection: $container.selectedTileSource) {
                        ForEach(TileSourceChoice.allCases) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    Button("Download current region (z 12–14)") {
                        Task {
                            let box = BoundingBox(
                                minLatitude: 37.70, maxLatitude: 37.82,
                                minLongitude: -122.52, maxLongitude: -122.36
                            )
                            await container.downloadCurrentRegion(box, zoomRange: 12...14)
                        }
                    }
                    if container.regionDownloadProgress > 0 && container.regionDownloadProgress < 1 {
                        ProgressView(value: container.regionDownloadProgress)
                    }
                }

                Section("Export") {
                    Button("Share GeoJSON") {
                        do {
                            exportPayload = try container.currentGeoJSONExport()
                            exportError = nil
                            showExport = true
                        } catch {
                            exportError = "Export failed: \(error)"
                        }
                    }
                    if let msg = exportError {
                        Text(msg).foregroundStyle(.red)
                    }
                }

                if let msg = container.lastActionMessage {
                    Section("Last Action") { Text(msg).font(.footnote) }
                }
            }
            .navigationTitle("Debug")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showExport) {
                if let payload = exportPayload,
                   let url = Self.writeTemporaryFile(data: payload, filename: "cartographer-demo.geojson") {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { container.syncEnabled },
            set: { _ in Task { await container.toggleSync() } }
        )
    }

    private static func writeTemporaryFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
