import std/[parseopt, strformat, os, strutils, pegs, options]
import settings, help, container, image, cgroups, network

type CmdOption* = object
  key*: string
  val*: string

type CmdParseInfo* = object
  argments*: seq[string]
  shortOptions*: seq[CmdOption]
  longOptions*: seq[CmdOption]

proc `$`(cmdOptions: seq[CmdOption]): string =
  result = "@["

  for i in 0 ..< cmdOptions.len:
    let option = cmdOptions[i]
    result &= fmt "(key: {option.key}, val: {option.val})"
    if i < cmdOptions.len - 1:
      result &= ","

  result &= "]"

proc `[]`(cmdOptions: seq[CmdOption], key: string): string =
  for option in cmdOptions:
    if option.key == key:
      return option.val

proc containsKey(cmdOptions: seq[CmdOption], key: string): bool =
  for option in cmdOptions:
    if option.key == key:
      return true

proc staticReadVersionFromNimble: string {.compileTime.} =
  let peg = """@ "version" \s* "=" \s* \" {[0-9.]+} \" @ $""".peg
  var captures: seq[string] = @[""]
  let
    nimblePath = currentSourcePath.parentDir() / "../../nicoru.nimble"
    nimbleSpec = staticRead(nimblePath)

  assert nimbleSpec.match(peg, captures)
  assert captures.len == 1
  return captures[0]

proc generateVersionInfoMessage(): string =
  const versionInfo = "nicoru v" & staticReadVersionFromNimble()
  result = versionInfo

proc writeVersion() =
  echo generateVersionInfoMessage()
  quit()

proc writeCmdLineError(key: string) =
  echo fmt"Unknown option: {key}"
  quit()

proc initCgroupsSettings(longOptions: seq[CmdOption]): CgroupsSettgings =
  result = CgroupsSettgings()

  if longOptions.containsKey("cpulimit"):
    if longOptions["cpulimit"].len > 0:
      result.cpu = true
      result.cpuLimit = parseInt(longOptions["cpulimit"])
    else:
      echo "Error: Invalid value: --cpulimit"
      quit()

  if longOptions.containsKey("cpucorelimit"):
    if longOptions["cpucorelimit"].len > 0:
      result.cpuCore = true
      result.cpuCoreLimit = parseInt(longOptions["cpucorelimit"])
    else:
      echo "Error: Invalid value: --cpucorelimit"
      quit()

  if longOptions.containsKey("memorylimit"):
    if longOptions["memorylimit"].len > 0:
      result.memory = true
      result.memoryLimit = parseInt(longOptions["memorylimit"])
    else:
      echo "Error: Invalid value: --memorylimit"
      quit()

proc parseCommandLineOption*(): CmdParseInfo =
  var parsedLine = initOptParser()

  for kind, key, val in parsedLine.getopt():
    case kind:
      of cmdArgument:
        result.argments.add key
      of cmdShortOption:
        let option = CmdOption(key: key, val: val)
        result.shortOptions.add(option)
      of cmdLongOption:
        let option = CmdOption(key: key, val: val)
        result.longOptions.add(option)
      of cmdEnd:
        assert(false)

proc isHelp(args: seq[string], shortOptions: seq[CmdOption]): bool {.inline.} =

  args.len == 1 and shortOptions.len == 1 and shortOptions[0].key == "h"

# leastArg is the number of args for option
proc writeNotEnoughArgError(option: string, leastArg: int) {.inline.} =
  echo fmt "nicoru {option}: requires at least {leastArg} argument."

proc parseImageAndTag(str: string): (string, string) =
  var
    image = ""
    tag = ""

  if str.contains(":"):
    let splited = str.split(":")
    image = splited[0]
    tag = splited[1]
  else:
    image = str
    tag = "latest"

  return (image, tag)

