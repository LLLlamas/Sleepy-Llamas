import SwiftUI
import MoonlogCore

struct TimelineEntry: Identifiable, Equatable {
    let id: UUID
    let at: Date
    let babyID: UUID?
    let icon: String
    let title: String
    let detail: String?
}

/// One merged, reverse-chronological list for the whole household.
///
/// Shared rather than per-baby even with twins: at 3am the question is usually
/// "what just happened", not "what happened to Mia". Each row carries the baby's
/// name so a shared list never becomes ambiguous.
struct TimelineSection: View {
    let entries: [TimelineEntry]
    let timeZone: TimeZone
    let babyNames: [UUID: String]
    let babyAccents: [UUID: BabyAccent]

    @Environment(\.palette) private var palette

    private var showsBabyNames: Bool { babyNames.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tonight")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.faint)
                .padding(.horizontal, 4)

            if entries.isEmpty {
                empty
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(entry)
                        if index < entries.count - 1 {
                            Divider().overlay(palette.line).padding(.leading, 46)
                        }
                    }
                }
                .background(
                    palette.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.line, lineWidth: 1))
            }
        }
    }

    private var empty: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Text("🌙").font(.title2)
                Text("Nothing logged yet")
                    .font(.subheadline)
                    .foregroundStyle(palette.faint)
            }
            Spacer()
        }
        .padding(.vertical, 28)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ entry: TimelineEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .font(.footnote)
                .frame(width: 22)
                .foregroundStyle(accentColor(for: entry))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if showsBabyNames, let id = entry.babyID, let name = babyNames[id] {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accentColor(for: entry))
                    }
                    Text(entry.title)
                        .font(.subheadline)
                        .foregroundStyle(palette.ink)
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.faint)
                }
            }

            Spacer()

            Text(Fmt.clock(entry.at, timeZone: timeZone))
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.soft)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func accentColor(for entry: TimelineEntry) -> Color {
        guard let id = entry.babyID, let accent = babyAccents[id] else { return palette.faint }
        return showsBabyNames ? accent.color(in: palette) : palette.faint
    }
}
