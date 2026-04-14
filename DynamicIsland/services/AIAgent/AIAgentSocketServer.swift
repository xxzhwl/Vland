/*
 * Vland (DynamicIsland)
 * Copyright (C) 2024-2026 Vland Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Darwin

final class AIAgentSocketServer: @unchecked Sendable {
    struct ClientConnection: Hashable, Sendable {
        let fd: Int32
    }

    typealias EventHandler = @MainActor (AIAgentHookEvent, ClientConnection) -> Void
    typealias DisconnectHandler = @MainActor (ClientConnection) -> Void
    typealias StateChangeHandler = @MainActor (_ isListening: Bool, _ errorMessage: String?) -> Void

    var onEvent: EventHandler?
    var onDisconnect: DisconnectHandler?
    var onStateChange: StateChangeHandler?

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.vland.aiagent.socket", qos: .userInitiated)
    private var serverFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var clientBuffers: [Int32: Data] = [:]

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit {
        queue.async { [socketPath] in
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.doStart()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.doStop()
        }
        Task { @MainActor [weak self] in
            self?.onStateChange?(false, nil)
        }
    }

    func sendResponse(
        _ payload: [String: Any],
        to connection: ClientConnection,
        closeAfterWrite: Bool = true
    ) async -> Bool {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let payloadData = String(data: data, encoding: .utf8)?
                .appending("\n")
                .data(using: .utf8) else {
            return false
        }

        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self, self.clientSources[connection.fd] != nil else {
                    continuation.resume(returning: false)
                    return
                }

                let success = payloadData.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return false
                    }

                    var totalWritten = 0
                    while totalWritten < payloadData.count {
                        let bytesWritten = Darwin.write(
                            connection.fd,
                            baseAddress.advanced(by: totalWritten),
                            payloadData.count - totalWritten
                        )
                        if bytesWritten <= 0 {
                            return false
                        }
                        totalWritten += bytesWritten
                    }

                    return true
                }

                if closeAfterWrite {
                    self.closeClient(fd: connection.fd, notifyDisconnect: false)
                }

                continuation.resume(returning: success)
            }
        }
    }

    private func doStart() {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            publishStateChange(isListening: false, errorMessage: "Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let pathBytes = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
            _ = socketPath.withCString { strncpy(pathBytes, $0, 103) }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(fd)
            publishStateChange(
                isListening: false,
                errorMessage: "Failed to bind socket: \(String(cString: strerror(errno)))"
            )
            return
        }

        chmod(socketPath, 0o777)

        guard listen(fd, 5) == 0 else {
            close(fd)
            unlink(socketPath)
            publishStateChange(isListening: false, errorMessage: "Failed to listen on socket")
            return
        }

        serverFileDescriptor = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [socketPath] in
            close(fd)
            unlink(socketPath)
        }
        source.resume()
        acceptSource = source

        publishStateChange(isListening: true, errorMessage: nil)
    }

    private func doStop() {
        let existingClientFDs = Array(clientSources.keys)
        existingClientFDs.forEach { closeClient(fd: $0, notifyDisconnect: false) }

        acceptSource?.cancel()
        acceptSource = nil
        serverFileDescriptor = -1
    }

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverFileDescriptor, sockPtr, &clientLen)
            }
        }

        guard clientFD >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readFromClient(fd: clientFD)
        }
        source.setCancelHandler { [weak self] in
            close(clientFD)
            self?.clientSources.removeValue(forKey: clientFD)
            self?.clientBuffers.removeValue(forKey: clientFD)
        }
        source.resume()

        clientSources[clientFD] = source
        clientBuffers[clientFD] = Data()
    }

    private func readFromClient(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = Darwin.read(fd, &buffer, buffer.count)

        guard bytesRead > 0 else {
            closeClient(fd: fd, notifyDisconnect: true)
            return
        }

        var pendingData = clientBuffers[fd] ?? Data()
        pendingData.append(contentsOf: buffer.prefix(bytesRead))

        while let newlineIndex = pendingData.firstIndex(of: 0x0A) {
            let messageData = pendingData.prefix(upTo: newlineIndex)
            pendingData.removeSubrange(...newlineIndex)

            guard !messageData.isEmpty,
                  let message = String(data: Data(messageData), encoding: .utf8),
                  let data = message.data(using: .utf8) else {
                continue
            }

            do {
                let event = try JSONDecoder().decode(AIAgentHookEvent.self, from: data)
                // Debug: log transcript_path for troubleshooting
                if event.hookType == "SessionStart" || event.hookType == "UserPromptSubmit" {
                    NSLog("[Vland] Hook event: source=\(event.source), hookType=\(event.hookType), transcriptPath=\(event.transcriptPath ?? "nil"), sessionId=\(event.sessionId ?? "nil")")
                }
                let connection = ClientConnection(fd: fd)
                Task { @MainActor [weak self] in
                    self?.onEvent?(event, connection)
                }
            } catch {
                print("[AIAgentSocketServer] Failed to decode event: \(error)")
            }
        }

        clientBuffers[fd] = pendingData
    }

    private func closeClient(fd: Int32, notifyDisconnect: Bool) {
        let connection = ClientConnection(fd: fd)
        if notifyDisconnect {
            Task { @MainActor [weak self] in
                self?.onDisconnect?(connection)
            }
        }

        clientSources[fd]?.cancel()
        clientSources.removeValue(forKey: fd)
        clientBuffers.removeValue(forKey: fd)
    }

    private func publishStateChange(isListening: Bool, errorMessage: String?) {
        Task { @MainActor [weak self] in
            self?.onStateChange?(isListening, errorMessage)
        }
    }
}
