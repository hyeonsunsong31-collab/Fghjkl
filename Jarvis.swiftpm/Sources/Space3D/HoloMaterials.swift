import RealityKit
import UIKit

/// Colour palette shared by the 3D space and the 2D hologram UI.
enum HoloPalette {
    static func uiColor(_ name: String) -> UIColor {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if key.hasPrefix("#"), let hex = Self.hex(key) { return hex }
        switch key {
        case "red": return UIColor(red: 1.00, green: 0.24, blue: 0.27, alpha: 1)
        case "maroon": return UIColor(red: 0.50, green: 0.10, blue: 0.15, alpha: 1)
        case "orange": return UIColor(red: 1.00, green: 0.56, blue: 0.16, alpha: 1)
        case "yellow": return UIColor(red: 1.00, green: 0.88, blue: 0.25, alpha: 1)
        case "lime": return UIColor(red: 0.65, green: 0.95, blue: 0.20, alpha: 1)
        case "green": return UIColor(red: 0.25, green: 0.80, blue: 0.40, alpha: 1)
        case "darkgreen": return UIColor(red: 0.12, green: 0.45, blue: 0.22, alpha: 1)
        case "teal": return UIColor(red: 0.10, green: 0.60, blue: 0.60, alpha: 1)
        case "cyan": return UIColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1)
        case "blue": return UIColor(red: 0.20, green: 0.48, blue: 1.00, alpha: 1)
        case "navy": return UIColor(red: 0.10, green: 0.16, blue: 0.42, alpha: 1)
        case "purple": return UIColor(red: 0.66, green: 0.38, blue: 1.00, alpha: 1)
        case "pink": return UIColor(red: 1.00, green: 0.50, blue: 0.75, alpha: 1)
        case "white": return UIColor(white: 0.96, alpha: 1)
        case "beige": return UIColor(red: 0.90, green: 0.83, blue: 0.68, alpha: 1)
        case "brown": return UIColor(red: 0.50, green: 0.32, blue: 0.18, alpha: 1)
        case "black": return UIColor(white: 0.10, alpha: 1)
        case "gray", "grey": return UIColor(white: 0.56, alpha: 1)
        case "darkgray", "darkgrey": return UIColor(white: 0.29, alpha: 1)
        case "silver": return UIColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 1)
        case "gold": return UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 1)
        default: return UIColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1)
        }
    }

    /// "#RRGGBB" from the language model.
    static func hex(_ text: String) -> UIColor? {
        let digits = text.dropFirst()
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static let background = UIColor(red: 0.010, green: 0.030, blue: 0.075, alpha: 1)
    static let grid = UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.22)
}

/// How objects are drawn: designed models get real materials by default ("auto"),
/// or everything can be shown as translucent holograms or with real materials.
enum RenderStyle: String, CaseIterable {
    case auto, hologram, solid

    static let key = "JarvisRenderStyle"
    static var current: RenderStyle {
        get { RenderStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Real materials for this object? (Designed models in auto mode, everything in solid mode.)
    func solid(composite: Bool) -> Bool {
        switch self {
        case .auto: return composite
        case .hologram: return false
        case .solid: return true
        }
    }
}

enum HoloMaterials {
    /// Semi-transparent, emissive "hologram" body material.
    static func body(_ color: UIColor, selected: Bool, hovered: Bool) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        m.metallic = 0.55
        m.roughness = 0.22
        m.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: color)
        m.emissiveIntensity = selected ? 1.3 : (hovered ? 0.95 : 0.5)
        m.blending = .transparent(opacity: .init(floatLiteral: selected ? 0.92 : 0.82))
        return m
    }

    /// A designed part with its real material (paint, metal, glass, …) and a faint holographic glow.
    static func part(_ color: UIColor, material: String?, solid: Bool, selected: Bool, hovered: Bool) -> RealityKit.Material {
        guard solid else { return body(color, selected: selected, hovered: hovered) }
        var m = PhysicallyBasedMaterial()
        m.baseColor = PhysicallyBasedMaterial.BaseColor(tint: color)
        let glow: Float = selected ? 0.32 : (hovered ? 0.2 : 0.07)
        m.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: color)
        m.emissiveIntensity = glow
        switch material ?? "plastic" {
        case "paint":
            m.metallic = 0.35
            m.roughness = 0.2
        case "metal":
            m.metallic = 0.8
            m.roughness = 0.3
            m.emissiveIntensity = glow + 0.06
        case "chrome":
            m.metallic = 0.9
            m.roughness = 0.1
            m.emissiveIntensity = glow + 0.1
        case "glass":
            m.metallic = 0.1
            m.roughness = 0.04
            m.emissiveIntensity = glow + 0.12
            m.blending = .transparent(opacity: .init(floatLiteral: 0.42))
        case "rubber":
            m.metallic = 0
            m.roughness = 0.92
        case "wood":
            m.metallic = 0
            m.roughness = 0.7
        case "stone":
            m.metallic = 0
            m.roughness = 0.88
        case "fabric":
            m.metallic = 0
            m.roughness = 0.96
        case "emissive":
            m.metallic = 0
            m.roughness = 0.4
            m.emissiveIntensity = selected ? 2.6 : 2.0
        default:
            m.metallic = 0.05
            m.roughness = 0.45
        }
        return m
    }

    static func line(_ color: UIColor, opacity: Float = 0.75) -> RealityKit.Material {
        var u = UnlitMaterial(color: color)
        u.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return u
    }
}
