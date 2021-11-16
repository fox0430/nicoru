import posix, strformat, os, strutils, osproc, json
import linuxutils, settings

proc getAllInterfaceName(): seq[string] =
  let
    cmd = "ip a"
    r = execCmdEx(cmd)

  if r.exitCode != 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r.exitCode}")

  let outputLines = r.output.splitLines
  for outputL in outputLines:
    if outputL.len > 0 and outputL[0].isDigit:
      let
        l = outputL.split(" ")
        interfaceName = l[1]

      if interfaceName.len > 2:
        # Remove ':' from interfaceName
        result.add interfaceName[0 .. interfaceName.high - 1]

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

# TODO: Add type for IP address
proc newVethIpAddr(): string =
  const filePath = networkStatePath()

  result = "10.0.0.1/24"

  if fileExists(filePath):
    let json = parseFile(filePath)

    if json.contains("ips"):
      let ipList = json["ips"]

      var maxNum = 1
      for ip in ipList:
        let
          splitedIp = ip.getStr.split("/")
          num = (splitedIp[0].join.split("."))[^1]

        if num.parseInt > maxNum:
          maxNum = num.parseInt

      let newNum = maxNum + 1
      result = fmt"10.0.0.{newNum}/24"

# TODO: Add type for IP address
proc addIpToIpList(containerId, ipAddr: string) =
  const filePath = networkStatePath()

  if fileExists(filePath):
    # TODO: Error handling
    let json = parseFile(filePath)

    if json.contains("ips"):
      var ipList = json["ips"]
      ipList.add(%* {containerId: ipAddr})

      let newJson = %* {"ips": ipList}
      writeFile(filePath, $newJson)
  else:
    let json = %* {"ips": [{containerId: ipAddr}]}
    # TODO: Error handling
    createDir(runPath())
    writeFile(filePath, $json)

# TODO: Add type for IP address
proc removeIpFromIpList*(containerId, ipAddr: string) =
  const filePath = networkStatePath()

  if fileExists(filePath):
    # TODO: Error handling
    let json = parseFile(filePath)

    if json.contains("ips") and json["ips"].contains(ipAddr):
      var newIpList: seq[(string, string)] = @[]
      for ip in json["ips"]:
        if $ip != ipAddr: newIpList.add (containerId, $ip)

      var newJson = json
      newJson["ips"] = %* {"ips": newIpList}
      # TODO: Error handling
      writeFile(filePath, $json)
    else:
      echo "Error: IP list not found"
  else:
    echo "Error: IP list not found"

proc checkIfExistNetworkInterface(interfaceName: string): bool =
  const CMD = "ip a"
  let r = execCmdEx(CMD)

  if r.exitCode == 0:
    result = r.output.contains(interfaceName)

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
    cmd = fmt"ip addr add {ipAddr} dev {interfaceName}"
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

proc addInterfaceToContainer*(
  containerId, hostInterfaceName, containerInterfaceName: string,
  pid: Pid): string =

  block:
    let
      cmd = fmt"ip link set {containerInterfaceName} netns {$pid}"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode: {r}")

  block:
    upNetworkInterface(hostInterfaceName)
    let ipAddr = newVethIpAddr()
    addIpAddrToVeth(hostInterfaceName, ipAddr)
    addIpToIpList(containerId, ipAddr)

proc createBridge*(bridgeName: string) =
  block:
    if not checkIfExistNetworkInterface(bridgeName):
      let
        cmd = fmt"ip link add {bridgeName} type bridge"
        r = execShellCmd(cmd)

      if r != 0:
        exception(fmt"Failed to '{cmd}': exitCode: {r}")

  block:
    let
      cmd = fmt"ip link set {bridgeName} up"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode {r}")

proc connectVethToBrige*(interfaceName, bridgeName: string) =
  let
    cmd = fmt"ip link set {interfaceName} master {bridgeName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

proc setDefaulRoute*(bridgeName, ipAddr: string) =
  let
    cmd = fmt"iptables -t nat -A POSTROUTING -s {ipAddr} ! -o {bridgeName} -j MASQUERADE"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

# Generate a new network interface name for host
proc newHostNetworkInterfaceName*(baseHostInterfaceName: string): string =
  let allInterfaceName = getAllInterfaceName()

  var countHostInterface = 0
  for name in allInterfaceName:
    if name.contains(baseHostInterfaceName):
      countHostInterface.inc

  result = baseHostInterfaceName & $countHostInterface

# TODO: Add type for IP address
proc initContainerNetwork*(
  containerId, hostInterfaceName, containerInterfaceName, bridgeName, ipAddr: string) =

  block:
    const DEVIC_ENAME = "lo"
    upNetworkInterface(DEVIC_ENAME)

  # Wait for a network interface to be ready.
  waitInterfaceReady(containerInterfaceName)

  addIpAddrToVeth(containerInterfaceName, ipAddr)
  upNetworkInterface(containerInterfaceName)
