import Foundation

/// Care context is chosen for a shift, never inferred from clock time or theme.
/// Existing persisted shifts without a context are interpreted as night by the app.
public enum CareContext: String, Codable, CaseIterable, Sendable {
    case night, day
}

/// Human-authored observations remain separate from the calculated care log.
public struct DayReportDraft: Codable, Sendable, Equatable {
    public var caregiverName: String
    public var summary: String
    public var eveningNotes: String
    public var questions: String

    public init(caregiverName: String = "", summary: String = "", eveningNotes: String = "", questions: String = "") {
        self.caregiverName = caregiverName
        self.summary = summary
        self.eveningNotes = eveningNotes
        self.questions = questions
    }

    public var normalized: Self {
        Self(caregiverName: caregiverName.trimmingCharacters(in: .whitespacesAndNewlines),
             summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
             eveningNotes: eveningNotes.trimmingCharacters(in: .whitespacesAndNewlines),
             questions: questions.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A frozen copy of exactly what was reviewed, independent of later log edits.
/// Publication means saved locally, not sent, delivered or read by anyone.
public struct DayReportPublication: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let version: Int
    public let publishedAt: Date
    public let sourceFingerprint: String
    public let draft: DayReportDraft
    public let plainText: String
    public let html: String
}

/// No remote identity or read receipt is implied by typing a name on this phone.
public enum DayReportAcknowledgementMethod: String, Codable, Sendable {
    case inPersonOnCaregiverDevice = "in-person-on-caregiver-device"
}

/// Optional receipt of a specific report revision, never consent to care decisions.
/// A parent's response stays separate from the caregiver's editable observations.
public struct DayReportAcknowledgement: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let publicationID: UUID
    public let version: Int
    public let parentName: String
    public let note: String
    public let acknowledgedAt: Date
    public let method: DayReportAcknowledgementMethod
}

public enum DayReportError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case caregiverNameRequired, invalidDraft, missingSource, missingRenderedReport
    case draftConflict, stalePublication, parentNameRequired, invalidParentNote, invalidDate, duplicateIdentifier

    public var description: String {
        switch self {
        case .caregiverNameRequired: return "Add the caregiver's name before publishing."
        case .invalidDraft: return "Use up to 80 characters for the caregiver name and 2,000 for each report note."
        case .missingSource: return "The current care log could not be verified. Reload the report and try again."
        case .missingRenderedReport: return "The report could not be prepared. Your draft is still here."
        case .draftConflict: return "A newer draft was saved elsewhere. Your entered notes are still here. Copy them, or reload the saved draft before editing again."
        case .stalePublication: return "This report has changed. Review and publish the current revision before recording a handoff acknowledgement."
        case .parentNameRequired: return "Add the name of the parent reviewing this report on this phone."
        case .invalidParentNote: return "Use up to 80 characters for the parent name and 2,000 for their note."
        case .invalidDate: return "The handoff time is invalid. Check the device clock and try again."
        case .duplicateIdentifier: return "This report identifier is already in use. Reload and try again."
        }
    }

    public var errorDescription: String? { description }
}

/// App persistence encodes this value on the owning shift and saves through
/// CareStore. The fingerprint is a stable digest of factual source records,
/// coverage window, roster, display units and care context, supplied by the app.
/// It must not use Swift's process-random Hasher or a continuously ticking clock.
public struct DayReportState: Codable, Sendable, Equatable {
    public var draft: DayReportDraft
    public private(set) var publications: [DayReportPublication]
    public private(set) var acknowledgements: [DayReportAcknowledgement]

    public init(draft: DayReportDraft = DayReportDraft()) {
        self.draft = draft
        self.publications = []
        self.acknowledgements = []
    }

    public var latestPublication: DayReportPublication? { publications.last }

    /// A changed source or edited narrative makes any previous receipt historical.
    /// Nothing mutates or erases the older copy that a parent may already hold.
    public func currentPublication(for sourceFingerprint: String) -> DayReportPublication? {
        guard !sourceFingerprint.isEmpty, let latest = publications.last,
              latest.sourceFingerprint == sourceFingerprint,
              latest.draft == draft.normalized else { return nil }
        return latest
    }

    public func acknowledgements(for publication: DayReportPublication) -> [DayReportAcknowledgement] {
        acknowledgements.filter { $0.publicationID == publication.id && $0.version == publication.version }
    }

    /// Repeating publication of unchanged content is idempotent, including after a
    /// lost save response. Callers must require a closed shift before this method.
    @discardableResult
    public mutating func publish(sourceFingerprint: String, plainText: String, html: String,
                                 at date: Date, id: UUID = UUID()) throws -> DayReportPublication {
        let reviewed = draft.normalized
        guard !reviewed.caregiverName.isEmpty else { throw DayReportError.caregiverNameRequired }
        guard reviewed.caregiverName.count <= 80,
              [reviewed.summary, reviewed.eveningNotes, reviewed.questions].allSatisfy({ $0.count <= 2_000 }) else {
            throw DayReportError.invalidDraft
        }
        guard !sourceFingerprint.isEmpty else { throw DayReportError.missingSource }
        guard !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DayReportError.missingRenderedReport }
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw DayReportError.invalidDate }
        if let current = currentPublication(for: sourceFingerprint) { return current }
        guard !publications.contains(where: { $0.id == id }) else { throw DayReportError.duplicateIdentifier }
        guard let version = nextVersion else { throw DayReportError.invalidDraft }
        if let latest = latestPublication, date < latest.publishedAt { throw DayReportError.invalidDate }
        let publication = DayReportPublication(id: id, version: version, publishedAt: date,
                                             sourceFingerprint: sourceFingerprint, draft: reviewed,
                                             plainText: plainText, html: html)
        draft = reviewed
        publications.append(publication)
        return publication
    }

    /// Entirely optional: never a prerequisite for ending, publishing or sharing.
    /// The caller explicitly hands this phone to the parent and states that the
    /// typed name is not authenticated. Unchanged retries do not invent receipts.
    @discardableResult
    public mutating func acknowledge(publicationID: UUID, version: Int, sourceFingerprint: String,
                                     parentName: String, note: String = "", at date: Date,
                                     id: UUID = UUID()) throws -> DayReportAcknowledgement {
        guard let current = currentPublication(for: sourceFingerprint),
              current.id == publicationID, current.version == version else { throw DayReportError.stalePublication }
        let name = parentName.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DayReportError.parentNameRequired }
        guard name.count <= 80, response.count <= 2_000 else { throw DayReportError.invalidParentNote }
        guard date.timeIntervalSinceReferenceDate.isFinite, date >= current.publishedAt else { throw DayReportError.invalidDate }
        if let existing = acknowledgements.first(where: {
            $0.publicationID == publicationID && $0.version == version && $0.parentName == name && $0.note == response
        }) { return existing }
        guard !acknowledgements.contains(where: { $0.id == id }) else { throw DayReportError.duplicateIdentifier }
        let acknowledgement = DayReportAcknowledgement(id: id, publicationID: publicationID, version: version,
                                                       parentName: name, note: response, acknowledgedAt: date,
                                                       method: .inPersonOnCaregiverDevice)
        acknowledgements.append(acknowledgement)
        return acknowledgement
    }

    private var nextVersion: Int? {
        let current = publications.map(\.version).max() ?? 0
        return current < Int.max ? current + 1 : nil
    }
}
