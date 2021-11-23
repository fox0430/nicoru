import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":

    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      veth = Veth(name: "veth", ipAddr: some(veth_IP_ADDR))
      brVeth = Veth(name: "brVeth", ipAddr: none(string))
      iface = NetworkInterface(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      bridge = Bridge(name: defaultBridgeName(), ifaces: @[iface])

      network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json.contains("bridges")
    check json["bridges"].len == 1

    check json["bridges"][0].contains("name")
    check json["bridges"][0]["name"].getStr == defaultBridgeName()

    check json["bridges"][0].contains("ifaces")
    check json["bridges"][0]["ifaces"].len == 1

    check json["bridges"][0]["ifaces"][0].contains("containerId")
    check json["bridges"][0]["ifaces"][0]["containerId"].getStr == containerId

    check json["bridges"][0]["ifaces"][0].contains("veth")
    let vethJson = json["bridges"][0]["ifaces"][0]["veth"]
    check vethJson == parseJson("""{"val":{"name":"veth","ipAddr":{"val":"10.0.0.2/24","has":true}},"has":true}""")

    check json["bridges"][0]["ifaces"][0].contains("brVeth")
    let brVethJson = json["bridges"][0]["ifaces"][0]["brVeth"]
    check brVethJson == parseJson("""{"val":{"name":"brVeth","ipAddr":{"val":"","has":false}},"has":true}""")

  test "Remove NetworkInterface and update":
    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()
      veth = Veth(name: "veth0", ipAddr: some(veth_IP_ADDR))
      brVeth = Veth(name: "brVeth0", ipAddr: none(string))
      iface = NetworkInterface(containerId: containerId, veth: some(veth), brVeth: some(brVeth))


      rtVethIpAddr = some(defaultBridgeIpAddr())
      rtVeth = Veth(name: defaultRtBridgeVethName(), ipAddr: rtVethIpAddr)
      brRtVeth = Veth(name: defaultRtRtBridgeVethName())

      bridgeName = defaultBridgeName()
      bridge = Bridge(name: bridgeName,
                      rtVeth: some(rtVeth),
                      brRtVeth: some(brRtVeth),
                      ifaces: @[iface])

    var network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    network.removeIpFromNetworkInterface(defaultBridgeName(), containerId)
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json == parseJson("""{"bridges":[{"name":"nicoru0","rtVeth":{"val":{"name":"rtVeth0","ipAddr":{"val":"10.0.0.1/16","has":true}},"has":true},"brRtVeth":{"val":{"name":"brRtVeth0","ipAddr":{"val":"","has":false}},"has":true},"ifaces":[]}]}""")

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges": [{"name": "nicoru0", "rtVeth": {"val": {"name": "rtVeth0", "ipAddr": {"val": "10.0.0.1/16", "has": true}}, "has": true}, "brRtVeth": {"val": {"name": "brRtVeth0", "ipAddr": {"val": "", "has": false}}, "has": true}, "ifaces": [{"containerId": "619d25b67e9ab4021a34aef2", "veth": {"val": {"name": "veth0", "ipAddr": {"val": "10.0.0.2/24", "has": true}}, "has": true}, "brVeth": {"val": {"name": "brVeth0", "ipAddr": {"val": "", "has": false}}, "has": true}}]}]}""")

      network = json.toNetwork

    check network.bridges.len == 1
    let bridge = network.bridges[0]
    check bridge.name == "nicoru0"

    check bridge.rtVeth.isSome
    check bridge.rtVeth.get.name == "rtVeth0"
    check bridge.rtVeth.get.ipAddr.isSome
    check bridge.rtVeth.get.ipAddr.get == "10.0.0.1/16"

    check bridge.brRtVeth.isSome
    check bridge.brRtVeth.get.name == "brRtVeth0"
    check bridge.brRtVeth.get.ipAddr.isNone

    check bridge.ifaces.len == 1
    let iface = bridge.ifaces[0]
    check iface.containerId == "619d25b67e9ab4021a34aef2"

    check iface.veth.isSome
    check iface.veth.get.name == "veth0"
    check iface.veth.get.ipAddr.isSome
    check iface.veth.get.ipAddr.get == "10.0.0.2/24"

    check iface.brVeth.isSome
    check iface.brVeth.get.name == "brVeth0"
    check iface.brVeth.get.ipAddr.isNone

  test "Remove NetworkInterface from Network":
    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      veth = Veth(name: "veth", ipAddr: some(veth_IP_ADDR))
      brVeth = Veth(name: "brVeth", ipAddr: none(string))
      iface = NetworkInterface(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      bridge = Bridge(name: defaultBridgeName(), ifaces: @[iface])

    var network = Network(bridges: @[bridge])

    network.removeIpFromNetworkInterface(defaultBridgeName(), containerId)

    check network.bridges[0].ifaces.len == 0

suite "parse IpAddr":
  test "parse IpAddr 1":
    check parseIpAdder("10.0.0.0") == IpAddr(address: "10.0.0.0", subnetMask: none(int))

  test "parse IpAddr 2":
    check parseIpAdder("10.0.0.0/24") == IpAddr(address: "10.0.0.0", subnetMask: some(24))
