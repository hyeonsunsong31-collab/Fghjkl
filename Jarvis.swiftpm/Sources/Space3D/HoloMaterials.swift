import RealityKit
import UIKit

/// Colour palette shared by the 3D space and the 2D hologram UI.
enum HoloPalette {
    static func uiColor(_ name: String) -> UIColor {
        switch name.lowercased() {
        case "red": return UIColor(red: 1.00, green: 0.24, blue: 0.27, alpha: 1)
        case "orange": return UIColor(red: 1.00, green: 0.56, blue: 0.16, alpha: 1)
        case "yellow": return UIColor(red: 1.00, green: 0.88, blue: 0.25, alpha: 1)
        case "green": return UIColor(red: 0.25, green: 0.95, blue: 0.55, alpha: 1)
        case "cyan": return UIColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1)
        case "blue": return UIColor(red: 0.20, green: 0.48, blue: 1.00, alpha: 1)
        case "purple": return UIColor(red: 0.66, green: 0.38, blue: 1.00, alpha: 1)
        case "pink": return UIColor(red: 1.00, green: 0.42, blue: 0.78, alpha: 1)
        case "white": return UIColor(white: 0.96, alpha: 1)
        case "black": return UIColor(white: 0.12, alpha: 1)
        case "gray", "grey": return UIColor(white: 0.6, alpha: 1)
        case "gold": return UIColor(red: 1.00, green: 0.78, blue: 0.30, alpha: 1)
        default: return UIColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1)
        }
    }

    static let background = UIColor(red: 0.010, green: 0.030, blue: 0.075, alpha: 1)
    static let grid = UIColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.22)
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

    static func line(_ color: UIColor, opacity: Float = 0.75) -> RealityKit.Material {
        var u = UnlitMaterial(color: color)
        u.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return u
    }
}
