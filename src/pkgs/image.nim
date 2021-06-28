import os, strformat, httpclient, json, asyncdispatch, strutils, osproc
import settings

type ImageInfo = object
  repo: string
  tag: string

type ImageConfig* = object
  hostname*: string
  domainname*: string
  user*: string
  attachStdin*: bool
  attachStdout*: bool
  attachStderr*: bool
  tty*: bool
  openStdin*: bool
  stdinOnce*: bool
  env*: seq[string]
  cmd*: seq[string]
  image*: string
  # TODO*: Check type
  volumes*: string
  workingDir*: string
  # TODO*: Check type
  entrypoint*: string
  # TODO*: Check type
  onBuild*: string
  # TODO*: Check type
  labels*: string

type ContainerConfig = object
  hostname*: string
  domainname*: string
  user*: string
  attachStdin*: bool
  attachStdout*: bool
  attachStderr*: bool
  tty*: bool
  openStdin*: bool
  stdinOnce*: bool
  env*: seq[string]
  # TODO*: Check type
  cmd*: seq[string]
  image*: string
  # TODO*: Check type
  volumes*: string
  workingDir*: string
  # TODO*: Check type
  entrypoint*: string
  # TODO*: Check type
  onBuild*: string
  # TODO*: Check type
  labels*: string

type ImageRootFs = object
  `type`*: string
  diffIds*: seq[string]

type Blob = object
  architecture*: string
  config*: ImageConfig
  container*: string
  containerConfig*: ContainerConfig
  created*: string
  dockerVersion*: string
  # TODO*: Check type
  history*: seq[string]
  os*: string
  rootfs*: ImageRootFs

proc extractTar(archive, directory: string) =
  let currentDir = getCurrentDir()

  createDir(directory)
  setCurrentDir(directory)
  discard execProcess(fmt"tar -xvzf {archive}")

  setCurrentDir(currentDir)

# Image list in local (json)
proc updateImageDb(settings: RuntimeSettings, repo, tag, imageId: string) =
  let dbPath = settings.databasePath()

  if fileExists(dbPath):
    let json = %* {fmt"{repo}:{tag}": imageId}
    var dbJson = parseFile(dbPath)
    dbJson["Repository"][repo] = json
    writeFile(dbPath, $dbJson)
  else:
    let json = %* {"Repository": {repo: {fmt"{repo}:{tag}": imageId}}}
    writeFile(dbPath, $json)

  if settings.debug: echo "Debug: Updated imagedb"

# Get token for docker hub
proc getToken*(repo, tag: string): string =
  let
    client = newHttpClient()
    url = fmt"https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/{repo}:pull"
  client.headers = newHttpHeaders({ "Content-Type": "application/json" })

  let res = client.get(url)

  if res.status != "200 OK":
    echo "Error: Failed to get token"
    quit(1)
  else:
    let token = $(res.body.parseJson)["token"]
    # Delete semicolon
    result = token[1 .. token.high - 1]

# Get docker images manifest
proc getManifest(repo, tag, token, imagePath: string, debug: bool) =
  if fileExists(imagePath): return

  let
    client = newHttpClient()
    url = fmt"https://registry-1.docker.io/v2/library/{repo}/manifests/{tag}"

  client.headers = newHttpHeaders({"Accept": "application/vnd.docker.distribution.manifest.v2+json",
                                   "Authorization": fmt"Bearer {token}"})

  let res = client.get(url)

  if res.status != "200 OK":
    echo fmt"Error Status:{res.status}: Failed to get manifest:"
    quit(1)
  else:
    writeFile(imagePath, res.body)
    if debug: echo fmt"Debug: Download manifest success"

proc getConfig(repo, tag, token, imageId, blobsDir: string, debug: bool) {.async.} =
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"Authorization": fmt"Bearer {token}"})

  let
    url = fmt"https://registry-1.docker.io/v2/library/{repo}/blobs/{imageId}"
    filename = imageId[7 .. ^1]

  if not fileExists(blobsDir / filename):
    # Download blob
    await client.downloadFile(url, blobsDir / filename)
    if debug: echo fmt"Debug: Download blob success: {imageId}"

