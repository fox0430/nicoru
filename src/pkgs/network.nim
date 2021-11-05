import posix, strformat, os, strutils, osproc
import linuxutils

proc upNetworkInterface*(interfaceName: string) =
  let
    cmd = fmt"ip link set {interfaceName} up"
    r = execShellCmd(cmd)

  if r != 0:
    exception("Failed to '{cmd}': exitCode: {r}")

proc createVirtualEthnet*(interfaceName: string) =
  let
    cmd = fmt"ip link add name {interfaceName} type veth peer name {interfaceName}-br"
    r = execShellCmd(cmd)

  if r != 0:
    exception("Failed to '{cmd}': exitCode: {r}")

# TODO: Add type for IP address
proc addIpAddrToVeth*(interfaceName, ipAddr: string) =
  let
    cmd = fmt"ip addr add {ipAddr} dev {interfaceName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception("Failed to '{cmd}': exitCode: {r}")

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
    let
      cmd = fmt"ip link set {interfaceName}-br netns {$pid}"
      r = execShellCmd(cmd)

    if r != 0:
      exception("Failed to '{cmd}': exitCode: {r}")

  block:
    # TODO: Fix IP
    const IP_ADDR = "10.0.0.1/24"
    addIpAddrToVeth(interfaceName, IP_ADDR)

  upNetworkInterface(interfaceName)

# TODO: Add type for IP address
proc initContainerNetwork*(containerId, interfaceName, ipAddr: string) =
  block:
    const DEVIC_ENAME = "lo"
    upNetworkInterface(DEVIC_ENAME)

  # Wait for a network interface to be ready.
  waitInterfaceReady(interfaceName)

  block:
    # TODO: Fix val name
    let interfaceName = fmt"{interfaceName}-br"

    addIpAddrToVeth(interfaceName, ipAddr)
    upNetworkInterface(interfaceName)
