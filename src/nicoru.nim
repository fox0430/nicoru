import parseopt, strformat, os, strutils, pegs
import pkgs/[image, container, settings, cgroups, help]

type CmdOption = object
  key: string
  val: string

type CmdParseInfo = object
  argments: seq[string]
  shortOptions: seq[CmdOption]
  longOptions: seq[CmdOption]

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
    nimblePath = currentSourcePath.parentDir() / "../nicoru.nimble"
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

proc cmdPull(runtimeSettings: RuntimeSettings, repo, tag: string) {.inline.} =
  pullImage(runtimeSettings, repo, tag)

proc cmdPull(runtimeSettings: RuntimeSettings, repo: string) {.inline.} =
  const tag = "latest"
  pullImage(runtimeSettings, repo, tag)

proc cmdImages(runtimeSettings: RuntimeSettings) {.inline.} =
  writeImageList(runtimeSettings.baseDir)

proc cmdCreate(runtimeSettings: RuntimeSettings,
               cgroupSettings: CgroupsSettgings,
               repo, tag: string,
               command: seq[string]) {.inline.} =

  let imagesDir = runtimeSettings.baseDir / "images"

  let containerDir = runtimeSettings.baseDir / "containers"

  if not checkImageInLocal(repo, tag, imagesDir, runtimeSettings.debug):
    pullImage(runtimeSettings, repo, tag)

  let containerId = createContainer(repo, tag, runtimeSettings.baseDir, containerDir,
                                    cgroupSettings,
                                    runtimeSettings.debug,
                                    command)
  echo fmt"{containerId} created"

proc cmdCreate(runtimeSettings: RuntimeSettings,
               cgroupSettings: CgroupsSettgings,
               repo, tag: string) {.inline.} =
  # TODO: Fix
  const command = @["/bin/sh"]

  cmdCreate(runtimeSettings, cgroupSettings, repo, tag, command)

proc cmdCreate(runtimeSettings: RuntimeSettings,
               cgroupSettings: CgroupsSettgings,
               repo: string) {.inline.} =
  const
    # TODO: Fix
    command = @["/bin/sh"]
    # TODO: Fix
    tag = "latest"

  cmdCreate(runtimeSettings, cgroupSettings, repo, tag, command)

proc cmdRun(runtimeSettings: RuntimeSettings,
            cgroupSettings: CgroupsSettgings,
            repo: string,
            command: seq[string]) {.inline.} =

  let
    imagesDir = runtimeSettings.baseDir / "images"
    containersDir = runtimeSettings.baseDir / "containers"

    repoSplit = repo.split(":")
    repo = repoSplit[0]
    tag = if repoSplit.len > 1: repoSplit[1] else: "latest"

  if not checkImageInLocal(repo, tag, imagesDir, runtimeSettings.debug):
    pullImage(runtimeSettings, repo, tag)

  runContainer(runtimeSettings, cgroupSettings, repo, tag, containersDir, command)

proc cmdRun(runtimeSettings: RuntimeSettings,
            cgroupSettings: CgroupsSettgings,
            repo: string) {.inline.} =

  # TODO: Fix
  const command = @["/bin/sh"]

  cmdRun(runtimeSettings, cgroupSettings, repo, command)

proc cmdPs(runtimeSettings: RuntimeSettings) {.inline.} =
  let
    containersDir = runtimeSettings.baseDir / "containers"
  writeAllContainerState(containersDir)

proc cmdRm(runtimeSettings: RuntimeSettings, containerId: string) {.inline.} =
  let containersDir = runtimeSettings.baseDir / "containers"
  removeContainer(containersDir, containerId)

proc cmdRmi(runtimeSettings: RuntimeSettings, item: string) {.inline.} =
  let
    imagesDir = runtimeSettings.baseDir / "images"
    layerDir = runtimeSettings.baseDir / "layer"
  removeImage(imagesDir, layerDir, item)

proc cmdStart(runtimeSettings: RuntimeSettings, containerId: string) {.inline.} =
  let containersDir = runtimeSettings.baseDir / "containers"
  startContainer(runtimeSettings, containersDir, containerId)

proc cmdLog(runtimeSettings: RuntimeSettings, containerId: string) {.inline.} =
  let containersDir = runtimeSettings.baseDir / "containers"
  writeContainerLog(containersDir, containerId)

proc cmdStop(runtimeSettings: RuntimeSettings,
             containerId: string, force: bool) {.inline.} =

  let containersDir = runtimeSettings.baseDir / "containers"
  if force:
    forceStopContainer(containersDir, containerId)
  else:
    stopContainer(containersDir, containerId)

