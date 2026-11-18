import CryptoKit
import Foundation

/// A workspace identity derived from its project path.
///
/// The same folder keeps the same identity across launches and no longer depends on which of its
/// agents arrived first, so a tree merged from different orders compares equal row for row.
func workspaceID(for projectPath: String) -> UUID {
    let digest = SHA256.hash(data: Data(projectPath.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    let identifier = [
        String(hex.prefix(8)),
        String(hex.dropFirst(8).prefix(4)),
        "4" + String(hex.dropFirst(13).prefix(3)),
        "8" + String(hex.dropFirst(17).prefix(3)),
        String(hex.dropFirst(20).prefix(12)),
    ].joined(separator: "-")
    return UUID(uuidString: identifier) ?? UUID()
}
