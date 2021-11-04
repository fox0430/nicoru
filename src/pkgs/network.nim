import posix, strformat, os, strutils, osproc
import linuxutils

proc upNetworkInterface*(interfaceName: string) =
  let cmd = fmt"ip link set {interfaceName} up"
  discard execShellCmd(cmd)

proc createVirtualEthnet*(interfaceName: string) =
  let cmd = fmt"ip link add name {interfaceName} type veth peer name {interfaceName}-br"
  discard execShellCmd(cmd)

# TODO: Add type for IP address
proc addIpAddrToVeth*(interfaceName, ipAddr: string) =
  let cmd = fmt"ip addr add {ipAddr} dev {interfaceName}"
  discard execShellCmd(cmd)

# Wait for a network interface to be ready.
proc waitInterfaceReady*(interfaceName: string) =
  let
    r = execCmdEx("ip a")
    exitCode = r.exitCode

  if exitCode == 0:
    let output = $r.output
    while true:
      if output.contains(interfaceName):
        break
  else:
    exception("Failed to ip command in container")

proc addInterfaceToContainer*(interfaceName: string, pid: Pid) =
  block:
    let cmd = fmt"ip link set {interfaceName}-br netns {$pid}"
    discard execShellCmd(cmd)

  block:
    # TODO: Fix IP
    const IP_ADDR = "10.0.0.1/24"
    addIpAddrToVeth(interfaceName, IP_ADDR)

  upNetworkInterface(interfaceName)

proc initContainerNetwork*(containerId: string) =
  block:
    const deviceName = "lo"
    upNetworkInterface(deviceName)
