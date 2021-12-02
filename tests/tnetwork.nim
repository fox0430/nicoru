import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":


    let
      # TODO: Fix
      containerId = $genOid()

      vethIpAddr = IpAddr(address: "10.0.0.2", subnetMask: some(24))
      veth = Veth(name: "veth", ipAddr: some(vethIpAddr))
      brVeth = Veth(name: "brVeth", ipAddr: none(IpAddr))
      vethPair = VethPair(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      bridge = Bridge(name: defaultBridgeName(), vethPairs: @[vethPair])

      network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json.contains("bridges")
    check json["bridges"].len == 1

    check json["bridges"][0].contains("name")
    check json["bridges"][0]["name"].getStr == defaultBridgeName()

    check json["bridges"][0].contains("vethPairs")
    check json["bridges"][0]["vethPairs"].len == 1

    check json["bridges"][0]["vethPairs"][0].contains("containerId")
    check json["bridges"][0]["vethPairs"][0]["containerId"].getStr == containerId

    check json["bridges"][0]["vethPairs"][0].contains("veth")
    let vethJson = json["bridges"][0]["vethPairs"][0]["veth"]
    check vethJson == parseJson("""{"val":{"name":"veth","ipAddr":{"val":{"address":"10.0.0.2","subnetMask":{"val":24,"has":true}},"has":true}},"has":true}""")

    check json["bridges"][0]["vethPairs"][0].contains("brVeth")
    let brVethJson = json["bridges"][0]["vethPairs"][0]["brVeth"]
    check brVethJson == parseJson("""{"val":{"name":"brVeth","ipAddr":{"val":{"address":"","subnetMask":{"val":0,"has":false}},"has":false}},"has":true}""")

  test "Remove NetworkInterface and update":
    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()
      veth = Veth(name: "veth0", ipAddr: some(IpAddr(address: "10.0.0.2", subnetMask: some(24))))
      brVeth = Veth(name: "brVeth0", ipAddr: none(IpAddr))
      vethPair = VethPair(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      rtVethIpAddr = some(defaultBridgeIpAddr())
      rtVeth = Veth(name: defaultRtBridgeVethName(), ipAddr: rtVethIpAddr)
      brRtVeth = Veth(name: defaultRtRtBridgeVethName())

      bridgeName = defaultBridgeName()
      bridge = Bridge(name: bridgeName,
                      rtVeth: some(rtVeth),
                      brRtVeth: some(brRtVeth),
                      vethPairs: @[vethPair])

    var network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    network.removeIpFromNetworkInterface(defaultBridgeName(), containerId)
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json == parseJson("""{"bridges":[{"name":"nicoru0","rtVeth":{"val":{"name":"rtVeth0","ipAddr":{"val":{"address":"10.0.0.1","subnetMask":{"val":16,"has":true}},"has":true}},"has":true},"brRtVeth":{"val":{"name":"brRtVeth0","ipAddr":{"val":{"address":"","subnetMask":{"val":0,"has":false}},"has":false}},"has":true},"vethPairs":[]}],"currentBridgeIndex":0}""")

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges": [{"name": "nicoru0", "rtVeth": {"val": {"name": "rtVeth0", "ipAddr": {"val": {"address": "10.0.0.1", "subnetMask": {"val": 0, "has": false}}, "has": true}}, "has": true}, "brRtVeth": {"val": {"name": "brRtVeth0", "ipAddr": {"val": {"address": "", "subnetMask": {"val": 0, "has": false}}, "has": false}}, "has": true}, "vethPairs": [{"containerId": "619d57d12a4f26fe94af3e31", "veth": {"val": {"name": "veth0", "ipAddr": {"val": {"address": "10.0.0.2", "subnetMask": {"val": 24, "has": true}}, "has": true}}, "has": true}, "brVeth": {"val": {"name": "brVeth0", "ipAddr": {"val": {"address": "", "subnetMask": {"val": 0, "has": false}}, "has": false}}, "has": true}}]}], "currentBridgeIndex": 0}""")

      network = json.toNetwork

    check network.bridges.len == 1
    let bridge = network.bridges[0]
    check bridge.name == "nicoru0"

    check bridge.rtVeth.isSome
    check bridge.rtVeth.get.name == "rtVeth0"
    check bridge.rtVeth.get.ipAddr.isSome
    check bridge.rtVeth.get.ipAddr.get == IpAddr(address: "10.0.0.1", subnetMask: none(int))

    check bridge.brRtVeth.isSome
    check bridge.brRtVeth.get.name == "brRtVeth0"
    check bridge.brRtVeth.get.ipAddr.isNone

    check bridge.vethPairs.len == 1
    let vethPair = bridge.vethPairs[0]
    check vethPair.containerId == "619d57d12a4f26fe94af3e31"

    check vethPair.veth.isSome
    check vethPair.veth.get.name == "veth0"
    check vethPair.veth.get.ipAddr.isSome
    check vethPair.veth.get.ipAddr.get == IpAddr(address: "10.0.0.2", subnetMask: some(24))

    check vethPair.brVeth.isSome
    check vethPair.brVeth.get.name == "brVeth0"
    check vethPair.brVeth.get.ipAddr.isNone

  test "Remove NetworkInterface from Network":
    let
      # TODO: Fix
      containerId = $genOid()

      vethIpAddr = IpAddr(address: "10.0.0.2", subnetMask: some(24))
      veth = Veth(name: "veth", ipAddr: some(vethIpAddr))
      brVeth = Veth(name: "brVeth", ipAddr: none(IpAddr))
      vethPair = VethPair(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      bridge = Bridge(name: defaultBridgeName(), vethPairs: @[vethPair])

    var network = Network(bridges: @[bridge])

    network.removeIpFromNetworkInterface(defaultBridgeName(), containerId)

    check network.bridges[0].vethPairs.len == 0

suite "IpAddr type":
  test "parse IpAddr 1":
    check parseIpAdder("10.0.0.0") == IpAddr(address: "10.0.0.0", subnetMask: none(int))

  test "parse IpAddr 2":
    check parseIpAdder("10.0.0.0/24") == IpAddr(address: "10.0.0.0", subnetMask: some(24))

  test "to string 1":
    check "10.0.0.0" ==  $IpAddr(address: "10.0.0.0", subnetMask: none(int))

  test "to string 2":
    check "10.0.0.0/24" == $IpAddr(address: "10.0.0.0", subnetMask: some(24))
