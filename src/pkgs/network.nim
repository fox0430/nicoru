{.deadCodeElim:on.}

import posix, strformat, os, strutils, osproc, json, marshal, options, sequtils
import linuxutils, settings

type
  Port = int

  PublishPortPair* = object
    host*: Port
    container*: Port

  IpAddr = object
    address: string
    subnetMask: Option[int]

  NetworkInterface = object
    name: string
    ipAddr: Option[IpAddr]

  VethPair* = object
    containerId: string
    # Created inside a container
    veth: Option[NetworkInterface]
    # Connect a bridge with veth (Doesn't have a IP Address)
    brVeth: Option[NetworkInterface]
    # Publish port
    publishPort*: Option[PublishPortPair]

  Bridge* = object
    # Bridge name
    name*: string
    # NAT ip address
    natIpAddr*: Option[IpAddr]
    # Connet to default NIC
    rtVeth: Option[NetworkInterface]
    # Connect a bridge with rtVeth (Doesn't have a IP Address)
    brRtVeth: Option[NetworkInterface]
    # veths for a container
    vethPairs*: seq[VethPair]

  Network* = object
    bridges*: seq[Bridge]

    currentBridgeIndex*: int
    # Default (Preferred) network interface on host
    defautHostNic*: Option[NetworkInterface]

proc networkStatePath*(): string {.inline.} =
  return "/var/run/nicoru/network_state.json"

proc lockedNetworkStatePath*(): string {.inline.} =
  return "/var/run/nicoru/network_state.json.lock"

proc baseVethName*(): string {.inline.} =
  return "veth"

proc baseBrVethName*(): string {.inline.} =
  return "brVeth"

proc defaultBridgeName*(): string {.inline.} =
  return "nicoru0"

proc defaultBridgeIpAddr(): IpAddr {.inline.} =
  return IpAddr(address: "10.0.0.1", subnetMask: some(16))

proc defaultRtBridgeVethName(): string {.inline.} =
  return "rtVeth0"

proc defaultRtRtBridgeVethName(): string {.inline.} =
  return "brRtVeth0"

proc defaultNatAddress(): IpAddr {.inline.} =
  return IpAddr(address: "10.0.0.0", subnetMask: some(24))

# TODO: Move
proc isDigit*(str: string): bool =
  for c in str:
    if not isDigit(c): return false
  return true

# Only address
proc isIpAddress(str: string): bool =
  let splited = str.split('.')
  if splited.len == 4:
    for s in splited:
      if (not (s.len > 0 and s.len < 4)) or (not isDigit(s)):
        return false
    return true

# Include a net mask
proc isIpAddr(str: string): bool =
  if str.contains('/'):
    let splited = str.split('/')
    return splited.len == 2 and isIpAddress(splited[0]) and isDigit(splited[1])
  else:
    return isIpAddress(str)

proc parseIpAdder*(str: string): IpAddr =
  let splited = str.split("/")

  if splited.len == 1:
    return IpAddr(address: splited[0], subnetMask: none(int))
  elif splited.len == 2:
      return IpAddr(address: splited[0], subnetMask: some(parseInt(splited[1])))
  else:
    exception(fmt"Failed to parseIpAdder: '{str}'")

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

        try: result = splited[1].splitWhitespace[0]
        except: exception(fmt"Failed to get actual interface name. Invalid value: '{splited}'")

proc getPrimaryIpOfHost(defautInterfaceName: string): IpAddr =
  let
    cmd = fmt"ip addr show dev {defautInterfaceName}"
    r = execCmdEx(cmd)

  if r.exitCode != 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r.exitCode}")

  for l in r.output.split("\n"):
    if l.split(" ").contains("inet"):
      let splited = l.split(" ")
      for i, e in splited:
        if e == "inet" and splited.high > i and isIpAddr(splited[i + 1]):
          return IpAddr(parseIpAdder(splited[i + 1]))

