import Foundation
import OuroAXTesting

let run = XrayCLI.run(Array(CommandLine.arguments.dropFirst()))
FileHandle.standardOutput.write(Data(run.stdout.utf8))
FileHandle.standardError.write(Data(run.stderr.utf8))
exit(run.code)
