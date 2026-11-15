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
/// folder, or `/tmp/ouro-reins-<bundle id>-<simulator UDID>.sock` when that is longer than a socket path may be (a
/// simulator app's temporary folder usually is). `start()` prints the path on stderr. From the Mac:
///
/// ```sh
/// printf 'ls\n' | nc -U "/tmp/ouro-reins-app.spoonjoy-$UDID.sock"
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
    /// The write end of the pipe that wakes the accept loop to stop.
    private var wake: Int32 = -1
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
        // Every simulator shares the Mac's /tmp, so the simulator's UDID keeps two devices running the same app apart.
        let device = ProcessInfo.processInfo.environment["SIMULATOR_UDID"].map { "-\($0)" } ?? ""
        let name = Bundle.main.bundleIdentifier ?? "pid-\(getpid())"
        let short = "/tmp/ouro-reins-\(name)\(device).sock"
        return short.utf8.count <= maximumPathBytes ? short : "/tmp/ouro-reins-\(getpid()).sock"
    }

    @MainActor
    public init(session: ReinsSession, path: String = ReinsSocketServer.defaultPath) {
        self.session = session
        self.path = path
    }

    /// Binds and starts accepting connections. Throws `POSIXError` when the socket can't be made: `ENAMETOOLONG` for a
    /// path over 103 bytes, `EADDRINUSE` when another server is live at the path or it holds something other than a
    /// socket, `EALREADY` when started.
    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listener < 0 else { throw POSIXError(.EALREADY) }
        let bytes = Array(path.utf8)
        guard bytes.count <= Self.maximumPathBytes else { throw POSIXError(.ENAMETOOLONG) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        // Replace a stale socket from an earlier run, never another kind of file and never a live server's socket.
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & S_IFMT == S_IFSOCK, !Self.answers(&address) else { throw POSIXError(.EADDRINUSE) }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else {
            let code = errno
            close(fd)
            unlink(path)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        // The accept loop can leave on its own (and close the read end) before stop() writes: no SIGPIPE for that.
        _ = fcntl(ends[1], F_SETNOSIGPIPE, 1)
        listener = fd
        wake = ends[1]
        FileHandle.standardError.write(Data("ouro-reins: serving on \(path)\n".utf8))
        Thread.detachNewThread { [self] in acceptLoop(fd, wake: ends[0]) }
    }

    /// Whether a server is accepting at `address` now.
    private static func answers(_ address: inout sockaddr_un) -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    /// Stops accepting, closes open connections and removes the socket file.
    ///
    /// Each descriptor is closed only by the thread that uses it, never from here: a descriptor closed under another
    /// thread gets its number reused at once, and that thread then acts on whatever socket took it. In a test run with
    /// several servers, a stopped server's accept loop took a connection meant for another server and closed it, or a
    /// shutdown here reached a connection that had since taken a closed one's number (#102). So this wakes the accept
    /// loop, which closes the listener itself, and shuts connections down while their threads can't close them.
    public func stop() {
        lock.lock()
        let fd = listener
        let wake = wake
        listener = -1
        self.wake = -1
        for client in clients { shutdown(client, SHUT_RDWR) }
        clients = []
        lock.unlock()
        guard fd >= 0 else { return }
        unlink(path)
        var byte: UInt8 = 1
        _ = write(wake, &byte, 1)
        close(wake)
    }

    private func acceptLoop(_ fd: Int32, wake: Int32) {
        defer {
            close(fd)
            close(wake)
        }
        while true {
            // Accept only when a connection is waiting, and leave once stop() writes to the pipe.
            var watched = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0), pollfd(fd: wake, events: Int16(POLLIN), revents: 0)]
            if poll(&watched, 2, -1) < 0 {
                if errno == EINTR { continue }
                return
            }
            if watched[1].revents != 0 { return }
            guard watched[0].revents & Int16(POLLIN) != 0 else {
                if watched[0].revents != 0 { return }
                continue
            }
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR || errno == EAGAIN || errno == ECONNABORTED { continue }
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
            guard accepting else {
                close(client)
                return
            }
            Thread.detachNewThread { [self] in serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        // Closed under the lock, so stop() never shuts down this number after it has gone to another socket.
        defer {
            lock.lock()
            clients.remove(client)
            close(client)
            lock.unlock()
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
