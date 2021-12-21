import std/[parseopt, strformat, os, strutils, pegs, options]
import settings, help, container, image, cgroups, network, containerutil

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

proc writeCmdArgError(key: string) =
  echo fmt"Error: Invalid arg: {key}"
  quit()

proc writeCmdOptionError(key: string) =
  echo fmt"Error: Invalid option: {key}"
  quit()

proc setCpuLimit(settings: var CgroupsSettgings, option: CmdOption) =
  if option.val.len > 0:
    settings.cpu = true
    settings.cpuLimit = parseInt(option.val)
  else:
    echo "Error: Invalid value: --cpulimit"
    quit()

proc setCpuCoreLimit(settings: var CgroupsSettgings, option: CmdOption) =
  if option.val.len > 0:
    settings.cpuCore = true
    settings.cpuCoreLimit = parseInt(option.val)
  else:
    echo "Error: Invalid value: --cpucorelimit"
    quit()

proc setMemoryLimit(settings: var CgroupsSettgings, option: CmdOption) =
  if option.val.len > 0:
    settings.memory = true
    settings.memoryLimit = parseInt(option.val)
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
    writeCmdArgError($args)

proc cmdImages(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeImageHelpMessage()
  elif args.len == 1:
    runtimeSettings.writeImageList()
  else:
    writeCmdArgError($args)

proc cmdCreate(runtimeSettings: RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeCreateHelpMessage()
  elif args.len == 1:
    writeNotEnoughArgError("create", 1)
  elif args.len > 1:
    let
      command = if args.len > 1: args[2 .. ^1] else: @[""]

      cgroupSettings = CgroupsSettgings()
      containerDir = runtimeSettings.baseDir / "containers"

      imageAndTag = parseImageAndTag(args[1])

    discard runtimeSettings.createContainer(
      imageAndTag[0],
      imageAndTag[1],
      containerDir,
      cgroupSettings,
      command)
  else:
    writeCmdArgError($args)

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

proc parsePublishPort(str: string): Option[PublishPortPair] =
  if str.contains(':'):
    let splited = str.split(":")
    if splited.len == 2 and isDigit(splited):
      let
        hPort = parseInt(splited[0])
        cPort = parseInt(splited[1])
        portPair = initPublishPortPair(hPort, cPort)
      return some(portPair)
    else:
      none(PublishPortPair)
  else:
    none(PublishPortPair)

proc cmdRun(runtimeSettings: var RuntimeSettings, cmdParseInfo: CmdParseInfo) =
  let args = cmdParseInfo.argments

  if isHelp(args, cmdParseInfo.shortOptions):
    writeRunHelp()
  elif args.len == 1:
    writeNotEnoughArgError("run", 1)
  else:
    # TODO: Fix: Add validator for options

    var
      portPair = none(PublishPortPair)

      cgroupSettings = CgroupsSettgings()

    for shortOption in cmdParseInfo.shortOptions:
      # Enable/Disable background
      if $shortOption == "b":
        runtimeSettings.background = true
      else:
        writeCmdOptionError($shortOption)

    for longOption in cmdParseInfo.longOptions:
      # Enable/Disable Seccomp
      if longOption.key == "seccomp":
        runtimeSettings.seccomp = true

      # Set a path for a seccomp profile
      elif longOption.key == "seccomp-profile":
        if len(longOption.val) > 0:
          runtimeSettings.seccompProfilePath = longOption.val
        else:
          writeCmdOptionError($longOption.key)

      # Set a network mode
      elif longOption.key == "net":
        let networkMode = longOption.val
        if isNetworkMode(networkMode):
          runtimeSettings.networkMode = toNetworkMode(networkMode)

      # Cgroup
      elif longOption.key == "cpulimit":
        cgroupSettings.setCpuLimit(longOption)

      # Cgroup
      elif longOption.key == "cpucorelimit":
        cgroupSettings.setCpuCoreLimit(longOption)

      # Cgroup
      elif longOption.key == "memorylimit":
        cgroupSettings.setMemoryLimit(longOption)

      # Set a publish port
      elif longOption.key == "port":
        if NetworkMode.bridge == runtimeSettings.networkMode:
          let p = parsePublishPort(cmdParseInfo.longOptions["port"])
          if p.isSome:
            portPair = p
          else:
            writeCmdOptionError($longOption.key)
        else:
          writeCmdOptionError($longOption.key)
      else:
        writeCmdOptionError($longOption.key)

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
    writeCmdArgError($args)

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
    writeCmdArgError($args)

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
    writeCmdArgError($args)

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
            let p = parsePublishPort(cmdParseInfo.longOptions["port"])
            if p.isSome:
              portPair = p
            else:
              writeCmdOptionError("port")
          else:
            writeCmdOptionError("port")

    startContainer(runtimeSettings, portPair, containersDir, containerId)
  else:
    writeCmdArgError($args)

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
    writeCmdArgError($args)

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
    writeCmdArgError($args)

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
      writeCmdArgError($args)

proc checkShortOptions*(shortOptions: seq[CmdOption]) =
  if shortOptions.len > 1:
    writeCmdOptionError($shortOptions)
  else:
    if shortOptions[0].key == "h":
      writeTopHelp()
    elif shortOptions[0].key == "v":
      writeVersion()
    else:
      writeCmdOptionError($shortOptions)

proc checkLongOptions*(longOptions: seq[CmdOption]) =
  if longOptions.len > 0:
    writeCmdOptionError($longOptions)
