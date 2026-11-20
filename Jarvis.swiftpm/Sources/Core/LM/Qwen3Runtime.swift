import Foundation

/// Placeholder; replaced by the full runtime implementation.
final class Qwen3Runtime: @unchecked Sendable {
    let summary: String
    init(directory: URL) throws {
        throw NSError(domain: "DeepThink", code: 2, userInfo: [NSLocalizedDescriptionKey: "Runtime not available yet"])
    }
    func generate(prompt: String, maxTokens: Int, temperature: Float, onToken: (String) -> Bool) throws {}
}
