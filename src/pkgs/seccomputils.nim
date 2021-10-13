import json
import os
import seccomp

type SyscallSetting = object
  name: string
  action: string

type SeccompSetting = object
  enable: bool
  syscall: seq[SyscallSetting]

proc defaultProfile(): string {.compiletime.} =
  readFile(currentSourcePath.parentDir() / "../../profile.json")

proc loadProfile(path: string): SeccompSetting =
  # TODO: Add error handle
  let profile = if path.len > 0: readFile(path)
                else: defaultProfile()

  # TODO: Init SeccompSetting

# TODO: Add option
proc setSysCallFiler*() =
  let
    # TODO: Change to KIll or Errono
    ctx = seccomp_ctx(Allow)

  #for syscall in syscallList:
  #  ctx.add_rule(Kill, syscall)

  #if sysCallList.len > 0:
  #  ctx.load()