# Get NetworkInterface of a default (preferred) network interface on host
proc getDefaultNetworkInterface(): Option[NetworkInterface] =
  let
    cmd = "ip route"
    r = execCmdEx(cmd)

  if r.exitCode != 0 or r.output.len == 0:
    exception(fmt"Failed to '{cmd}': exitCode: {r.exitCode}")

  var interfaceName = ""

  for l in r.output.split('\n'):
    let splited = l.split(" ")
    if splited[0] == "default":
      for index, word in splited:
        if "dev" == word:
          interfaceName = splited[index + 1]

  if interfaceName.len > 0:
    let
      ipAddr = getPrimaryIpOfHost(interfaceName)
      iface = NetworkInterface(name: interfaceName, ipAddr: some(ipAddr))
    return some(iface)

proc getRtVethIpAddr*(bridge: Bridge): IpAddr {.inline.} =
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
        interfaceName = l[1][0 ..< l[1].high]

      if interfaceName == bridgeName:
        return true

proc getVethIpAddr*(vethPair: VethPair): IpAddr {.inline.} =
  return vethPair.veth.get.ipAddr.get

proc getBridge*(bridges: seq[Bridge], bridgeName: string): Bridge =
  for bridge in bridges:
    if bridge.name == bridgeName:
      return bridge

  exception(fmt"Bridge object not found: '{bridgeName}'")

proc getVethPair*(bridge: Bridge,
                          containerId: string): VethPair =

  for vethPair in bridge.vethPairs:
    if vethPair.containerId == containerId:
      return vethPair

  exception(fmt"NetworkInterface object not found: '{containerId}'")

proc `$`(ipAddr: IpAddr): string =
  result = ipAddr.address
  if ipAddr.subnetMask.isSome:
    result &= "/" & $ipAddr.subnetMask.get

proc parsePort*(num: int): Port =
  if num >= 0 and num <= 65535:
    return Port(num)
  else:
    exception(fmt"Failed to parsePort: {num}")

proc initPublishPortPair*(hPort, cPort: int): PublishPortPair {.inline.} =
  return PublishPortPair(host: parsePort(hPort), container: parsePort(cPort))

proc initVeth(name: string, ipAddr: IpAddr): NetworkInterface =
  return NetworkInterface(name: name, ipAddr: some(ipAddr))

proc initVethPair(containerId: string,
                  veth, brVeth: NetworkInterface): VethPair =

  return VethPair(containerId: containerId,
                  veth: some(veth),
                  brVeth: some(brVeth))

proc initBridge*(bridgeName: string): Bridge =
  let
    rtVeth = NetworkInterface(name: defaultRtBridgeVethName())
    brRtVeth = NetworkInterface(name: defaultRtRtBridgeVethName())

  return Bridge(name: bridgeName,
                rtVeth: some(rtVeth),
                brRtVeth: some(brRtVeth),
                vethPairs: @[])

proc setPublishPortPair*(vethPair: var VethPair, portPair: PublishPortPair) =
  vethPair.publishPort = some(portPair)

proc setBridgeIpAddr*(bridge: var Bridge,
                      ipAddr: IpAddr = defaultBridgeIpAddr()) {.inline.} =

  if bridge.rtVeth.isSome and bridge.rtVeth.get.ipAddr.isNone:
    bridge.rtVeth.get.ipAddr = some(ipAddr)

proc setNatIpAddr*(bridge: var Bridge,
                   ipAddr: IpAddr = defaultNatAddress()) {.inline.} =

  if bridge.natIpAddr.isNone:
    bridge.natIpAddr = some(ipAddr)

proc toIpAddr(json: JsonNode): IpAddr =
  result.address = json["address"].getStr

  if json["subnetMask"]["has"].getBool:
    let subnetMask = json["subnetMask"]["val"].getInt
    result.subnetMask = some(subnetMask)

proc toNetworkInterface(json: JsonNode): NetworkInterface =
  result.name = json["name"].getStr

  if json["ipAddr"]["has"].getBool:
    let ipAddr = toIpAddr(json["ipAddr"]["val"])
    result.ipAddr = some(ipAddr)

proc toPublishPortPair(json: JsonNode): PublishPortPair =
  result.host = parsePort(json["host"].getInt)
  result.container = parsePort(json["container"].getInt)

