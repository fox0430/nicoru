import os, oids, strformat, json, osproc, posix, inotify, strutils
import image, linuxutils, settings, cgroups
import seccomp/seccomp

type State = enum
  running
  stop
  dead

type ContainerConfig = object
  containerId: string
  imageId: string
  repo: string
  tag: string
  state: State
  pid: Pid
  hostname: string
  env: seq[string]
  cmd: seq[string]
  cgroups: CgroupsSettgings

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
proc checkExistContainers(containersDir: string): seq[string] =
  for containerDir in walkDir(containersDir):
    for p in walkDir(containerDir.path):
      if p.kind == pcFile and p.path == containerDir.path / "config.json":
        let
          json = parseFile(p.path)
          id = json["ContainerId"].getStr
          repo =json["Repository"].getStr
          tag =json["Tag"].getStr
          state = json.checkContainerState
        result.add(fmt"{id} {repo}:{tag} {state}")

proc writeAllContainerState*(containesrDir: string) =
  let list = checkExistContainers(containesrDir)
  for s in list:
    echo s

proc isExistContainer(containesrsDir, containerId: string): bool =
  for p in walkDir(containesrsDir):
    let kind = p.kind
    if kind == pcDir:
      let
        pathSplit = splitPath(p.path)
        name = pathSplit.tail
      if name == containerId:
        return true

proc removeContainer*(containesrsDir, containerId: string) =
  if isExistContainer(containesrsDir, containerId):
    let
      dir = containesrsDir / containerId

    try:
      removeDir(dir)
    except OSError:
      echo fmt"Error: Remove container failed: {containerId}"

proc initContainerConfigJson(config: ContainerConfig): JsonNode =
  let cgroupsJson = %* {
    "Cpu": config.cgroups.cpu,
    "Cpu": config.cgroups.cpuLimit,
    "CpuCore": config.cgroups.cpuCore,
    "CpuCoreLimit": config.cgroups.cpuCoreLimit,
    "memory": config.cgroups.memory,
    "memoryLimit": config.cgroups.memoryLimit
  }

  %* { "ContainerId": config.containerId,
       "Repository": config.repo,
       "Tag": config.tag,
       "State": {"Running": true, "Stop": false, "Dead": false},
       "Pid": config.pid,
       "Hostname": config.hostname,
       "Env": config.env,
       "Cmd": config.cmd,
       "Cgroups": cgroupsJson
     }