# Get all layer
proc getLayer(repo, tag, token, layerDir, manifestPath: string,
              debug: bool) {.async.} =

  let
    manifest = parseFile(manifestPath)
    client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
                                   "Authorization": fmt"Bearer {token}"})

  echo fmt"Pulling image"

  for item in manifest["layers"].items:
    let
      imageId = item["digest"].getStr
      url = fmt"https://registry-1.docker.io/v2/library/{repo}/blobs/{imageId}"
      id = imageId[7 .. ^1]
      filename = fmt"{id}.tar.gz"
      downloadFilePath = layerDir / filename

    if not fileExists(downloadFilePath):
      echo fmt "Download layer: {id}"
      # TODO: Add progress bar
      # Download image layer
      await client.downloadFile(url, downloadFilePath)
      echo fmt"Download layer success: {id}"

      # Check if 0 bytes image layer
      if getFileSize(downloadFilePath) > 32:
        let layerPath = layerDir / id
        extractTar(downloadFilePath, layerPath)

        # Remove downloaded layer archive
        if fileExists(downloadFilePath):
          removeFile(downloadFilePath)

# Get image id from docker hub
proc getImageIdFromDockerHub*(repo, tag, token: string, debug: bool): string =
  let
    client = newHttpClient()
    url = fmt"https://registry-1.docker.io/v2/library/{repo}/manifests/{tag}"
  client.headers = newHttpHeaders({
    "Accept": "application/vnd.docker.distribution.manifest.v2+json",
    "Authorization": fmt"Bearer {token}"})

  let res = client.get(url)
  if res.status != "200 OK":
    echo fmt"Error Status:{res.status}: Failed to get image id:"
    quit(1)
  else:
    let manifest = parseJson(res.body)
    result = manifest["config"]["digest"].getStr
    if debug: echo fmt"Debug: Image Id: {result}"

# Get image id from local
proc getImageIdFromLocal*(settings: RuntimeSettings, repo, tag: string): string =
  let dbPath = settings.databasePath()
  if not fileExists(dbPath): return

  let dbJson = parseFile(dbPath)

  result = dbJson["Repository"][repo][fmt"{repo}:{tag}"].getStr
  if settings.debug: echo fmt"Debug: Get image id from local: {result}"

# Get config.json (OCI bundle)
proc getConfigV2*(repo, tag, imageId, token: string, debug: bool): JsonNode =
  let
    client = newHttpClient()
    url = fmt"https://registry-1.docker.io/v2/library/{repo}/blobs/{imageId}"
  client.headers = newHttpHeaders({"Authorization": fmt"Bearer {token}"})

  let res = client.get(url)
  if debug: echo fmt"Debug: get configv2.json from docker hub: {url}"

  if res.status != "200 OK":
    echo fmt"Error Status:{res.status}: Failed to get image id:"
    quit(1)
  else:
    result = parseJson(res.body)
    if debug: echo fmt"Debug: Get configv2.json success"

# Pulling docker images from docker hub
proc pullImage*(settings: RuntimeSettings, repo, tag: string) =
  let imageDir = settings.imagesPath()

  if settings.debug: echo fmt"Debug: Pulling image: {repo}:{tag}"

  let token = getToken(repo, tag)
  if settings.debug: echo fmt"Debug: Get token: {token}"

  let imageId = getImageIdFromDockerHub(repo, tag, token, settings.debug)

  block:
    createDir(imageDir / "sha256")
    # Delete string "sha256:"
    let manifestPath = imageDir / "sha256" / imageId[7 .. ^1]
    getManifest(repo, tag, token, manifestPath, settings.debug)

    let blobsDir = settings.baseDir / "blobs"
    createDir(blobsDir)
    waitFor getConfig(repo, tag, token, imageId, blobsDir, settings.debug)

    let layerDir = settings.baseDir / "layer"
    createDir(layerDir)

    waitFor getLayer(repo, tag, token, layerDir, manifestPath, settings.debug)

  settings.updateImageDb(repo, tag, imageId)