proc toVethPair(json: JsonNode): VethPair =
  let containerId = json["containerId"].getStr

  result.containerId = containerId

  if json["veth"]["has"].getBool:
    let veth = toNetworkInterface(json["veth"]["val"])
    result.veth = some(veth)

  if json["brVeth"]["has"].getBool:
    let brVeth = toNetworkInterface(json["brVeth"]["val"])
    result.brVeth = some(brVeth)

  if json["publishPort"]["has"].getBool:
    let portPair = toPublishPortPair(json["publishPort"]["val"])
    result.publishPort = some(portPair)

proc toBridge(json: JsonNode): Bridge =
  result.name = json["name"].getStr

  if json["natIpAddr"]["has"].getBool:
    result.natIpAddr = some(toIpAddr(json["natIpAddr"]["val"]))

  if json["rtVeth"]["has"].getBool:
    let rtVeth = toNetworkInterface(json["rtVeth"]["val"])
    result.rtVeth = some(rtVeth)

  if json["brRtVeth"]["has"].getBool:
    let brRtVeth = toNetworkInterface(json["brRtVeth"]["val"])
    result.brRtVeth = some(brRtVeth)

  if json["vethPairs"].len > 0:
    for vethPairJson in json["vethPairs"].items:
      result.vethPairs.add toVethPair(vethPairJson)

proc toNetwork(json: JsonNode): Network =
  for b in json["bridges"]:
    result.bridges.add toBridge(b)

  if json["defautHostNic"]["has"].getBool:
    let iface = toNetworkInterface(json["defautHostNic"]["val"])
    result.defautHostNic = some(iface)

proc getVethName*(vethPair: VethPair): Option[string] =
  if vethPair.veth.isSome:
    return some(vethPair.veth.get.name)

proc getBrVethName*(vethPair: VethPair): Option[string] =
  if vethPair.brVeth.isSome:
    return some(vethPair.brVeth.get.name)

# Write/Overwrite a network_state.json
proc updateNetworkState*(network: Network, networkStatePath: string) =
  let (dir, _, _) = networkStatePath.splitFile
  if not dirExists(dir):
    createDir(runPath())

  let json = $$network
  writeFile(networkStatePath, $json)

# Read a network_state.json
# If a network_state.json doesn't exist, return a new Network object.
proc loadNetworkState*(networkStatePath: string): Network =
  if fileExists(networkStatePath):
    try:
      let json = parseFile(networkStatePath)
      return json.toNetwork
    except: exception(fmt"Failed to parse network_state.json. Please check {networkStatePath}")
  else:
    return Network(bridges: @[], defautHostNic: getDefaultNetworkInterface())

proc getCurrentBridgeIndex*(bridges: seq[Bridge],
                            bridgeName: string): Option[int] =

  for index, b in bridges:
    if b.name == bridgeName:
      return some(index)

proc newVethName(vethPairs: seq[VethPair], baseName: string): string =
  var countVeth = 0
  for v in vethPairs:
    if v.veth.isSome:
      countVeth.inc

  return baseName & $countVeth

proc newBrVethName(vethPairs: seq[VethPair], baseName: string): string =
  var countBrVeth = 0
  for v in vethPairs:
    if v.veth.isSome:
      countBrVeth.inc

  return baseName & $countBrVeth

proc getRightEndNum(ipAddr: IpAddr): int =
  let
    splitedIpAddr = ipAddr.address.split("/")
    numStr = (splitedIpAddr[0].join.split("."))[^1]

  try: return numStr.parseInt
  except: exception(fmt"Failed to parse int: '{numStr}'")

proc newVethIpAddr(vethPairs: seq[VethPair]): string =
  var maxNum = 1
  for v in vethPairs:
    if v.veth.isSome and v.veth.get.ipAddr.isSome:
      let
        num = getRightEndNum(v.veth.get.ipAddr.get)
      if num > maxNum:
        maxNum = num

    if v.brVeth.isSome and v.brVeth.get.ipAddr.isSome:
      let
        num = getRightEndNum(v.brVeth.get.ipAddr.get)
      if num > maxNum:
        maxNum = num

  return fmt"10.0.0.{maxNum + 1}"

