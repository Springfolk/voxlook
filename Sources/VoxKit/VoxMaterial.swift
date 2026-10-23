/// A palette entry's material from a `MATL` chunk (MagicaVoxel 0.99+).
///
/// Only what a rasterised preview can show is kept: which kind of surface it
/// is, and the few parameters that change how it looks.
public struct VoxMaterial: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case diffuse = "_diffuse", metal = "_metal", glass = "_glass", emit = "_emit", blend = "_blend", media = "_media"
    }

    public var kind: Kind = .diffuse
    /// 0…1; `_trans` (or the older `_alpha`).
    public var transparency: Float = 0
    /// 0…1.
    public var metalness: Float = 0
    /// 0…1.
    public var roughness: Float = 0.1
    /// Emission strength; 0 = none.
    public var emission: Float = 0

    public init(kind: Kind = .diffuse) { self.kind = kind }

    init(attributes a: [String: String]) {
        func value(_ key: String) -> Float? { a[key].flatMap(Float.init).map { min(max($0, 0), 1) } }
        kind = a["_type"].flatMap(Kind.init) ?? .diffuse
        transparency = value("_trans") ?? value("_alpha") ?? 0
        metalness = value("_metal") ?? 0
        roughness = value("_rough") ?? 0.1
        emission = a["_emit"].flatMap(Float.init).map { max($0, 0) } ?? 0
    }

    /// How the preview draws it.
    public var surface: VoxSurface {
        switch kind {
        case .emit where emission > 0: return .emissive
        case .glass where transparency > 0, .media where transparency > 0, .blend where transparency > 0: return .glass
        case .metal where metalness > 0, .blend where metalness > 0.5: return .metal
        default: return .diffuse
        }
    }
}

/// The surface classes the mesher splits geometry into, in draw order.
public enum VoxSurface: Int, CaseIterable, Sendable {
    case diffuse, metal, emissive, glass

    /// Light passes through it: faces behind it stay, and it doesn't occlude.
    public var isTransparent: Bool { self == .glass }
}