# Get all images in local
proc getImageList(settings: RuntimeSettings, baseDir: string): seq[string] =
  let
    dbPath = settings.databasePath()

  if fileExists(dbPath):
    let dbJson = parseFile(dbPath)
    for key, val in dbJson["Repository"]:
      for key, item in val:
        let id = (item.getStr)[7 .. ^1]
        result.add(fmt "{key} {id}")

# Show all image in local
proc writeImageList*(settings: RuntimeSettings, baseDir: string) =
  let images = settings.getImageList(baseDir)

  echo "Repository:Tag\n"
  for image in images:
    echo image

proc checkImageInLocal*(settings: RuntimeSettings, repo, tag: string): bool =
  let
    dbPath = settings.databasePath()
    image = fmt"{repo}:{tag}"

  if fileExists(dbPath):
    let dbJson = parseFile(dbPath)
    for key, val in dbJson["Repository"]:
      for key in val.keys:
        if image == key: return true
  else:
    return false

proc getImageId*(settings: RuntimeSettings, repo, tag: string): string =
  if settings.checkImageInLocal(repo, tag):
    result = settings.getImageIdFromLocal(repo, tag)
  else:
    let token = getToken(repo, tag)
    if settings.debug: echo fmt"Debug: Get token: {token}"

    result = getImageIdFromDockerHub(repo, tag, token, settings.debug)

# Get manifest file in local by image id
proc getManifestByImageId(settings: RuntimeSettings, item: string): JsonNode =
  let dbJson = parseFile(settings.databasePath())
  for repo, node in dbJson["Repository"]:
    for repoAndTag, val in node:
      let
        valStr = val.getStr
        id = valStr[7 .. ^1]

      if id == item:
        let manifestPath = settings.imagesHashPath() / id
        return parseFile(manifestPath)

proc getManifestByRepo(settings: RuntimeSettings, item: string): JsonNode =
  let
    dbJson = parseFile(settings.databasePath())
    repo = if item.contains(":"): (item.split(":"))[0]
           else: item
    tag = if item.contains(":"): (item.split(":"))[1]
          else: "latest"

  for repo, node in dbJson["Repository"]:
    for repoAndTag, val in node:
      let
        valStr = val.getStr
        id = valStr[7 .. ^1]

      if repoAndTag == item:
        let manifestPath = settings.imagesHashPath() / id
        return parseFile(manifestPath)

proc getRepoAndTagByimageId(settings: RuntimeSettings, imageId: string): ImageInfo =

  let dbJson = parseFile(settings.databasePath())
  for repo, node in dbJson["Repository"]:
    for repoAndTag, val in node:
      let
        valStr = val.getStr
        id = valStr[7 .. ^1]

      if id == imageId:
        let strSplit = repoAndTag.split(":")
        if strSplit.len == 2:
          return ImageInfo(repo: strSplit[0], tag: strSplit[1])

proc removeImage*(settings: RuntimeSettings, layerDir, item: string) =
  let
    imagesPath = settings.imagesPath()
    dbPath = settings.databasePath()
    dbJson = parseFile(dbPath)

    isImageId = not item.contains(":")

    manifestJson = if isImageId: settings.getManifestByImageId(item)
                   else: settings.getManifestByRepo(item)

  let  imageId = (manifestJson["config"]["digest"].getStr)[7 .. ^1]

  for item in manifestJson["layers"]:
    let
      digest = item["digest"].getStr
      id = digest[7 .. ^1]
    block:
      let path = layerDir / id
      try:
        removeDir(path)
      except OSError:
        echo fmt "Failed to delete the layers: {path}"
        return

  # Remove manifest
  block:
    let path = imagesPath / imageId
    try:
      removeFile(path)
    except OSError:
      echo fmt "Failed to delete the manifest file: {path}"
      return

  # Update DB
  let info = settings.getRepoAndTagByimageId(imageId)
  var newJson = dbJson
  if newJson["Repository"][info.repo].len == 1:
    newJson["Repository"].delete(info.repo)
  else:
    newJson["Repository"][info.repo].delete(fmt "{info.repo}:{info.tag}")

  try:
    writeFile(dbPath, $newJson)
  except IOError:
    echo fmt "Failed to Update image DB: {dbPath}"

  return

