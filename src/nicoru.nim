import pkgs/[settings, cmdparse]

when isMainModule:
  var runtimeSettings = initRuntimeSetting()
  let cmdParseInfo = parseCommandLineOption()

  if cmdParseInfo.argments.len > 0:
    checkArgments(runtimeSettings, cmdParseInfo)
  elif cmdParseInfo.shortOptions.len > 0:
    checkShortOptions(cmdParseInfo.shortOptions)
  else:
    checkLongOptions(cmdParseInfo.longOptions)