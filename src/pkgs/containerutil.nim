import std/[os, oids, strformat, json, osproc, posix, options,
            oids]

import image, linuxutils, settings, cgroups

type
  ContainerId* = distinct string

  State* = enum
    running
    stop
    dead

  ContainerInfo* = object
    containerId*: ContainerId
    repository*: string
    tag*: string
    state*: State

  ContainerConfig* = object
    containerId*: ContainerId
    imageId*: string
    repo*: string
    tag*: string
    state*: State
    pid*: Pid
    hostname*: string
    env*: seq[string]
    cmd*: seq[string]
    cgroups*: CgroupsSettgings

proc genContainerId*(): ContainerId {.inline.} = ContainerId($genOid())

proc `$`*(containerId: ContainerId): string {.inline.} = string(containerId)

proc `==`*(a, b: ContainerId): bool {.inline.} = string(a) == string(b)

proc containerConfigPath*(settings: RuntimeSettings,
                          containerId: ContainerId): string {.inline.} =

  return settings.containersPath() / $containerId / "config.json"

proc checkContainerState(json: JsonNode): State =
  for key, item in json["State"]:
    if $item == "true":
      case key:
        of "Running":
          result = State.running
        of "Stop":
          result = State.stop
        of "Dead":
          result = State.dead

# Get all container
proc getAllConrainer*(containersDir: string): seq[ContainerInfo] =
  for containerDir in walkDir(containersDir):
    for p in walkDir(containerDir.path):
      if p.kind == pcFile and p.path == containerDir.path / "config.json":
        let
          json = parseFile(p.path)
          id = json["ContainerId"].getStr
          repo = json["Repository"].getStr
          tag = json["Tag"].getStr
          state = json.checkContainerState
        result.add ContainerInfo(containerId: ContainerId(id),
                                 repository: repo,
                                 tag: tag,
                                 state: state)

proc isExistContainer*(containesrsDir: string, containerId: ContainerId): bool =
  for p in walkDir(containesrsDir):
    let kind = p.kind
    if kind == pcDir:
      let
        pathSplit = splitPath(p.path)
        name = pathSplit.tail
      if name == $containerId:
        return true

proc removeContainer*(containesrsDir: string, containerId: ContainerId) =
  if isExistContainer(containesrsDir, containerId):
    let
      dir = containesrsDir / $containerId

    try:
      removeDir(dir)
    except OSError:
      echo fmt"Error: Remove container failed: {containerId}"

proc initContainerConfigJson*(config: ContainerConfig): JsonNode =
  let cgroupsJson = %* {
    "Cpu": config.cgroups.cpu,
    "Cpu": config.cgroups.cpuLimit,
    "CpuCore": config.cgroups.cpuCore,
    "CpuCoreLimit": config.cgroups.cpuCoreLimit,
    "memory": config.cgroups.memory,
    "memoryLimit": config.cgroups.memoryLimit
  }

  %* { "ContainerId": $config.containerId,
       "Repository": config.repo,
       "Tag": config.tag,
       "State": {"Running": true, "Stop": false, "Dead": false},
       "Pid": config.pid,
       "Hostname": config.hostname,
       "Env": config.env,
       "Cmd": config.cmd,
       "Cgroups": cgroupsJson
     }

proc updateContainerConfigJson*(config: ContainerConfig,
                                configPath: string) =

  var stateJson: JsonNode
  case $config.state:
    of "running":
      stateJson = %* {"Running": false, "Stop": false, "Dead": false}
    of "stop":
      stateJson = %* {"Running": false, "Stop": true, "Dead": false}
    of "dead":
      stateJson = %* {"Running": false, "Stop": false, "Dead": true}

  let cgroupsJson = %* {
    "Cpu": config.cgroups.cpu,
    "Cpu": config.cgroups.cpuLimit,
    "CpuCore": config.cgroups.cpuCore,
    "CpuCoreLimit": config.cgroups.cpuCoreLimit,
    "memory": config.cgroups.memory,
    "memoryLimit": config.cgroups.memoryLimit
  }

  let json = %* { "ContainerId": $config.containerId,
                  "Repository": config.repo,
                  "Tag": config.tag,
                  "State": stateJson,
                  "Pid": config.pid,
                  "Hostname": config.hostname,
                  "Env": config.env,
                  "Cmd": config.cmd,
                  "Cgroups": cgroupsJson
                }

  writeFile(configPath, $json)

proc initContainerConfig*(settings: RuntimeSettings,
                          containerId: ContainerId,
                          imageId, repo, tag: string,
                          cgroups: CgroupsSettgings): ContainerConfig =

  let
    blobPath = settings.blobPath(imageId)
    blob = parseBlob(parseFile(blobPath))

  let
    configPath = settings.containerConfigPath(containerId)

  if not fileExists(configPath):
    let hostname = if blob.config.hostname.len() > 0: blob.config.hostname
                   else: $containerId
    result = ContainerConfig(containerId: ContainerId(containerId),
                             imageId: imageId,
                             repo: repo,
                             tag: tag,
                             state: State.running,
                             hostname: hostname,
                             env: blob.config.env,
                             cmd: blob.config.cmd,
                             cgroups: cgroups)

    let json = initContainerConfigJson(result)
    writeFile(configPath, $json)

