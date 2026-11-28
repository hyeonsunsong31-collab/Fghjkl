import SwiftUI
import WebKit
import UIKit
import UniformTypeIdentifiers
import CoreImage.CIFilterBuiltins

/// The local development studio: workspace slots, stacked requests, a terminal, files and a
/// live preview, with links for web products and files to save for everything else.
struct StudioPanel: View {
    @Environment(JarvisController.self) private var jarvis
    @Bindable private var studio = StudioController.shared
    @State private var tab = 0
    @State private var requestText = ""
    @State private var importing = false

    private var korean: Bool { jarvis.currentLanguage == .korean }

    var body: some View {
        PanelContainer(title: korean ? "스튜디오" : "Studio", icon: "hammer", close: { jarvis.showPanel(nil) }) {
            WorkspaceBar(studio: studio, korean: korean)
            Picker("", selection: $tab) {
                Text(korean ? "요청" : "Requests").tag(0)
                Text(korean ? "터미널" : "Terminal").tag(1)
                Text(korean ? "파일" : "Files").tag(2)
                Text(korean ? "미리보기" : "Preview").tag(3)
            }
            .pickerStyle(.segmented)
            switch tab {
            case 0: requests
            case 1: StudioTerminal(studio: studio)
            case 2: StudioFiles(studio: studio, korean: korean, openPreview: { tab = 3 })
            default: preview
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await studio.importFile(url) }
        }
        .onAppear { studio.refresh() }
    }

    // MARK: Requests

