import AppKit
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Network
import SystemConfiguration
import UniformTypeIdentifiers

struct Pad: Codable {
    let name: String
    let icon: String
}

struct PadSettings {
    let pad: Pad
    let volume: Int
    let filename: String
}

private let starterPads = [
    Pad(name: "Air Horn", icon: "📣"), Pad(name: "Low Drop", icon: "⬇️"),
    Pad(name: "Victory", icon: "🏆"), Pad(name: "Error", icon: "⚠️"),
    Pad(name: "Level Up", icon: "⬆️"), Pad(name: "Rimshot", icon: "🥁"),
    Pad(name: "Sad Trombone", icon: "🎺"), Pad(name: "Record Scratch", icon: "💿"),
    Pad(name: "Coin", icon: "🪙"), Pad(name: "Alert", icon: "🚨"),
    Pad(name: "Explosion", icon: "💥"), Pad(name: "Game Over", icon: "🎮"),
    Pad(name: "Notification", icon: "🔔"), Pad(name: "Countdown", icon: "⏱️"),
    Pad(name: "Whoosh", icon: "💨")
]

private let presets: [(basename: String, pad: Pad)] = [
    ("bruh", Pad(name: "Bruh", icon: "😑")),
    ("vine-boom", Pad(name: "Vine Boom", icon: "💥")),
    ("huh-cat-meme", Pad(name: "Huh Cat", icon: "🐱")),
    ("rizz-sound-effect", Pad(name: "Rizz", icon: "😏")),
    ("windows-error-sound_9pcnr0c", Pad(name: "Windows Error", icon: "⚠️")),
    ("anime-ahh", Pad(name: "Anime Ahh", icon: "😲")),
    ("anime-wow", Pad(name: "Anime Wow", icon: "✨")),
    ("bone-crack", Pad(name: "Bone Crack", icon: "🦴")),
    ("cat-laugh", Pad(name: "Cat Laugh", icon: "😹")),
    ("tuco-get-out", Pad(name: "Tuco Get Out", icon: "🚪")),
    ("aznhuh", Pad(name: "Azn Huh", icon: "❓")),
    ("faaah", Pad(name: "Faaah", icon: "📣")),
    ("end credit", Pad(name: "End Credit", icon: "🎬")),
    ("violin-sad-violin", Pad(name: "Sad Violin", icon: "🎻")),
    ("sponge-bob-sad", Pad(name: "Sad SpongeBob", icon: "🧽"))
] + starterPads.map { ($0.name.lowercased(), $0) }

private let presetIndices = Dictionary(uniqueKeysWithValues: presets.enumerated().map {
    ($0.element.basename, $0.offset)
})

class Board {
    let folder: URL
    let resources = Bundle.main.resourceURL!
    let defaults: UserDefaults
    let soundsFolder: URL
    let defaultSounds: [URL]
    var players: [Int: AVAudioPlayer] = [:]
    private var previewPlayer: AVAudioPlayer?

    init(folder: URL, defaults: UserDefaults = .standard,
         soundsFolder: URL = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("sounds", isDirectory: true)) {
        self.folder = folder
        self.defaults = defaults
        self.soundsFolder = soundsFolder
        let bundledFolder = resources.appendingPathComponent("sounds", isDirectory: true)
        let bundled = Self.audioFiles(in: bundledFolder)
        let external = Self.audioFiles(in: soundsFolder)
        let externalNames = Set(external.map { $0.lastPathComponent.lowercased() })
        let missing = bundled.filter { !externalNames.contains($0.lastPathComponent.lowercased()) }
        defaultSounds = external + missing.prefix(max(0, bundled.count - external.count))
    }

