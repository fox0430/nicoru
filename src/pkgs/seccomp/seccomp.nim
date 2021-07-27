#
#  Seccomp high-level adaptor for Nim
#
# 2016 Federico Ceratto <federico.ceratto@gmail.com>
# Released under LGPLv2.1, see LICENSE file

import strutils

import seccomp_lowlevel


proc get_version*(): (int, int, int) =
  ## Get seccomp version
  let v = seccompVersion()
  return (v.major.int, v.minor.int, v.micro.int)


type
  ScmpAction* = enum
    Kill =  0x00000000    # SECCOMP_RET_KILL
    Trap =  0x00030000,   # SECCOMP_RET_TRAP
    Errno = 0x00050000,   # SECCOMP_RET_ERRNO
    Log =   0x00070000,   # SECCOMP_RET_LOG
    Allow = 0x7FFF0000,   # SECCOMP_RET_ALLOW

proc seccomp_ctx*(defaultAction = ScmpAction.Kill): ScmpFilterCtx =
  ## Create seccomp context
  return seccompInit(defaultAction.uint32)


proc reset*(ctx: ScmpFilterCtx, defAction = ScmpAction.Kill) =
  ##  Destroy the filter state and releases any resources
  doAssert seccompReset(ctx, defAction.uint32) == 0


proc release*(ctx: ScmpFilterCtx) =
  ## Destroy the given seccomp filter state and releases any
  ## resources, including memory, associated with the filter state.  This
  ## function does not reset any seccomp filters already loaded into the kernel.
  ## The filter context can no longer be used after calling this function.
  seccompRelease(ctx)


proc load*(ctx: ScmpFilterCtx) =
  ## Apply seccomp context
  doAssert seccompLoad(ctx) == 0


proc add_rule*(ctx: ScmpFilterCtx, action: ScmpAction, syscall_name: string, argCnt = 0) =
  ## Add rule
  let num = seccompSyscallResolveName(syscall_name)
  assert num >= 0, "Unable to resolve syscall $#" % syscall_name
  discard ctx.seccompRuleAdd(action.uint32, num, 0)


proc setSeccomp*(allow: seq[string], defaultAction = ScmpAction.Kill) =
  ## Helper to configure seccomp. Whitelist syscalls in `allow`
  let ctx = seccomp_ctx(defaultAction)
  for syscall_name in allow:
    ctx.add_rule(Allow, syscall_name)
  ctx.load()

proc setSeccomp*(allow: string, defaultAction = ScmpAction.Kill) =
  ## Helper to configure seccomp. Whitelist whitespace-separated syscalls in `allow`
  let ctx = seccomp_ctx(defaultAction)
  for syscall_name in allow.split(' '):
    ctx.add_rule(Allow, syscall_name)
  ctx.load()
