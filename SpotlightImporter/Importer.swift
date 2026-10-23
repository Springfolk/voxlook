import CoreFoundation
import Foundation
import VoxKit

/// Spotlight metadata for one `.vox`: size, voxel and model counts, and the
/// object and layer names, so files can be found by what's in them. Parses
/// only — no meshing or rendering. Called from plugin.c.
@_cdecl("VoxLookImportFile")
func importFile(_ attributes: CFMutableDictionary, _ path: CFString) -> DarwinBoolean {
    guard let file = try? VoxFile(contentsOf: URL(fileURLWithPath: path as String)) else { return false }
    let summary = VoxSummary(file)
    let dict = attributes as NSMutableDictionary
    dict[kMDItemDescription as String] = summary.description
    dict[kMDItemVersion as String] = String(file.version)
    if !summary.names.isEmpty {
        dict[kMDItemKeywords as String] = summary.names
        dict[kMDItemTextContent as String] = summary.names.joined(separator: " ")
    }
    return true
}
