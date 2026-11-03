// ouro-devicehub: drives Xcode's Device Hub through accessibility, for iPhone Duo journeys.
//   ouro-devicehub dump          print the window's buttons (description | help | frame)
//   ouro-devicehub press <desc>  press the first element whose description or help is <desc>, e.g. "Partially Open"
//   ouro-devicehub serve <dir>   answer a UI test's numbered .request files (OuroDuoHinge) until stopped
// Exit codes, as the apps' devicehub.swift: 0 ok, 1 no DeviceHub process, 2 not found, 3 not trusted for
// accessibility, 4 the press failed; 64 usage.
import Foundation
import OuroDeviceHub

#if os(macOS)
let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first ?? "dump" {
    case "dump":
        OuroDeviceHub.dumpLines(try OuroDeviceHub.elements().all.map(\.info)).forEach { print($0) }
    case "press" where args.count == 2:
        try OuroDeviceHub.press(args[1])
        print("pressed \(args[1]): 0")
    case "serve" where args.count == 2:
        let dir = URL(fileURLWithPath: args[1], isDirectory: true)
        print("serving \(dir.path)")
        while true {
            OuroDuoDriver.handlePending(in: dir) { button in
                do { try OuroDeviceHub.press(button); sleep(8); return true } catch { print(error); return false }
            }
            usleep(500_000)
        }
    default:
        FileHandle.standardError.write(Data("usage: ouro-devicehub dump | press <description> | serve <request-dir>\n".utf8))
        exit(64)
    }
} catch {
    print(error)
    exit(error.exitCode)
}
#else
print("ouro-devicehub runs on the Mac.")
exit(1)
#endif
