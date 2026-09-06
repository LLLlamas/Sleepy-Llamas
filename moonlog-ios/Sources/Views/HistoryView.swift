import SwiftUI
import SwiftData
import MoonlogCore

/// Every night this household has had, newest first.
///
/// Its own screen, pushed from Settings. It used to be a section under tonight's
/// totals on Summary — and because that section rendered only in the branch where
/// no shift was open, a doula mid-shift could not reach last night at all. That is
/// the one moment she is most likely to want it: "how long did she go last night?"
struct HistoryView: View {
    let family: Family

    /// Closed shifts, newest first. The predicate cannot capture `family.id`, so
    /// the household filter happens below in Swift.
    @Query(filter: #Predicate<Shift> { !$0.isOpen }, sort: \Shift.startedAt, order: .reverse)
    private var closedShifts: [Shift]

    @Environment(\.palette) private var palette

    /// Bounded at 14. A doula accumulates one of these a night and nobody scrolls
    /// a year back on a phone; the cap was here before this screen was.
    private var pastNights: [Shift] {
        closedShifts.filter { $0.familyIDRaw == family.id }.prefix(14).map { $0 }
    }

    var body: some View {
        Group {
            if pastNights.isEmpty {
                EmptyStatePlaceholder(
                    emoji: "🌙",
                    title: "No finished nights yet",
                    message: "When you end a shift for \(family.name), it appears here "
                        + "with its totals and handoff.")
            } else {
                ScrollView {
                    PastNightsSection(family: family, shifts: pastNights)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, MoonLayout.tabBarClearance)
                }
            }
        }
        .moonBackground(palette)
        .navigationTitle("Past nights")
        .navigationBarTitleDisplayMode(.inline)
    }
}
