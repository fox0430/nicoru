import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":

    # TODO: Fix
    let containerId = $genOid()

    var network = initNetwork(containerId)

    const
      VETH_IP_ADDR = "10.0.0.1/24"
      CETH_IP_ADDR = "10.0.0.2/24"
    network.bridges[0].ipList[0].cethIp = some(CETH_IP_ADDR)
    network.bridges[0].ipList[0].vethIp = some(VETH_IP_ADDR)

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

    check json["bridges"][0]["ipList"][0].contains("cethIp")
    check json["bridges"][0]["ipList"][0]["cethIp"].contains("has")
    check json["bridges"][0]["ipList"][0]["cethIp"]["has"].getBool
    check json["bridges"][0]["ipList"][0]["cethIp"].contains("val")
    check json["bridges"][0]["ipList"][0]["cethIp"]["val"].getStr == CETH_IP_ADDR

    check json["bridges"][0]["ipList"][0].contains("vethIp")
    check json["bridges"][0]["ipList"][0]["vethIp"].contains("has")
    check json["bridges"][0]["ipList"][0]["vethIp"]["has"].getBool
    check json["bridges"][0]["ipList"][0]["vethIp"].contains("val")
    check json["bridges"][0]["ipList"][0]["vethIp"]["val"].getStr == VETH_IP_ADDR

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges":[{"name":"nicoru0","ipList":[{"containerId":"61951964ed2c0c1061a1727c","cethIp":{"val":"10.0.0.2/24","has":true}, "vethIp":{"val":"10.0.0.1/24","has":true}}]}]}""")

      network = json.toNetwork

    check network.bridges.len == 1
    check network.bridges[0].name == "nicoru0"

    check network.bridges[0].ipList.len == 1
    check network.bridges[0].ipList[0].containerId == "61951964ed2c0c1061a1727c"

    check network.bridges[0].ipList[0].cethIp.isSome
    check network.bridges[0].ipList[0].cethIp.get == "10.0.0.2/24"

    check network.bridges[0].ipList[0].vethIp.isSome
    check network.bridges[0].ipList[0].vethIp.get == "10.0.0.1/24"

  test "Remove IP address from Network":
    # TODO: Fix
    let containerId = $genOid()

    var network = initNetwork(containerId)

    const
      CETH_IP_ADDR = "10.0.0.2/24"
      VETH_IP_ADDR = "10.0.0.1/24"
    network.bridges[0].ipList[0].cethIp = some(CETH_IP_ADDR)
    network.bridges[0].ipList[0].vethIp = some(VETH_IP_ADDR)

    network.removeIpFromIpList(defaultBridgeName(), containerId)

    check network.bridges[0].ipList.len == 0