    private var requests: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(requestPlaceholder, text: $requestText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "paperplane.fill").foregroundStyle(Holo.cyan)
                }
                .buttonStyle(.plain)
                .disabled(requestText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 8) {
                Button { importing = true } label: { Label(korean ? "파일 가져오기" : "Import file", systemImage: "square.and.arrow.down") }
                Menu {
                    ForEach(["zip", "exe", "app", "html", "sh"], id: \.self) { format in
                        Button(".\(format)") { Task { await studio.deliver(as: format) } }
                    }
                } label: {
                    Label(korean ? "파일로 내보내기" : "Export as", systemImage: "shippingbox")
                }
                if studio.busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            .font(Holo.mono(11))
            .foregroundStyle(Holo.cyan)
            if let delivery = studio.delivery {
                ShareLink(item: delivery.url) {
                    Label((korean ? "저장 / 보내기: " : "Save / send: ") + delivery.title, systemImage: "square.and.arrow.up")
                }
                .font(Holo.mono(11))
                .foregroundStyle(Holo.amber)
            }
            if let link = studio.shareLink { LinkCard(link: link, korean: korean) }
            RequestList(workspace: studio.active, korean: korean)
        }
    }

    private var requestPlaceholder: String {
        korean ? "만들거나 고칠 것을 말씀하세요 (예: 파란 뱀 게임)" : "Describe what to build or change (e.g. a snake game with a blue snake)"
    }

    private func send() {
        let text = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        requestText = ""
        studio.request(text, korean: Hangul.hangulRatio(text) > 0.3)
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let url = studio.previewURL {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(url.lastPathComponent).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.7))
                    Spacer()
                    Button { studio.previewReload += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(Holo.cyan)
                }
                StudioWebView(url: url, reload: studio.previewReload)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Holo.cyan.opacity(0.3)).allowsHitTesting(false))
            }
        } else {
            Text(korean ? "아직 미리 볼 웹 결과물이 없습니다. 요청 탭에서 만들어 보세요." : "Nothing to preview yet. Build something from the Requests tab.")
                .font(Holo.mono(11)).foregroundStyle(Holo.ice.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Workspace slots

private struct WorkspaceBar: View {
    @Bindable var studio: StudioController
    let korean: Bool
    @State private var renaming: Workspace?
    @State private var newName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(studio.workspaces) { ws in
                    chip(ws)
                }
                Button { studio.newWorkspace() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 26)
                        .background(Capsule().strokeBorder(Holo.cyan.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Holo.cyan)
            }
        }
        .alert(korean ? "이름 바꾸기" : "Rename workspace", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("", text: $newName)
            Button(korean ? "확인" : "OK") {
                if let ws = renaming { studio.rename(ws.id, to: newName) }
                renaming = nil
            }
            Button(korean ? "취소" : "Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func chip(_ ws: Workspace) -> some View {
        let selected: Bool = ws.id == studio.activeID
        let pending: Int = ws.pending.count
        return Button { studio.select(ws.id) } label: {
            HStack(spacing: 4) {
                Text(ws.name).lineLimit(1)
                if pending > 0 { Text("\(pending)").foregroundStyle(Holo.amber) }
            }
            .font(Holo.mono(11, selected ? .bold : .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(selected ? Holo.cyan.opacity(0.22) : Color.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Holo.cyan.opacity(selected ? 0.8 : 0.25)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Holo.cyan : Holo.ice)
        .contextMenu {
            Button(korean ? "이름 바꾸기" : "Rename") { newName = ws.name; renaming = ws }
            Button(korean ? "삭제" : "Delete", role: .destructive) { studio.delete(ws.id) }
        }
    }
}

// MARK: - Requests

private struct RequestList: View {
    let workspace: Workspace?
    let korean: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let product = workspace?.product {
                    Text("\(product.title) · \(product.kind) · v\(workspace?.latestVersion ?? 0)")
                        .font(Holo.mono(11, .bold)).foregroundStyle(Holo.cyan)
                }
                ForEach((workspace?.requests ?? []).reversed()) { r in
                    row(r)
                }
                if (workspace?.requests ?? []).isEmpty {
                    Text(korean ? "요청을 여러 개 쌓아 두면 순서대로 모두 적용합니다." : "Stack as many requests as you like; they are applied one after another.")
                        .font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ r: WorkRequest) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon(r.status)).foregroundStyle(color(r.status))
                Text(r.text).font(Holo.mono(11)).foregroundStyle(Holo.ice)
            }
            if let summary = r.summary {
                Text(summary).font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.65))
            }
            ForEach(r.checks.prefix(8), id: \.self) { check in
                Text(check).font(Holo.mono(9)).foregroundStyle(check.hasPrefix("✗") ? Holo.red : Holo.green.opacity(0.85))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    private func icon(_ s: WorkRequest.Status) -> String {
        switch s {
        case .queued: return "clock"
        case .running: return "gearshape.2"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private func color(_ s: WorkRequest.Status) -> Color {
        switch s {
        case .done: return Holo.green
        case .failed: return Holo.red
        case .running: return Holo.amber
        default: return Holo.ice.opacity(0.7)
        }
    }
}

// MARK: - Link with QR code

private struct LinkCard: View {
    let link: URL
    let korean: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let qr = Self.qrImage(link.absoluteString) {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 64, height: 64)
                    .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(korean ? "같은 Wi-Fi의 기기에서 열기" : "Open on any device on this Wi-Fi")
                    .font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.7))
                Link(link.absoluteString, destination: link).font(Holo.mono(11, .bold)).foregroundStyle(Holo.cyan)
                Button {
                    UIPasteboard.general.string = link.absoluteString
                } label: {
                    Label(korean ? "링크 복사" : "Copy link", systemImage: "doc.on.doc")
                }
                .font(Holo.mono(10)).foregroundStyle(Holo.amber).buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
    }

    static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Terminal

private struct StudioTerminal: View {
    @Bindable var studio: StudioController
    @State private var command = ""

    var body: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(studio.lines) { line in
                            Text(line.text)
                                .font(Holo.mono(10))
                                .foregroundStyle(Self.color(line.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)))
                .onChange(of: studio.lines.count) {
                    if let last = studio.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack(spacing: 6) {
                Text("$").font(Holo.mono(12, .bold)).foregroundStyle(Holo.green)
                TextField("help · ls · inspect game.gba · convert settings.ini json · pack exe", text: $command)
                    .font(Holo.mono(12))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(runCommand)
                if studio.busy { ProgressView().controlSize(.small) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        }
    }

    private func runCommand() {
        let line = command
        command = ""
        Task { await studio.run(line) }
    }

    static func color(_ kind: StudioController.TerminalLine.Kind) -> Color {
        switch kind {
        case .input: return Holo.cyan
        case .output: return Holo.ice
        case .error: return Holo.red
        case .info: return Holo.amber
        }
    }
}

// MARK: - Files

private struct StudioFiles: View {
    @Bindable var studio: StudioController
    let korean: Bool
    let openPreview: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if studio.fileList.isEmpty {
                    Text(korean ? "파일이 없습니다. 가져오거나 만들어 보세요." : "No files yet. Import one or build something.")
                        .font(Holo.mono(10)).foregroundStyle(Holo.ice.opacity(0.6))
                }
                ForEach(studio.fileList, id: \.self) { path in
                    Button { open(path) } label: {
                        HStack {
                            Image(systemName: Self.icon(path)).foregroundStyle(Holo.cyan.opacity(0.8))
                            Text(path).font(Holo.mono(11)).foregroundStyle(Holo.ice)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
    }

    private func open(_ path: String) {
        let lower = path.lowercased()
        if lower.hasSuffix(".html") || lower.hasSuffix(".htm") {
            Task { await studio.run("preview \(StudioController.quote(path))") }
            openPreview()
        } else {
            Task { await studio.run("file \(StudioController.quote(path))") }
        }
    }

    static func icon(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "globe"
        case "js", "ts", "py", "swift", "css", "json": return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "zip", "gz", "tar": return "archivebox"
        case "gba", "gb", "gbc", "nes": return "gamecontroller"
        case "exe", "app", "sh": return "shippingbox"
        default: return "doc"
        }
    }
}

// MARK: - Preview

struct StudioWebView: UIViewRepresentable {
    let url: URL
    let reload: Int

    final class Coordinator {
        var lastURL: URL?
        var lastReload = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.lastURL != url || context.coordinator.lastReload != reload else { return }
        context.coordinator.lastURL = url
        context.coordinator.lastReload = reload
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
