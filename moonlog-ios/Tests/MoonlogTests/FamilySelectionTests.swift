import XCTest
@testable import Moonlog

/// The selected household is persisted as a raw string, so it outlives the family
/// it names: archive one, or delete the app's rows on another device, and the id
/// left in `@AppStorage` points at nothing. Every one of those cases has to land on
/// a real family — a dangling id showing an empty screen would look, at 3am, exactly
/// like the app having lost the night's records.
final class FamilySelectionTests: XCTestCase {

    private let first = UUID()
    private let second = UUID()
    private let gone = UUID()

    func testStoredSelectionWinsWhenItStillExists() {
        XCTAssertEqual(
            FamilySelection.resolve(storedID: second.uuidString, among: [first, second]),
            second)
    }

    /// First run and every install before this key existed.
    func testFallsBackToTheFirstFamilyWhenNothingIsStored() {
        XCTAssertEqual(FamilySelection.resolve(storedID: "", among: [first, second]), first)
    }

    func testFallsBackWhenTheStoredValueIsNotAUUID() {
        XCTAssertEqual(
            FamilySelection.resolve(storedID: "not-a-uuid", among: [first, second]), first)
    }

    /// Archived families are filtered out of the query before they get here, so an
    /// archived selection and a deleted one look identical — both are simply absent.
    func testFallsBackWhenTheStoredFamilyIsArchivedOrDeleted() {
        XCTAssertEqual(
            FamilySelection.resolve(storedID: gone.uuidString, among: [first, second]), first)
    }

    /// The only nil case: onboarding. Anything else would strand the user.
    func testResolvesToNilOnlyWhenThereAreNoFamilies() {
        XCTAssertNil(FamilySelection.resolve(storedID: "", among: []))
        XCTAssertNil(FamilySelection.resolve(storedID: gone.uuidString, among: []))
    }

    /// Case is not part of a UUID's identity; a hand-edited or round-tripped
    /// defaults value must not silently reset the selection.
    func testStoredSelectionIsCaseInsensitive() {
        XCTAssertEqual(
            FamilySelection.resolve(
                storedID: second.uuidString.lowercased(), among: [first, second]),
            second)
    }
}