    private static func audioFiles(in folder: URL) -> [URL] {
        let formats: Set<String> = ["mp3", "wav", "m4a", "aac", "aif", "aiff", "caf", "flac"]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        return files.filter { file in
            formats.contains(file.pathExtension.lowercased())
                && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted {
            let left = presetIndices[$0.deletingPathExtension().lastPathComponent.lowercased()] ?? presets.count
            let right = presetIndices[$1.deletingPathExtension().lastPathComponent.lowercased()] ?? presets.count
            if left != right { return left < right }
            let order = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return order == .orderedSame ? $0.lastPathComponent < $1.lastPathComponent : order == .orderedAscending
        }
    }

    private func defaultPad(_ index: Int) -> Pad {
        let basename = defaultSounds[index].deletingPathExtension().lastPathComponent
        if let preset = presetIndices[basename.lowercased()] { return presets[preset].pad }
        return Pad(name: basename.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression), icon: "🎵")
    }

    func soundFile(_ index: Int) -> URL {
        let custom = importedFile(index)
        if FileManager.default.fileExists(atPath: custom.path) { return custom }
        return defaultSounds[index]
    }

    func importedFile(_ index: Int) -> URL {
        folder.appendingPathComponent("pad-\(index).audio")
    }

    func pads() -> [Pad] {
        defaultSounds.indices.map { settings($0).pad }
    }

    func settings(_ index: Int) -> PadSettings {
        let pad = defaultPad(index)
        let saved = defaults.dictionary(forKey: "pad-settings-\(index)") ?? [:]
        let legacyName = defaults.string(forKey: "pad-\(index)")
        let file = soundFile(index)
        let name = saved["name"] as? String ?? legacyName ?? pad.name
        let icon = saved["icon"] as? String ?? pad.icon
        let volume = min(100, max(0, saved["volume"] as? Int ?? 100))
        let filename = file == importedFile(index)
            ? saved["filename"] as? String ?? legacyName ?? "Imported sound"
            : file.lastPathComponent
        return PadSettings(pad: Pad(name: name, icon: icon), volume: volume, filename: filename)
    }

    func makePlayer(_ file: URL, volume: Int) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: Data(contentsOf: file))
        player.volume = Float(volume) / 100
        return player
    }

    func play(_ index: Int) -> Bool {
        if players[index] == nil {
            players[index] = try? makePlayer(soundFile(index), volume: settings(index).volume)
        }
        guard let player = players[index] else { return false }
        player.currentTime = 0
        return player.play()
    }

    func stop() {
        stopPreview()
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }

    func preview(_ file: URL, volume: Int) throws -> Bool {
        stopPreview()
        let player = try makePlayer(file, volume: volume)
        previewPlayer = player
        return player.play()
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    func save(_ pad: Pad, volume: Int, source: URL?, to index: Int) throws {
        let name = pad.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = pad.icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, icon.count <= 4, (0...100).contains(volume) else {
            throw NSError(domain: "Soundboard", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Use a button name of 1–40 characters and an icon of up to four characters."
            ])
        }
        let filename = source?.lastPathComponent ?? settings(index).filename
        if let source {
            let data = try Data(contentsOf: source)
            _ = try AVAudioPlayer(data: data)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: importedFile(index), options: .atomic)
        }
        defaults.set(["name": name, "icon": icon, "volume": volume, "filename": filename],
                     forKey: "pad-settings-\(index)")
        players.removeValue(forKey: index)?.stop()
    }

    func restore(_ index: Int) throws {
        let file = importedFile(index)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        defaults.removeObject(forKey: "pad-settings-\(index)")
        defaults.removeObject(forKey: "pad-\(index)")
        players.removeValue(forKey: index)?.stop()
    }
}

class Server {
    let listener: NWListener
    let board: Board
    let obs: OBSControl
    let token: String
    let page: Data
    let icon: Data
    var onChange: (() -> Void)?

