import SwiftUI

/// A nappy, because SF Symbols has none. The stand-in was `square.on.square`, a stack
/// of squares that reads as "duplicate" — on the one row where the doula picks a
/// button by its shape, in the dark, at four in the morning.
///
/// Used the way a symbol is used: a point size, and whatever `foregroundStyle` is in
/// force. `DiaperGlyph(size: 17).foregroundStyle(palette.soft)` stands beside
/// `Image(systemName: "drop.fill").font(.body)` without either looking bolted on.
struct DiaperGlyph: View {
    /// Point size, read the way `Image(systemName:)` reads a font size: the text size
    /// the glyph is matched to, not the height of the ink.
    @ScaledMetric private var size: CGFloat

    /// `relativeTo` is here for the reason a symbol takes a `Font`: symbols grow with
    /// Dynamic Type and this drawing has to grow with them, or the two drift apart at
    /// the accessibility sizes the card already lays out for.
    init(size: CGFloat = 17, relativeTo textStyle: Font.TextStyle = .body) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    var body: some View {
        // The ink height and the box are measured off real symbols rather than chosen.
        // At 20pt, Apple's solid, roughly square glyphs — `square.fill`, `app.fill`,
        // `heart.fill` — carry 18pt of ink, 0.90em, in a box about 0.15em larger, with
        // the ink centred. (The tall, narrow fills like `drop.fill` reach a full 1.0em;
        // a solid mass this wide at that height would out-weigh everything beside it.)
        // Matching the box as well as the ink is what keeps the row spacing and the
        // centre line the same as a symbol's, so a centred `HStack` needs no nudging.
        //
        // The width is the drawing's own: a nappy laid flat is wider than it is tall,
        // and a portrait one reads as a head.
        DiaperShape()
            .frame(width: size * 1.10, height: size * 0.90)
            .frame(width: size * 1.25, height: size * 1.05)
    }
}

/// A wide waistband with the leg openings taken out of the bottom corners, leaving the
/// crotch as a tab between them. That is the whole glyph: at 17pt the leg cutouts are
/// what say "garment", and everything else is a rounded rectangle.
///
/// Three silhouettes were tried at 17pt beside `drop.fill` before this one. A tabbed
/// top pinching to a rounded bottom is the shape a nappy actually is, and it is
/// unusable: two lobes flanking a dip read as **ears**, and the pinch below them reads
/// as a muzzle, so the glyph came out a cow's head — a confidently wrong icon, which is
/// harder to look past than the neutral squares it replaces. Removing the dip only
/// moved it to a plant pot. A separate waistband bar with a hairline gap under it reads
/// well at 20pt, but the gap is under a point by the time the glyph is caption-sized,
/// which is where it would fill in and muddy.
///
/// Drawn in the rect's own points, not in a normalised square, so the cutouts stay
/// circles and the corners stay round under a non-square frame.
private struct DiaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corner = rect.height * 0.17
        let body = CGPath(
            roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // Centred on the bottom corners, so each bite takes a quarter of a disc out of
        // the side and the bottom at once. The radius sets the crotch: at 0.36 of the
        // width the tab between them is a little under a third of the glyph, which is
        // the proportion that still reads as legs rather than as a bib.
        let legs = CGMutablePath()
        let radius = rect.width * 0.36
        let centreY = rect.maxY - rect.height * 0.02
        for centreX in [rect.minX, rect.maxX] {
            legs.addEllipse(in: CGRect(
                x: centreX - radius, y: centreY - radius, width: radius * 2, height: radius * 2))
        }
        return Path(body.subtracting(legs))
    }
}

/// An icon named the way an SF Symbol is named, that may not be one.
///
/// The app's icons travel as symbol names — `EventKind.icon` returns a `String`,
/// `TimelineEntry` carries one — and the diaper is now a drawing rather than a name
/// in that catalogue. Rather than widen every value type that carries an icon into
/// something that can hold a view, one sentinel name resolves here.
///
/// `Image(systemName:)` renders a blank for an unknown name and reports nothing, so
/// the sentinel must never reach one. It is only ever produced by `EventKind.icon`
/// for `.diaper`, and the one place that renders those is `TimelineSection`. The
/// overflow menu builds its buttons from `EventKind.optional`, which `.diaper` is
/// not — if a diaper ever joins that list, its button needs this too.
struct CareGlyph: View {
    /// The one name that is not in Apple's catalogue.
    static let diaper = "moonlog.diaper"

    let name: String
    var textStyle: Font.TextStyle = .body
    /// The point size the drawing is matched to. Symbols take theirs from `.font`.
    var size: CGFloat = 17

    init(_ name: String, size: CGFloat = 17, relativeTo textStyle: Font.TextStyle = .body) {
        self.name = name
        self.size = size
        self.textStyle = textStyle
    }

    var body: some View {
        if name == Self.diaper {
            DiaperGlyph(size: size, relativeTo: textStyle)
        } else {
            Image(systemName: name).font(.system(textStyle))
        }
    }
}
