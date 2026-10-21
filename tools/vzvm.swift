// Run an ARM64 Linux VM headlessly under Apple's Virtualization framework, the engine behind
// UTM's "Use Apple Virtualization" option, with Apple's Rosetta shared in for x86-64 programs.
// The QEMU guest agent's port is bridged to a TCP port on 127.0.0.1, so qga.py can drive the
// guest as it drives the QEMU test VMs. vzvm.sh compiles and signs this on first use.
//
// usage: vzvm --iso ISO [--disk RAW_DISK] [--vars EFI_VARS] [--qga-port PORT] [--cpus N]
//             [--memory GB] [--no-rosetta]
import Darwin
import Foundation
import Virtualization

func fail(_ message: String) -> Never {
  FileHandle.standardError.write("vzvm: \(message)\n".data(using: .utf8)!)
  exit(1)
}

var iso: URL?, disk: URL?, vars = URL(fileURLWithPath: "vzvm-efi-vars")
var qgaPort: UInt16 = 4460, cpus = 4, memoryGB: UInt64 = 6, rosetta = true
var args = CommandLine.arguments.dropFirst()
func value(_ flag: String) -> String {
  guard let value = args.popFirst() else { fail("\(flag) needs a value") }
  return value
}
func number<T: LosslessStringConvertible>(_ flag: String) -> T {
  guard let number = T(value(flag)) else { fail("\(flag) needs a number") }
  return number
}
while let arg = args.popFirst() {
  switch arg {
  case "--iso": iso = URL(fileURLWithPath: value(arg))
  case "--disk": disk = URL(fileURLWithPath: value(arg))
  case "--vars": vars = URL(fileURLWithPath: value(arg))
  case "--qga-port": qgaPort = number(arg)
  case "--cpus": cpus = number(arg)
  case "--memory": memoryGB = number(arg)
  case "--no-rosetta": rosetta = false
  default: fail("unknown argument \(arg)")
  }
}
if iso == nil && disk == nil { fail("give --iso, --disk or both") }

let config = VZVirtualMachineConfiguration()
config.platform = VZGenericPlatformConfiguration()
let bootLoader = VZEFIBootLoader()
do {
  bootLoader.variableStore = FileManager.default.fileExists(atPath: vars.path)
    ? VZEFIVariableStore(url: vars)
    : try VZEFIVariableStore(creatingVariableStoreAt: vars)
} catch { fail("EFI variable store: \(error.localizedDescription)") }
config.bootLoader = bootLoader
config.cpuCount = cpus
config.memorySize = memoryGB << 30

// UTM attaches an ISO the same way: as a USB storage device.
var storage: [VZStorageDeviceConfiguration] = []
do {
  if let iso {
    storage.append(VZUSBMassStorageDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: iso, readOnly: true)))
  }
  if let disk {
    storage.append(VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: disk, readOnly: false)))
  }
} catch { fail("disk image: \(error.localizedDescription)") }
config.storageDevices = storage

let network = VZVirtioNetworkDeviceConfiguration()
network.attachment = VZNATNetworkDeviceAttachment()
config.networkDevices = [network]
config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
let graphics = VZVirtioGraphicsDeviceConfiguration()
graphics.scanouts = [VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1920, heightInPixels: 1080)]
config.graphicsDevices = [graphics]
config.keyboards = [VZUSBKeyboardConfiguration()]
config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

if rosetta {
  guard VZLinuxRosettaDirectoryShare.availability == .installed else {
    fail("Rosetta is not installed on this Mac (softwareupdate --install-rosetta), or use --no-rosetta")
  }
  let share = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
  do { share.share = try VZLinuxRosettaDirectoryShare() } catch { fail("Rosetta share: \(error.localizedDescription)") }
  config.directorySharingDevices = [share]
}

// The guest agent's virtio port, bridged to TCP: one client at a time; what the guest sends
// while nobody is connected is dropped (qga.py resynchronises on every connection).
let toGuest = Pipe(), fromGuest = Pipe()
let agentPort = VZVirtioConsolePortConfiguration()
agentPort.name = "org.qemu.guest_agent.0"
agentPort.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: toGuest.fileHandleForReading,
                                                        fileHandleForWriting: fromGuest.fileHandleForWriting)
let console = VZVirtioConsoleDeviceConfiguration()
console.ports[0] = agentPort
config.consoleDevices = [console]

do { try config.validate() } catch { fail("configuration: \(error.localizedDescription)") }

let lock = NSLock()
var client: Int32 = -1
func sendAll(_ fd: Int32, _ data: Data) {
  data.withUnsafeBytes { raw in
    var offset = 0
    while offset < raw.count {
      let n = send(fd, raw.baseAddress! + offset, raw.count - offset, 0)
      if n <= 0 { return }
      offset += n
    }
  }
}
fromGuest.fileHandleForReading.readabilityHandler = { handle in
  let data = handle.availableData
  lock.lock(); let fd = client; lock.unlock()
  if fd >= 0 && !data.isEmpty { sendAll(fd, data) }
}
let listener = socket(AF_INET, SOCK_STREAM, 0)
var yes: Int32 = 1
setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
var address = sockaddr_in()
address.sin_family = sa_family_t(AF_INET)
address.sin_port = qgaPort.bigEndian
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &address) {
  $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
if bound != 0 || listen(listener, 4) != 0 { fail("cannot listen on 127.0.0.1:\(qgaPort)") }
Thread.detachNewThread {
  var buffer = [UInt8](repeating: 0, count: 1 << 16)
  while true {
    let fd = accept(listener, nil, nil)
    if fd < 0 { continue }
    lock.lock(); client = fd; lock.unlock()
    while true {
      let n = recv(fd, &buffer, buffer.count, 0)
      if n <= 0 { break }
      toGuest.fileHandleForWriting.write(Data(buffer[0..<n]))
    }
    lock.lock(); client = -1; lock.unlock()
    close(fd)
  }
}

final class Watcher: NSObject, VZVirtualMachineDelegate {
  func guestDidStop(_ virtualMachine: VZVirtualMachine) { print("vzvm: the guest stopped"); exit(0) }
  func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
    fail("stopped with an error: \(error.localizedDescription)")
  }
}
let watcher = Watcher()
let vm = VZVirtualMachine(configuration: config)
vm.delegate = watcher
for sig in [SIGINT, SIGTERM] {
  signal(sig, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
  source.setEventHandler { vm.stop { _ in exit(0) } }
  source.resume()
  _ = Unmanaged.passRetained(source)
}
vm.start { result in
  if case .failure(let error) = result { fail("cannot start: \(error.localizedDescription)") }
  print("vzvm: running (\(cpus) CPUs, \(memoryGB) GB, Rosetta \(rosetta ? "shared" : "off"), guest agent on 127.0.0.1:\(qgaPort))")
}
dispatchMain()
