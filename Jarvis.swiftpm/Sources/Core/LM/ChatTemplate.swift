import Foundation

/// Qwen chat formatting and parsing of tool calls / thinking blocks.
enum ChatTemplate {
    static func qwen(system: String, user: String, history: [(role: String, text: String)] = []) -> String {
        var s = "<|im_start|>system\n\(system)<|im_end|>\n"
        for turn in history { s += "<|im_start|>\(turn.role)\n\(turn.text)<|im_end|>\n" }
        s += "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
        return s
    }

    struct ToolCall: Equatable {
        var name: String
        var arguments: [String: String]
    }

    /// Extract `<tool_call>{...}</tool_call>` blocks.
    static func toolCalls(in text: String) -> [ToolCall] {
        var calls: [ToolCall] = []
        var rest = Substring(text)
        while let open = rest.range(of: "<tool_call>") {
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "</tool_call>") else { break }
            let json = after[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = json.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = obj["name"] as? String {
                var args: [String: String] = [:]
                for (k, v) in (obj["arguments"] as? [String: Any]) ?? [:] { args[k] = "\(v)" }
                calls.append(ToolCall(name: name, arguments: args))
            }
            rest = after[close.upperBound...]
        }
        return calls
    }

    /// Remove thinking/tool markup and special tokens from a reply.
    static func stripMarkup(_ text: String) -> String {
        var s = text
        for (open, close) in [("<think>", "</think>"), ("<tool_call>", "</tool_call>")] {
            while let a = s.range(of: open) {
                if let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                    s.removeSubrange(a.lowerBound..<b.upperBound)
                } else {
                    s.removeSubrange(a.lowerBound..<s.endIndex)
                }
            }
        }
        for token in ["<|im_end|>", "<|im_start|>", "<|endoftext|>", "</think>"] { s = s.replacingOccurrences(of: token, with: "") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Streaming filter that hides `<think>…</think>` and `<tool_call>…</tool_call>`
/// from the user (and from speech) while text is being generated.
struct ThinkFilter {
    private var buffer = ""
    private var hiddenUntil: String?

    mutating func feed(_ piece: String) -> String {
        buffer += piece
        var out = ""
        while !buffer.isEmpty {
            if let end = hiddenUntil {
                guard let r = buffer.range(of: end) else {
                    // Keep only a tail that could contain the start of the end tag.
                    if buffer.count > end.count { buffer = String(buffer.suffix(end.count)) }
                    return out
                }
                buffer = String(buffer[r.upperBound...])
                hiddenUntil = nil
                continue
            }
            var earliest: (Range<String.Index>, String)?
            for (open, close) in [("<think>", "</think>"), ("<tool_call>", "</tool_call>")] {
                if let r = buffer.range(of: open), earliest == nil || r.lowerBound < earliest!.0.lowerBound { earliest = (r, close) }
            }
            if let (r, close) = earliest {
                out += buffer[..<r.lowerBound]
                buffer = String(buffer[r.upperBound...])
                hiddenUntil = close
                continue
            }
            // Hold back a possible partial tag at the end.
            if let lt = buffer.lastIndex(of: "<"), buffer.distance(from: lt, to: buffer.endIndex) < 12 {
                out += buffer[..<lt]
                buffer = String(buffer[lt...])
                return out.replacingOccurrences(of: "<|im_end|>", with: "")
            }
            out += buffer
            buffer = ""
        }
        return out.replacingOccurrences(of: "<|im_end|>", with: "")
    }
}
