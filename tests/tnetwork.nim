import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":

    # TODO: Fix
    let containerId = $genOid()

    var network = initNetwork(containerId, defaultBridgeName())

    const
      VETH_IP_ADDR = "10.0.0.1/24"
      CETH_IP_ADDR = "10.0.0.2/24"

    let
      ceth = Veth(name: "ceth", ip: some(CETH_IP_ADDR))
      veth = Veth(name: "veth", ip: some(VETH_IP_ADDR))
      ipList = IpList(containerId: containerId, ceth: some(ceth), veth: some(veth))

    network.bridges[0].ipList[0] = ipList

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
    check vethJson == parseJson("""{"val":{"name":"veth","ip":{"val":"10.0.0.1/24","has":true}},"has":true}""")

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges":[{"name":"nicoru0","ipList":[{"containerId":"6196223e33df0dba12df4c55","ceth":{"val":{"name":"ceth","ip":{"val":"10.0.0.2/24","has":true}},"has":true},"veth":{"val":{"name":"veth","ip":{"val":"10.0.0.1/24","has":true}},"has":true}}]}]}""")

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
    check network.bridges[0].ipList[0].veth.get.ip.isSome
    check network.bridges[0].ipList[0].veth.get.ip.get == "10.0.0.1/24"

  test "Remove IP address from Network":
    # TODO: Fix
    let containerId = $genOid()

    var network = initNetwork(containerId, defaultBridgeName())

    const
      CETH_IP_ADDR = "10.0.0.2/24"
      VETH_IP_ADDR = "10.0.0.1/24"

    let
      ceth = initVeth("ceth", CETH_IP_ADDR)
      veth = initVeth("veth", VETH_IP_ADDR)

      ipList = initIpList(containerId, ceth, veth)

    network.bridges[0].ipList[0] = ipList

    network.removeIpFromIpList(defaultBridgeName(), containerId)

    check network.bridges[0].ipList.len == 0