    init(board: Board, obs: OBSControl, token: String, port: NWEndpoint.Port = 8745) throws {
        self.board = board
        self.obs = obs
        self.token = token
        page = try Data(contentsOf: board.resources.appendingPathComponent("index.html"))
        icon = try Data(contentsOf: board.resources.appendingPathComponent("touch.png"))
        listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak connection] in
                connection?.cancel()
            }
            self?.receive(connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [weak self] _ in self?.onChange?() }
        listener.start(queue: .main)
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, end, error in
            guard let self, error == nil else { connection.cancel(); return }
            var request = buffer
            request.append(data ?? Data())
            guard request.count <= 8192 else {
                self.send(connection, status: "431 Request Header Fields Too Large")
                return
            }
            if let headerEnd = request.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: request[..<headerEnd.lowerBound], as: UTF8.self)
                self.route(header, connection: connection)
            } else if end {
                connection.cancel()
            } else {
                self.receive(connection, buffer: request)
            }
        }
    }

    private func route(_ header: String, connection: NWConnection) {
        let lines = header.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count == 3 else { send(connection, status: "400 Bad Request"); return }
        let method = parts[0]
        let path = parts[1]
        let root = "/\(token)/"
        guard path.hasPrefix(root) else { send(connection, status: "404 Not Found"); return }
        let endpoint = path.dropFirst(root.count)
        let remoteHeader = lines.dropFirst().contains { line in
            let field = line.split(separator: ":", maxSplits: 1)
            return field.count == 2 && field[0].lowercased() == "x-soundboard"
                && field[1].trimmingCharacters(in: .whitespaces) == "play"
        }
        if let command = OBSCommand(path: endpoint, isGet: method == "GET"),
           method == "GET" || (method == "POST" && remoteHeader) {
            Task { @MainActor in
                do {
                    if let state = try await self.obs.run(command) {
                        self.send(connection, type: "application/json", body: try JSONEncoder().encode(state))
                    } else {
                        self.send(connection, status: "204 No Content")
                    }
                } catch {
                    let data = (try? JSONEncoder().encode(["error": error.localizedDescription])) ?? Data()
                    self.send(connection, status: "503 Service Unavailable", type: "application/json", body: data)
                }
            }
            return
        }
        if method == "GET" {
            switch endpoint {
            case "": send(connection, type: "text/html; charset=utf-8", body: page)
            case "touch.png": send(connection, type: "image/png", body: icon)
            case "pads":
                let data = (try? JSONEncoder().encode(board.pads())) ?? Data("[]".utf8)
                send(connection, type: "application/json", body: data)
            default: send(connection, status: "404 Not Found")
            }
            return
        }
        guard method == "POST", remoteHeader else {
            send(connection, status: "403 Forbidden")
            return
        }
        if endpoint == "stop" {
            board.stop()
            send(connection, status: "204 No Content")
        } else if endpoint.hasPrefix("play/"), let index = Int(endpoint.dropFirst(5)), board.defaultSounds.indices.contains(index) {
            send(connection, status: board.play(index) ? "204 No Content" : "500 Internal Server Error")
        } else {
            send(connection, status: "404 Not Found")
        }
    }

    private func send(_ connection: NWConnection, status: String = "200 OK",
                      type: String = "text/plain", body: Data = Data()) {
        let headers = [
            "HTTP/1.1 \(status)", "Content-Type: \(type)", "Content-Length: \(body.count)",
            "Connection: close", "Cache-Control: no-store", "Referrer-Policy: no-referrer",
            "X-Content-Type-Options: nosniff",
            "Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self'; frame-ancestors 'none'"
        ]
        var response = Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        response.append(body)
        connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }
}

