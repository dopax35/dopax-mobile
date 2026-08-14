import XCTest
@testable import PDCollectiOS

/// The medication editor gained separate `count` and `unit` fields after 43
/// production accounts had already recorded free-text dosages. These cover the
/// upgrade path for that stored data.
final class MedicationMigrationTests: XCTestCase {

    private func decode(_ json: String) throws -> Medication {
        try JSONDecoder().decode(Medication.self, from: Data(json.utf8))
    }

    func testLegacyNumericDosageSplitsIntoCountAndUnit() throws {
        let med = try decode(#"{"name":"Levodopa","dosage":"100mg"}"#)

        XCTAssertEqual(med.count, "100")
        XCTAssertEqual(med.unit, "mg")
        XCTAssertEqual(med.dosage, "100mg", "the original text must survive decoding")
    }

    func testLegacyDosageWithSpaceSplits() throws {
        let med = try decode(#"{"name":"Sinemet","dosage":"2 pill(s)"}"#)

        XCTAssertEqual(med.count, "2")
        XCTAssertEqual(med.unit, "pill(s)")
    }

    func testLegacyDecimalDosageSplits() throws {
        let med = try decode(#"{"name":"Ropinirole","dosage":"0.5 mg"}"#)

        XCTAssertEqual(med.count, "0.5")
        XCTAssertEqual(med.unit, "mg")
    }

    func testUnparsableLegacyDosageIsPreservedVerbatim() throws {
        let med = try decode(#"{"name":"Amantadine","dosage":"one tablet after food"}"#)

        XCTAssertEqual(med.dosage, "one tablet after food",
                       "a dosage we cannot parse must never be rewritten")
        XCTAssertEqual(med.count, "1")
        XCTAssertEqual(med.unit, "pill(s)")
    }

    func testStoredCountAndUnitWinOverDosage() throws {
        let med = try decode(#"{"name":"Levodopa","dosage":"stale","unit":"ml","count":"3"}"#)

        XCTAssertEqual(med.count, "3")
        XCTAssertEqual(med.unit, "ml")
    }

    func testMissingDosageIsComposedFromFields() throws {
        let med = try decode(#"{"name":"Levodopa","unit":"mg","count":"250"}"#)

        XCTAssertEqual(med.dosage, "250 mg")
    }

    func testEditingFieldsRewritesDosage() throws {
        var med = try decode(#"{"name":"Levodopa","dosage":"100mg"}"#)

        med.count = "200"
        med.syncDosageFromFields()

        XCTAssertEqual(med.dosage, "200 mg")
    }

    func testRoundTripDoesNotMutateParsableDosage() throws {
        let original = try decode(#"{"name":"Levodopa","dosage":"100 mg"}"#)
        let reencoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Medication.self, from: reencoded)

        XCTAssertEqual(decoded.dosage, "100 mg")
        XCTAssertEqual(decoded.count, "100")
        XCTAssertEqual(decoded.unit, "mg")
    }
}
