// MARK: - Annotation Sheet
// SwiftUI sheet for editing / deleting a single annotation. All mutations
// route through `MapCoordinator` (and therefore the CRDT operation log).

import Foundation
#if canImport(SwiftUI)
import SwiftUI

public struct AnnotationSheet: View {
    public let annotationID: EntityID
    public var initialTitle: String
    public var initialBody: String
    public let coordinator: MapCoordinator
    public let onDismiss: @MainActor () -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var isSaving: Bool = false

    public init(
        annotationID: EntityID,
        initialTitle: String = "",
        initialBody: String = "",
        coordinator: MapCoordinator,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.annotationID = annotationID
        self.initialTitle = initialTitle
        self.initialBody = initialBody
        self.coordinator = coordinator
        self.onDismiss = onDismiss
        _title    = State(initialValue: initialTitle)
        _bodyText = State(initialValue: initialBody)
    }

    public var body: some View {
        #if os(iOS) || targetEnvironment(macCatalyst)
        NavigationStack {
            formContent
                .navigationTitle("Annotation")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onDismiss)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).disabled(isSaving)
                    }
                }
        }
        #else
        VStack(spacing: 12) {
            Text("Annotation").font(.headline)
            formContent
            HStack {
                Button("Cancel", action: onDismiss)
                Spacer()
                Button("Save", action: save).disabled(isSaving)
            }
        }
        .padding()
        .frame(minWidth: 320, minHeight: 260)
        #endif
    }

    private var formContent: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $title)
            }
            Section("Notes") {
                TextField("Body", text: $bodyText, axis: .vertical)
                    .lineLimit(3...8)
            }
            Section {
                Button("Delete", role: .destructive, action: delete)
                    .disabled(isSaving)
            }
        }
    }

    private func save() {
        isSaving = true
        let id = annotationID
        let newTitle: String? = (title    == initialTitle) ? nil : title
        let newBody:  String? = (bodyText == initialBody)  ? nil : bodyText
        let coord = coordinator
        let done = onDismiss
        Task { @MainActor in
            await coord.applyEdit(
                annotationID: id,
                title: newTitle,
                body: newBody,
                coordinate: nil
            )
            isSaving = false
            done()
        }
    }

    private func delete() {
        isSaving = true
        let id = annotationID
        let coord = coordinator
        let done = onDismiss
        Task { @MainActor in
            await coord.deleteAnnotation(id)
            isSaving = false
            done()
        }
    }
}
#endif
