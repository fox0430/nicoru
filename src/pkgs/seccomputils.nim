import json, os, strformat
import seccomp
import linuxutils

type SyscallSetting = object
  name: string
  action: ScmpAction

type SeccompSetting = object
  defaultAction: ScmpAction
  syscall: seq[SyscallSetting]

# Load a default prfile for Seccomp in compile time
proc defaultProfile(): string {.compiletime.} =
  readFile(currentSourcePath.parentDir() / "../../profile.json")

proc isAction(action: string): bool =
  case action:
    of "ALLOW", "ERRNO", "KILL":
      true
    else:
      false

proc toAction(action: string): ScmpAction =
  case action:
    of "ALLOW":
      result = ScmpAction.Allow
    of "ERRNO":
      result = ScmpAction.Trap
    of "KILL":
      result = ScmpAction.Kill
    else:
      exception(fmt"Seccomp: Invalid Action {action}")

proc initSysCallSetting(name: string, action: ScmpAction): SyscallSetting =
  if name.len > 0:
    result.name = name
    result.action = action

# Load prfile for Seccomp and init SeccompSetting and SyscallSetting
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
            result.syscall.add initSysCallSetting($name, action)
      else:
        exception(fmt"Seccomp: Invalid profile: Invalid item: {item.key}")

# Set system call filter using Seccomp
proc setSysCallFiler*(profilePath: string = "") =
  let
    seccompSetting = loadProfile(profilePath)
    ctx = seccomp_ctx(seccompSetting.defaultAction)

  if seccompSetting.syscall.len > 0:
    for syscall in seccompSetting.syscall:
      ctx.add_rule(syscall.action, syscall.name)

    ctx.load()