# Add a new iface to Bridge.iface
proc addNewNetworkInterface*(bridge: var Bridge,
                             containerId, baseVethName, baseBrVethName: string,
                             isBridgeMode: bool) =

  var vethPair = VethPair(containerId: containerId)

  if isBridgeMode:
    block:
      let
        vethName = newVethName(bridge.vethPairs, baseVethName)
        ipAddr = IpAddr(address: newVethIpAddr(bridge.vethPairs),
                        subnetMask: some(24))
        veth = NetworkInterface(name: vethName, ipAddr: some(ipAddr))
      vethPair.veth = some(veth)

    block:
      let
        brVethName = newBrVethName(bridge.vethPairs, baseBrVethName)
        brVeth = NetworkInterface(name: brVethName, ipAddr: none(IpAddr))
      vethPair.brVeth = some(brVeth)
  else:
    vethPair.veth = none(NetworkInterface)
    vethPair.brVeth = none(NetworkInterface)

  bridge.vethPairs.add vethPair

proc add*(bridge: var Bridge, vethPair: VethPair) =
  bridge.vethPairs.add vethPair

proc addIpToNetworkInterface(containerId, ipAddr: string) =
  const filePath = networkStatePath()

  if fileExists(filePath):
    let json = try:
                 parseFile(filePath)
               except:
                 echo fmt"Failed to parseFile: '{filePath}'"
                 quit(1)

    if json.contains("ips"):
      var iface = json["ips"]
      iface.add(%* {containerId: ipAddr})

      let newJson = %* {"ips": iface}
      writeFile(filePath, $newJson)
  else:
    let json = %* {"ips": [{containerId: ipAddr}]}

    try: createDir(runPath())
    except: exception(fmt"Failed to create a directory: '{runPath()}'")

    try: writeFile(filePath, $json)
    except: exception(fmt"Failed to write a json: '{filePath}'")

proc removeIpFromNetworkInterface*(network: var Network, bridgeName, containerId: string) =
  for bridgeIndex, b in network.bridges:
    if b.name == bridgeName:
      for ifaceIndex, vethPair in b.vethPairs:
        if vethPair.containerId == containerId:
          network.bridges[bridgeIndex].vethPairs.delete(ifaceIndex .. ifaceIndex)
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

proc addIpAddrToVeth*(veth: NetworkInterface) =
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

proc addInterfaceToContainer*(vethPair: VethPair, pid: Pid) =
  block:
    let
      containerInterfaceName = vethPair.veth.get.name
      cmd = fmt"ip link set {containerInterfaceName} netns {$pid}"
      r = execShellCmd(cmd)

    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode: {r}")

  block:
    let hostInterfaceName = vethPair.brVeth.get.name
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

# Check if an iptables rule already exists.
# Use "iptables -C"
proc iptablesRuleExist(rule: string): bool =
  let
    cmd = rule.replace(" -A ", " -C ") & "; echo $?"
    r = execCmdEx(cmd)

  # 0 is already exist
  if r.output == "0\n":
    return true

proc setNat*(iface: NetworkInterface, ipAddr: IpAddr) =
  let
    interfaceName = iface.name
    cmd = fmt"iptables -t nat -A POSTROUTING -s {ipAddr} -o {interfaceName} -j MASQUERADE"

  if not iptablesRuleExist(cmd):
    let r = execShellCmd(cmd)
    if r != 0:
      exception(fmt"Failed to '{cmd}': exitCode {r}")

proc setDefaultGateWay(ipAddr: IpAddr) =
  let
    address = ipAddr.address
    cmd = fmt"ip route add default via {address}"
    r = execShellCmd(cmd)

  if r != 0:
    exception(fmt"Failed to '{cmd}': exitCode {r}")

