import os, options, strformat
import linuxutils


type NetworkMode* {.pure.} = enum
  none
  bridge
  host

type
  RuntimeSettings* = object
    baseDir*: string
    debug*: bool
    background*: bool
    seccomp*: bool
    seccompProfilePath*: string
    networkMode*: NetworkMode

proc initRuntimeSetting*(): RuntimeSettings {.inline.} =
  result.baseDir = getHomeDir() / ".local/share/nicoru"
  result.networkMode = NetworkMode.none

proc shortId*(imageId: string): string {.inline.} =
  return imageId[7 .. ^1]

proc imagesPath*(settings: RuntimeSettings): string {.inline.} =
  return settings.baseDir / "images"

proc databasePath*(settings: RuntimeSettings): string {.inline.} =
  return settings.imagesPath() / "repositories.json"

proc imagesHashPath*(settings: RuntimeSettings): string {.inline.} =
  return settings.imagesPath() / "sha256"

proc imagesHashPath*(settings: RuntimeSettings, blob: string): string {.inline.} =
  return settings.imagesHashPath() / shortId(blob)

proc blobPath*(settings: RuntimeSettings): string =
  return settings.baseDir / "blobs"

proc blobPath*(settings: RuntimeSettings, imageId: string): string {.inline.} =
  return settings.blobPath() / shortId(imageId)

proc containersPath*(settings: RuntimeSettings): string {.inline.} =
  return settings.baseDir / "containers"

proc layerPath*(settings: RuntimeSettings): string {.inline.} =
  return settings.baseDir / "layer"

proc layerPath*(settings: RuntimeSettings, blob: string): string {.inline.} =
  return settings.baseDir / "layer" / shortId(blob)

proc containerConfigPath*(settings: RuntimeSettings, containerId: string): string {.inline.} =
  return settings.containersPath() / containerId / "config.json"

proc netNsPath*(): string {.inline.} =
  return "/var/run/nicoru/netns"

proc runPath*(): string {.inline.} =
  return "/var/run/nicoru"

proc toNetworkMode*(str: string): NetworkMode {.inline.} =
  case str:
    of "bridge":
      return NetworkMode.bridge
    of "host":
      return NetworkMode.host
    of "none":
      return NetworkMode.none
