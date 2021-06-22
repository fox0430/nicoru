import os

type RuntimeSettings* = object
  baseDir*: string
  debug*: bool
  background*: bool

proc initRuntimeSetting*(): RuntimeSettings =
  result.baseDir = getHomeDir() / ".local/share/dress"
