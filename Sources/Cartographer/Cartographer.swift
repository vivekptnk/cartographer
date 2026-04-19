// MARK: - Cartographer module root
//
// Public entry point for the Cartographer library. Consumers import the
// module (`import Cartographer`) and use the exported types directly:
//
//     import Cartographer
//
//     let clock = HLCClock(nodeID: UUID())
//     let log   = OperationLog()
//     let eng   = AnnotationEngine(clock: clock, operationLog: log)
//
// There is no module-level facade type by design. A root struct named
// `Cartographer` would shadow the module namespace and block
// `Cartographer.Annotation`-style qualification at call sites that have
// `Annotation` colliding with `SwiftUI.Annotation` or similar. Wiring is the
// app's job (see `CartographerDemo/AppContainer.swift` for the reference
// composition).

import Foundation
