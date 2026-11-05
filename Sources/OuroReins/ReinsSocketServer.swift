// The debug socket exists only in debug builds: a release build of an app has no Reins server to find or reach.
// CI builds this target in release and checks that no `ReinsSocketServer` symbol is left (ci.yml, "Reins").
#if DEBUG && canImport(Darwin)
import Foundation
import Darwin

/// Serves the Reins line protocol on a Unix domain socket in a running debug build, so an agent drives the same view
/// models the screen is bound to.
///
/// A Unix socket rather than a TCP port: it opens no port (no firewall prompt, nothing on the network), and on a
/// simulator the app's container is a host folder, so each simulator's app has its own socket path and several run side
/// by side. From the host:
///
/// ```sh
/// sock="$(xcrun simctl get_app_container booted app.spoonjoy data)/tmp/ouro-reins.sock"
/// printf 'ls\n' | nc -U "$sock"
/// ```
///
/// Start it once, from the app's debug launch path, behind an opt-in such as a launch argument.
public final class ReinsSocketServer: @unchecked Sendable {
    public let path: String
    private let session: ReinsSession
    private var listener: Int32 = -1
    private let queue = DispatchQueue(label: "ouro.reins.socket")

    /// The default path: `ouro-reins.sock` in the process's temporary folder.
    public static var defaultPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("ouro-reins.sock")
    }

    @MainActor
    public init(session: ReinsSession, path: String = ReinsSocketServer.defaultPath) {
        self.session = session
        self.path = path
    }

    /// Binds and starts accepting connections. Throws `POSIXError` when the socket can't be made.
    public func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        listener = fd
        queue.async { [self] in acceptLoop(fd) }
    }

    /// Stops accepting and removes the socket file.
    public func stop() {
        guard listener >= 0 else { return }
        shutdown(listener, SHUT_RDWR)
        close(listener)
        listener = -1
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            Thread.detachNewThread { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                guard let reply = handleOnMain(line) else { continue }
                let out = Array((reply + "\n").utf8)
                var sent = 0
                while sent < out.count {
                    let n = out[sent...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                    guard n > 0 else { return }
                    sent += n
                }
            }
        }
    }

    /// Runs one request on the main actor and waits for its reply on this connection's thread.
    private func handleOnMain(_ line: String) -> String? {
        let box = ReplyBox()
        let done = DispatchSemaphore(value: 0)
        let session = self.session
        Task { @MainActor in
            box.value = await ReinsWire.handle(line, session: session)
            done.signal()
        }
        done.wait()
        return box.value
    }
}

private final class ReplyBox: @unchecked Sendable {
    var value: String?
}
#endif
