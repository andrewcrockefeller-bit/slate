import SwiftUI

/// Every color is a Color Set in Assets.xcassets with Any + Dark appearances,
/// so dark mode resolves from the asset catalog. No `@Environment(\.colorScheme)`
/// checks at call sites — the one exception is `markerBlend`, which is a blend
/// mode and genuinely cannot come from an asset.
enum Palette {
    // ---- Ground ----
    static let paper      = Color("Paper")       // #F0EEE8  dark #17191B
    static let surface    = Color("Surface")     // #F8F7F3  dark #1F2225
    static let paperGrain = Color.black.opacity(0.03)

    // ---- Ink / text ----
    static let graphite   = Color("Graphite")    // #1A1C1E  dark #E6E7E3
    static let inkSoft    = Color("InkSoft")     // #565E64  dark #A0A7AB
    static let inkFaint   = Color("InkFaint")    // #868D92  dark #737A7F
    static let hairline   = Color("Hairline")    // #D2D5CF  dark #2D3236

    // ---- Interface accent: buttons, selection, focus ----
    static let pen        = Color("Pen")         // #2E4A66  dark #8AB2D6

    // ---- RESERVED FOR THE TUTOR. Never an interface element. ----
    static let tutor      = Color("Tutor")       // #8A5A3B  dark #CE9A73
    static let tutorWash  = Color("TutorWash")   // #F0E4DA  dark #2E241C

    // ---- Loud failure states. Deliberately distinct from InkCrimson so a
    // system alert is never visually mistaken for a chosen ink color. Not in
    // the original token spec — added for CanvasScreen's "SAVE FAILED" state,
    // see docs/DS-CONFLICTS.md, C-7. ----
    static let alert      = Color("Alert")       // #A62F22  dark #E8836F

    // ---- User ink palette: exactly six, no picker in v1 ----
    // On dark paper the graphite ink inverts to chalk; the rest lift and
    // desaturate so they read as ink rather than as glowing UI color.
    static let inks: [Color] = [
        Color("InkGraphite"),   // #1A1C1E  dark #E8E9E5
        Color("InkNavy"),       // #2E4A66  dark #93B4D2
        Color("InkCrimson"),    // #8C3A33  dark #D4877E
        Color("InkForest"),     // #3F5F4A  dark #8FB79C
        Color("InkPlum"),       // #5A4262  dark #B49BC0
        Color("InkOchre")       // #A8792F  dark #D9AF63
    ]

    // ---- Highlighter: exactly three. Always composited BEHIND ink. ----
    static let markers: [Color] = [
        Color("MarkerGold"),    // #C4A265  dark #5C4A22
        Color("MarkerMint"),    // #86B29A  dark #2E4A3B
        Color("MarkerSky")      // #8FAAC6  dark #2F4256
    ]

    /// Highlighter blend mode is scheme-dependent. Multiply darkens, which
    /// is correct on paper and wrong on a dark ground — on dark the marker
    /// must add light instead, or it reads as a hole punched in the page.
    static func markerBlend(_ scheme: ColorScheme) -> BlendMode {
        scheme == .dark ? .plusLighter : .multiply
    }
}
