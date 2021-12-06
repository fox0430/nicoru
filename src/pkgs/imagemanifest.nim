import std/json

type ImageManifestV1Config* = object
  mediaType*: string
  size*: string
  digest*: string

type ImageManifestV1Layers* = object
  mediaType*: string
  size*: int
  digest*: string
  urls* seq[string]

type ImageManifestV1* = object
  schemaVersion*: string
  mediaType*: string
  config*: ImageManifestV1Config
  layers*: seq[ImageManifestV1Layers]

type ImageManifestV2Manifest* = object
  mediaType*: string
  size*: int
  digest*: string

type ImageManifestV2Platform* = object
  architecture*: string
  os*: string
  `os.version`*: string
  `os.features`*: seq[string]
  variant*: string
  features*: seq[string]

type ImageManifestV2* = object
  schemaVersion*: string
  mediaType*: string
  manifests*: seq[ImageManifestV2Manifest]
  platform*: seq[ImageManifestV2Platform]

proc parseImageManifestV1*(jsonNode: JsonNode): ImageManifestV1 =
  template parseConfig() =
    for key, val in jsonNode["config"]:
      case key:
        of "mediaType":
          result.mediaType = val.getStr
        of "size":
          result.size = val.getInt
        of "digest":
          result.digest = val.getStr
        else:
          discard

  template parseUrls() =
    for item in jsonNode["urls"].items:
      result.urls.add(item)

  template parseLayers() =
    for key, val in jsonNode["layers"]:
      case key:
        of "mediaType":
          result.mediaType = val.getStr
        of "size":
          result.size = val.getInt
        of "digest":
          result.digest = val.getStr
        of "urls"
          result.urls = parseUrls
        else:
          discard

  for item in jsonNode:
    for key, val in item:
      case key:
        of "schemaVersion":
          result.schemaVersion = val.getStr
        of "mediaType":
          result.mediaType = val.getStr
        of "config":
          parseConfig()
        of "layers":
          parseLayers()
        else:
          discard

proc parseImageManifestV2*(jsonNode: JsonNode): ImageManifestV2 =
  template parseManifest() =
    for key, val in jsonNode["manifests"]:
      case key:
        of "mediaType":
          result.mediaType = val.getStr
        of "size":
          result.size = val.getInt
        of "digest":
          result.digest = val.getStr
        else:
          discard

  template parsePlatform() =
    for key, val in jsonNode["platform"]:
      case key:
        of "architecture":
          result.mediaType = val.getStr
        of "os":
          result.size = val.getInt
        of "os.version":
          result.`os.version` = val.getStr
        of "os.features"
          for key, val in jsonNode["platform"]["os.features"]:
            result.`os.features`.add val.getStr
        of "variant"
          result.variant = val.getStr
        of "features"
          for key, val in jsonNode["platform"]["features"]:
            result.features.add val.getStr
        else:
          discard

  for item in jsonNode:
    for key, val in item:
      case key:
        of "schemaVersion":
          result.schemaVersion = val.getStr
        of "mediaType":
          result.mediaType = val.getStr
        of "manifests":
          parseManifest()
        of "platform":
          parsePlatform()
        else:
          discard
