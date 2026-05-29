import SwiftUI

/// The Empire tab is a deliberate, *scoped* exception to Marble's strictly-monochrome brand:
/// the rest of the app stays grayscale, but the gamification "reward realm" earns colour so
/// progress feels luminous. Colour is organised by `EmpireAge` so unlocking an era visibly
/// recolours your world — the palette itself doubles as a progression signal.
///
/// Functional chrome (body copy, card fills) keeps using `Theme.*`; these palettes layer on top
/// for the *rewards* — monument emblems, the living skyline, progress, and celebrations.
struct EmpirePalette {
    /// Scene background gradient, top → bottom. The skyline supplies its own backdrop, so these
    /// read consistently in both light and dark mode (the scene is colour-scheme independent).
    let sky: [Color]
    /// Primary identity colour — chip accents, progress fill, emblem mid-tone.
    let accent: Color
    /// Emblem gradient highlight (top-left) — gives the glyph a lit, dimensional edge.
    let emblemLight: Color
    /// Emblem gradient shade (bottom-right).
    let emblemDark: Color
    /// Soft halo behind emblems and the celestial orb.
    let glow: Color
    /// Drifting particle tint for the living scene.
    let particle: Color
    /// How this age's particles behave.
    let particleStyle: EmpireParticleStyle

    /// The emblem's lit gradient, top-leading → bottom-trailing.
    var emblemGradient: LinearGradient {
        LinearGradient(
            colors: [emblemLight, accent, emblemDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The scene sky, top → bottom.
    var skyGradient: LinearGradient {
        LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
    }
}

/// Particle personalities per age. Drives the `Canvas` renderer in the living skyline.
enum EmpireParticleStyle {
    case embers   // warm flecks drifting upward (dawn / forge)
    case motes    // soft dust floating gently (gilded air)
    case sparks   // bright points that twinkle and dart (glory / the future)
}

extension EmpireAge {
    /// Each age recolours the world. Hues are chosen to read on both white and black card
    /// surfaces (mid-luminance, medium-saturation) and to tell a clear material story:
    /// sandstone dawn → Mediterranean gold → imperial crimson → copper & steel → neon future.
    var palette: EmpirePalette {
        switch self {
        case .foundations:
            return EmpirePalette(
                sky: [empireHex(0xF2C79A), empireHex(0xC77B53)],
                accent: empireHex(0xC56A3E),
                emblemLight: empireHex(0xE8A66B),
                emblemDark: empireHex(0xB5582F),
                glow: empireHex(0xF0A860),
                particle: empireHex(0xF7D9A8),
                particleStyle: .embers
            )
        case .golden:
            return EmpirePalette(
                sky: [empireHex(0xFCE39A), empireHex(0xE0A02E)],
                accent: empireHex(0xCE9A2A),
                emblemLight: empireHex(0xF6D873),
                emblemDark: empireHex(0xBB8016),
                glow: empireHex(0xFFD54A),
                particle: empireHex(0xFFEEAA),
                particleStyle: .motes
            )
        case .empire:
            return EmpirePalette(
                sky: [empireHex(0x9B2D55), empireHex(0x3A1E4D)],
                accent: empireHex(0xC0395E),
                emblemLight: empireHex(0xD75C84),
                emblemDark: empireHex(0x7A2348),
                glow: empireHex(0xD6557E),
                particle: empireHex(0xF1C75A),
                particleStyle: .sparks
            )
        case .industrial:
            return EmpirePalette(
                sky: [empireHex(0x3E6E6B), empireHex(0x1B2A30)],
                accent: empireHex(0xC8773F),
                emblemLight: empireHex(0xE0975A),
                emblemDark: empireHex(0x9A552A),
                glow: empireHex(0xE0894A),
                particle: empireHex(0xF0A24E),
                particleStyle: .embers
            )
        case .future:
            return EmpirePalette(
                sky: [empireHex(0x1B1148), empireHex(0x0C2747)],
                accent: empireHex(0x3AD1E6),
                emblemLight: empireHex(0x7FE6F2),
                emblemDark: empireHex(0x2A7FB0),
                glow: empireHex(0x8A6CF0),
                particle: empireHex(0xBFF6FF),
                particleStyle: .sparks
            )
        }
    }
}

/// Deterministic sRGB colour from a 0xRRGGBB literal. Kept Empire-local (prefixed) so it never
/// collides with a future app-wide hex initialiser, and so these vivid values stay quarantined to
/// the one tab that's allowed colour.
func empireHex(_ value: UInt) -> Color {
    Color(
        red: Double((value >> 16) & 0xFF) / 255.0,
        green: Double((value >> 8) & 0xFF) / 255.0,
        blue: Double(value & 0xFF) / 255.0
    )
}
