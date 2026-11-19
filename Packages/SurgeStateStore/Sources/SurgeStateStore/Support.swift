import CryptoKit
import Foundation

/// A workspace identity derived from its project path.
///
/// The same folder keeps the same identity across launches and no longer depends on which of its
/// agents arrived first, so a tree merged from different orders compares equal row for row.
func workspaceID(for projectPath: String) -> UUID {
    let digest = SHA256.hash(data: Data(projectPath.utf8))
    let hex: String = digest.map { byte -> String in
        String(format: "%02x", byte)
    }.joined()
    let first: String = String(hex.prefix(8))
    let second: String = String(hex.dropFirst(8).prefix(4))
    let third: String = "4" + String(hex.dropFirst(13).prefix(3))
    let fourth: String = "8" + String(hex.dropFirst(17).prefix(3))
    let fifth: String = String(hex.dropFirst(20).prefix(12))
    let identifier: String = [first, second, third, fourth, fifth].joined(separator: "-")
    return UUID(uuidString: identifier) ?? UUID()
}
