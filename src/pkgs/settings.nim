import os

type NetworkMode* {.pure.} = enum
  none
  bridge
  host

type RuntimeSettings* = object
  baseDir*: string
  debug*: bool
  background*: bool
  seccomp*: bool
  seccompProfilePath*: string
  networkMode*: NetworkMode

proc initRuntimeSetting*(): RuntimeSettings =
  result.baseDir = getHomeDir() / ".local/share/nicoru"
  result.networkMode = NetworkMode.none

proc shortId*(imageId: string): string =
  return imageId[7 .. ^1]

proc imagesPath*(settings: RuntimeSettings): string =
  return settings.baseDir / "images"

proc databasePath*(settings: RuntimeSettings): string =
  return settings.imagesPath() / "repositories.json"

proc imagesHashPath*(settings: RuntimeSettings): string =
  return settings.imagesPath() / "sha256"

proc imagesHashPath*(settings: RuntimeSettings, blob: string): string =
  return settings.imagesHashPath() / shortId(blob)

proc blobPath*(settings: RuntimeSettings): string =
  return settings.baseDir / "blobs"

proc blobPath*(settings: RuntimeSettings, imageId: string): string =
  return settings.blobPath() / shortId(imageId)

proc containersPath*(settings: RuntimeSettings): string =
  return settings.baseDir / "containers"

proc layerPath*(settings: RuntimeSettings): string =
  return settings.baseDir / "layer"

proc layerPath*(settings: RuntimeSettings, blob: string): string =
  return settings.baseDir / "layer" / shortId(blob)

proc containerConfigPath*(settings: RuntimeSettings, containerId: string): string =
  return settings.containersPath() / containerId / "config.json"

proc netNsPath*(): string =
  return "/var/run/nicoru/netns"

proc runPath*(): string =
  return "/var/run/nicoru"

proc networkStatePath*(): string =
  return "/var/run/nicoru/network_state.json"

proc baseVethName*(): string =
  return "veth"

proc baseBrVethName*(): string =
  return "brVeth"

proc defaultBridgeName*(): string =
  return "nicoru0"

# TODO: Add type for IP address
proc defaultBridgeIpAddr*(): string =
  return "10.0.0.1/16"

proc defaultRtBridgeVethName*(): string =
  return "rtVeth0"

proc defaultRtRtBridgeVethName*(): string =
  return "brRtVeth0"
