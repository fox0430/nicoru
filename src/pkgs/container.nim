import std/[os, strformat, json, posix, inotify, strutils, options, linux]
import image, linuxutils, settings, cgroups, seccomputils, network, containerutil

proc writeAllContainerState*(containesrDir: string) =
  let list = getAllConrainer(containesrDir)

  const CONTAINER_ID_LEN = 24
  var firstLine = "CONTAINER ID"
  firstLine &= " ".repeat(CONTAINER_ID_LEN - "CONTAINER_ID".len + 2)

  var
    repoMaxLen = "REPOSITORY".len
    tagMaxLen = "TAG".len

  for item in list:
    let repo = item.repository
    if repo.len > repoMaxLen and repo.len > "REPOSITORY".len:
      repoMaxLen = item.repository.len

    let tag = item.tag
    if tag.len > tagMaxLen and tag.len > "TAG".len:
      tagMaxLen = item.tag.len

  firstLine &= "REPOSITORY" & " ".repeat(repoMaxLen - "REPOSITORY".len + 2)
  firstLine &= "TAG" & " ".repeat(tagMaxLen - "TAG".len + 2)
  firstLine &= "STATE"

  # Show container list
  echo firstLine
  for c in list:
    let
      space1 = "  "
      space2 = " ".repeat(repoMaxLen - c.repository.len + 2)
      space3 = " ".repeat(tagMaxLen - c.tag.len + 2)
    echo $c.containerId & space1 &
         c.repository & space2 &
         c.tag & space3 &
         $c.state

proc createContainer*(settings: RuntimeSettings,
                      repo, tag, containersDir: string,
                      cgroups: CgroupsSettgings,
                      command: seq[string]): ContainerConfig  =

  let containerId = genContainerId()

  echo fmt"Create container: {containerId}"

  createDir(containersDir)

  let imageId = settings.getImageIdFromLocal(repo, tag)

  let cDir = containersDir / $containerId
  if not dirExists(cDir):
    createDir(cDir)

  result = settings.initContainerConfig(
    containerId,
    imageId,
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
                   network: var Network,
                   settings: RuntimeSettings,
                   state: State,
                   bridgeName, configPath: string) =

  config.state = state
  config.updateContainerConfigJson(configPath)

  if NetworkMode.bridge == settings.networkMode:
    let
      bridge = network.bridges.getBridge(bridgeName)
      vethPair = bridge.getVethPair(config.containerId)

    if vethPair.publishPort.isSome and network.defautHostNic.isSome:
      removeContainerIptablesRule(vethPair,
                                  vethPair.publishPort.get,
                                  network.defautHostNic.get,
                                  bridge.natIpAddr.get)

  network.removeIpFromNetworkInterface(bridgeName, config.containerId)
  network.updateNetworkState(networkStatePath())

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

proc createNamespaces(networkMode: NetworkMode) =
  var flags = CLONE_NEWUTS or CLONE_NEWIPC or CLONE_NEWPID or CLONE_NEWNS

  case networkMode:
    of NetworkMode.none, NetworkMode.bridge:
      flags = flags or CLONE_NEWNET
    else:
      discard

  unshare(flags)

