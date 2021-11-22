import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":

    const CETH_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      ceth = Veth(name: "ceth", ip: some(CETH_IP_ADDR))
      veth = Veth(name: "veth", ip: none(string))
      ipList = IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

      bridge = Bridge(name: defaultBridgeName(), ipList: @[ipList])

      network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json.contains("bridges")
    check json["bridges"].len == 1

    check json["bridges"][0].contains("name")
    check json["bridges"][0]["name"].getStr == defaultBridgeName()

    check json["bridges"][0].contains("ipList")
    check json["bridges"][0]["ipList"].len == 1

    check json["bridges"][0]["ipList"][0].contains("containerId")
    check json["bridges"][0]["ipList"][0]["containerId"].getStr == containerId

    check json["bridges"][0]["ipList"][0].contains("ceth")
    let cethJson = json["bridges"][0]["ipList"][0]["ceth"]
    check cethJson == parseJson("""{"val":{"name":"ceth","ip":{"val":"10.0.0.2/24","has":true}},"has":true}""")

    check json["bridges"][0]["ipList"][0].contains("veth")
    let vethJson = json["bridges"][0]["ipList"][0]["veth"]
    check vethJson == parseJson("""{"val":{"name":"veth","ip":{"val":"","has":false}},"has":true}""")

  test "Remove IpList and update":
    const CETH_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      ceth = Veth(name: "ceth", ip: some(CETH_IP_ADDR))
      veth = Veth(name: "veth", ip: none(string))
      ipList = IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

      bridge = Bridge(name: defaultBridgeName(), ipList: @[ipList])

    var network = Network(bridges: @[bridge])

    const NETWORK_STATE_PATH = "/tmp/network_state.json"
    updateNetworkState(network, NETWORK_STATE_PATH)

    network.removeIpFromIpList(defaultBridgeName(), containerId)
    updateNetworkState(network, NETWORK_STATE_PATH)

    let json = parseFile(NETWORK_STATE_PATH)

    check json == parseJson("""{"bridges":[{"name":"nicoru0","ipList":[]}]}""")

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges":[{"name":"nicoru0","ipList":[{"containerId":"6196223e33df0dba12df4c55","ceth":{"val":{"name":"ceth","ip":{"val":"10.0.0.2/24","has":true}},"has":true},"veth":{"val":{"name":"veth","ip":{"val":"","has":false}},"has":true}}]}]}""")

    let network = json.toNetwork

    check network.bridges.len == 1
    check network.bridges[0].name == "nicoru0"

    check network.bridges[0].ipList.len == 1
    check network.bridges[0].ipList[0].containerId == "6196223e33df0dba12df4c55"

    check network.bridges[0].ipList[0].ceth.isSome
    check network.bridges[0].ipList[0].ceth.get.name == "ceth"
    check network.bridges[0].ipList[0].ceth.get.ip.isSome
    check network.bridges[0].ipList[0].ceth.get.ip.get == "10.0.0.2/24"

    check network.bridges[0].ipList[0].veth.isSome
    check network.bridges[0].ipList[0].veth.get.name == "veth"
    check network.bridges[0].ipList[0].veth.get.ip.isNone

  test "Remove IpList from Network":
    const CETH_IP_ADDR = "10.0.0.2/24"

    let
      # TODO: Fix
      containerId = $genOid()

      ceth = Veth(name: "ceth", ip: some(CETH_IP_ADDR))
      veth = Veth(name: "veth", ip: none(string))
      ipList = IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

      bridge = Bridge(name: defaultBridgeName(), ipList: @[ipList])

    var network = Network(bridges: @[bridge])

    network.removeIpFromIpList(defaultBridgeName(), containerId)

    check network.bridges[0].ipList.len == 0