proc cmdPull(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writePullHelpMessage()
  elif args.len == 1:
    writeNotEnoughArgError("pull", 1)
  elif args.len == 2:
    let imageAndTag = parseImageAndTag(args[1])
    pullImage(runtimeSettings, imageAndTag[0], imageAndTag[1])
  else:
    writeCmdLineError($args)

proc cmdImages(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeImageHelpMessage()
  elif args.len == 1:
    runtimeSettings.writeImageList()
  else:
    writeCmdLineError($args)

proc cmdCreate(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeCreateHelpMessage()
  elif args.len == 1:
    writeNotEnoughArgError("create", 1)
  elif args.len > 1:
    let
      command = if args.len > 1: args[2 .. ^1] else: @[""]

      cgroupSettings = initCgroupsSettings(cmdParseInfo.longOptions)
      containerDir = runtimeSettings.baseDir / "containers"

      imageAndTag = parseImageAndTag(args[1])

    discard runtimeSettings.createContainer(
      imageAndTag[0],
      imageAndTag[1],
      containerDir,
      cgroupSettings,
      command)
  else:
    writeCmdLineError($args)

proc isNetworkMode(str: string): bool {.inline.} =
  case str:
    of "bridge", "host", "none":
      return true
    else:
      return false

# TODO: Move
proc isDigit*(seqStr: seq[string]): bool =
  for str in seqStr:
    for c in str:
      if not isDigit(c): return false
  return true

proc parsePublishPort(str: string): PublishPortPair =
  if str.contains(':'):
    let splited = str.split(":")
    if splited.len == 2 and isDigit(splited):
      let
        hPort = parseInt(splited[0])
        cPort = parseInt(splited[1])
      return initPublishPortPair(hPort, cPort)
    else:
      # TODO: Fix this error
      writeCmdLineError(fmt"Failed to parse port: '{str}'")
  else:
    # TODO: Fix this error
    writeCmdLineError(fmt"Failed to parse port: '{str}'")

proc cmdRun(runtimeSettings: var RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeRunHelp()
  elif args.len == 1:
    writeNotEnoughArgError("run", 1)
  else:
    # TODO: Fix: Add validator for options

    let cgroupSettings = initCgroupsSettings(cmdParseInfo.longOptions)

    # Enable/Disable background
    if cmdParseInfo.shortOptions.containsKey("b"):
      runtimeSettings.background = true

    # Enable/Disable seccomp
    if cmdParseInfo.longOptions.containsKey("seccomp"):
      runtimeSettings.seccomp = true

    # Set a path for a seccomp profile
    if cmdParseInfo.longOptions.containsKey("seccomp-profile"):
      if cmdParseInfo.longOptions["seccomp-profile"].len > 0:
        runtimeSettings.seccompProfilePath = cmdParseInfo.longOptions["seccomp-profile"]
      else:
        writeCmdLineError($args)

    # Set a network mode
    var portPair = none(PublishPortPair)
    if cmdParseInfo.longOptions.containsKey("net"):
      let networkMode = cmdParseInfo.longOptions["net"]
      if isNetworkMode(networkMode):
        runtimeSettings.networkMode = cmdParseInfo.longOptions["net"].toNetworkMode

        if cmdParseInfo.longOptions.containsKey("port"):
          if NetworkMode.bridge == runtimeSettings.networkMode:
            portPair = some(parsePublishPort(cmdParseInfo.longOptions["port"]))
          else:
            # TODO: Fix
            writeCmdLineError($args)

    if args.len > 1:
      let
        containersDir = runtimeSettings.baseDir / "containers"

        imageAndTag = parseImageAndTag(args[1])

        image = imageAndTag[0]
        tag = imageAndTag[1]

      if not runtimeSettings.checkImageInLocal(image, tag):
        runtimeSettings.pullImage(image, tag)

      let command = if args.len > 1: args[2 .. ^1] else: @[""]

      runContainer(
        runtimeSettings,
        cgroupSettings,
        image,
        tag,
        containersDir,
        portPair,
        command)

proc cmdPs(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writePsHelpMessage()
  elif args.len == 1:
    let containersDir = runtimeSettings.baseDir / "containers"
    writeAllContainerState(containersDir)
  else:
    writeCmdLineError($args)

proc cmdRm(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeRmHelpMessage()
  elif args.len == 1:
    writeNotEnoughArgError("rm", 1)
  elif args.len == 2:
    let
      containersDir = runtimeSettings.baseDir / "containers"
      containerId = ContainerId(args[1])
    removeContainer(containersDir, containerId)
  else:
    writeCmdLineError($args)

proc cmdRmi(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeRmiHelpMessage()
  elif args.len == 1:
    writeNotEnoughArgError("rmi", 1)
  elif args.len == 2:
    let
      image = args[1]
    runtimeSettings.removeImage(image)
  else:
    writeCmdLineError($args)

proc cmdStart(runtimeSettings: var RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeStartHelp()
  elif args.len == 1:
    writeNotEnoughArgError("start", 1)

  elif args.len == 2:
    let
      containersDir = runtimeSettings.baseDir / "containers"
      containerId = ContainerId(args[1])

    # Set a network mode
    var portPair = none(PublishPortPair)
    if cmdParseInfo.longOptions.containsKey("net"):
      let networkMode = cmdParseInfo.longOptions["net"]
      if isNetworkMode(networkMode):
        runtimeSettings.networkMode = cmdParseInfo.longOptions["net"].toNetworkMode

        if cmdParseInfo.longOptions.containsKey("port"):
          if NetworkMode.bridge == runtimeSettings.networkMode:
            portPair = some(parsePublishPort(cmdParseInfo.longOptions["port"]))
          else:
            # TODO: Fix
            writeCmdLineError($args)

    startContainer(runtimeSettings, portPair, containersDir, containerId)
  else:
    writeCmdLineError($args)

proc cmdLog(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeStartHelp()
  elif args.len == 1:
    writeNotEnoughArgError("log", 1)
  elif args.len == 2:
    let
      containersDir = runtimeSettings.baseDir / "containers"
      containerId = ContainerId(args[1])
    writeContainerLog(containersDir, containerId)
  else:
    writeCmdLineError($args)

proc cmdStop(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let
    args = cmdParseInfo.argments
    shortOptions = cmdParseInfo.shortOptions

  if isHelp(args, shortOptions):
    writeStopHelp()
  elif args.len == 1:
    writeNotEnoughArgError("stop", 1)
  elif args.len == 2:
    let
      containersDir = runtimeSettings.baseDir / "containers"
      containerId = ContainerId(args[1])
      isForce = if shortOptions.containsKey("f"): true else: false
    if isForce:
      forceStopContainer(containersDir, containerId)
    else:
      stopContainer(containersDir, containerId)
  else:
    writeCmdLineError($args)

proc checkArgments*(runtimeSettings: var RuntimeSettings,
                    cmdParseInfo: CmdParseInfo) =

  let longOptions = cmdParseInfo.longOptions
  if longOptions.len > 0 and longOptions.containsKey("debug"):
    runtimeSettings.debug = true

  let args = cmdParseInfo.argments

  case args[0]:
    of "pull":
      cmdPull(runtimeSettings, cmdParseInfo)
    of "images":
      cmdImages(runtimeSettings, cmdParseInfo)
    of "create":
      cmdCreate(runtimeSettings, cmdParseInfo)
    of "run":
      cmdRun(runtimeSettings, cmdParseInfo)
    of "ps":
      cmdPs(runtimeSettings, cmdParseInfo)
    of "rm":
      cmdRm(runtimeSettings, cmdParseInfo)
    of "rmi":
      cmdRmi(runtimeSettings, cmdParseInfo)
    of "start":
      cmdStart(runtimeSettings, cmdParseInfo)
    of "log":
      cmdLog(runtimeSettings, cmdParseInfo)
    of "stop":
      cmdStop(runtimeSettings, cmdParseInfo)
    else:
      writeCmdLineError($args)

proc checkShortOptions*(shortOptions: seq[CmdOption]) =
  if shortOptions.len > 1:
    writeCmdLineError($shortOptions)
  else:
    if shortOptions[0].key == "h":
      writeTopHelp()
    elif shortOptions[0].key == "v":
      writeVersion()
    else:
      writeCmdLineError($shortOptions)

proc checkLongOptions*(longOptions: seq[CmdOption]) =
  if longOptions.len > 0:
    writeCmdLineError($longOptions)
