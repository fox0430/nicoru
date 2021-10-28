import posix, strformat, os
import linuxutils, settings

proc upNetworkInterface(deviceName: string) =
  let cmd = fmt"ip link set {deviceName} up"
  discard execShellCmd(cmd)

proc initContainerNetwork*(containerId: string) =
  block:
    const deviceName = "lo"
    upNetworkInterface(deviceName)
