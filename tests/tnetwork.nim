import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":

    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      veth = Veth(name: "veth", ip: some(veth_IP_ADDR))
      brVeth = Veth(name: "brVeth", ip: none(string))
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
    check vethJson == parseJson("""{"val":{"name":"veth","ip":{"val":"10.0.0.2/24","has":true}},"has":true}""")

    check json["bridges"][0]["ifaces"][0].contains("brVeth")
    let brVethJson = json["bridges"][0]["ifaces"][0]["brVeth"]
    check brVethJson == parseJson("""{"val":{"name":"brVeth","ip":{"val":"","has":false}},"has":true}""")

  test "Remove NetworkInterface and update":
    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      veth = Veth(name: "veth", ip: some(veth_IP_ADDR))
      brVeth = Veth(name: "brVeth", ip: none(string))
      iface = NetworkInterface(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      bridge = Bridge(name: defaultBridgeName(), ifaces: @[iface])

    var network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    network.removeIpFromNetworkInterface(defaultBridgeName(), containerId)
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json == parseJson("""{"bridges":[{"name":"nicoru0","ifaces":[]}]}""")

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges":[{"name":"nicoru0","iface":[{"containerId":"6196223e33df0dba12df4c55","veth":{"val":{"name":"veth","ip":{"val":"10.0.0.2/24","has":true}},"has":true},"brVeth":{"val":{"name":"brVeth","ip":{"val":"","has":false}},"has":true}}]}]}""")

    let network = json.toNetwork

    check network.bridges.len == 1
    check network.bridges[0].name == "nicoru0"

    check network.bridges[0].ifaces.len == 1
    check network.bridges[0].ifaces[0].containerId == "6196223e33df0dba12df4c55"

    check network.bridges[0].ifaces[0].veth.isSome
    check network.bridges[0].ifaces[0].veth.get.name == "veth"
    check network.bridges[0].ifaces[0].veth.get.ip.isSome
    check network.bridges[0].ifaces[0].veth.get.ip.get == "10.0.0.2/24"

    check network.bridges[0].ifaces[0].brVeth.isSome
    check network.bridges[0].ifaces[0].brVeth.get.name == "brVeth"
    check network.bridges[0].ifaces[0].brVeth.get.ip.isNone

  test "Remove NetworkInterface from Network":
    const veth_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      veth = Veth(name: "veth", ip: some(veth_IP_ADDR))
      brVeth = Veth(name: "brVeth", ip: none(string))
      iface = NetworkInterface(containerId: containerId, veth: some(veth), brVeth: some(brVeth))

      bridge = Bridge(name: defaultBridgeName(), ifaces: @[iface])

    var network = Network(bridges: @[bridge])

    network.removeIpFromNetworkInterface(defaultBridgeName(), containerId)

    check network.bridges[0].ifaces.len == 0