proc putHostnameFile*(containerId: ContainerId, path: string) =
  let hostname = ($containerId)[0 .. 12]
  writeFile(path, hostname)

proc setUplowerDir*(settings: RuntimeSettings, layers: JsonNode): string =
  for i in countdown(layers.len - 1, 0):
    let
      blob = layers[i]["digest"].getStr
      id = blob.shortId()
      layerDir = settings.layerPath()

    if dirExists(layerDir / id):
      result &= layerDir / id

      if i  > 0:
        result &= ":"

proc setOverlayfs*(settings: RuntimeSettings, layers: JsonNode, isRootless: bool) =
  createDir("./upper")
  createDir("./work")
  createDir("./merged")

  let lowerdir = settings.setUplowerDir(layers)

  if isRootless:
    # Fuse-overlayfs
    let
      cmd = fmt"fuse-overlayfs -o lowerdir={lowerdir},upper=./upper,workdir=./work ./merged"
    if settings.debug: echo fmt "Debug: exec fuse-overlayfs: {cmd}"

    let exitCode = execShellCmd(cmd)
    if exitCode == 0:
      if settings.debug: echo fmt "Debug: fuse-overlayfs success"
    else:
      echo fmt "Error: Falild to fuse-overlayfs: {exitCode}"
      quit()
  else:
    let
      ovfs_opts = fmt"lowerdir={lowerdir},upperdir=./upper,workdir=./work"
      mergeDir = getCurrentDir() / "merged"

    mount("overlay", mergeDir, "overlay", MS_RELATIME, ovfs_opts)

proc umountOverlayfs*(settings: RuntimeSettings, rootfs: string) =
  if settings.debug: echo fmt "umount rootfs use \"fusermount3 -u {rootfs}\""

  let r = execCmdEx(fmt "fusermount3 -u {rootfs}")
  if r.exitCode == 0:
    echo "Success umount"
  else:
    echo fmt "Error: Failed fusermount3: {r.exitCode}"
    quit()

proc pivotRoot*(new, old: string) =
  mount(new, new, "bind", MS_BIND or MS_REC, "")

  createDir(old)
  linuxutils.pivotRoot(new, old)

  chdir("/")

  #TODO mount resolv.conf

  umount2(old, MNT_DETACH)
  rmdir(old)

proc setupEuidMap() =
  const
    range = 1
    mapUser = 0
  let
    realEuid = $geteuid()
    path = "/proc/self/uid_map"

  echo path
  echo fileExists(path)
  echo "before: " & readFile(path)

  writeFile(path, fmt"{mapUser} {realEuid} {range}")

  echo "after: " & readFile(path)

proc isRootUser*(): bool {.inline.} = geteuid() == 0

proc setupGidMap*() =
  const
    range = 1
    mapUser = 0
  let
    realEuid = $getgid()
    path = "/proc/self/gid_map"

  echo path
  echo fileExists(path)
  echo "before: " & readFile(path)

  writeFile(path, fmt"{mapUser} {realEuid} {range}")

  echo "after: " & readFile(path)

proc isCgroups*(cgroups: CgroupsSettgings): bool {.inline.} =
  cgroups.cpu or cgroups.cpuCore or cgroups.memory

proc getCurrentstate*(stateJson: JsonNode): State {.inline.} =
  for key, item in stateJson:
    if $item == "true":
      case key:
        of "Running":
          return State.running
        of "Stop":
          return State.stop
        of "Dead":
          return State.dead

# Get ContainerConfig from config.json
proc getContainerConfig*(containesrsDir: string,
                         containerId: ContainerId): ContainerConfig =

  if not isExistContainer(containesrsDir, containerId):
    echo fmt "Error: No such container: {containerId}"
    quit()
  else:
    let
      configPath = containesrsDir / $containerId / "config.json"
      json = parseFile(configPath)

    result = ContainerConfig()
    for key, item in json:
      case key:
        of "ContainerId":
          result.containerId = ContainerId(item.getStr)
        of "Repository":
          result.repo = item.getStr
        of "Tag":
          result.tag = item.getStr
        of "State":
          result.state = getCurrentstate(item)
        of "Pid":
          result.pid = Pid(item.getInt)
        of "Hostname":
          result.hostname = item.getStr
        of "Env":
          for item in json[key]:  result.env.add item.getStr
        of "Cmd":
          for item in json[key]:  result.cmd.add item.getStr
        else:
          discard
