// The debug socket exists only in debug builds: a release build of an app has no Reins server to find or reach.
// CI builds this target in release and checks that no `ReinsSocketServer` symbol is left (ci.yml, "Reins").
#if DEBUG && canImport(Darwin)
import Foundation
import Darwin

/// Serves the Reins line protocol on a Unix domain socket in a running debug build, so an agent drives the same view
/// models the screen is bound to.
///
/// A Unix socket rather than a TCP port: it opens no port (no firewall prompt, nothing on the network). The path is
/// `OURO_REINS_SOCKET` when the launch environment sets it, otherwise `ouro-reins.sock` in the process's temporary
/// folder, or `/tmp/ouro-reins-<bundle id>.sock` when that is longer than a socket path may be (a simulator app's
/// temporary folder usually is). `start()` prints the path on stderr. From the Mac:
///
/// ```sh
/// printf 'ls\n' | nc -U /tmp/ouro-reins-app.spoonjoy.sock
/// ```
///
/// Call it only from debug code, so the app compiles in release too:
///
/// ```swift
/// #if DEBUG
/// let reins = ReinsSocketServer(session: ReinsSession(shell))
/// try? reins.start()
/// #endif
/// ```
///
/// Requests from every connection run one at a time, in arrival order, so two agents can't interleave actions.
public final class ReinsSocketServer: @unchecked Sendable {
    public let path: String
    private let session: ReinsSession
    private let lock = NSLock()
    private var listener: Int32 = -1
    private var clients = Set<Int32>()
    /// One request at a time across all connections.
    private let serial = DispatchSemaphore(value: 1)
    /// Longest request line accepted; a longer one closes the connection.
    static let maximumLineBytes = 1 << 20

    /// The longest path a Unix socket address holds, without its terminating zero.
    static let maximumPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    /// Where the socket goes when no path is given (see the type's documentation).
    public static var defaultPath: String {
        if let chosen = ProcessInfo.processInfo.environment["OURO_REINS_SOCKET"], !chosen.isEmpty { return chosen }
        let temporary = (NSTemporaryDirectory() as NSString).appendingPathComponent("ouro-reins.sock")
        if temporary.utf8.count <= maximumPathBytes { return temporary }
        let name = Bundle.main.bundleIdentifier ?? "pid-\(getpid())"
        return "/tmp/ouro-reins-\(name).sock"
    }

    @MainActor
    public init(session: ReinsSession, path: String = ReinsSocketServer.defaultPath) {
        self.session = session
        self.path = path
    }

    /// Binds and starts accepting connections. Throws `POSIXError` when the socket can't be made: `ENAMETOOLONG` for a
    /// path over 103 bytes, `EADDRINUSE` when something other than a socket is at the path, `EALREADY` when started.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listener < 0 else { throw POSIXError(.EALREADY) }
        let bytes = Array(path.utf8)
        guard bytes.count <= Self.maximumPathBytes else { throw POSIXError(.ENAMETOOLONG) }
        // Replace a stale socket from an earlier run, never another kind of file.
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & S_IFMT == S_IFSOCK else { throw POSIXError(.EADDRINUSE) }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
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
        FileHandle.standardError.write(Data("ouro-reins: serving on \(path)\n".utf8))
        Thread.detachNewThread { [self] in acceptLoop(fd) }
    }

    /// Stops accepting, closes open connections and removes the socket file.
    public func stop() {
        lock.lock()
        let fd = listener
        let open = clients
        listener = -1
        clients = []
        lock.unlock()
        guard fd >= 0 else { return }
        shutdown(fd, SHUT_RDWR)
        close(fd)
        for client in open { shutdown(client, SHUT_RDWR) }
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var on: Int32 = 1
            // A client that hangs up before its reply must not kill the app with SIGPIPE. One that hung up before
            // `accept` returned can't take the option (EINVAL): it's gone, so drop it.
            guard setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
                close(client)
                continue
            }
            lock.lock()
            let accepting = listener == fd
            if accepting { clients.insert(client) }
            lock.unlock()
            guard accepting else { close(client); return }
            Thread.detachNewThread { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        defer {
            lock.lock()
            clients.remove(client)
            lock.unlock()
            close(client)
        }
        var pending: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                // The last line may come without a newline, as on stdin.
                if !pending.isEmpty, let reply = handle(ReinsWire.line(pending)) { _ = send(reply, to: client) }
                return
            }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = ReinsWire.line(pending[..<newline])
                pending.removeSubrange(...newline)
                if let reply = handle(line), !send(reply, to: client) { return }
            }
            guard pending.count <= Self.maximumLineBytes else { return }
        }
    }

    /// Writes one reply line; false when the client has gone.
    private func send(_ reply: String, to client: Int32) -> Bool {
        let out = Array((reply + "\n").utf8)
        var sent = 0
        while sent < out.count {
            let n = out[sent...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            if n < 0, errno == EINTR { continue }
            guard n > 0 else { return false }
            sent += n
        }
        return true
    }

    /// Runs one request on the main actor, after any request already running, and waits for its reply on this
    /// connection's thread.
    private func handle(_ line: String) -> String? {
        serial.wait()
        defer { serial.signal() }
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
