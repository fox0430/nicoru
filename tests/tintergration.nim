import std/[unittest, osproc, strutils]

proc buildNicoru(): bool =
  let r = execCmdEx("nimble build -y")
  if r.exitCode == 0:
    return true

proc getLastLineOfCmdResult(output: string): string =
  let splited = output.splitLines
  result = splited[splited.high - 1]

suite "Integration":
  test "Run Container":

    # First of all, build Nicoru
    check buildNicoru()

    let r = execCmdEx("""sudo ./nicoru run alpine:latest echo "ok"""")
    check r.exitCode == 0
    check getLastLineOfCmdResult(r.output) == "ok"

  test "ping in the container (Host mode)":
    let r = execCmdEx("""sudo ./nicoru run alpine:latest ping -c 1 google.com""")
    check r.exitCode == 0

  test "ping in the container (Bridge mode)":
    let r = execCmdEx("""sudo ./nicoru run --network=bridge alpine:latest ping -c 1 google.com""")
    check r.exitCode == 0

  test "Show containers":
    let r = execCmdEx("sudo ./nicoru ps")
    check r.exitCode == 0

  test "Show images":
    let r = execCmdEx("sudo ./nicoru images")
    check r.exitCode == 0

