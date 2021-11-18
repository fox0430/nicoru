import posix, strformat, os, strutils, osproc, json, marshal, options
import linuxutils, settings

type
  Veth = object
    name: string
    ip: Option[string]

  # TODO: Fix type name
  IpList* = object
    containerId: string
    ceth: Option[Veth]
    veth: Option[Veth]

  Bridge* = object
    name: string
    ipList: seq[IpList]

  Network* = object
    bridges*: seq[Bridge]

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

proc initVeth(name, ipAddr: string): Veth =
  return Veth(name: name, ip: some(ipAddr))

proc initIpList(containerId: string, ceth, veth: Veth): IpList =
  return IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

proc initNetwork*(containerId, bridgeName: string): Network =
  let
    ipList = IpList(containerId: containerId,
                    ceth: none(Veth),
                    veth: none(Veth))

    bridge = Bridge(name: bridgeName, ipList: @[ipList])

  result = Network(bridges: @[bridge])

proc toNetwork(json: JsonNode): Network =
  for b in json["bridges"]:
    var bridge = Bridge(name: b["name"].getStr)

    for ip in b["ipList"]:
      let containerId = ip["containerId"].getStr

      var ipList = IpList(containerId: containerId)

      let cethJson = ip["ceth"]
      if cethJson["has"].getBool:
        let
          cethName = cethJson["val"]["name"].getStr

          ipAddr = if cethJson["val"]["ip"]["has"].getBool:
                     some(cethJson["val"]["ip"]["val"].getStr)
                   else:
                     none(string)

          ceth = Veth(name: cethName, ip: ipAddr)

        ipList.ceth = some(ceth)

      let vethJson = ip["veth"]
      if vethJson["has"].getBool:
        let
          vethName = vethJson["val"]["name"].getStr

          ipAddr = if vethJson["val"]["ip"]["has"].getBool:
                     some(vethJson["val"]["ip"]["val"].getStr)
                   else:
                     none(string)

          veth = Veth(name: vethName, ip: ipAddr)

        ipList.veth = some(veth)

        bridge.ipList.add ipList

    result.bridges.add bridge

# Write/Overwrite a network_state.json
proc updateNetworkState(network: Network, networkStatePath: string) =
  let (dir, _, _) = networkStatePath.splitFile
  if not dirExists(dir):
    createDir(runPath())

  # TODO: Error handling
  let json = $$network
  writeFile(networkStatePath, $json)

# Read a network_state.json
proc readNetworkState(networkStatePath: string): Option[Network] =
  if fileExists(networkStatePath):
    let json = parseFile(networkStatePath)

proc getCurrentBrigeIndex*(bridges: seq[Bridge], bridgeName: string): Option[int] =
  for index, b in bridges:
    if b.name == bridgeName:
      return some(index)

# TODO: Add type for IP address
# Get a new ipList (cethIp and vethIp)
proc newIpList*(bridge: Bridge, containerId: string): IpList =
  var maxNum = 0
  for ip in bridge.iplist:
    let
      veth = ip.veth.get
      ipAddr = veth.ip.get
      splitedIpAddr = ipAddr.split("/")
      numStr = (splitedIpAddr[0].join.split("."))[^1]
      num = numStr.parseInt
    if num > maxNum:
      maxNum = num

  let
    newCethIpAddr = fmt"10.0.0.{maxNum + 1}/24"
    ceth = Veth(name: "ceth", ip: some(newCethIpAddr))

    newVethIpAddr = fmt"10.0.0.{maxNum + 2}/24"
    veth = Veth(name: "veth", ip: some(newVethIpAddr))

  return IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

proc add*(bridge: var Bridge, ipList: IpList) =
  bridge.ipList.add(ipList)

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
proc removeIpFromIpList*(network: var Network, bridgeName, containerId: string) =
  for bridgeIndex, b in network.bridges:
    if b.name == bridgeName:
      for ipListIndex, ip in b.ipList:
        if ip.containerId == containerId:
          network.bridges[bridgeIndex].ipList.delete(ipListIndex)
          return

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

  # r == 2 is already exist
  if r != 0 and r != 2:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

# TODO: Add type for IP address
proc addIpAddrToVeth*(interfaceName: string, veth: Veth) =
  let
    ipAddr = veth.ip.get
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
  ipList: IpList,
  containerId, hostInterfaceName, containerInterfaceName: string,
  pid: Pid) =

  block:
    let
      cmd = fmt"ip link set {containerInterfaceName} netns {$pid}"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode: {r}")

  upNetworkInterface(hostInterfaceName)
  addIpAddrToVeth(hostInterfaceName, ipList.ceth.get)

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
proc newHostNetworkInterfaceName*(baseHostInterfaceName: string,
                                  bridgeIndex: int): string {.inline.} =

  return baseHostInterfaceName & $bridgeIndex

# TODO: Add type for IP address
proc initContainerNetwork*(
  ipList: IpList,
  containerId, hostInterfaceName, containerInterfaceName, bridgeName: string) =

  block:
    const DEVIC_ENAME = "lo"
    upNetworkInterface(DEVIC_ENAME)

  # Wait for a network interface to be ready.
  waitInterfaceReady(containerInterfaceName)

  addIpAddrToVeth(containerInterfaceName, ipList.veth.get)
  upNetworkInterface(containerInterfaceName)
