import XCTest
@testable import JarvisCore

final class LMRuntimeTests: XCTestCase {
    var fixtures: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)! }

    func testHalfConversions() {
        XCTAssertEqual(HalfConversion.f16(0x3C00), 1.0)
        XCTAssertEqual(HalfConversion.f16(0xC000), -2.0)
        XCTAssertEqual(HalfConversion.f16(HalfConversion.toF16(0.333)), 0.333, accuracy: 1e-3)
        XCTAssertEqual(HalfConversion.bf16(0x3F80), 1.0)
        XCTAssertEqual(HalfConversion.f16(HalfConversion.toF16(65504)), 65504)
        XCTAssertEqual(HalfConversion.f16(HalfConversion.toF16(1e-6)), 1e-6, accuracy: 1e-7)
    }

    func testSafetensorsParsing() throws {
        let store = try SafetensorsStore(directory: fixtures.appendingPathComponent("tiny_qwen3"))
        let embed = try store.tensor("model.embed_tokens.weight")
        XCTAssertEqual(embed.dtype, .u32)
        XCTAssertEqual(embed.shape, [320, 8])
        XCTAssertEqual(try store.tensor("model.embed_tokens.scales").dtype, .bf16)
        XCTAssertEqual(try store.tensor("model.norm.weight").floats().count, 64)
    }

    func testTinyQwen3MatchesNumPyReference() throws {
        try checkReference(modelDir: "tiny_qwen3")
    }

    /// Same weights, data section starting at an odd offset (like real MLX files).
    func testUnalignedSafetensorsMatchReference() throws {
        let store = try SafetensorsStore(directory: fixtures.appendingPathComponent("tiny_qwen3_unaligned"))
        XCTAssertNotEqual(try store.tensor("model.embed_tokens.weight").offset % 4, 0)
        try checkReference(modelDir: "tiny_qwen3_unaligned")
    }

    private func checkReference(modelDir: String) throws {
        let dir = fixtures.appendingPathComponent(modelDir)
        let refDir = fixtures.appendingPathComponent("tiny_qwen3")
        let model = try Qwen3CPUModel(directory: dir, maxContext: 64)
        XCTAssertEqual(model.config.heads, 4)
        XCTAssertEqual(model.config.groupSize, 32)
        let ref = try JSONSerialization.jsonObject(with: Data(contentsOf: refDir.appendingPathComponent("reference.json"))) as! [String: Any]
        let tokens = ref["tokens"] as! [Int]
        let logits = ref["logits"] as! [[Double]]
        for (step, t) in tokens.enumerated() {
            let out = try model.forward(token: t)
            XCTAssertEqual(out.count, 320)
            var maxErr: Float = 0
            for i in 0..<out.count { maxErr = max(maxErr, abs(out[i] - Float(logits[step][i]))) }
            XCTAssertLessThan(maxErr, 2e-3, "step \(step): max |Δlogit| = \(maxErr)")
            let refArgmax = logits[step].indices.max { logits[step][$0] < logits[step][$1] }
            XCTAssertEqual(out.indices.max { out[$0] < out[$1] }, refArgmax)
        }
    }

    func testTokenizerMatchesHuggingFace() throws {
        let tok = try BPETokenizer(jsonData: Data(contentsOf: fixtures.appendingPathComponent("tiny_tokenizer.json")))
        let refs = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("tiny_tokenizer_reference.json"))) as! [[String: Any]]
        for r in refs {
            let text = r["text"] as! String
            let expected = r["ids"] as! [Int]
            XCTAssertEqual(tok.encode(text), expected, "encode(\(text.debugDescription))")
            XCTAssertEqual(tok.decode(expected), text.precomposedStringWithCanonicalMapping)
        }
        XCTAssertNotNil(tok.id(of: "<|im_end|>"))
    }

    func testStreamingDetokenizerHandlesSplitUTF8() {
        var d = StreamingDetokenizer()
        let bytes = Array("한국어".utf8)
        var out = ""
        for b in bytes { out += d.append([b]) }
        out += d.flush()
        XCTAssertEqual(out, "한국어")
    }

    func testChatTemplateAndThinkFilter() {
        let p = ChatTemplate.qwen(system: "S", user: "U")
        XCTAssertTrue(p.hasSuffix("<|im_start|>assistant\n"))
        var f = ThinkFilter()
        var shown = ""
        for piece in ["Hello <thi", "nk>secret plan</th", "ink> sir. <tool_call>{\"name\":\"run_command\",", "\"arguments\":{\"command\":\"open 3D\"}}</tool_call> Done."] {
            shown += f.feed(piece)
        }
        XCTAssertEqual(shown, "Hello  sir.  Done.")
        let calls = ChatTemplate.toolCalls(in: "x <tool_call>{\"name\":\"run_command\",\"arguments\":{\"command\":\"open 3D\"}}</tool_call>")
        XCTAssertEqual(calls, [ChatTemplate.ToolCall(name: "run_command", arguments: ["command": "open 3D"])])
        XCTAssertEqual(ChatTemplate.stripMarkup("<think>a</think>Yes, sir.<|im_end|>"), "Yes, sir.")
    }

    func testSamplerRespectsGreedyAndTopP() {
        var s = TokenSampler(temperature: 0)
        XCTAssertEqual(s.sample([0.1, 3, 0.2], recent: []), 1)
        var t = TokenSampler(temperature: 0.8, topK: 2, topP: 0.5)
        for _ in 0..<50 { XCTAssertEqual(t.sample([0, 10, 1, -5], recent: []), 1) }
    }

    /// Optional: compare against the real Qwen3 tokenizer when available
    /// (set QWEN_TOKENIZER=/path/to/tokenizer.json and QWEN_TOKENIZER_REF=/path/to/ref.json).
    func testRealQwenTokenizerIfAvailable() throws {
        guard let path = ProcessInfo.processInfo.environment["QWEN_TOKENIZER"],
              let refPath = ProcessInfo.processInfo.environment["QWEN_TOKENIZER_REF"] else {
            throw XCTSkip("Real tokenizer not provided")
        }
        let tok = try BPETokenizer(jsonData: Data(contentsOf: URL(fileURLWithPath: path)))
        let refs = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: refPath))) as! [[String: Any]]
        for r in refs {
            XCTAssertEqual(tok.encode(r["text"] as! String), r["ids"] as! [Int], r["text"] as! String)
        }
    }
}
