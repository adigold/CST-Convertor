// CST to Patch
// Converts Logic Pro channel strip settings (.cst) into Logic 13 patches (.patch).
// Created and powered by AGsoundtrax LLC.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - App

@main
struct CSTtoPatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {
                Link("AGsoundtrax Website", destination: Brand.website)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Brand {
    static let company = "AGsoundtrax LLC"
    static let website = URL(string: "https://agsoundtrax.com")!
    static let accent = Color(red: 1.0, green: 0.55, blue: 0.16)
    static let purple = Color(red: 0.42, green: 0.30, blue: 0.85)
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Model

enum Phase: Equatable { case scanning, ready, converting, finished, cancelled }

struct ScanSummary {
    var sourceExists = true
    var presets = 0
    var patches = 0
    var folders = 0
    var existing = 0
    var total: Int { presets + patches }
    var toConvert: Int { max(total - existing, 0) }
}

struct WorkItem {
    let url: URL
    let rel: String
    let isPatch: Bool
}

struct LogLine: Identifiable {
    enum Kind { case converted, copied, skipped, error }
    let id: Int
    let kind: Kind
    let text: String
}

final class CancelToken {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

final class Converter: ObservableObject {
    @Published var source: URL {
        didSet { UserDefaults.standard.set(source.path, forKey: "source"); scan() }
    }
    @Published var dest: URL {
        didSet { UserDefaults.standard.set(dest.path, forKey: "dest"); scan() }
    }
    @Published var copyExistingPatches: Bool {
        didSet { UserDefaults.standard.set(copyExistingPatches, forKey: "copyPatches"); scan() }
    }
    @Published var openWhenDone: Bool {
        didSet { UserDefaults.standard.set(openWhenDone, forKey: "openWhenDone") }
    }

    @Published var phase: Phase = .scanning
    @Published var summary = ScanSummary()
    @Published var total = 0
    @Published var done = 0
    @Published var converted = 0
    @Published var skipped = 0
    @Published var errors = 0
    @Published var current = ""
    @Published var log: [LogLine] = []

    private var token = CancelToken()
    private var scanID = 0

    init() {
        let d = UserDefaults.standard
        let music = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Audio Music Apps")
        source = URL(fileURLWithPath: d.string(forKey: "source")
            ?? music.appendingPathComponent("Channel Strip Settings/Instrument").path)
        dest = URL(fileURLWithPath: d.string(forKey: "dest")
            ?? music.appendingPathComponent("Patches/Instrument").path)
        copyExistingPatches = d.object(forKey: "copyPatches") as? Bool ?? true
        openWhenDone = d.object(forKey: "openWhenDone") as? Bool ?? true
        scan()
    }

    // Counts what will be converted, without writing anything.
    func scan() {
        guard phase != .converting else { return }
        scanID += 1
        let id = scanID
        let src = Self.norm(source), dst = Self.norm(dest), withPatches = copyExistingPatches
        phase = .scanning
        DispatchQueue.global(qos: .userInitiated).async {
            var s = ScanSummary()
            s.sourceExists = FileManager.default.fileExists(atPath: src.path)
            var folders = Set<String>()
            for item in Self.collect(src: src, dst: dst, includePatches: withPatches) {
                if item.isPatch { s.patches += 1 } else { s.presets += 1 }
                let target = Self.target(for: item, dst: dst)
                if FileManager.default.fileExists(atPath: target.path) { s.existing += 1 }
                folders.insert(target.deletingLastPathComponent().path)
            }
            s.folders = folders.count
            DispatchQueue.main.async {
                guard id == self.scanID else { return }
                self.summary = s
                self.phase = .ready
            }
        }
    }

    func start() {
        let src = Self.norm(source), dst = Self.norm(dest), withPatches = copyExistingPatches
        token = CancelToken()
        let token = self.token
        phase = .converting
        total = 0; done = 0; converted = 0; skipped = 0; errors = 0; current = ""; log = []

        DispatchQueue.global(qos: .userInitiated).async {
            let items = Self.collect(src: src, dst: dst, includePatches: withPatches)
            DispatchQueue.main.async { self.total = items.count }
            for (i, item) in items.enumerated() {
                if token.isCancelled { break }
                let (kind, text) = Self.process(item, dst: dst)
                DispatchQueue.main.async {
                    self.done += 1
                    self.current = item.rel
                    switch kind {
                    case .converted, .copied: self.converted += 1
                    case .skipped: self.skipped += 1
                    case .error: self.errors += 1
                    }
                    self.log.append(LogLine(id: i, kind: kind, text: text))
                }
            }
            DispatchQueue.main.async {
                self.phase = token.isCancelled ? .cancelled : .finished
                NSSound(named: "Glass")?.play()
                if self.phase == .finished && self.openWhenDone && self.converted > 0 {
                    NSWorkspace.shared.open(dst)
                }
            }
        }
    }

    func cancel() { token.cancel() }

    func reset() { scan() }

    var logText: String {
        log.map { line -> String in
            switch line.kind {
            case .converted: return "Converted  \(line.text)"
            case .copied: return "Copied     \(line.text)"
            case .skipped: return "Skipped    \(line.text)"
            case .error: return "Error      \(line.text)"
            }
        }.joined(separator: "\n")
    }

    // MARK: File work

    static func norm(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    // Finds .cst files (and existing .patch bundles). Skips Logic projects and the destination folder.
    static func collect(src: URL, dst: URL, includePatches: Bool) -> [WorkItem] {
        var result: [WorkItem] = []
        let skipDest = dst.path != src.path
        guard let en = FileManager.default.enumerator(
            at: src, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in en {
            let path = url.resolvingSymlinksInPath().path
            let ext = url.pathExtension.lowercased()
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if skipDest && (path == dst.path || path.hasPrefix(dst.path + "/")) {
                    en.skipDescendants()
                } else if ext == "logicx" {
                    en.skipDescendants()
                } else if ext == "patch" {
                    en.skipDescendants()
                    if includePatches { result.append(item(url, path, src, true)) }
                }
            } else if ext == "cst" {
                result.append(item(url, path, src, false))
            }
        }
        return result.sorted { $0.rel.localizedStandardCompare($1.rel) == .orderedAscending }
    }

    private static func item(_ url: URL, _ path: String, _ src: URL, _ isPatch: Bool) -> WorkItem {
        WorkItem(url: url, rel: String(path.dropFirst(src.path.count + 1)), isPatch: isPatch)
    }

    static func patchName(for item: WorkItem) -> String {
        var name = item.url.deletingPathExtension().lastPathComponent
        while name.last?.isWhitespace == true { name.removeLast() }
        return name
    }

    static func relDir(_ item: WorkItem) -> String { (item.rel as NSString).deletingLastPathComponent }

    static func target(for item: WorkItem, dst: URL) -> URL {
        let dir = relDir(item)
        let outDir = dir.isEmpty ? dst : dst.appendingPathComponent(dir)
        return item.isPatch
            ? outDir.appendingPathComponent(item.url.lastPathComponent)
            : outDir.appendingPathComponent(patchName(for: item) + ".patch")
    }

    static func process(_ item: WorkItem, dst: URL) -> (LogLine.Kind, String) {
        let fm = FileManager.default
        let out = Self.target(for: item, dst: dst)
        if fm.fileExists(atPath: out.path) { return (.skipped, "\(item.rel) (already exists)") }
        do {
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            if item.isPatch {
                try fm.copyItem(at: item.url, to: out)
                return (.copied, item.rel)
            }
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            try fm.copyItem(at: item.url, to: out.appendingPathComponent("#Root.cst"))
            let dir = relDir(item)
            let category = dir.isEmpty ? "" : (dir as NSString).lastPathComponent
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist(name: patchName(for: item), category: category),
                format: .binary, options: 0)
            try data.write(to: out.appendingPathComponent("data.plist"))
            return (.converted, item.rel)
        } catch {
            return (.error, "\(item.rel): \(error.localizedDescription)")
        }
    }

    // Matches the data.plist Logic writes inside a .patch bundle.
    static func plist(name: String, category: String) -> [String: Any] {
        func send(_ mode: Int, _ index: Int) -> [String: Any] {
            ["sendIsMuted": false, "sendMode": mode, "sendOutputIndex": index, "sendVolume": 0.0]
        }
        var sends: [[String: Any]] = [send(1, 0), send(1, 1)]
        for i in 2...7 { sends.append(send(2, i)) }
        sends.append([:])
        let channel: [String: Any] = [
            "Channel_chaStrCategory": category,
            "Channel_inputIndex_1": -1,
            "Channel_inputIsBus": false,
            "Channel_instID": 88,
            "Channel_isMuted": false,
            "Channel_isSolo": false,
            "Channel_name": name,
            "Channel_outputIndex": 0,
            "Channel_outputIsBus": false,
            "Channel_outputIsStereo": true,
            "Channel_receiveChannel": -1,
            "Channel_sends": sends,
            "Channel_seqColorIndex": 21,
            "Channel_userDidModifySmartControls": true,
            "Filename": "#Root.cst",
            "Root": true,
            "Track_icon": 4505,
            "UUID": UUID().uuidString,
        ]
        return ["VersionPatches": 40014, "channels": [channel]]
    }

    static var logicURL: URL? {
        ["com.apple.logic10", "com.apple.logic"]
            .lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var c = Converter()
    @State private var showLog = false

    var busy: Bool { c.phase == .converting }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            VStack(spacing: 10) {
                FolderCard(step: 1, title: "Your .cst presets",
                           hint: "Drop a folder here or click Change",
                           symbol: "slider.vertical.3", tint: Brand.accent,
                           url: c.source, disabled: busy) { c.source = $0 }

                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)

                FolderCard(step: 2, title: "Save Logic 13 patches to",
                           hint: "Drop a folder here or click Change",
                           symbol: "shippingbox.fill", tint: Brand.purple,
                           url: c.dest, disabled: busy) { c.dest = $0 }

                HStack(spacing: 20) {
                    Toggle("Also copy existing .patch files", isOn: $c.copyExistingPatches)
                    Toggle("Open folder when done", isOn: $c.openWhenDone)
                    Spacer()
                }
                .toggleStyle(.checkbox)
                .font(.callout)
                .disabled(busy)
                .padding(.top, 6)
                .padding(.horizontal, 4)

                ActionPanel(c: c)
                    .padding(.top, 8)

                if !c.log.isEmpty {
                    LogSection(c: c, expanded: $showLog)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)

            FooterView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: c.phase)
        .animation(.easeInOut(duration: 0.2), value: showLog)
    }
}

struct HeaderView: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("CST to Patch")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Turn your Logic channel strip settings into Logic 13 patches. Your original files stay untouched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 38)
        .padding(.bottom, 22)
        .background(
            LinearGradient(colors: [Brand.purple.opacity(0.16), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

struct FolderCard: View {
    let step: Int
    let title: String
    let hint: String
    let symbol: String
    let tint: Color
    let url: URL
    let disabled: Bool
    let onPick: (URL) -> Void

    @State private var dropTargeted = false
    @State private var hovering = false

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("STEP \(step)  ·  \(title.uppercased())")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(dropTargeted ? hint : displayPath)
                    .font(.caption)
                    .foregroundStyle(dropTargeted ? AnyShapeStyle(tint) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path)
            }

            Spacer(minLength: 8)

            Button("Change…") {
                if let picked = Self.choose(start: url) { onPick(picked) }
            }
            .controlSize(.regular)
            .disabled(disabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.10 : 0.05), radius: hovering ? 6 : 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(dropTargeted ? tint : Color.primary.opacity(0.08),
                              style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: dropTargeted ? [6, 4] : []))
        )
        .onHover { hovering = $0 }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard !disabled, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { dropped, _ in
                guard let dropped,
                      (try? dropped.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { return }
                DispatchQueue.main.async { onPick(dropped) }
            }
            return true
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .disabled(!exists)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(url.lastPathComponent)")
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    static func choose(start: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct ActionPanel: View {
    @ObservedObject var c: Converter

    var body: some View {
        VStack(spacing: 14) {
            switch c.phase {
            case .scanning:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning your presets…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 92)

            case .ready:
                readyView

            case .converting:
                convertingView

            case .finished, .cancelled:
                finishedView
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder var readyView: some View {
        let s = c.summary
        if !s.sourceExists {
            Label("The presets folder was not found. Choose another folder.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else if s.total == 0 {
            Label("No .cst presets found in this folder.", systemImage: "tray")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 56)
        } else {
            HStack(spacing: 10) {
                StatChip(value: s.presets, label: "presets", color: Brand.accent)
                if c.copyExistingPatches && s.patches > 0 {
                    StatChip(value: s.patches, label: "patches", color: Brand.purple)
                }
                StatChip(value: s.folders, label: "folders", color: .blue)
                if s.existing > 0 {
                    StatChip(value: s.existing, label: "already done", color: .gray)
                }
            }
            Button {
                c.start()
            } label: {
                Label(s.toConvert == 0 ? "Everything is already converted"
                      : "Convert \(s.toConvert) \(s.toConvert == 1 ? "Preset" : "Presets")",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(s.toConvert == 0)
        }
    }

    var convertingView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Converting…").font(.headline)
                Spacer()
                Text("\(c.done) of \(c.total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(c.done), total: Double(max(c.total, 1)))
                .tint(Brand.accent)
            HStack {
                Text(c.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel", role: .cancel) { c.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    var finishedView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: c.phase == .cancelled ? "stop.circle.fill"
                      : (c.errors > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"))
                    .font(.system(size: 30))
                    .foregroundStyle(c.phase == .cancelled ? Color.gray : (c.errors > 0 ? Color.orange : Color.green))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.phase == .cancelled ? "Stopped"
                         : "\(c.converted) \(c.converted == 1 ? "patch is" : "patches are") ready")
                        .font(.title3.bold())
                    Text(c.phase == .cancelled ? "Files converted so far are kept."
                         : "Open Logic 13 and find them in the Library under Patches.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                StatChip(value: c.converted, label: "converted", color: .green)
                StatChip(value: c.skipped, label: "skipped", color: .gray)
                if c.errors > 0 { StatChip(value: c.errors, label: "errors", color: .red) }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    NSWorkspace.shared.open(c.dest)
                } label: {
                    Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .keyboardShortcut(.defaultAction)

                if let logic = Converter.logicURL {
                    Button {
                        NSWorkspace.shared.openApplication(at: logic, configuration: .init())
                    } label: {
                        Label("Open Logic Pro", systemImage: "music.note").frame(maxWidth: .infinity)
                    }
                }

                Button {
                    c.reset()
                } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
        }
    }
}

struct StatChip: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(value)").font(.callout.weight(.semibold).monospacedDigit())
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct LogSection: View {
    @ObservedObject var c: Converter
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    expanded.toggle()
                } label: {
                    Label(expanded ? "Hide details" : "Show details",
                          systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                if expanded {
                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(c.logText, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            if expanded {
                List(c.log) { line in
                    HStack(spacing: 8) {
                        Image(systemName: icon(line.kind))
                            .foregroundStyle(color(line.kind))
                            .frame(width: 14)
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .listStyle(.plain)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }

    func icon(_ k: LogLine.Kind) -> String {
        switch k {
        case .converted: return "checkmark.circle.fill"
        case .copied: return "doc.on.doc.fill"
        case .skipped: return "arrow.uturn.right.circle"
        case .error: return "xmark.octagon.fill"
        }
    }

    func color(_ k: LogLine.Kind) -> Color {
        switch k {
        case .converted: return .green
        case .copied: return Brand.purple
        case .skipped: return .gray
        case .error: return .red
        }
    }
}

struct FooterView: View {
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundStyle(Brand.accent)
                Text("Created and powered by")
                    .foregroundStyle(.secondary)
                Link(Brand.company, destination: Brand.website)
                    .fontWeight(.semibold)
                Spacer()
                Text("Version \(Brand.version)")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.03))
    }
}
