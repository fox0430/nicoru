{.deadCodeElim:on.}

import posix, linux, strformat
import syscall

const
  MS_RDONLY* = 1
  MS_NOSUID* = 2
  MS_NODEV* = 4
  MS_NOEXEC* = 8
  MS_SYNCHRONOUS* = 16
  MS_REMOUNT* =32
  MS_MANDLOCK* =64
  MS_DIRSYNC* = 128
  MS_NOATIME* = 1024
  MS_NODIRATIME* = 2048
  MS_BIND* = 4096
  MS_MOVE* = 8192
  MS_REC* = 16384
  MS_VERBOSE* = 32768
  MS_SILENT* = 32768
  MS_POSIXACL* = (1 shl 16)
  MS_UNBINDABLE* = (1 shl 17)
  MS_PRIVATE * = (1 shl 18)
  MS_SLAVE* = (1 shl 19)
  MS_SHARED* = (1 shl 20)
  MS_RELATIME* = (1 shl 21)
  MS_KERNMOUNT* = (1 shl 22)
  MS_I_VERSION* = (1 shl 23)
  MS_STRICTATIME* = (1 shl 24)
  MS_LAZYTIME* = (1 shl 25)
  MS_SUBMOUNT* = (1 shl 26)
  MS_NOREMOTELOCK* = (1 shl 27)
  MS_NOSEC* = (1 shl 28)
  MS_BORN* = (1 shl 29)
  MS_ACTIVE* = (1 shl 30)
  MS_NOUSER* = (1 shl 31)
  MS_MGC_VAL* = 0xC0ED0000

const
  MNT_DETACH* = 0x00000002

const
  # Can get size with "sizeof (struct inotify_event)" in C
  INOTIFY_EVENT_SZIE* = 32768

# Exception
type Error = object of Exception

proc exception*(message: string) =
  raise newException(Error, message)

## Import from c

proc unshare(flag: cint): cint {.importc, header: "<sched.h>"}

proc mount(source: cstring, target: cstring, filesystemtype: cstring,
           mountflags: culong, data: pointer): cint {.importc, header:"<sys/mount.h>"}

proc umount(target: cstring): cint {.importc, header:"<sys/mount.h>"}

proc umount2(target: cstring, flags: cint): cint {.importc, header:"<sys/mount.h>"}

proc chroot(path: cstring): cint {.importc, header:"<linux/unistd.h>"}

proc chdir(path: cstring): cint {.importc, header:"<linux/unistd.h>"}

proc sethostname(name: cstring, len: csize_t): cint {.importc, header:"<linux/unistd.h>"}

proc setenv(name, value: cstring, overwrite: cint): cint {.importc, header: "<stdlib.h>"}

## Raw system call

proc pivotRoot*(newRoot, putOld: string) =
  let exitCode = syscall(PIVOT_ROOT, cstring(newRoot), cstring(putOld))
  if exitCode < 0:
    exception(fmt"System call: pivot_root failed. Error code: {exitCode}")

## Wapper procs

proc unshare*(flag: int) =
  let exitCode = unshare(cint(flag))
  if exitCode < 0: exception(fmt "System call: unshare failed: {exitCode}")

proc chroot*(path: string) =
  let exitCode = chroot(cstring(path))
  if exitCode < 0: exception(fmt "System call: chroot failed: {exitCode}")

proc chdir*(path: string) =
  let exitCode = chdir(cstring(path))

  if exitCode < 0: exception(fmt "System call: chdir failed: {exitCode}")

proc mount* (source: string, target: string, filesystemtype: string, mountflags: uint32, data: string) =
  var dataPtr = pointer(cstring(data))
  let exitCode = mount(cstring(source), cstring(target), cstring(filesystemtype), culong(mountflags), dataPtr)
  if exitCode < 0: exception("fmt System call: mount failed: {exitCode}")

proc mount* (source: string, target: string, filesystemtype: string, mountflags: uint32) =
  let exitCode = mount(cstring(source), cstring(target), cstring(filesystemtype), culong(mountflags), nil)
  if exitCode < 0: exception(fmt "System call: mount failed: {exitCode}")

proc setHostname*(name: string) =
  let exitCode = sethostname(cstring(name), csize_t(name.len))

  if exitCode < 0: exception(fmt "System call: setHostname failed: {exitCode}")

proc clone*(fn: pointer, flags: cint, arg: pointer): Pid =
  const stackSize = 65536
  let
    stackEnd = cast[clong](alloc(stackSize))
    stack = cast[pointer](stackEnd + stackSize)

  let exitCode = clone(fn, stack, flags, arg, nil, nil, nil)
  if exitCode < 0: exception(fmt "System call: clone failed: {exitCode}")

  result = Pid(exitCode)

proc getHostname*(): string =
  const size = 64
  var s = cstring(newString(size))

  let exitCode = s.getHostname(size)
  if exitCode < 0: exception(fmt "System call: getHostname failed: {exitCode}")

  result = $s

proc umount*(target: string) =
  let exitCode = umount(cstring(target))
  if exitCode < 0: exception(fmt "System call: umount failed: {exitCode}")

proc umount2*(target: string, flags: int) =
  let exitCode = umount2(cstring(target), cint(flags))
  if exitCode < 0: exception(fmt "System call: umount2 failed: {exitCode}")

proc pipe*(fd: array[0..1, cint]) =
  let exitCode = posix.pipe(fd)
  if exitCode < 0: exception(fmt "System call: pipe failed: {exitCode}")

proc close*(fd: cint) =
  let exitCode = posix.close(fd)
  if exitCode < 0: exception(fmt "System call: close failed: {exitCode}")

proc read*(fd: cint, ch: var char, count: int) =
  let exitCode = read(fd, pointer(addr ch), 1)
  if exitCode < 0: exception(fmt "System call: read failed: {exitCode}")

proc mkdir*(name: string, mode: Mode) =
  let exitCode = posix.mkdir(cstring(name), mode)
  if exitCode < 0: exception(fmt "System call: mkdir failed: {exitCode}")

proc rmdir*(name: string) =
  let exitCode = rmdir(cstring(name))
  if exitCode < 0: exception(fmt "System call: rmdir failed: {exitCode}")

proc pipe2*(fd: array[0..1, cint], flags: int) =
  let exitCode = linux.pipe2(fd, cint(flags))
  if exitCode < 0: exception(fmt "System call: rmdir pipe2: {exitCode}")

proc setEnv*(name, value: string, overwrite: int) =
  let exitCode = setenv(cstring(name), cstring(value), cint(overwrite))
  if exitCode < 0: exception(fmt "Failed setenv: {exitCode}")

proc execvp*(command: seq[string]) =
  let
    cmd = cstring(command[0])
    args = allocCStringArray(command)

  let exitCode = execvp(cmd, args)
  if exitCode < 0: exception(fmt "Failed execv: {exitCode}")