final class PadEditor: NSObject {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 326),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let name = NSTextField()
    let icon = NSTextField()
    let volume = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    let percent = NSTextField(labelWithString: "")
    let filename = NSTextField(labelWithString: "")
    let board: Board
    let index: Int
    var source: URL?

    init(board: Board, index: Int) {
        self.board = board
        self.index = index
        super.init()
        window.title = "Customize Button \(index + 1)"
        window.isReleasedWhenClosed = false
        let settings = board.settings(index)
        name.stringValue = settings.pad.name
        icon.stringValue = settings.pad.icon
        icon.placeholderString = "Optional emoji"
        filename.stringValue = settings.filename
        filename.lineBreakMode = .byTruncatingMiddle
        volume.integerValue = settings.volume
        volume.isContinuous = true
        volume.target = self
        volume.action = #selector(showVolume)
        percent.alignment = .right
        showVolume()

        let level = NSStackView(views: [volume, percent])
        let file = NSStackView(views: [filename, button("Choose File…", #selector(chooseFile))])
        let saveButton = button("Save", #selector(save))
        saveButton.keyEquivalent = "\r"
        let cancelButton = button("Cancel", #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        let actions = NSStackView(views: [button("Preview", #selector(preview)), cancelButton, saveButton])
        let form = NSStackView(views: [
            NSTextField(labelWithString: "Sound file"), file,
            NSTextField(labelWithString: "Button name"), name,
            NSTextField(labelWithString: "Button icon"),
            NSStackView(views: [icon, button("Emoji…", #selector(chooseEmoji))]),
            NSTextField(labelWithString: "Playback volume"), level, actions
        ])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.setCustomSpacing(15, after: level)
        form.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            form.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            file.widthAnchor.constraint(equalTo: form.widthAnchor),
            name.widthAnchor.constraint(equalTo: form.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 130),
            level.widthAnchor.constraint(equalTo: form.widthAnchor),
            percent.widthAnchor.constraint(equalToConstant: 50)
        ])
        window.initialFirstResponder = name
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    @objc private func showVolume() {
        percent.stringValue = "\(volume.integerValue)%"
    }

    @objc private func chooseEmoji() {
        window.makeFirstResponder(icon)
        NSApp.orderFrontCharacterPalette(self)
    }

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.directoryURL = (source ?? board.soundFile(index)).deletingLastPathComponent()
        if source == nil && FileManager.default.fileExists(atPath: board.soundsFolder.path) {
            panel.directoryURL = board.soundsFolder
        }
        guard panel.runModal() == .OK, let file = panel.url else { return }
        board.stopPreview()
        source = file
        filename.stringValue = file.lastPathComponent
    }

    @objc private func preview() {
        do {
            if try !board.preview(source ?? board.soundFile(index), volume: volume.integerValue) {
                showError("The Mac could not play this sound.")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func save() {
        window.makeFirstResponder(nil)
        do {
            try board.save(Pad(name: name.stringValue, icon: icon.stringValue),
                           volume: volume.integerValue, source: source, to: index)
            close(.OK)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func cancel() { close(.cancel) }

    private func close(_ response: NSApplication.ModalResponse) {
        board.stopPreview()
        window.sheetParent?.endSheet(window, returnCode: response)
    }

    private func showError(_ description: String) {
        let alert = NSAlert()
        alert.messageText = description
        alert.runModal()
    }
}

final class SoundboardApp: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 410),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    let address = NSTextField(labelWithString: "")
    let qrView = NSImageView()
    let slots = NSPopUpButton()
    let board = Board(folder: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PatsHelloworld Soundboard", isDirectory: true))
    var server: Server?
    var link: URL?
    var editor: PadEditor?
    lazy var obs = OBSControl(folder: board.folder)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenuItem()
        let appActions = NSMenu()
        appActions.addItem(withTitle: "Quit PatsHelloworld Soundboard", action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q")
        appMenu.submenu = appActions
        menu.addItem(appMenu)
        let editMenu = NSMenuItem()
        let editActions = NSMenu(title: "Edit")
        editActions.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editActions.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editActions.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editActions.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.submenu = editActions
        menu.addItem(editMenu)
        NSApp.mainMenu = menu
        let defaults = UserDefaults.standard
        let token = defaults.string(forKey: "PairingToken") ?? UUID().uuidString.lowercased()
        defaults.set(token, forKey: "PairingToken")
        window.title = "PatsHelloworld Soundboard"
        address.isSelectable = true
        address.alignment = .center
        address.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        refreshSlots()

        let stack = NSStackView(views: [
            NSTextField(labelWithString: "Scan with your iPhone on the same Wi-Fi"),
            qrView, address, row("Copy Link", #selector(copyLink), "Open on Mac", #selector(openLink)),
            slots, row("Customize…", #selector(customize), "Restore Default…", #selector(restoreSound)),
            NSButton(title: "OBS Settings…", target: self, action: #selector(configureOBS))
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            qrView.widthAnchor.constraint(equalToConstant: 195),
            qrView.heightAnchor.constraint(equalTo: qrView.widthAnchor),
            slots.widthAnchor.constraint(equalToConstant: 265),
            address.widthAnchor.constraint(lessThanOrEqualToConstant: 484)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        do {
            server = try Server(board: board, obs: obs, token: token)
            server?.onChange = { [weak self] in self?.updateLink() }
            updateLink()
        } catch {
            address.stringValue = error.localizedDescription
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func row(_ first: String, _ firstAction: Selector, _ second: String, _ secondAction: Selector) -> NSStackView {
        NSStackView(views: [
            NSButton(title: first, target: self, action: firstAction),
            NSButton(title: second, target: self, action: secondAction)
        ])
    }

    private func refreshSlots() {
        let index = max(0, slots.indexOfSelectedItem)
        slots.removeAllItems()
        slots.addItems(withTitles: board.pads().enumerated().map { "\($0.offset + 1). \($0.element.name)" })
        slots.selectItem(at: index)
    }

    private func updateLink() {
        guard let server else { return }
        switch server.listener.state {
        case .ready:
            let host = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
                ?? ProcessInfo.processInfo.hostName
            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = Int(server.listener.port?.rawValue ?? 8745)
            components.path = "/\(server.token)/"
            link = components.url
            guard let link else { return }
            address.stringValue = link.absoluteString
            let code = CIFilter.qrCodeGenerator()
            code.message = Data(link.absoluteString.utf8)
            if let output = code.outputImage {
                // Composite over white to give the code a quiet zone on dark appearances.
                let white = CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -4, dy: -4))
                let framed = output.composited(over: white).transformed(by: CGAffineTransform(scaleX: 5, y: 5))
                if let image = CIContext().createCGImage(framed, from: framed.extent) {
                    qrView.image = NSImage(cgImage: image, size: .zero)
                }
            }
        case .failed(let error), .waiting(let error):
            address.stringValue = "Soundboard server: \(error.localizedDescription)"
        default:
            address.stringValue = "Starting soundboard…"
        }
    }

    @objc private func copyLink() {
        guard let link else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
    }

    @objc private func openLink() {
        guard var components = link.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return }
        components.host = "127.0.0.1"
        if let local = components.url { NSWorkspace.shared.open(local) }
    }

    @objc private func configureOBS() {
        let settings = obs.settings ?? .defaults
        let port = NSTextField(string: String(settings.port))
        let password = NSSecureTextField(string: settings.password)
        let mic = NSTextField(string: settings.microphone)
        mic.placeholderString = "Auto (first enabled Mic/Aux)"
        let fields = NSGridView(views: [
            [NSTextField(labelWithString: "Server port"), port],
            [NSTextField(labelWithString: "Password"), password],
            [NSTextField(labelWithString: "Mic input"), mic]
        ])
        fields.rowSpacing = 10
        NSLayoutConstraint.activate([port.widthAnchor.constraint(equalToConstant: 230),
                                      password.widthAnchor.constraint(equalTo: port.widthAnchor),
                                      mic.widthAnchor.constraint(equalTo: port.widthAnchor)])
        fields.frame.size = fields.fittingSize
        let alert = NSAlert()
        alert.messageText = "Connect to OBS on this Mac"
        alert.informativeText = "In OBS, open Tools → WebSocket Server Settings. Enable the server and copy its port and password. Enter the exact Audio Mixer name if you use a custom mic source."
        alert.accessoryView = fields
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if obs.settings != nil { alert.addButton(withTitle: "Disconnect") }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            do {
                if response == .alertFirstButtonReturn {
                    guard let value = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces)), value > 0 else {
                        throw OBSError.rejected("Enter a port from 1 to 65535.")
                    }
                    try self.obs.configure(OBSSettings(port: value, password: password.stringValue,
                        microphone: mic.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else if response == .alertThirdButtonReturn {
                    try self.obs.configure(nil)
                }
            } catch {
                NSAlert(error: error).beginSheetModal(for: self.window)
            }
        }
    }

    @objc private func customize() {
        let editor = PadEditor(board: board, index: slots.indexOfSelectedItem)
        self.editor = editor
        window.beginSheet(editor.window) { [weak self] response in
            if response == .OK { self?.refreshSlots() }
            self?.editor = nil
        }
    }

    @objc private func restoreSound() {
        let index = slots.indexOfSelectedItem
        let alert = NSAlert()
        alert.messageText = "Restore button \(index + 1) to its default?"
        alert.informativeText = "This resets the sound, name, icon, and volume for this button."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.board.restore(index)
                self.refreshSlots()
            } catch {
                NSAlert(error: error).beginSheetModal(for: self.window)
            }
        }
    }
}

@main
struct SoundboardMain {
    static func main() throws {
        if let testIndex = CommandLine.arguments.firstIndex(of: "--check-audio") {
            let suite = "SoundboardTest.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            let suppliedPath = CommandLine.arguments.dropFirst(testIndex + 1).first
            let sounds = suppliedPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? folder.appendingPathComponent("sounds", isDirectory: true)
            let board = Board(folder: folder, defaults: defaults, soundsFolder: sounds)
            do {
                defer {
                    try? FileManager.default.removeItem(at: folder)
                    defaults.removePersistentDomain(forName: suite)
                }
                let initialPads = board.pads()
                let initialFile = board.soundFile(0)
                for index in board.defaultSounds.indices {
                    let player = try AVAudioPlayer(data: Data(contentsOf: board.soundFile(index)))
                    precondition(player.duration > 0)
                }
                if suppliedPath == nil {
                    precondition(initialPads.map(\.name) == starterPads.map(\.name))
                }
                let sample = board.defaultSounds[1]
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: sample, to: board.importedFile(0))
                defaults.set("Legacy clip", forKey: "pad-0")
                precondition(board.pads()[0].name == "Legacy clip")
                precondition(board.settings(0).volume == 100)
                precondition(board.soundFile(0) == board.importedFile(0))

                let custom = Pad(name: "  Custom reaction  ", icon: "🎙️")
                try board.save(custom, volume: 32, source: nil, to: 0)
                precondition(board.settings(0).filename == "Legacy clip")
                precondition(board.soundFile(0) == board.importedFile(0))
                let replacement = board.defaultSounds[2]
                try board.save(custom, volume: 32, source: replacement, to: 0)
                let reopened = Board(folder: folder, defaults: defaults, soundsFolder: sounds)
                let saved = reopened.settings(0)
                precondition(saved.pad.name == "Custom reaction" && saved.pad.icon == "🎙️")
                precondition(saved.volume == 32 && saved.filename == replacement.lastPathComponent)
                let bytes = try Data(contentsOf: board.importedFile(0))
                let expected = try Data(contentsOf: replacement)
                precondition(bytes == expected)
                let player = try reopened.makePlayer(reopened.soundFile(0), volume: saved.volume)
                precondition(abs(player.volume - 0.32) < 0.001)
                do {
                    try board.save(Pad(name: "Should not persist", icon: ""), volume: 0,
                                   source: board.resources.appendingPathComponent("index.html"), to: 0)
                    preconditionFailure("Invalid audio was accepted")
                } catch {
                    let afterFailure = try Data(contentsOf: board.importedFile(0))
                    precondition(afterFailure == expected && board.settings(0).volume == 32)
                }

                try board.restore(0)
                precondition(board.pads()[0].name == initialPads[0].name)
                precondition(board.soundFile(0) == initialFile && board.settings(0).volume == 100)
                print("Decoded \(board.defaultSounds.count) playable sounds.")
                print("Verified legacy imports, saved name and icon, playback volume, replacement, invalid-file handling, and restore.")
            }
        } else {
            let app = NSApplication.shared
            let delegate = SoundboardApp()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        }
    }
}
