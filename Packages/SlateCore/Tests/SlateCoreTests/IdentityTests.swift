import XCTest
@testable import SlateCore

final class IdentityTests: XCTestCase {

    func testFreshIdentifiersAreUnique() {
        let ids = (0..<1_000).map { _ in ElementID() }
        XCTAssertEqual(Set(ids).count, 1_000)
    }

    func testIdentifiersWithTheSameRawValueAreEqual() {
        let raw = UUID()
        XCTAssertEqual(DocumentID(rawValue: raw), DocumentID(rawValue: raw))
    }

    func testDescriptionIsTheUUIDString() {
        let raw = UUID()
        XCTAssertEqual(OperationID(rawValue: raw).description, raw.uuidString)
    }

    func testIdentifierSurvivesACodableRoundTrip() throws {
        let original = DocumentID()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DocumentID.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // The v1 owner value is written into every object the app persists. If it
    // ever changes, every document already on a device is orphaned from its
    // owner, so this test exists to make that change loud and deliberate.
    func testLocalDefaultOwnerIsStable() {
        XCTAssertEqual(
            OwnerID.localDefault.rawValue.uuidString,
            "00000000-0000-0000-0000-000000000001"
        )
    }
}

final class ProvenanceTests: XCTestCase {

    func testStampsFromAnInjectedTimeSource() {
        let source = FixedTimeSource.reference
        let provenance = Provenance(now: source)

        XCTAssertEqual(provenance.lastModified, source.now)
        XCTAssertEqual(provenance.owner, .localDefault)
    }

    func testTouchingPreservesTheOwner() {
        let owner = OwnerID()
        let original = Provenance(lastModified: FixedTimeSource.reference.now, owner: owner)
        let later = original.touched(at: original.lastModified.addingTimeInterval(60))

        XCTAssertEqual(later.owner, owner)
        XCTAssertEqual(later.lastModified, original.lastModified.addingTimeInterval(60))
    }

    func testTouchingFromATimeSourcePreservesTheOwner() {
        let owner = OwnerID()
        let original = Provenance(lastModified: .distantPast, owner: owner)
        let later = original.touched(by: FixedTimeSource.reference)

        XCTAssertEqual(later.owner, owner)
        XCTAssertEqual(later.lastModified, FixedTimeSource.reference.now)
    }

    func testProvenanceSurvivesACodableRoundTrip() throws {
        let original = Provenance(now: FixedTimeSource.reference, owner: OwnerID())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)

        XCTAssertEqual(decoded.owner, original.owner)
        XCTAssertEqual(
            decoded.lastModified.timeIntervalSince1970,
            original.lastModified.timeIntervalSince1970,
            accuracy: 0.001
        )
    }
}
