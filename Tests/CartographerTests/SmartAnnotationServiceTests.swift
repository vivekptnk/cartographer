import XCTest
@testable import Cartographer

final class MockSmartAnnotationServiceTests: XCTestCase {

    let service = MockSmartAnnotationService()
    let projectID = UUID()

    private func annotation(
        title: String = "",
        body: String = "",
        type: AnnotationType = .pin,
        metadata: [String: String] = [:],
        updatedAt: Date = Date()
    ) -> Annotation {
        Annotation(
            type: type,
            coordinate: GeoCoordinate(latitude: 0, longitude: 0),
            title: title,
            body: body,
            metadata: metadata,
            updatedAt: updatedAt,
            projectID: projectID
        )
    }

    // MARK: - search

    func testSearchReturnsMatchesOrderedByScore() async throws {
        let a = annotation(title: "Coffee at Blue Bottle")                 // 1 hit
        let b = annotation(title: "Best coffee in town", body: "coffee, coffee everywhere") // 3 hits
        let c = annotation(title: "Tea house")                              // 0 hits
        let result = try await service.search(query: "coffee", in: [a, b, c])

        XCTAssertEqual(result, [b.id, a.id])
    }

    func testSearchIsCaseInsensitiveAndTokenizes() async throws {
        let a = annotation(title: "Point Lobos", body: "Great sunset view")
        let b = annotation(title: "Rainbow Point", body: "Lobos spotted here")
        let result = try await service.search(query: "point lobos", in: [a, b])

        // Both hit twice (point + lobos); tie broken by most-recent updatedAt.
        XCTAssertEqual(Set(result), Set([a.id, b.id]))
        XCTAssertEqual(result.count, 2)
    }

    func testSearchIgnoresAnnotationsWithNoHits() async throws {
        let a = annotation(title: "Coffee")
        let b = annotation(title: "Tea")
        let result = try await service.search(query: "coffee", in: [a, b])
        XCTAssertEqual(result, [a.id])
    }

    func testSearchMatchesMetadataValues() async throws {
        let a = annotation(title: "Unnamed", metadata: ["notes": "favorite coffee stop"])
        let b = annotation(title: "Unnamed", metadata: ["notes": "gas station"])
        let result = try await service.search(query: "coffee", in: [a, b])
        XCTAssertEqual(result, [a.id])
    }

    func testSearchEmptyQueryThrows() async {
        do {
            _ = try await service.search(query: "   ", in: [])
            XCTFail("expected invalidQuery")
        } catch SmartAnnotationServiceError.invalidQuery {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSearchEmptyCorpusReturnsEmpty() async throws {
        let result = try await service.search(query: "coffee", in: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testSearchTieBreaksByUpdatedAt() async throws {
        let older = annotation(title: "coffee", updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = annotation(title: "coffee", updatedAt: Date(timeIntervalSince1970: 2_000))
        let result = try await service.search(query: "coffee", in: [older, newer])
        XCTAssertEqual(result, [newer.id, older.id])
    }

    // MARK: - summarize

    func testSummarizeEmpty() async throws {
        let text = try await service.summarize(annotations: [])
        XCTAssertEqual(text, "No annotations.")
    }

    func testSummarizeCountsAndGroupsByType() async throws {
        let pins = (0..<3).map { annotation(title: "Pin \($0)", type: .pin) }
        let routes = [annotation(title: "Rim Trail", type: .route)]
        let notes = [annotation(title: "Note A", type: .note)]

        let text = try await service.summarize(annotations: pins + routes + notes)
        // Order must be: pin → note → route → polygon.
        XCTAssertTrue(text.contains("3 pins (e.g. Pin 0)"))
        XCTAssertTrue(text.contains("1 note (e.g. Note A)"))
        XCTAssertTrue(text.contains("1 route (e.g. Rim Trail)"))
        let pinIdx = text.range(of: "pin")!.lowerBound
        let routeIdx = text.range(of: "route")!.lowerBound
        XCTAssertLessThan(pinIdx, routeIdx)
    }

    func testSummarizeHandlesUntitledAnnotations() async throws {
        let untitledPin = annotation(title: "", type: .pin)
        let text = try await service.summarize(annotations: [untitledPin])
        XCTAssertEqual(text, "1 pin")
    }
}
