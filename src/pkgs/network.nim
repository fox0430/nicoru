import posix, strformat, os, strutils, osproc
import linuxutils

proc upNetworkInterface*(interfaceName: string) =
  let
    cmd = fmt"ip link set {interfaceName} up"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

proc createVirtualEthnet*(hostInterfaceName, containerInterfaceName: string) =
  let
    cmd = fmt"ip link add name {hostInterfaceName} type veth peer name {containerInterfaceName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

# TODO: Add type for IP address
proc addIpAddrToVeth*(interfaceName, ipAddr: string) =
  let
    cmd = fmt"ip addr add {ipAddr} dev {interfaceName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

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

proc addInterfaceToContainer*(containerInterfaceName: string, pid: Pid) =
  block:
    let
      cmd = fmt"ip link set {containerInterfaceName} netns {$pid}"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode: {r}")

  block:
    # TODO: Fix IP
    const IP_ADDR = "10.0.0.1/24"
    addIpAddrToVeth(containerInterfaceName, IP_ADDR)

  upNetworkInterface(containerInterfaceName)

# TODO: Add type for IP address
proc initContainerNetwork*(
  containerId, hostInterfaceName, containerInterfaceName, ipAddr: string) =

  block:
    const DEVIC_ENAME = "lo"
    upNetworkInterface(DEVIC_ENAME)

  # Wait for a network interface to be ready.
  waitInterfaceReady(containerInterfaceName)

  addIpAddrToVeth(hostInterfaceName, ipAddr)
  upNetworkInterface(containerInterfaceName)
