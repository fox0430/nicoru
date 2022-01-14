import unittest, json
include src/pkgs/seccomputils

proc searchSyscallSetting(seccompSetting: SeccompSetting,
                          name: string): SyscallSetting =

  for syscallSetting in seccompSetting.syscall:
    if syscallSetting.name == name:
      return syscallSetting

  raise

suite "Seccomp":
  test "Load and init a default profile":
    let
      profile = loadProfile("./default_seccomp_profile.json")
      setting = initSeccompSetting(profile)

      defaultProfileStr = readFile("./default_seccomp_profile.json")
      defaultProfileJson = parseJson(defaultProfileStr)

    block:
      let defaultAction = defaultProfileJson["defaultAction"].getStr.toAction
      check setting.defaultAction == defaultAction

    block:
      let action = defaultProfileJson["syscalls"][0]["action"].getStr.toAction
      for name in defaultProfileJson["syscalls"][0]["names"].items:
        let syscallSetting = setting.searchSyscallSetting(name.getStr)
        check syscallSetting.action == action

  test "Load and init profile":
    let profileJson = parseJson("""
{
  "defaultAction": "ERRNO",
  "syscalls": [
    {
      "action": "ALLOW",
      "names": [
        "accept"
      ]
    },
    {
      "action": "KILL",
      "names": [
        "access"
      ]
    }
  ]
}""")

    let setting = initSeccompSetting(profileJson)

    block:
      let defaultAction = profileJson["defaultAction"].getStr.toAction
      check setting.defaultAction == defaultAction

    block:
      for syscallProfile in  profileJson["syscalls"].items:
        let action = syscallProfile["action"].getStr.toAction
        for name in syscallProfile["names"].items:
          let syscallSetting = setting.searchSyscallSetting(name.getStr)
          check syscallSetting.action == action

  test "Load and init profile 2":
    let profileJson = parseJson("""
{
  "defaultAction": "ERRNO"
}""")

    let
      setting = initSeccompSetting(profileJson)
      defaultAction = profileJson["defaultAction"].getStr.toAction
    check setting.defaultAction == defaultAction
