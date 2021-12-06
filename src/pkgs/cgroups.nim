import std/posix
import linuxutils

type CgroupsSettgings* = object
  memory*: bool
  memoryLimit*: int
  cpu*: bool
  cpuLimit*: int
  cpuCore*: bool
  cpuCoreLimit*: int

proc setupMemeryLimit(pid: Pid, memoryLimit: int) =
  # Create dir for set memory limit in cgroups dir
  let cgroupsMemDir = "/sys/fs/cgroup/memory/" & $pid
  mkdir(cgroupsMemDir, 700)

  ## Set memory limit
  block:
    let
      cgroupsFile = cgroupsMemDir & "/memory.limit_in_bytes"
      f = open(cgroupsFile, FileMode.fmWrite)
      memorylimit = memorylimit * (1024 * 1024)

    f.write($memorylimit)
    f.close

  ## Add the container pid to the group
  block:
    let
      cgroupsFile = cgroupsMemDir & "/cgroup.procs"
      f = open(cgroupsFile, FileMode.fmWrite)

    f.write($pid)
    f.close

proc setupCpuLimit(pid: Pid, cpuLimit: int) =
  # Create dir for set cpu limit in cgroups dir
  let cgroupsCpuDir = "/sys/fs/cgroup/cpu/" & $pid
  mkdir(cgroupsCpuDir, 700)

  # Set single cpu limit
  block:
    let
      cgroupsFile = cgroupsCpuDir & "/cpu.cfs_quota_us"
      f = open(cgroupsFile, FileMode.fmWrite)
      cpulimit = cpuLimit * 1000

    f.write($cpulimit)
    f.close

  # Add the container pid to the group
  block:
    let
      cgroupsFile = cgroupsCpuDir & "/cgroup.procs"
      f = open(cgroupsFile, FileMode.fmWrite)

    f.write($pid)
    f.close

proc setupCgroups*(cgroupsSettgings: CgroupsSettgings, pid: Pid) =
  if cgroupsSettgings.memory:
    setupMemeryLimit(pid, cgroupsSettgings.memoryLimit)

  if cgroupsSettgings.cpu:
    setupCpuLimit(pid, cgroupsSettgings.cpuLimit)
