public enum VoxPalette {
    /// MagicaVoxel's built-in palette, used when a file has no `RGBA` chunk.
    ///
    /// Index 0 is empty. 1–215 are the 6×6×6 colour cube (blue varies fastest,
    /// each channel stepping down from 0xFF by 0x33, black omitted), followed by
    /// ten-step ramps of red, green, blue and grey (0xEE … 0x11, skipping
    /// multiples of 0x33).
    public static let `default`: [VoxColor] = {
        var colors = [VoxColor(r: 0, g: 0, b: 0, a: 0)]
        let cube: [UInt8] = [0xFF, 0xCC, 0x99, 0x66, 0x33, 0x00]
        for r in cube {
            for g in cube {
                for b in cube where !(r == 0 && g == 0 && b == 0) {
                    colors.append(VoxColor(r: r, g: g, b: b))
                }
            }
        }
        let ramp: [UInt8] = [0xEE, 0xDD, 0xBB, 0xAA, 0x88, 0x77, 0x55, 0x44, 0x22, 0x11]
        for v in ramp { colors.append(VoxColor(r: v, g: 0, b: 0)) }
        for v in ramp { colors.append(VoxColor(r: 0, g: v, b: 0)) }
        for v in ramp { colors.append(VoxColor(r: 0, g: 0, b: v)) }
        for v in ramp { colors.append(VoxColor(r: v, g: v, b: v)) }
        return colors
    }()
}
