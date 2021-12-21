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

    check buildNicoru()

    let r = execCmdEx("""sudo ./nicoru run alpine:latest echo "ok"""")
    check r.exitCode == 0
    check getLastLineOfCmdResult(r.output) == "ok"