proc execContainer*(settings: RuntimeSettings,
                    config: var ContainerConfig,
                    portPair: Option[PublishPortPair],
                    containersDir: string) =

  let
    containerId = config.containerId

    isBridgeMode = NetworkMode.bridge == settings.networkMode

  while isLockedNetworkStateFile(networkStatePath()):
    sleep 500

  lockNetworkStatefile(networkStatePath())

  let
    isLocked = isLockedNetworkStateFile(networkStatePath())
    currentNetworkStatePath = if isLocked: lockedNetworkStatePath()
                              else: networkStatePath()

  var network = initNicoruNetwork(currentNetworkStatePath, isBridgeMode)

  if isBridgeMode:
    let index = network.currentBridgeIndex

    network.bridges[index].addNewNetworkInterface(
      containerId,
      baseVethName(),
      baseBrVethName(),
      isBridgeMode)

    if portPair.isSome:
      network.bridges[index].vethPairs[^1].setPublishPortPair(portPair.get)

  network.updateNetworkState(currentNetworkStatePath)
  unlockNetworkStatefile(networkStatePath())

  let
    bridge = network.bridges[network.currentBridgeIndex]
    bridgeName = bridge.name

  # Create a user defined bridge
  if defaultBridgeName() != bridge.name:
    if not bridgeExists(bridgeName):
      createBridge(network.bridges[^1])

  if isBridgeMode:
    if network.defautHostNic.isSome:
      setNat(network.defautHostNic.get, bridge.natIpAddr.get)

    let vethPair = bridge.vethPairs[^1]

    createVethPair(vethPair.getBrVethName.get, vethPair.getVethName.get)

    if vethPair.publishPort.isSome and network.defautHostNic.isSome:
      setPortForward(vethPair.getVethIpAddr,
                     vethPair.publishPort.get,
                     network.defautHostNic.get)

  let
    imageId = config.imageId

    # TODO: Fix name
    containerDir = containersDir / $containerId

    parentPid = getpid()
    firstForkPid = fork()

  if getpid() != parentPid:

    # Create Linux namespaces using unshare syscall
    createNamespaces(settings.networkMode)

    let secondForkPid = fork()

    if getpid() == 1:
      let manifestJson = parseFile(settings.imagesHashPath(imageId))

      # Set up container network
      if isBridgeMode:
        bridge.vethPairs[^1].initContainerNetwork(bridge.getRtVethIpAddr)

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
        containerutil.pivotRoot(newRoot, oldRoot)

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

      # seccomp
      if settings.seccomp:
        let path = if settings.seccompProfilePath.len > 0:
                     settings.seccompProfilePath
                    else:
                      ""
        try:
          setSysCallFiler(path)
        except:
          echo "Failed to init Seccomp"
          writeFile(containerDir / "pid", "-1")
          quit(1)

      try:
        execvp(config.cmd)
      except:
        writeFile(containerDir / "pid", "-1")
        echo "Error execute command failed"
        quit(1)
    else:
      if config.cgroups.isCgroups:
        try:
          config.cgroups.setupCgroups(secondForkPid)
        except:
          echo "Failed to init Cgroup"
          writeFile(containerDir / "pid", "-1")
          quit(1)

      writeFile(containerDir / "pid", $secondForkPid)

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
    if pid == "-1":
      let configPath = "config.json"
      config.exitContainer(network, settings, State.dead, bridgeName, configPath)
      echo "Failed to start a container"
      quit(1)

    if isBridgeMode:
      # Add network interface
      addInterfaceToContainer(bridge.vethPairs[^1], pid.toPid)

      connectVethToBridge(bridge.vethPairs[^1].getBrVethName.get, bridgeName)

    # TODO: Delete
    var status: cint
    discard waitpid(firstForkPid, status, WUNTRACED)

    let configPath = "config.json"
    if WIFEXITED(status):
      config.exitContainer(network, settings, State.stop, bridgeName, configPath)
    else:
      config.exitContainer(network, settings, State.dead, bridgeName, configPath)

proc runContainer*(settings: RuntimeSettings,
                   cgroupSettings: CgroupsSettgings,
                   repo, tag, containersDir: string,
                   portPair: Option[PublishPortPair],
                   command: seq[string]) =

  var config = settings.createContainer(
    repo,
    tag,
    containersDir,
    cgroupSettings,
    command)

  if isRootUser():
    execContainer(settings, config, portPair, containersDir)
  else:
    # TODO: Add Root-less mode
    echo "Error: You need to be root to run nicoru."

proc startContainer*(settings: RuntimeSettings,
                     portPair: Option[PublishPortPair],
                     containersDir:string,
                     containerId: ContainerId) =

  var config = getContainerConfig(containersDir, containerId)

  let imageId = settings.getImageIdFromLocal(config.repo, config.tag)
  if imageId.len > 0:
    config.imageId = imageId
  else:
    echo "Error: Not found image in local"
    quit()

  if dirExists(containersDir / $config.containerId):
    chdir(containersDir / $config.containerId)
  else:
    echo fmt "Error: No such container: {config.containerId}"
    quit()

  if isRootUser():
    # Normal mode
    execContainer(settings, config, portPair, containersDir)
  else:
    # TODO: Add Rootless mode
    echo "Error: You need to be root to run nicoru."

proc writeContainerLog*(containersDir: string, containerId: ContainerId) =
  if isExistContainer(containersDir, containerId):
    let
      containerDir = containersDir / $containerId
      logFilePath = containerDir / "logfile"
    echo readFile(logFilePath)

proc getContainerPid(containersDir: string, containerId: ContainerId): Pid =
  let
    path = containersDir / $containerId / "pid"
    pidStr = readFile(path)

  result = Pid(pidStr.parseInt)

proc stopContainer*(containersDir: string, containerId: ContainerId) =
  let pid = getContainerPid(containersDir, containerId)

  if kill(pid, SIGTERM) != 0:
    raiseOSError(osLastError())
  else:
    echo fmt "Stpod container: {containerId}"

proc forceStopContainer*(containersDir: string, containerId: ContainerId) =
  let pid = getContainerPid(containersDir, containerId)

  if kill(pid, SIGSTOP) != 0:
    raiseOSError(osLastError())
  else:
    echo fmt "Stpod container: {containerId}"
