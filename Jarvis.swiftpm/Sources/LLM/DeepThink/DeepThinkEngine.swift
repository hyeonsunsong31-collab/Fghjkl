import Foundation
import Observation

/// **Deep Think** — an optional larger open-weights model (Qwen3, 4-bit) that
/// runs entirely on the device with Jarvis' own pure-Swift + Metal inference
/// runtime (no MLX/C++ — Swift Playgrounds can build it). Downloaded once.
@MainActor
@Observable
final class DeepThinkEngine: LanguageEngine {
    struct Variant: Equatable {
        let repo: String
        let label: String
        let bytes: Int64
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    static let large = Variant(repo: "mlx-community/Qwen3-4B-Instruct-2507-4bit", label: "Qwen3 4B", bytes: 2_260_000_000)
    static let small = Variant(repo: "mlx-community/Qwen3-1.7B-4bit", label: "Qwen3 1.7B", bytes: 980_000_000)

    let name = "Deep Think (local Qwen3)"
    var statusText = "Not installed"
    var progress: Double?
    @ObservationIgnored private var runtime: Qwen3Runtime?

    var recommendedVariant: Variant { DeviceState.physicalMemoryGB >= 7.5 ? Self.large : Self.small }
    var isAvailable: Bool { runtime != nil }
    var unavailableReason: String? { isAvailable ? nil : statusText }

    private var directory: URL { JarvisPaths.models.appendingPathComponent("DeepThink", isDirectory: true) }

    var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("config.json").path)
            && fm.fileExists(atPath: directory.appendingPathComponent("tokenizer.json").path)
            && ((try? fm.contentsOfDirectory(atPath: directory.path))?.contains { $0.hasSuffix(".safetensors") } ?? false)
    }

    func install() {
        let variant = recommendedVariant
        statusText = "Downloading \(variant.label)…"
        progress = 0
        Task {
            do {
                let items = try await ModelDownloader.huggingFaceFiles(repo: variant.repo) { path in
                    path.hasSuffix(".safetensors") || path == "config.json" || path == "tokenizer.json"
                        || path == "tokenizer_config.json" || path == "model.safetensors.index.json"
                }
                try await ModelDownloader().download(items, to: directory) { p in
                    Task { @MainActor in self.progress = p }
                }
                progress = nil
                await loadIfInstalled()
            } catch {
                progress = nil
                statusText = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    func loadIfInstalled() async {
        guard isInstalled else { statusText = "Not installed"; return }
        statusText = "Loading…"
        let dir = directory
        do {
            let rt = try await Task.detached(priority: .userInitiated) { try Qwen3Runtime(directory: dir) }.value
            runtime = rt
            statusText = "Ready — \(rt.summary)"
        } catch {
            runtime = nil
            statusText = "Load failed: \(error.localizedDescription)"
        }
    }

    func prewarm() {}

    func respond(_ request: LLMRequest, onText: @escaping (String) -> Void) async throws -> LLMResult {
        guard let runtime else { throw NSError(domain: "DeepThink", code: 1, userInfo: [NSLocalizedDescriptionKey: statusText]) }
        let system = Persona.instructions(request.language, deviceName: DeviceState.deviceName)
            + (request.language == .korean
               ? " 기기 기능이 필요하면 <tool_call>{\"name\": \"run_command\", \"arguments\": {\"command\": \"...\"}}</tool_call> 형식으로 호출하십시오."
               : " To use a device function, emit <tool_call>{\"name\": \"run_command\", \"arguments\": {\"command\": \"...\"}}</tool_call>.")
        let prompt = ChatTemplate.qwen(system: system, user: PromptBuilder.prompt(for: request))
        var visible = ""
        let maxTokens = request.maxTokens
        let temperature = request.temperature
        let stream = AsyncStream<String> { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try runtime.generate(prompt: prompt, maxTokens: maxTokens, temperature: temperature) { piece in
                        continuation.yield(piece)
                        return !Task.isCancelled
                    }
                } catch {
                    continuation.yield("\n[error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
        var raw = ""
        var filter = ThinkFilter()
        for await piece in stream {
            raw += piece
            let shown = filter.feed(piece)
            if !shown.isEmpty {
                visible += shown
                onText(shown)
            }
        }
        var toolCalls: [ToolCallRecord] = []
        for call in ChatTemplate.toolCalls(in: raw) where call.name == "run_command" {
            let result = await ToolRegistry.shared.invoke("run_command", ["command": call.arguments["command"] ?? ""])
            toolCalls.append(ToolCallRecord(name: call.name, arguments: call.arguments.description, result: result,
                                            success: !result.hasPrefix("FAILED"), duration: 0))
        }
        let reply = ChatTemplate.stripMarkup(visible)
        return LLMResult(reply: reply, toolCalls: toolCalls, engineName: name)
    }
}
