import unittest, os, json, oids, strformat
include src/pkgs/image

suite "Update image DB":
  test "Create the DB":
    let
      baseDir = getCurrentDir() / "imageTest"
      imageDir = baseDir / "images"

    createDir(imageDir)

    let
      repo = $genOid()
      tag = $genOid()
      id = $genOid()
      debug = false
      settings = RuntimeSettings(baseDir: baseDir, debug: debug)

    settings.updateImageDb(repo, tag, id)

    let
      dbPath = baseDir / "images" / "repositories.json"
      dbJson = parseFile(dbPath)

    check dbJson == %* {"Repository":{repo:{fmt "{repo}:{tag}": id}}}

    removeDir(baseDir)

  test "Create and update the DB":
    let
      baseDir = getCurrentDir() / "imageTest"
      imageDir = baseDir / "images"

    createDir(imageDir)

    const debug = false

    let
      repo = $genOid()
      tag = $genOid()
      id = $genOid()
      settings = RuntimeSettings(baseDir: baseDir, debug: debug)

    # Create new DB
    settings.updateImageDb(repo, tag, id)

    let
      repo2 = $genOid()
      tag2 = $genOid()
      id2 = $genOid()
    # Update DB
    settings.updateImageDb(repo2, tag2, id2)

    let
      dbPath = baseDir / "images" / "repositories.json"
      dbJson = parseFile(dbPath)

    check dbJson == %* {"Repository":{repo:{fmt "{repo}:{tag}": id}, repo2:{fmt "{repo2}:{tag2}": id2}}}

    removeDir(baseDir)

suite "Image blob (layer)":
  test "Parse blob":
    let blobJson = parseJson("""
{"architecture":"amd64","config":{"Hostname":"","Domainname":"","User":"","AttachStdin":false,"AttachStdout":false,"AttachStderr":false,"Tty":false,"OpenStdin":false,"StdinOnce":false,"Env":["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],"Cmd":["sh"],"Image":"sha256:bbb267d519febe6fbc3db198c29806127961535bce09bc940ec6903b4efdf511","Volumes":null,"WorkingDir":"","Entrypoint":null,"OnBuild":null,"Labels":null},"container":"a6f030b9cc95854927e5f463bec519889b793aa90138e35d845fdc72ef5293b4","container_config":{"Hostname":"a6f030b9cc95","Domainname":"","User":"","AttachStdin":false,"AttachStdout":false,"AttachStderr":false,"Tty":false,"OpenStdin":false,"StdinOnce":false,"Env":["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],"Cmd":["/bin/sh","-c","#(nop) ","CMD [\"sh\"]"],"Image":"sha256:bbb267d519febe6fbc3db198c29806127961535bce09bc940ec6903b4efdf511","Volumes":null,"WorkingDir":"","Entrypoint":null,"OnBuild":null,"Labels":{}},"created":"2021-01-13T09:25:26.251775554Z","docker_version":"19.03.12","history":[{"created":"2021-01-13T09:25:26.062905442Z","created_by":"/bin/sh -c #(nop) ADD file:92e389f575fd4d0a48a8273242a1bd10a1b4c020cfd73a3558ae723e819b6b8c in / "},{"created":"2021-01-13T09:25:26.251775554Z","created_by":"/bin/sh -c #(nop)  CMD [\"sh\"]","empty_layer":true}],"os":"linux","rootfs":{"type":"layers","diff_ids":["sha256:0064d0478d0060343cb2888ff3e91e718f0bffe9994162e8a4b310adb2a5ff74"]}}""")

    let blob = blobJson.parseBlob

    check blob.architecture == "amd64"

    check blob.config.hostname  == ""
    check blob.config.domainname == ""
    check blob.config.user == ""
    check not blob.config.attachStdin
    check not blob.config.attachStdout
    check not blob.config.attachStderr
    check not blob.config.tty
    check not blob.config.stdinOnce
    check blob.config.env == @["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
    check blob.config.cmd == @["sh"]
    check blob.config.image == "sha256:bbb267d519febe6fbc3db198c29806127961535bce09bc940ec6903b4efdf511"
    check blob.config.volumes.len == 0
    check blob.config.workingDir == ""
    check blob.config.entrypoint.len == 0
    check blob.config.onBuild == ""
    check blob.config.labels == ""

    check blob.container == "a6f030b9cc95854927e5f463bec519889b793aa90138e35d845fdc72ef5293b4"

    check blob.containerConfig.hostname == "a6f030b9cc95"
    check blob.containerConfig.domainname == ""
    check blob.containerConfig.user == ""
    check not blob.containerConfig.attachStdin
    check not blob.containerConfig.attachStdout
    check not blob.containerConfig.attachStderr
    check not blob.containerConfig.tty
    check not blob.containerConfig.stdinOnce
    check blob.containerConfig.image == "sha256:bbb267d519febe6fbc3db198c29806127961535bce09bc940ec6903b4efdf511"
    check blob.containerConfig.volumes.len == 0
    check blob.containerConfig.workingDir == ""
    check blob.containerConfig.entrypoint.len == 0
    check blob.containerConfig.onBuild == ""
    check blob.containerConfig.labels == ""

    check blob.created == "2021-01-13T09:25:26.251775554Z"
    check blob.dockerVersion == "19.03.12"
    check blob.os == "linux"

    check blob.rootfs.`type` == "layers"
    check blob.rootfs.diffIds  ==  @["sha256:0064d0478d0060343cb2888ff3e91e718f0bffe9994162e8a4b310adb2a5ff74"]