proc setPortForward*(vethIpAddr: IpAddr,
                     portPair: PublishPortPair,
                     defautHostNic: NetworkInterface) =

  if defautHostNic.ipAddr.isSome:
    let
      hPort = portPair.host
      cPort = portPair.container

      hostAddress = defautHostNic.ipAddr.get
      containerAddress = vethIpAddr.address

    # External traffic
    block:
      let cmd = fmt"iptables -t nat -A PREROUTING -d {hostAddress} -p tcp -m tcp --dport {hPort} -j DNAT --to-destination {containerAddress}:{cPort}"

      if not iptablesRuleExist(cmd):
        let r = execShellCmd(cmd)
        if r != 0:
          exception(fmt"Failed to '{cmd}': exitCode {r}")

    # Local traffic
    block:
      let cmd = fmt "iptables -t nat -A OUTPUT -d {hostAddress} -p tcp -m tcp --dport {hPort} -j DNAT --to-destination {containerAddress}:{cPort}"

      if not iptablesRuleExist(cmd):
        let r = execShellCmd(cmd)

        if r != 0:
          exception(fmt"Failed to '{cmd}': exitCode {r}")

proc removeIptablesRule(rule: string) =
  if rule.contains(" -A "):
    if iptablesRuleExist(rule):
      discard execShellCmd(rule.replace(" -A ", " -D "))
  elif rule.contains(" -D "):
    discard execShellCmd(rule)
  else:
    exception(fmt"Invalid iptables rule: '{rule}'")

proc removeContainerIptablesRule*(vethPair: VethPair,
                                  portPair: PublishPortPair,
                                  defautHostNic: NetworkInterface,
                                  natIpAddr: IpAddr) =

  if defautHostNic.ipAddr.isSome:
    let
      veth = vethPair.veth.get

      hostAddress = defautHostNic.ipAddr.get
      containerAddress = veth.ipAddr.get.address

      hPort = portPair.host
      cPort = portPair.container

    block:
      let cmd = fmt"iptables -t nat -D PREROUTING -d {hostAddress} -p tcp -m tcp --dport {hPort} -j DNAT --to-destination {containerAddress}:{cPort}"
      discard execShellCmd(cmd)

    block:
      let cmd = fmt"iptables -t nat -D OUTPUT -d {hostAddress} -p tcp -m tcp --dport {hPort} -j DNAT --to-destination {containerAddress}:{cPort}"
      discard execShellCmd(cmd)

    block:
      let
        interfaceName = defautHostNic.name
        cmd = fmt"iptables -t nat -D POSTROUTING -s {natIpAddr} -o {interfaceName} -j MASQUERADE"
      discard execShellCmd(cmd)

proc lockNetworkStatefile*(networkStatePath: string) {.inline.} =
  if fileExists(networkStatePath):
    moveFile(networkStatePath, lockedNetworkStatePath())

proc unlockNetworkStatefile*(networkStatePath: string) {.inline.} =
  if fileExists(lockedNetworkStatePath()):
    moveFile(lockedNetworkStatePath(), networkStatePath)

proc isLockedNetworkStateFile*(networkStatePath: string): bool {.inline.} =
  fileExists(lockedNetworkStatePath())

proc initContainerNetwork*(vethPair: VethPair, rtVethIpAddr: IpAddr) =
  # Up loopback interface
  block:
    const LOOPBACK_INTERFACE= "lo"
    upNetworkInterface(LOOPBACK_INTERFACE)

  # Wait for a network interface to be ready.
  let vethName = vethPair.getVethName.get

  waitInterfaceReady(vethName)

  addIpAddrToVeth(vethPair.veth.get)
  upNetworkInterface(vethName)

  setDefaultGateWay(rtVethIpAddr)

proc initNicoruNetwork*(networkStatePath: string, isBridgeMode: bool): Network =
  const BRIDGE_NAME = defaultBridgeName()

  result = loadNetworkState(networkStatePath)

  if result.defautHostNic.isNone:
    result.defautHostNic = getDefaultNetworkInterface()

  if result.bridges.len == 0:
    result.bridges.add initBridge(BRIDGE_NAME)

  if isBridgeMode:
    result.bridges[^1].setBridgeIpAddr
    result.bridges[^1].setNatIpAddr

  if not bridgeExists(BRIDGE_NAME):
    createBridge(result.bridges[^1])
