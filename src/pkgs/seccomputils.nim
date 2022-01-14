import std/[json, os, strformat, strutils]
import seccomp
import linuxutils

type SyscallSetting = object
  name: string
  action: ScmpAction

type SeccompSetting = object
  defaultAction: ScmpAction
  syscall: seq[SyscallSetting]

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
proc initSeccompSetting(profile: JsonNode): SeccompSetting =
  if profile.contains("defaultAction"):
    let val = profile["defaultAction"].getStr.replace($"\\\"", "")
    if isAction(val):
      result.defaultAction = toAction(val)

  if profile.contains("syscalls"):
    for item in profile["syscalls"].items:
      let action = item["action"].getStr.replace($"\\\"", "").toAction
      for n in item["names"].items:
        let name = n.getStr.replace($"\\\"", "")
        result.syscall.add initSysCallSetting(name, action)

# Load a default prfile for Seccomp in compile time
proc defaultProfile(): string {.compiletime.} =
  readFile(currentSourcePath.parentDir() / "../../default_seccomp_profile.json")

proc loadProfile(path: string = ""): JsonNode =
  var profile = ""
  if path.len > 0:
    try:
      profile = readFile(path)
    except IOError:
      echo fmt"Seccomp: Filed to load profile. {path}"
  else:
    profile = defaultProfile()

  try:
    result = parseJson(profile)
  except:
    echo "Seccomp: Filed to parse json"


# Set system call filter using Seccomp
proc setSysCallFiler*(profilePath: string = "") =
  let
    profile = loadProfile(profilePath)
    seccompSetting = initSeccompSetting(profile)
    ctx = seccomp_ctx(seccompSetting.defaultAction)

  if seccompSetting.syscall.len > 0:
    for syscall in seccompSetting.syscall:
      echo syscall
      ctx.add_rule(syscall.action, syscall.name)

    ctx.load()
