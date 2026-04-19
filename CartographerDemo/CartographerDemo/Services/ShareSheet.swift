import SwiftUI
import UIKit

/// Thin `UIActivityViewController` wrapper so SwiftUI can present the system
/// share sheet with pre-built data payloads. Used by the debug menu's GeoJSON
/// export action.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
