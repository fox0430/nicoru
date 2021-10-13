import json, os, strformat
import seccomp
import linuxutils

type SeccompAction = enum
  SCMP_ACT_ALLOW
  SCMP_ACT_ERRNO

type SyscallSetting = object
  name: string
  action: SeccompAction

type SeccompSetting = object
  enable: bool
  defaultAction: SeccompAction
  syscall: seq[SyscallSetting]

proc defaultProfile(): string {.compiletime.} =
  readFile(currentSourcePath.parentDir() / "../../profile.json")

proc isAction(action: string): bool =
  case action:
    of "SCMP_ACT_ALLOW", "SCMP_ACT_ERRNO":
      true
    else:
      false

proc toAction(action: string): SeccompAction =
  case action:
    of "SCMP_ACT_ALLOW":
      result = SeccompAction.SCMP_ACT_ALLOW
    of "SCMP_ACT_ERRNO":
      result = SeccompAction.SCMP_ACT_ERRNO
    else:
      exception(fmt"Seccomp: Invalid Action {action}")

proc setSysCallSetting(name: string, action: SeccompAction): SyscallSetting =
  if name.len > 0:
    result.name = name
    result.action = action

proc loadProfile(path: string): SeccompSetting =
  # TODO: Add error handle
  let profile = if path.len > 0: readFile(path)
                else: defaultProfile()

  let json = parseJson(profile)

  for item in json.pairs:
    case item.key:
      of "defaultAction":
        if isAction(item.val.getStr):
          result.defaultAction = toAction(item.val.getStr)

      of "syscalls":
        let syscallsJson = item.val
        var action = result.defaultAction

        for item in syscallsJson.items:
          if isAction(item["action"].getStr):
            action = toAction(item["action"].getStr)

          for name in item["names"].items:
            result.syscall.add setSysCallSetting($name, action)
      else:
        exception(fmt"Seccomp: Invalid profile: Invalid item: {item.key}")

# TODO: Add option
proc setSysCallFiler*() =
  let
    # TODO: Change to KIll or Errono
    ctx = seccomp_ctx(Allow)

  #for syscall in syscallList:
  #  ctx.add_rule(Kill, syscall)

  #if sysCallList.len > 0:
  #  ctx.load()
