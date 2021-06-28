import os

type RuntimeSettings* = object
  baseDir*: string
  debug*: bool
  background*: bool

proc initRuntimeSetting*(): RuntimeSettings =
  result.baseDir = getHomeDir() / ".local/share/nicoru"

proc imagesPath*(settings: RuntimeSettings): string =
  return settings.baseDir / "images"

proc databasePath*(settings: RuntimeSettings): string =
  return settings.imagesPath() / "repositories.json"

proc imagesHashPath*(settings: RuntimeSettings): string =
  return settings.imagesPath() / "sha256"
