import posix, strformat, os, strutils, osproc, json, marshal, options, sequtils
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

  # TODO: Add IpAddr
  Bridge* = object
    name*: string
    ipList*: seq[IpList]

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

proc getDefaultNetworkInterface*(): string =
  let
    cmd = "ip route"
    r = execCmdEx(cmd)

  if r.exitCode != 0 or r.output.len == 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r.exitCode}")

  for l in r.output.split('\n'):
    let splited = l.splitWhitespace
    if splited[0] == "default":
      for index, word in splited:
        if "dev" == word:
          return splited[index + 1]

proc bridgeExists*(bridgeName: string): bool =
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
        # TODO: Error handling
        interfaceName = l[1][0 ..< l[1].high]

      if interfaceName == bridgeName:
        return true

proc initVeth(name, ipAddr: string): Veth =
  return Veth(name: name, ip: some(ipAddr))

proc initIpList(containerId: string, ceth, veth: Veth): IpList =
  return IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

proc initBridge*(bridgeName: string): Bridge =
  return Bridge(name: bridgeName, ipList: @[])

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

proc getCethName*(ipList: IpList): Option[string] =
  if ipList.ceth.isSome:
    return some(ipList.ceth.get.name)

proc getVethName*(ipList: IpList): Option[string] =
  if ipList.veth.isSome:
    return some(ipList.veth.get.name)

# Write/Overwrite a network_state.json
proc updateNetworkState*(network: Network, networkStatePath: string) =
  let (dir, _, _) = networkStatePath.splitFile
  if not dirExists(dir):
    createDir(runPath())

  # TODO: Fix
  # TODO: Error handling
  let json = $$network
  writeFile(networkStatePath, $json)

# Read a network_state.json
# If a network_state.json doesn't exist, return a new Network object.
proc loadNetworkState*(networkStatePath: string): Network =
  if fileExists(networkStatePath):
    # TODO: Error handling
    let json = parseFile(networkStatePath)
    return json.toNetwork
  else:
    return Network(bridges: @[])

proc getCurrentBridgeIndex*(bridges: seq[Bridge], bridgeName: string): Option[int] =
  for index, b in bridges:
    if b.name == bridgeName:
      return some(index)

proc newCethName(ipList: seq[IpList], baseName: string): string =
  var countCeth = 0
  for ip in ipList:
    if ip.ceth.isSome:
      countCeth.inc

  return baseName & $countCeth

proc newVethName(ipList: seq[IpList], baseName: string): string =
  var countVeth = 0
  for ip in ipList:
    if ip.veth.isSome:
      countVeth.inc

  return baseName & $countVeth

# TODO: Fix proc name
proc getNum(ipAddr: string): int =
  let
    splitedIpAddr = ipAddr.split("/")
    numStr = (splitedIpAddr[0].join.split("."))[^1]
  # TODO: Add Error handling
  return numStr.parseInt

proc newVethIpAddr(iplist: seq[IpList]): string =
  var maxNum = 0
  for ip in iplist:
    if ip.ceth.isSome and ip.ceth.get.ip.isSome:
      let
        ipAddr = ip.ceth.get.ip.get
        num = getNum(ipAddr)
      if num > maxNum:
        maxNum = num

    if ip.veth.isSome and ip.veth.get.ip.isSome:
      let
        ipAddr = ip.veth.get.ip.get
        num = getNum(ipAddr)
      if num > maxNum:
        maxNum = num

  return fmt"10.0.0.{maxNum + 1}/24"

# TODO: Add type for IP address
# Add a new ipList to Bridge.ipList
proc addNewIpList*(bridge: var Bridge, containerId, baseCethName, baseVethName: string) =
  var ipList = IpList(containerId: containerId)

  block:
    let
      cethName = newCethName(bridge.ipList, baseCethName)
      cethIpAddr = newVethIpAddr(bridge.ipList)
      ceth = Veth(name: cethName, ip: some(cethIpAddr))
    ipList.ceth = some(ceth)

  block:
    let
      vethName = newCethName(bridge.ipList, baseVethName)
      veth = Veth(name: vethName, ip: none(string))
    ipList.veth = some(veth)

  bridge.ipList.add ipList

proc newIpList*(containerId, baseCethName, baseVethName: string): IpList =
  let
    ipList: seq[IpList] = @[]

    cethName = baseCethName & "0"
    cethIpAddr = "10.0.0.2/24"
    ceth = Veth(name: cethName, ip: some(cethIpAddr))

    vethName = baseVethName & "0"
    veth = Veth(name: vethName, ip: none(string))

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
          network.bridges[bridgeIndex].ipList.delete(ipListIndex .. ipListIndex)
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

proc createVeth*(hostInterfaceName, containerInterfaceName: string) =
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

proc connectVethToBridge*(interfaceName, bridgeName: string) =
  let
    cmd = fmt"ip link set {interfaceName} master {bridgeName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

proc createBridge*(bridgeName: string) =
  block:
    if not checkIfExistNetworkInterface(bridgeName):
      block:
        let
          # TODO: Fix veth name
          cmd = "ip link add name veth0 type veth peer name br-veth0"
          r = execShellCmd(cmd)

        if r != 0:
          exception(fmt"Failed to '{cmd}': exitCode: {r}")

      block:
        let
          cmd = fmt"ip link add {bridgeName} type bridge"
          r = execShellCmd(cmd)

        if r != 0:
          exception(fmt"Failed to '{cmd}': exitCode: {r}")

      block:
        # TODO: Fix INTERFACE_NAME
        const INTERFACE_NAME = "br-veth0"
        connectVethToBridge(INTERFACE_NAME, bridgeName)

  block:
    # TODO: Fix INTERFACE_NAME
    const INTERFACE_NAME = "veth0"
    let
      ipAddr = defaultBridgeIpAddr()
      cmd = fmt"ip addr add {ipAddr} dev veth0"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode {r}")

  block:
    # TODO: Fix INTERFACE_NAME
    const INTERFACE_NAME = "br-veth0"
    upNetworkInterface(INTERFACE_NAME)

  block:
    # TODO: Fix INTERFACE_NAME
    const INTERFACE_NAME = "veth0"
    upNetworkInterface(INTERFACE_NAME)

  block:
    upNetworkInterface(bridgeName)

proc setNat*(interfaceName, ipAddr: string) =
  let
    cmd = fmt"iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o {interfaceName} -j MASQUERADE"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

proc setDefaultGateWay(ipAddr: string) =
  let
    cmd = fmt"ip route add default via {ipAddr}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

# TODO: Add type for IP address
proc initContainerNetwork*(ipList: IpList, containerId: string) =
  # Up loopback interface
  block:
    const LOOPBACK_INTERFACE= "lo"
    upNetworkInterface(LOOPBACK_INTERFACE)

  # Wait for a network interface to be ready.
  let cethName = ipList.getCethName.get
  waitInterfaceReady(cethName)

  addIpAddrToVeth(cethName, ipList.ceth.get)
  upNetworkInterface(cethName)

  block:
    # TODO: Fix
    const IP_ADDR = "10.0.0.1"
    setDefaultGateWay(IP_ADDR)
