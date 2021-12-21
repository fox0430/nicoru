import std/[unittest, os]

suite "Integration":
  test "Run Container":
    check execShellCmd("nimble build -y") == 0
    check execShellCmd("sudo ./nicoru run alpine:latest ls") == 0
