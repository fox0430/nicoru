const topHelpMessage = """

Usage:  dress [OPTIONS] COMMAND

Options:
  -v    Print version
  -h    Print help

Commands:
  create  Create a new container
  images  List images
  ps      List containers
  pull    Pull an image from a registry
  rm      Remove one containers
  rmi     Remove one images
  run     Run a command new container
  start   Start one stopped container
  stop    Stop one running containers
  log     Fetch the logs of a container
"""

const createHelpMessage = """

Usage:  dress create IMAGE
"""

const imageHelpMessage = """

Usage:  dress images
"""

const psHelpMessage = """

Usage:  dress ps
"""

const pullHelpMessage = """

Usage:  dress pull IMAGE
"""

const rmHelpMessage = """

Usage:  dress rm IMAGE
"""

const rmiHelpMessage = """

Usage:  dress rmi IMAGE
"""

const runHelpMessage = """

Usage:  dress run [OPTIONS] IMAGE [COMMAND] [ARG...]

Options:
  -b                    Run a container in background

  --cpulimit int        Limit CPU
  --cpucorelimit int    Limit CPU core
  --memorylimit         Limit memory
"""

const startHelpMessage = """

Usage:  dress start IMAGE
"""

const logHelpMessage = """

Usage:  dress log CONTAINER
"""

const stopHelpMessage = """

Usage:  dress stop [OPTIONS] CONTAINER

Options:
  -f    Force stop a container
"""

proc writeTopHelp*() {.inline.} = echo topHelpMessage

proc writeCreateHelpMessage*() {.inline.} = echo createHelpMessage

proc writeImageHelpMessage*() {.inline.} = echo imageHelpMessage

proc writePsHelpMessage*() {.inline.} = echo psHelpMessage

proc writePullHelpMessage*() {.inline.} = echo pullHelpMessage

proc writeRmHelpMessage*() {.inline.} = echo rmHelpMessage

proc writeRmiHelpMessage*() {.inline.} = echo rmiHelpMessage

proc writeRunHelp*() {.inline.} = echo runHelpMessage

proc writeStartHelp*() {.inline.} = echo startHelpMessage

proc writeLogHelp*() {.inline.} = echo logHelpMessage

proc writeStopHelp*() {.inline.} = echo stopHelpMessage