proc updateContainerConfigJson(config: ContainerConfig,
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

  let json = %* { "ContainerId": config.containerId,
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

proc initContainerConfig(settings: RuntimeSettings,
                         imageId, containerId, repo, tag: string,
                         cgroups: CgroupsSettgings): ContainerConfig =

  let
    blobPath = settings.blobPath(imageId)
    blob = parseBlob(parseFile(blobPath))

  let
    configPath = settings.containerConfigPath(containerId)

  if not fileExists(configPath):
    let hostname = if blob.config.hostname.len() > 0: blob.config.hostname
                   else: containerId
    result = ContainerConfig(containerId: containerId,
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

proc putHostnameFile(containerId, path: string) =
  let hostname = containerId[0 .. 12]
  writeFile(path, hostname)

proc setUplowerDir(settings: RuntimeSettings, layers: JsonNode): string =
  for i in 0 ..< layers.len:
    let
      blob = layers[i]["digest"].getStr
      id = blob.shortId()
      layerDir = settings.layerPath()

    if dirExists(layerDir / id):
      result &= layerDir / id

      if i  < layers.len - 1:
        result &= ":"

proc setOverlayfs(settings: RuntimeSettings, layers: JsonNode, isRootless: bool) =
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

proc umountOverlayfs(settings: RuntimeSettings, rootfs: string) =
  if settings.debug: echo fmt "umount rootfs use \"fusermount3 -u {rootfs}\""

  let r = execCmdEx(fmt "fusermount3 -u {rootfs}")
  if r.exitCode == 0:
    echo "Success umount"
  else:
    echo fmt "Error: Failed fusermount3: {r.exitCode}"
    quit()

proc pivotRoot(new, old: string) =
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

proc setupGidMap() =
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

proc createContainer*(settings: RuntimeSettings,
                      repo, tag, containersDir: string,
                      cgroups: CgroupsSettgings,
                      command: seq[string]): ContainerConfig  =

  let containerId = $genOid()

  echo fmt"Create container: {containerId}"

  createDir(containersDir)

  let
    imagesDir = settings.imagesPath()
    dbPath = settings.databasePath()
    imageId = settings.getImageIdFromLocal(repo, tag)

  let cDir = containersDir / containerId
  if not dirExists(cDir):
    createDir(cDir)

  result = settings.initContainerConfig(
                               imageId,
                               containerId,
                               repo,
                               tag,
                               cgroups)

  if command.len > 0 and command[0].len > 0:
    result.cmd = command

  let hostnamePath = cDir / "hostname"
  putHostnameFile(containerId, hostnamePath)

  setCurrentDir(cDir)

  let
    imgHashPath = settings.imagesHashPath()
  if fileExists(imgHashPath / imageId[7 .. ^1]):
    let
      manifestJson = parseFile(imgHashPath / imageId[7 .. ^1])

proc exitContainer(config: var ContainerConfig,
                   state: State,
                   configPath: string) =

  # exit pivot_root
  chroot(".")

  config.state = state
  config.updateContainerConfigJson(configPath)

proc isCgroups(cgroups: CgroupsSettgings): bool {.inline.} =
  cgroups.cpu or cgroups.cpuCore or cgroups.memory

proc setEnv(envs: seq[string]) =
  for env in envs:
    let
      envSplit  = env.split("=")
    if envSplit.len != 2:
      exception(fmt "Error: config.env is invalid {envs}")

    let
      name = envSplit[0]
      value = envSplit[1]
    setenv(name, value, 1)

proc execContainer*(settings: RuntimeSettings,
                    config: var ContainerConfig,
                    containersDir: string) =

  let
    repo = config.repo
    tag = config.tag
    dbPath = settings.imagesPath()
    imageId = config.imageId

  # TODO: Fix name
  let
    containerId = config.containerId
    containerDir = containersDir / containerId

    parentPid = getpid()
    firstForkPid = fork()

  if getpid() != parentPid:

    const flags = CLONE_NEWUTS or CLONE_NEWIPC or CLONE_NEWPID or CLONE_NEWNS
    unshare(flags)
    let secondForkPid = fork()

    if getpid() == 1:
      let
        imageDir = settings.imagesHashPath()
        manifestJson = parseFile(settings.imagesHashPath(imageId))

      mount("/", "/", "none", MS_PRIVATE or MS_REC)

      const isRootless = false
      settings.setOverlayfs(manifestJson["layers"], isRootless)

      let rootfs = containerDir / "merged"
      setCurrentDir(rootfs)

      if settings.background:
        discard setsid()

        discard umask(0)

        block:
          # Redirect std I/O and error
          let logFilePath = containerDir / "logfile"
          var sinp, sout, serr: File
          if not sinp.open("/dev/null", fmRead):
            quit(1)
          if not sout.open(logFilePath, fmAppend):
            quit(1)
          if not serr.open(logFilePath, fmAppend):
            quit(1)

          if settings.background:
            if dup2(getFileHandle(sinp), getFileHandle(stdin)) < 0:
              quit(1)
            if dup2(getFileHandle(sout), getFileHandle(stdout)) < 0:
              quit(1)
            if dup2(getFileHandle(serr), getFileHandle(stderr)) < 0:
              quit(1)

      block:
        # Get /etc/resolv.conf
        let resolvConf = if fileExists("/etc/resolv.conf"):
                           readFile("/etc/resolv.conf")
                         else:
                           ""

        # Chnage root directory
        umount2("/proc", MNT_DETACH)
        let
          newRoot = "."
          oldRoot = ".old"
        pivotRoot(newRoot, oldRoot)

        # Remount
        createDir("/dev")
        mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID or MS_RELATIME)

        createDir("/proc")
        mount("proc", "/proc", "proc", 0)

        createDir("/sys")
        mount("sysfs", "/sys", "sysfs", 0)

        createDir("/tmp")
        mount("none", "/tmp", "tmpfs", 0)

        if resolvConf.len > 0:
          writeFile("/etc/resolv.conf", resolvConf)

      setHostname(config.hostname)

      setEnv(config.env)

      # TODO: Fix
      let ctx = seccomp_ctx(Allow)
      ctx.add_rule(Kill, "reboot")
      ctx.load()

      try:
        execvp(config.cmd)
      except:
        echo "Error execute command failed"
        quit(1)
    else:
      if config.cgroups.isCgroups:
        config.cgroups.setupCgroups(secondForkPid)

      writeFile(containerDir / "pid", $secondForkPid)

      # TODO: Delete
      if not settings.background:
        var status: cint
        discard waitpid(secondForkPid, status, WUNTRACED)
  else:
    block:
      let
        fd = inotify_init()
        watch = fd.inotify_add_watch(cstring(containerDir), IN_CREATE)
      while not fileExists(containerDir / "pid"):
        var buffer = alloc(INOTIFY_EVENT_SZIE)
        discard fd.read(buffer, INOTIFY_EVENT_SZIE)

    # This pid is secondForkPid
    let pid = readFile(containerDir / "pid")

    var status: cint
    discard waitpid(firstForkPid, status, WUNTRACED)

    let configPath = "config.json"
    if WIFEXITED(status):
      config.exitContainer(State.stop, configPath)
    else:
      config.exitContainer(State.dead, configPath)

proc isRootUser(): bool {.inline.} = geteuid() == 0

proc runContainer*(settings: RuntimeSettings,
                   cgroupSettings: CgroupsSettgings,
                   repo, tag, containersDir: string,
                   command: seq[string]) =

  var config = settings.createContainer(
                               repo,
                               tag,
                               containersDir,
                               cgroupSettings,
                               command)

  if isRootUser():
    execContainer(settings, config, containersDir)
  else:
    # TODO: Add Root-less mode
    echo "Error: You need to be root to run nicoru."

proc getCurrentstate(stateJson: JsonNode): State {.inline.} =
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
proc getContainerConfig(containesrsDir, containerId: string): ContainerConfig =
  if not isExistContainer(containesrsDir, containerId):
    echo fmt "Error: No such container: {containerId}"
    quit()
  else:
    let
      configPath = containesrsDir / containerId / "config.json"
      json = parseFile(configPath)

    result = ContainerConfig()
    for key, item in json:
      case key:
        of "ContainerId":
          result.containerId = item.getStr
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

proc startContainer*(settings: RuntimeSettings,
                     containersDir, containerId: string) =

  var config = getContainerConfig(containersDir, containerId)

  let imageId = settings.getImageIdFromLocal(config.repo, config.tag)
  if imageId.len > 0:
    config.imageId = imageId
  else:
    echo "Error: Not found image in local"
    quit()

  if dirExists(containersDir / config.containerId):
    chdir(containersDir / config.containerId)
  else:
    echo fmt "Error: No such container: {config.containerId}"
    quit()

  if isRootUser():
    # Normal mode
    execContainer(settings, config, containersDir)
  else:
    # TODO: Add Rootless mode
    echo "Error: You need to be root to run nicoru."

proc writeContainerLog*(containersDir, containerId: string) =
  if isExistContainer(containersDir, containerId):
    let
      containerDir = containersDir / containerId
      logFilePath = containerDir / "logfile"
    echo readFile(logFilePath)

proc getContainerPid(containersDir, containerId: string): Pid =
  let
    path = containersDir / containerId / "pid"
    pidStr = readFile(path)

  result = Pid(pidStr.parseInt)

proc stopContainer*(containersDir, containerId: string) =
  let pid = getContainerPid(containersDir, containerId)

  if kill(pid, SIGTERM) != 0:
    raiseOSError(osLastError())
  else:
    echo fmt "Stpod container: {containerId}"

proc forceStopContainer*(containersDir, containerId: string) =
  let pid = getContainerPid(containersDir, containerId)

  if kill(pid, SIGSTOP) != 0:
    raiseOSError(osLastError())
  else:
    echo fmt "Stpod container: {containerId}"
