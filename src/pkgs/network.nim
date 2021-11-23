{.deadCodeElim:on.}

import posix, strformat, os, strutils, osproc, json, marshal, options, sequtils
import linuxutils, settings

type
  IpAddr = object
    address: string
    subnetMask: Option[int]

  Veth = object
    name: string
    ipAddr: Option[IpAddr]

  NetworkInterface* = object
    containerId: string
    # Created inside a container
    veth: Option[Veth]
    # Connect a bridge with veth (Doesn't have a IP Address)
    brVeth: Option[Veth]

  Bridge* = object
    # Bridge name
    name*: string
    # Connet to default NIC
    rtVeth: Option[Veth]
    # Connect a bridge with rtVeth (Doesn't have a IP Address)
    brRtVeth: Option[Veth]
    # veths for a container
    ifaces*: seq[NetworkInterface]

  Network* = object
    bridges*: seq[Bridge]
    currentBridgeIndex*: int

proc networkStatePath*(): string =
  return "/var/run/nicoru/network_state.json"

proc baseVethName*(): string =
  return "veth"

proc baseBrVethName*(): string =
  return "brVeth"

proc defaultBridgeName*(): string =
  return "nicoru0"

proc defaultBridgeIpAddr*(): IpAddr =
  return IpAddr(address: "10.0.0.1", subnetMask: none(int))

proc defaultRtBridgeVethName*(): string =
  return "rtVeth0"

proc defaultRtRtBridgeVethName*(): string =
  return "brRtVeth0"

# TODO: Add type for IP address
proc defaultNatAddress*(): IpAddr =
  return IpAddr(address: "10.0.0.0", subnetMask: some(16))

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

# TODO; IP address type 
proc getRtVethIpAddr*(bridge: Bridge): IpAddr =
  return bridge.rtVeth.get.ipAddr.get

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

# TODO: Move
proc isDigit(str: string): bool =
  for c in str:
    if not isDigit(c): return false
  return true

proc ipAddressValidate(str: string): bool =
  let splited = str.split('.')
  if splited.len == 4:
    for str in splited:
      if not isDigit(str): return false
    return true

proc parseIpAdder*(str: string): IpAddr =
  let splited = str.split("/")

  if splited.len == 1 and ipAddressValidate(splited[0]):
    return IpAddr(address: splited[0], subnetMask: none(int))
  elif splited.len == 2:
    if ipAddressValidate(splited[0]) and isDigit(splited[1]):
      return IpAddr(address: splited[0], subnetMask: some(parseInt(splited[1])))
    else:
      exception(fmt"Failed to parseIpAdder: '{str}'")
  else:
    exception(fmt"Failed to parseIpAdder: '{str}'")

proc `$`(ipAddr: IpAddr): string =
  result = ipAddr.address
  if ipAddr.subnetMask.isSome:
    result &= $ipAddr.subnetMask.get

proc initVeth(name: string, ipAddr: IpAddr): Veth =
  return Veth(name: name, ipAddr: some(ipAddr))

proc initNetworkInterface(containerId: string,
                          veth, brVeth: Veth): NetworkInterface =

  return NetworkInterface(containerId: containerId,
                          veth: some(veth),
                          brVeth: some(brVeth))

proc initBridge*(bridgeName: string): Bridge =
  let
    rtVethIpAddr = some(defaultBridgeIpAddr())
    rtVeth = Veth(name: defaultRtBridgeVethName(), ipAddr: rtVethIpAddr)
    brRtVeth = Veth(name: defaultRtRtBridgeVethName())

  return Bridge(name: bridgeName,
                rtVeth: some(rtVeth),
                brRtVeth: some(brRtVeth),
                ifaces: @[])

proc toVeth(json: JsonNode): Veth =
  result.name = json["name"].getStr

  if json["ipAddr"]["has"].getBool:
    let ipAddr = parseIpAdder(json["ipAddr"]["val"].getStr)
    result.ipAddr = some(ipAddr)

