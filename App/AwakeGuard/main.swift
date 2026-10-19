import ClamshellKit
import Darwin

// Fail-safe for lid-closed sleep prevention, spawned by T-Utilities while it is active.
// stdin is a heartbeat pipe from the app. When the pipe closes (app quit or crashed) or stays silent
// for 30 s (app hung), restore lid-closed sleep and exit.

let heartbeatTimeoutMilliseconds: Int32 = 30_000

var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
var buffer = [UInt8](repeating: 0, count: 64)
while true {
    guard poll(&descriptor, 1, heartbeatTimeoutMilliseconds) > 0 else { break }
    guard read(STDIN_FILENO, &buffer, buffer.count) > 0 else { break }
}
Clamshell.setSleepDisabled(false)
exit(0)
