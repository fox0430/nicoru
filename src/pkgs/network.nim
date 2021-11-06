import posix, strformat, os, strutils, osproc
import linuxutils

proc getActualInterfaceName(interfaceName: string): string =
  if interfaceName.len < 1:
    exception("Invalid interface name")

  let r = execCmdEx("ip a")

  if r.exitCode == 0:
    let lines = r.output.splitLines
    for l in lines:
      if l.contains(interfaceName):
        let splited = l.split(":")
        # TODO: Add error handling
        result = splited[1].splitWhitespace[0]

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

  if r != 0 and r != 2:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

# TODO: Add type for IP address
proc addIpAddrToVeth*(interfaceName, ipAddr: string) =
  let
    actualInterfaceName = getActualInterfaceName(interfaceName)
    cmd = fmt"ip addr add {ipAddr} dev {actualInterfaceName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

# Wait for a network interface to be ready.
proc waitInterfaceReady*(interfaceName: string) =
  let r = execCmdEx("ip a")
  if r.exitCode == 0:
    while true:
      if r.output.contains(interfaceName):
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
    # TODO: Need to get actial interface name from new netns
    let actualInterfaceName = getActualInterfaceName(containerInterfaceName)

    # TODO: Fix IP
    const IP_ADDR = "10.0.0.1/24"
    addIpAddrToVeth(actualInterfaceName, IP_ADDR)

    upNetworkInterface(actualInterfaceName)

# TODO: Add type for IP address
proc initContainerNetwork*(
  containerId, hostInterfaceName, containerInterfaceName, ipAddr: string) =

  let actualInterfaceName = getActualInterfaceName(containerInterfaceName)

  block:
    const DEVIC_ENAME = "lo"
    upNetworkInterface(DEVIC_ENAME)

  # Wait for a network interface to be ready.
  waitInterfaceReady(actualInterfaceName)

  addIpAddrToVeth(hostInterfaceName, ipAddr)
  upNetworkInterface(actualInterfaceName)