proc initCgroupsSettings(longOptions: seq[CmdOption]): CgroupsSettgings =
  result = CgroupsSettgings()

  if longOptions.containsKey("cpulimit"):
    result.cpu = true
    result.cpuLimit = parseInt(longOptions["cpulimit"])

  if longOptions.containsKey("cpucorelimit"):
    result.cpuCore = true
    result.cpuCoreLimit = parseInt(longOptions["cpucorelimit"])

  if longOptions.containsKey("memorylimit"):
    result.memory = true
    result.memoryLimit = parseInt(longOptions["memorylimit"])

proc isHelp(args: seq[string],
            shortOptions: seq[CmdOption]): bool {.inline.} =

  args.len == 1 and shortOptions.len == 1 and shortOptions[0].key == "h"

proc checkArgments(runtimeSettings: var RuntimeSettings,
                   cmdParseInfo: CmdParseInfo) =

  let
    longOptions = cmdParseInfo.longOptions
    shortOptions = cmdParseInfo.shortOptions
  if longOptions.len > 0 and longOptions.containsKey("debug"):
    runtimeSettings.debug = true

  let args = cmdParseInfo.argments

  case args[0]:
    of "pull":
      if isHelp(args, shortOptions): writePullHelpMessage()
      elif args.len == 2: cmdPull(runtimeSettings, args[1])
      elif args.len == 3: cmdPull(runtimeSettings, args[1], args[2])
      else: writeCmdLineError($args)
    of "images":
      if isHelp(args, shortOptions): writeImageHelpMessage()
      elif args.len == 1: cmdImages(runtimeSettings)
      else: writeCmdLineError($args)
    of "create":
      if isHelp(args, shortOptions): writeCreateHelpMessage()
      else:
        let cgroupSettings = initCgroupsSettings(longOptions)
        if args.len == 2: cmdCreate(runtimeSettings, cgroupSettings, args[1])
        elif args.len == 3: cmdCreate(runtimeSettings, cgroupSettings, args[1], args[2])
        else: writeCmdLineError($args)
    of "run":
      if isHelp(args, shortOptions): writeRunHelp()
      else:
        let cgroupSettings = initCgroupsSettings(longOptions)
        if shortOptions.containsKey("b"):
          runtimeSettings.background = true
        if args.len == 2: cmdRun(runtimeSettings, cgroupSettings, args[1])
        else: cmdRun(runtimeSettings, cgroupSettings, args[1], args[2 .. ^1])
    of "ps":
      if isHelp(args, shortOptions): writePsHelpMessage()
      elif args.len == 1: cmdPs(runtimeSettings)
    of "rm":
      if isHelp(args, shortOptions): writeRmHelpMessage()
      elif args.len == 2: cmdRm(runtimeSettings, args[1])
    of "rmi":
      if isHelp(args, shortOptions): writeRmiHelpMessage()
      elif args.len == 2: cmdRmi(runtimeSettings, args[1])
    of "start":
      if isHelp(args, shortOptions): writeStartHelp()
      elif args.len == 2: cmdStart(runtimeSettings, args[1])
    of "log":
      if isHelp(args, shortOptions): writeLogHelp()
      elif args.len == 2: cmdLog(runtimeSettings, args[1])
    of "stop":
      if isHelp(args, shortOptions): writeStopHelp()
      elif args.len == 2:
        let force = if shortOptions.containsKey("f"): true else: false
        cmdStop(runtimeSettings, args[1], force)

      else: writeCmdLineError($args)
    else:
      writeCmdLineError($args)

proc checkShortOptions(shortOptions: seq[CmdOption]) =
  if shortOptions.len > 1:
    writeCmdLineError($shortOptions)
  else:
    if shortOptions[0].key == "h":
      writeTopHelp()
    elif shortOptions[0].key == "v":
      writeVersion()
    else:
      writeCmdLineError($shortOptions)

proc checkLongOptions(longOptions: seq[CmdOption]) =
  if longOptions.len > 0:
    writeCmdLineError($longOptions)

when isMainModule:
  var runtimeSettings = initRuntimeSetting()
  let cmdParseInfo = parseCommandLineOption()

  if cmdParseInfo.argments.len > 0:
    checkArgments(runtimeSettings, cmdParseInfo)
  elif cmdParseInfo.shortOptions.len > 0:
    checkShortOptions(cmdParseInfo.shortOptions)
  else:
    checkLongOptions(cmdParseInfo.longOptions)
