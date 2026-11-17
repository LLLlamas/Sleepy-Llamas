import SwiftUI
import SwiftData

/// IDs cross the navigation boundary. A family deleted from another tab must
/// show an unavailable screen, never dereference a cascaded invalidated model.
struct ClosedShiftCorrectionsView: View {
    private let shiftID: UUID
    @Query private var shifts: [Shift]
    @Query private var families: [Family]
    @Environment(\.modelContext) private var context
    @Environment(\.palette) private var palette

    init(shiftID: UUID) {
        self.shiftID = shiftID
        let id = shiftID
        _shifts = Query(filter: #Predicate<Shift> { $0.id == id && !$0.isOpen })
        _families = Query(filter: #Predicate<Family> { !$0.isArchived })
    }

    private var liveShift: Shift? {
        let id = shiftID
        let query = FetchDescriptor<Shift>(predicate: #Predicate { $0.id == id && !$0.isOpen })
        guard let surviving = try? context.fetchIdentifiers(query) else { return nil }
        let ids = Set(surviving)
        return shifts.first { ids.contains($0.persistentModelID) }
    }

    private func liveFamily(_ id: UUID) -> Family? {
        let query = FetchDescriptor<Family>(predicate: #Predicate { $0.id == id && !$0.isArchived })
        guard let surviving = try? context.fetchIdentifiers(query) else { return nil }
        let ids = Set(surviving)
        return families.first { ids.contains($0.persistentModelID) }
    }

    var body: some View {
        Group {
            if let shift = liveShift, let familyID = shift.familyIDRaw, let family = liveFamily(familyID) {
                TonightView(family: family, shift: shift, correctionsOnly: true)
                    .environment(\.timeZone, TimeZone(identifier: shift.timeZoneIdentifier) ?? .current)
            } else {
                EmptyStatePlaceholder(emoji: "📋", title: "Shift unavailable",
                                      message: "This ended shift is no longer on this phone. Return to your current family.")
            }
        }
        .moonBackground(palette)
        .navigationTitle("Correct care log")
        .navigationBarTitleDisplayMode(.inline)
    }
}
