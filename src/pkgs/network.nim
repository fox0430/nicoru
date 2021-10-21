import posix
import linuxutils, settings

proc initNetworkInterface(containerId: string) =
  let nsMount = netNsPath / containerId
  linuxutils.open(nsMount, O_RDONLY, 0.Mode)

  let
    veth1 = "veth1_" + containerId[..6]

proc initNetns*(containerId: string) =
  let nsMount = netNsPath / containerId
  discard linuxutils.open(nsMount, O_RDONLY | O_CREAT | O_EXCL, 0644.Mode)

  let fd = linuxutils.open("/proc/self/ns/net", O_RDONLY, 0.Mode)

  unshare(CLONE_NEWNET)

  mount("/proc/self/ns/net", nsMount, "bind", MS_BIND)

  setns(fd, CLONE_NEWNET)
