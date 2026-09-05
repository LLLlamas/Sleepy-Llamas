import SwiftUI
import MoonlogCore

struct TimelineEntry: Identifiable, Equatable {
    let id: UUID
    let at: Date
    let babyID: UUID?
    let icon: String
    let title: String
    let detail: String?
    /// Which sheet corrects this row. Nil for a row that cannot be edited.
    let edit: LogSheet?
}

/// One merged, reverse-chronological list for the household. Shared rather than
/// per-baby because at 3am the question is "what just happened"; each row carries
/// the baby's name so it never becomes ambiguous.
struct TimelineSection: View {
    let entries: [TimelineEntry]
    let timeZone: TimeZone
    let names: [UUID: String]
    let accents: [UUID: BabyAccent]
    var onEdit: (LogSheet) -> Void = { _ in }

    @Environment(\.palette) private var palette
    @Environment(\.moonTheme) private var theme

    private var showsNames: Bool { names.count > 1 }

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
                        if let edit = entry.edit {
                            Button {
                                Haptics.tap()
                                onEdit(edit)
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                        } else {
                            row(entry)
                        }
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
                    if showsNames, let id = entry.babyID, let name = names[id] {
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

            if entry.edit != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(palette.faint.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func accentColor(for entry: TimelineEntry) -> Color {
        guard let id = entry.babyID, let accent = accents[id] else { return palette.faint }
        return showsNames ? accent.color(for: theme) : palette.faint
    }
}