proc toNetworkInterface(json: JsonNode): NetworkInterface =
  let containerId = json["containerId"].getStr

  result.containerId = containerId

  if json["veth"]["has"].getBool:
    let veth = toVeth(json["veth"]["val"])
    result.veth = some(veth)

  if json["brVeth"]["has"].getBool:
    let brVeth = toVeth(json["brVeth"]["val"])
    result.brVeth = some(brVeth)

proc toBridge(json: JsonNode): Bridge =
  result.name = json["name"].getStr

  if json["rtVeth"]["has"].getBool:
    let rtVeth = toVeth(json["rtVeth"]["val"])
    result.rtVeth = some(rtVeth)

  if json["brRtVeth"]["has"].getBool:
    let brRtVeth = toVeth(json["brRtVeth"]["val"])
    result.brRtVeth = some(brRtVeth)

  if json["ifaces"].len > 0:
    for ifaceJson in json["ifaces"].items:
      result.ifaces.add toNetworkInterface(ifaceJson)

proc toNetwork(json: JsonNode): Network =
  for b in json["bridges"]:
    result.bridges.add toBridge(b)

proc getVethName*(iface: NetworkInterface): Option[string] =
  if iface.veth.isSome:
    return some(iface.veth.get.name)

proc getBrVethName*(iface: NetworkInterface): Option[string] =
  if iface.brVeth.isSome:
    return some(iface.brVeth.get.name)

# Write/Overwrite a network_state.json
proc updateNetworkState*(network: Network, networkStatePath: string) =
  let (dir, _, _) = networkStatePath.splitFile
  if not dirExists(dir):
    createDir(runPath())

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

proc getCurrentBridgeIndex*(
  bridges: seq[Bridge], bridgeName: string): Option[int] =

  for index, b in bridges:
    if b.name == bridgeName:
      return some(index)

proc newVethName(iface: seq[NetworkInterface], baseName: string): string =
  var countVeth = 0
  for i in iface:
    if i.veth.isSome:
      countVeth.inc

  return baseName & $countVeth

proc newBrVethName(iface: seq[NetworkInterface], baseName: string): string =
  var countBrVeth = 0
  for i in iface:
    if i.veth.isSome:
      countBrVeth.inc

  return baseName & $countBrVeth

# TODO: Fix proc name
proc getNum(ipAddr: string): int =
  let
    splitedIpAddr = ipAddr.split("/")
    numStr = (splitedIpAddr[0].join.split("."))[^1]
  # TODO: Add Error handling
  return numStr.parseInt

proc newVethIpAddr(iface: seq[NetworkInterface]): string =
  var maxNum = 1
  for ip in iface:
    if ip.veth.isSome and ip.veth.get.ipAddr.isSome:
      let
        ipAddr = ip.veth.get.ipAddr.get
        num = getNum(ipAddr.address)
      if num > maxNum:
        maxNum = num

    if ip.brVeth.isSome and ip.brVeth.get.ipAddr.isSome:
      let
        ipAddr = ip.brVeth.get.ipAddr.get
        num = getNum(ipAddr.address)
      if num > maxNum:
        maxNum = num

  return fmt"10.0.0.{maxNum + 1}/24"

# TODO: Add type for IP address
# Add a new iface to Bridge.iface
proc addNewNetworkInterface*(bridge: var Bridge, containerId,
                             baseVethName, baseBrVethName: string) =

  var iface = NetworkInterface(containerId: containerId)

  block:
    let
      vethName = newVethName(bridge.ifaces, baseVethName)
      ipAddr = IpAddr(address: newVethIpAddr(bridge.ifaces), subnetMask: none(int))
      veth = Veth(name: vethName, ipAddr: some(ipAddr))
    iface.veth = some(veth)

  block:
    let
      brVethName = newBrVethName(bridge.ifaces, baseBrVethName)
      brVeth = Veth(name: brVethName, ipAddr: none(IpAddr))
    iface.brVeth = some(brVeth)

  bridge.ifaces.add iface

proc add*(bridge: var Bridge, iface: NetworkInterface) =
  bridge.ifaces.add(iface)

