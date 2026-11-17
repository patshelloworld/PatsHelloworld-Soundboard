import CryptoKit
import Foundation

struct OBSSettings: Codable {
    let port: UInt16
    let password: String
    let microphone: String

    static let defaults = OBSSettings(port: 4455, password: "", microphone: "")
}

struct OBSState: Encodable {
    let scenes: [String]
    let currentScene: String?
    let microphone: String?
    let muted: Bool?
    let recording: Bool?
}

enum OBSCommand {
    case status
    case scene(String)
    case mute(Bool)
    case record(Bool)

    init?(path: Substring, isGet: Bool) {
        if isGet {
            guard path == "obs" else { return nil }
            self = .status
        } else if path.hasPrefix("obs/scene/name="),
                  let name = path.dropFirst("obs/scene/name=".count).removingPercentEncoding, !name.isEmpty {
            self = .scene(name)
        } else {
            switch path {
            case "obs/mic/mute": self = .mute(true)
            case "obs/mic/unmute": self = .mute(false)
            case "obs/record/start": self = .record(true)
            case "obs/record/stop": self = .record(false)
            default: return nil
            }
        }
    }
}

enum OBSError: LocalizedError {
    case disabled, disconnected, authentication, invalidResponse, missingMic, rejected(String)

    var errorDescription: String? {
        switch self {
        case .disabled: return "Open OBS Settings in the Mac soundboard to set up the connection."
        case .disconnected: return "Cannot reach OBS. Open OBS and check its WebSocket server and port."
        case .authentication: return "OBS rejected the password. Check OBS Settings on the Mac."
        case .invalidResponse: return "OBS returned an unexpected response. Check that it supports WebSocket v5."
        case .missingMic: return "No mic found. Enter its Audio Mixer name in OBS Settings on the Mac."
        case .rejected(let message): return message
        }
    }
}

struct OBSSession {
    let sendText: (String) async throws -> Void
    let receiveText: () async throws -> String

    func identify(password: String) async throws {
        let hello = try await receive(op: 0)
        guard let version = hello["rpcVersion"] as? Int, version >= 1 else {
            throw OBSError.invalidResponse
        }
        var fields: [String: Any] = ["rpcVersion": 1, "eventSubscriptions": 0]
        if let auth = hello["authentication"] as? [String: String],
           let salt = auth["salt"], let challenge = auth["challenge"] {
            guard !password.isEmpty else { throw OBSError.authentication }
            let secret = Data(SHA256.hash(data: Data((password + salt).utf8))).base64EncodedString()
            fields["authentication"] = Data(SHA256.hash(data: Data((secret + challenge).utf8))).base64EncodedString()
        }
        try await send(op: 1, fields: fields)
        _ = try await receive(op: 2)
    }

    private func send(op: Int, fields: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["op": op, "d": fields])
        try await sendText(String(decoding: data, as: UTF8.self))
    }

    private func receive(op: Int) async throws -> [String: Any] {
        let text = try await receiveText()
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        guard object?["op"] as? Int == op, let fields = object?["d"] as? [String: Any] else {
            throw OBSError.invalidResponse
        }
        return fields
    }

    func request(_ type: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        let id = UUID().uuidString
        try await send(op: 6, fields: ["requestType": type, "requestId": id, "requestData": data])
        let response = try await receive(op: 7)
        guard response["requestId"] as? String == id, response["requestType"] as? String == type,
              let status = response["requestStatus"] as? [String: Any],
              let success = status["result"] as? Bool else {
            throw OBSError.invalidResponse
        }
        guard success else {
            throw OBSError.rejected(status["comment"] as? String ?? "OBS could not run \(type).")
        }
        return response["responseData"] as? [String: Any] ?? [:]
    }

    func run(_ command: OBSCommand, microphone: String) async throws -> OBSState? {
        switch command {
        case .status:
            let sceneInfo = try await request("GetSceneList")
            guard let entries = sceneInfo["scenes"] as? [[String: Any]] else { throw OBSError.invalidResponse }
            let scenes = entries.sorted { ($0["sceneIndex"] as? Int ?? 0) > ($1["sceneIndex"] as? Int ?? 0) }
                .compactMap { $0["sceneName"] as? String }
            let recording = try await request("GetRecordStatus")["outputActive"] as? Bool
            let mic = try await micName(preferred: microphone)
            var muted: Bool?
            if let mic {
                muted = try? await request("GetInputMute", ["inputName": mic])["inputMuted"] as? Bool
            }
            return OBSState(scenes: scenes, currentScene: sceneInfo["currentProgramSceneName"] as? String,
                            microphone: mic, muted: muted, recording: recording)
        case .scene(let name):
            _ = try await request("SetCurrentProgramScene", ["sceneName": name])
        case .mute(let muted):
            guard let name = try await micName(preferred: microphone) else { throw OBSError.missingMic }
            _ = try await request("SetInputMute", ["inputName": name, "inputMuted": muted])
        case .record(let recording):
            guard let active = try await request("GetRecordStatus")["outputActive"] as? Bool else {
                throw OBSError.invalidResponse
            }
            if active != recording { _ = try await request(recording ? "StartRecord" : "StopRecord") }
        }
        return nil
    }

    private func micName(preferred: String) async throws -> String? {
        if !preferred.isEmpty { return preferred }
        let inputs = try await request("GetSpecialInputs")
        return ["mic1", "mic2", "mic3", "mic4"].compactMap { inputs[$0] as? String }
            .first { !$0.isEmpty }
    }
}

final class OBSControl {
    private let directory: URL
    private(set) var settings: OBSSettings?
    private var updating = false

    init(folder: URL) {
        directory = folder.appendingPathComponent("OBS", isDirectory: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("connection.json")) {
            settings = try? JSONDecoder().decode(OBSSettings.self, from: data)
        }
    }

    func configure(_ settings: OBSSettings?) throws {
        let path = directory.appendingPathComponent("connection.json")
        if let settings {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try JSONEncoder().encode(settings).write(to: path, options: .atomic)
        } else if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        self.settings = settings
    }

    @MainActor
    func run(_ command: OBSCommand) async throws -> OBSState? {
        guard let settings else { throw OBSError.disabled }
        let isChange: Bool
        if case .status = command { isChange = false } else { isChange = true }
        if isChange {
            guard !updating else { throw OBSError.rejected("OBS is finishing another command. Try again.") }
            updating = true
        }
        defer { if isChange { updating = false } }
        let url = URL(string: "ws://127.0.0.1:\(settings.port)")!
        let socket = URLSession.shared.webSocketTask(with: url, protocols: ["obswebsocket.json"])
        socket.maximumMessageSize = 1_048_576
        let timeout = DispatchWorkItem { socket.cancel() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)
        defer {
            timeout.cancel()
            socket.cancel(with: .normalClosure, reason: nil)
        }
        socket.resume()
        let session = OBSSession(sendText: { try await socket.send(.string($0)) }, receiveText: {
            guard case .string(let text) = try await socket.receive() else { throw OBSError.invalidResponse }
            return text
        })
        do {
            try await session.identify(password: settings.password)
            return try await session.run(command, microphone: settings.microphone)
        } catch let error as OBSError {
            throw error
        } catch {
            if socket.closeCode.rawValue == 4009 { throw OBSError.authentication }
            throw OBSError.disconnected
        }
    }
}
