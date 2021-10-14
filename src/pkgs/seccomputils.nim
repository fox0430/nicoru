import json, os, strformat
import seccomp
import linuxutils

type SyscallSetting = object
  name: string
  action: ScmpAction

type SeccompSetting = object
  defaultAction: ScmpAction
  syscall: seq[SyscallSetting]

proc defaultProfile(): string {.compiletime.} =
  readFile(currentSourcePath.parentDir() / "../../profile.json")

proc isAction(action: string): bool =
  case action:
    of "SCMP_ACT_ALLOW", "SCMP_ACT_ERRNO":
      true
    else:
      false

proc toAction(action: string): ScmpAction =
  case action:
    of "SCMP_ACT_ALLOW":
      result = ScmpAction.Allow
    of "SCMP_ACT_ERRNO":
      result = ScmpAction.Trap
    else:
      exception(fmt"Seccomp: Invalid Action {action}")

proc setSysCallSetting(name: string, action: ScmpAction): SyscallSetting =
  if name.len > 0:
    result.name = name
    result.action = action

proc loadProfile(path: string = ""): SeccompSetting =
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

proc setSysCallFiler*(profilePath: string = "") =
  let
    seccompSetting = loadProfile(profilePath)
    ctx = seccomp_ctx(seccompSetting.defaultAction)

  if seccompSetting.syscall.len > 0:
    for syscall in seccompSetting.syscall:
      ctx.add_rule(syscall.action, syscall.name)

    ctx.load()
