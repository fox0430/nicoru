import unittest, oids
import src/pkgs/settings
include src/pkgs/network

suite "Update network_state.json":
  test "Write network_state.json":

    # TODO: Fix
    let containerId = $genOid()

    var network = initNetwork(containerId)

    const IP_ADDR = "10.0.0.1/24"
    network.bridges[0].ipList[0].ip = some(IP_ADDR)

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

    check json["bridges"][0]["ipList"][0].contains("ip")
    check json["bridges"][0]["ipList"][0]["ip"].contains("has")
    check json["bridges"][0]["ipList"][0]["ip"]["has"].getBool
    check json["bridges"][0]["ipList"][0]["ip"].contains("val")
    check json["bridges"][0]["ipList"][0]["ip"]["val"].getStr == IP_ADDR

suite "Network object":
  test "JsonNode to Network":
    let
      json = parseJson("""{"bridges":[{"name":"nicoru0","ipList":[{"containerId":"61951964ed2c0c1061a1727c","ip":{"val":"10.0.0.1/24","has":true}}]}]}""")

      network = json.toNetwork

    check network.bridges.len == 1
    check network.bridges[0].name == "nicoru0"

    check network.bridges[0].ipList.len == 1
    check network.bridges[0].ipList[0].containerId == "61951964ed2c0c1061a1727c"

    check network.bridges[0].ipList[0].ip.isSome
    check network.bridges[0].ipList[0].ip.get == "10.0.0.1/24"