proc parseImageConfig(configJson: JsonNode): ImageConfig =
  for key, val in configJson.pairs:
    case key:
      of "Hostname":
        result.hostname = val.getStr
      of "Domainname":
        result.domainname = val.getStr
      of "User":
        result.user = val.getStr
      of "AttachStdin":
        result.attachStdin = val.getBool
      of "AttachStdout":
        result.attachStdout = val.getBool
      of "AttachStderr":
        result.attachStderr = val.getBool
      of "Tty":
        result.tty = val.getBool
      of "OpenStdin":
        result.openStdin = val.getBool
      of "StdinOnce":
        result.stdinOnce = val.getBool
      of "Env":
        for val in configJson[key]:
          result.env.add val.getStr
      of "Cmd":
        for val in configJson[key]:
          result.cmd.add val.getStr
      of "Image":
        result.image = val.getStr
      of "Volumes":
        result.volumes = val.getStr
      of "WorkingDir":
        result.workingDir = val.getStr
      of "Entrypoint":
        result.entrypoint = val.getStr
      of "OnBuild":
        result.onBuild = val.getStr
      of "Labels":
        result.labels = val.getStr
      else:
        discard

proc parseContainerConfig(configJson: JsonNode): ContainerConfig =
  for key, val in configJson.pairs:
    case key:
      of "Hostname":
        result.hostname = val.getStr
      of "Domainname":
        result.domainname = val.getStr
      of "User":
        result.user = val.getStr
      of "AttachStdin":
        result.attachStdin = val.getBool
      of "AttachStdout":
        result.attachStdout = val.getBool
      of "AttachStderr":
        result.attachStderr = val.getBool
      of "Tty":
        result.tty = val.getBool
      of "OpenStdin":
        result.openStdin = val.getBool
      of "StdinOnce":
        result.stdinOnce = val.getBool
      of "Env":
        for val in configJson[key]:
          result.env.add val.getStr
      of "Cmd":
        for val in configJson[key]:
          result.cmd.add val.getStr
      of "Image":
        result.image = val.getStr
      of "Volumes":
        result.volumes = val.getStr
      of "WorkingDir":
        result.workingDir = val.getStr
      of "Entrypoint":
        result.entrypoint = val.getStr
      of "OnBuild":
        result.onBuild = val.getStr
      of "Labels":
        result.labels = val.getStr
      else:
        discard

proc parseImageRootfs(rootfsJson: JsonNode): ImageRootFs =
  for key, val in rootfsJson.pairs:
    case key:
      of "type":
        result.`type` = val.getStr
      of "diff_ids":
        for val in rootfsJson[key]:
          result.diffIds.add val.getStr
      else:
        discard

proc parseBlob*(blobJson: JsonNode): Blob =
  for key, val in blobJson.pairs:
    case key:
      of "architecture":
        result.architecture = val.getStr
      of "config":
        result.config = parseImageConfig(val)
      of "container":
        result.container = val.getStr
      of "container_config":
        result.containerConfig = parseContainerConfig(val)
      of "created":
        result.created = val.getStr
      of "docker_version":
        result.dockerVersion = val.getStr
      of "history":
        for val in blobJson[key]:
          result.history.add val.getStr
      of "os":
        result.os = val.getStr
      of "rootfs":
        result.rootfs = parseImageRootfs(val)
      else:
        discard