# TODO: Add type for IP address
proc addIpToNetworkInterface(containerId, ipAddr: string) =
  const filePath = networkStatePath()

  if fileExists(filePath):
    # TODO: Error handling
    let json = parseFile(filePath)

    if json.contains("ips"):
      var iface = json["ips"]
      iface.add(%* {containerId: ipAddr})

      let newJson = %* {"ips": iface}
      writeFile(filePath, $newJson)
  else:
    let json = %* {"ips": [{containerId: ipAddr}]}
    # TODO: Error handling
    createDir(runPath())
    writeFile(filePath, $json)

# TODO: Add type for IP address
proc removeIpFromNetworkInterface*(network: var Network, bridgeName, containerId: string) =
  for bridgeIndex, b in network.bridges:
    if b.name == bridgeName:
      for ifaceIndex, ip in b.ifaces:
        if ip.containerId == containerId:
          network.bridges[bridgeIndex].ifaces.delete(ifaceIndex .. ifaceIndex)
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

proc createVethPair*(hostInterfaceName, containerInterfaceName: string) =
  let
    cmd = fmt"ip link add name {hostInterfaceName} type veth peer name {containerInterfaceName}"
    r = execShellCmd(cmd)

  # r == 2 is already exist
  if r != 0 and r != 2:
    exception(fmt"Failed to '{cmd}': exitCode: {r}")

# TODO: Add type for IP address
proc addIpAddrToVeth*(veth: Veth) =
  let
    ipAddr = veth.ipAddr.get
    interfaceName = veth.name
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

proc addInterfaceToContainer*(iface: NetworkInterface, pid: Pid) =
  block:
    let
      containerInterfaceName = iface.veth.get.name
      cmd = fmt"ip link set {containerInterfaceName} netns {$pid}"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode: {r}")

  block:
    let hostInterfaceName = iface.brVeth.get.name
    upNetworkInterface(hostInterfaceName)

proc connectVethToBridge*(interfaceName, bridgeName: string) =
  let
    cmd = fmt"ip link set {interfaceName} master {bridgeName}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

proc createBridge*(bridge: Bridge) =
  let
    bridgeName = bridge.name
    rtVethName = bridge.rtVeth.get.name
    brRtVethName = bridge.brRtVeth.get.name

  block:
    if not checkIfExistNetworkInterface(bridgeName):

      block:
        let
          cmd = fmt"ip link add name {rtVethName} type veth peer name {brRtVethName}"
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
        connectVethToBridge(brRtVethName, bridgeName)

  block:
    let
      ipAddr = bridge.rtVeth.get.ipAddr.get
      cmd = fmt"ip addr add {ipAddr} dev {rtVethName}"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode {r}")

  upNetworkInterface(brRtVethName)
  upNetworkInterface(rtVethName)
  upNetworkInterface(bridgeName)

proc setNat*(interfaceName: string, ipAddr: IpAddr) =
  let
    cmd = fmt"iptables -t nat -A POSTROUTING -s {ipAddr} -o {interfaceName} -j MASQUERADE"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

proc setDefaultGateWay(ipAddr: IpAddr) =
  let
    cmd = fmt"ip route add default via {ipAddr}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

# TODO: Add type for IP address
proc initContainerNetwork*(iface: NetworkInterface, rtVethIpAddr: IpAddr) =
  # Up loopback interface
  block:
    const LOOPBACK_INTERFACE= "lo"
    upNetworkInterface(LOOPBACK_INTERFACE)

  # Wait for a network interface to be ready.
  let vethName = iface.getVethName.get

  waitInterfaceReady(vethName)

  addIpAddrToVeth(iface.veth.get)
  upNetworkInterface(vethName)

  setDefaultGateWay(rtVethIpAddr)

proc initNicoruNetwork*(): Network =
  const BRIDGE_NAME = defaultBridgeName()

  result = loadNetworkState(networkStatePath())

  if result.bridges.len == 0:
    result.bridges.add initBridge(BRIDGE_NAME)

  if not bridgeExists(BRIDGE_NAME):
    createBridge(result.bridges[0])
