#
#  Seccomp Library wrapper
#
#  Copyright (c) 2012,2013 Red Hat <pmoore@redhat.com>
#  Author: Paul Moore <paul@paul-moore.com>
#
#
#  This library is free software; you can redistribute it and/or modify it
#  under the terms of version 2.1 of the GNU Lesser General Public License as
#  published by the Free Software Foundation.
#
#  This library is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License
#  for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with this library; if not, see <http://www.gnu.org/licenses>.
#


const libname = "libseccomp.so.2"

type
  ScmpVersion* = object
    major*: cuint
    minor*: cuint
    micro*: cuint

#
#  types
#



#*
#  Filter context/handle
#

type ScmpFilterCtx* = pointer


#*
#  Filter attributes
#

type ScmpFilterAttr* {.size: sizeof(cint).} = enum
    SCMP_FLTATR_MIN = 0, SCMP_FLTATR_ACT_DEFAULT = 1, #*< default filter action
    SCMP_FLTATR_ACT_BADARCH = 2, #*< bad architecture action
    SCMP_FLTATR_CTL_NNP = 3,  #*< set NO_NEW_PRIVS on filter load
    SCMP_FLTATR_CTL_TSYNC = 4, #*< sync threads on filter load
    SCMP_FLTATR_MAX


#*
#  Comparison operators
#

type
  ScmpCompare* {.size: sizeof(cint).} = enum
    SCMP_CMP_MIN = 0, SCMP_CMP_NE = 1, #*< not equal
    SCMP_CMP_LT = 2,          #*< less than
    SCMP_CMP_LE = 3,          #*< less than or equal
    SCMP_CMP_EQ = 4,          #*< equal
    SCMP_CMP_GE = 5,          #*< greater than or equal
    SCMP_CMP_GT = 6,          #*< greater than
    SCMP_CMP_MASKED_EQ = 7,   #*< masked equality
    SCMP_CMP_MAX



#*
#  Argument datum
#

type
  ScmpDatumT* = uint64


#*
#  Argument / Value comparison definition
#

type
  ScmpArgCmp* = object
    arg*: cuint               #*< argument number, starting at 0
    op*: ScmpCompare          #*< the comparison op, e.g. SCMP_CMP_*
    datumA*: ScmpDatumT
    datumB*: ScmpDatumT


#
#  macros/defines
#



#*
#  The native architecture token
#

const
  SCMP_ARCH_NATIVE* = 0




#*
#  The x86 (32-bit) architecture token
#

#const SCMP_ARCH_X86* = audit_Arch_I386




#*
#  The x86-64 (64-bit) architecture token
#

#const SCMP_ARCH_X86_64* = audit_Arch_X8664




#*
#  The x32 (32-bit x86_64) architecture token
#
#  NOTE: this is different from the value used by the kernel because we need to
#  be able to distinguish between x32 and x86_64
#

#const SCMP_ARCH_X32* = (em_X8664 or audit_Arch_Le)




#*
#  The ARM architecture tokens
#

#const SCMP_ARCH_ARM* = audit_Arch_Arm

# AArch64 support for audit was merged in 3.17-rc1

#when not defined(AUDIT_ARCH_AARCH64):
#  const
#    AUDIT_ARCH_AARCH64* = (em_Aarch64 or audit_Arch_64bit or audit_Arch_Le)
#const
#  SCMP_ARCH_AARCH64* = audit_Arch_Aarch64




#*
#  The MIPS architecture tokens
#

# MIPS64N32 support was merged in 3.15

# MIPSEL64N32 support was merged in 3.15

#const
#  SCMP_ARCH_MIPS* = audit_Arch_Mips
#  SCMP_ARCH_MIPS64* = audit_Arch_Mips64
#  SCMP_ARCH_MIPS64N32* = audit_Arch_Mips64n32
#  SCMP_ARCH_MIPSEL* = audit_Arch_Mipsel
#  SCMP_ARCH_MIPSEL64* = audit_Arch_Mipsel64
#  SCMP_ARCH_MIPSEL64N32* = audit_Arch_Mipsel64n32




#*
#  The PowerPC architecture tokens
#

#const
#  SCMP_ARCH_PPC* = audit_Arch_Ppc
#  SCMP_ARCH_PPC64* = audit_Arch_Ppc64
#
#const
#  SCMP_ARCH_PPC64LE* = audit_Arch_Ppc64le
#
##*
##  The S390 architecture tokens
##
#
#const
#  SCMP_ARCH_S390* = audit_Arch_S390
#  SCMP_ARCH_S390X* = audit_Arch_S390x
#
##*
##  The PA-RISC hppa architecture tokens
##
#
#const
#  SCMP_ARCH_PARISC* = audit_Arch_Parisc
#  SCMP_ARCH_PARISC64* = audit_Arch_Parisc64




#*
#  Convert a syscall name into the associated syscall number
#  @param x the syscall name
#
# #define SCMP_SYS(x)		(__NR_##x)



#*
#  Specify an argument comparison struct for use in declaring rules
#  @param arg the argument number, starting at 0
#  @param op the comparison operator, e.g. SCMP_CMP_*
#  @param datum_a dependent on comparison
#  @param datum_b dependent on comparison, optional
#
# #define SCMP_CMP(...)		((struct scmp_arg_cmp){__VA_ARGS__})



#*
#  Specify an argument comparison struct for argument 0
#
# #define SCMP_A0(...)		SCMP_CMP(0, __VA_ARGS__)



#*
#  Specify an argument comparison struct for argument 1
#
# #define SCMP_A1(...)		SCMP_CMP(1, __VA_ARGS__)



#*
#  Specify an argument comparison struct for argument 2
#
# #define SCMP_A2(...)		SCMP_CMP(2, __VA_ARGS__)



#*
#  Specify an argument comparison struct for argument 3
#
# #define SCMP_A3(...)		SCMP_CMP(3, __VA_ARGS__)



#*
#  Specify an argument comparison struct for argument 4
#
# #define SCMP_A4(...)		SCMP_CMP(4, __VA_ARGS__)



#*
#  Specify an argument comparison struct for argument 5
#
# #define SCMP_A5(...)		SCMP_CMP(5, __VA_ARGS__)
#
#  seccomp actions
#



#*
#  Kill the process
#

const SCMP_ACT_KILL* = 0x00000000




#*
#  Throw a SIGSYS signal
#

const SCMP_ACT_TRAP* = 0x00030000




#*
#  Return the specified error code
#

template scmp_Act_Errno*(x: untyped): untyped =
  (0x00050000 or ((x) and 0x0000FFFF))




#*
#  Notify a tracing process with the specified value
#

template scmp_Act_Trace*(x: untyped): untyped =
  (0x7FF00000 or ((x) and 0x0000FFFF))


#*
#  Allow the syscall to be executed
#

const SCMP_ACT_ALLOW* = 0x7FFF0000

#
#  functions
#


#*
#  Query the library version information
#
#  This function returns a pointer to a populated scmp_version struct, the
#  caller does not need to free the structure when finished.
#
#
proc seccompVersion*(): ptr ScmpVersion {.cdecl, importc: "seccomp_version",
    dynlib: libname.}



#*
#  Initialize the filter state
#  @param def_action the default filter action
#
#  This function initializes the internal seccomp filter state and should
#  be called before any other functions in this library to ensure the filter
#  state is initialized.  Returns a filter context on success, NULL on failure.
#
#
proc seccompInit*(defAction: uint32): ScmpFilterCtx {.cdecl,
    importc: "seccomp_init", dynlib: libname.}



#*
#  Reset the filter state
#  @param ctx the filter context
#  @param def_action the default filter action
#
#  This function resets the given seccomp filter state and ensures the
#  filter state is reinitialized.  This function does not reset any seccomp
#  filters already loaded into the kernel.  Returns zero on success, negative
#  values on failure.
#
#
proc seccompReset*(ctx: ScmpFilterCtx; defAction: uint32): cint {.cdecl,
    importc: "seccomp_reset", dynlib: libname.}



#*
#  Destroys the filter state and releases any resources
#  @param ctx the filter context
#
#  This functions destroys the given seccomp filter state and releases any
#  resources, including memory, associated with the filter state.  This
#  function does not reset any seccomp filters already loaded into the kernel.
#  The filter context can no longer be used after calling this function.
#
#
proc seccompRelease*(ctx: ScmpFilterCtx) {.cdecl, importc: "seccomp_release",
    dynlib: libname.}



#*
#  Merge two filters
#  @param ctx_dst the destination filter context
#  @param ctx_src the source filter context
#
#  This function merges two filter contexts into a single filter context and
#  destroys the second filter context.  The two filter contexts must have the
#  same attribute values and not contain any of the same architectures; if they
#  do, the merge operation will fail.  On success, the source filter context
#  will be destroyed and should no longer be used; it is not necessary to
#  call seccomp_release() on the source filter context.  Returns zero on
#  success, negative values on failure.
#
#
proc seccompMerge*(ctxDst: ScmpFilterCtx; ctxSrc: ScmpFilterCtx): cint {.cdecl,
    importc: "seccomp_merge", dynlib: libname.}



#*
#  Resolve the architecture name to a architecture token
#  @param arch_name the architecture name
#
#  This function resolves the given architecture name to a token suitable for
#  use with libseccomp, returns zero on failure.
#
#
proc seccompArchResolveName*(archName: cstring): uint32 {.cdecl,
    importc: "seccomp_arch_resolve_name", dynlib: libname.}



#*
#  Return the native architecture token
#
#  This function returns the native architecture token value, e.g. SCMP_ARCH_*.
#
#
proc seccompArchNative*(): uint32 {.cdecl, importc: "seccomp_arch_native",
                                     dynlib: libname.}



#*
#  Check to see if an existing architecture is present in the filter
#  @param ctx the filter context
#  @param arch_token the architecture token, e.g. SCMP_ARCH_*
#
#  This function tests to see if a given architecture is included in the filter
#  context.  If the architecture token is SCMP_ARCH_NATIVE then the native
#  architecture will be assumed.  Returns zero if the architecture exists in
#  the filter, -EEXIST if it is not present, and other negative values on
#  failure.
#
#
proc seccompArchExist*(ctx: ScmpFilterCtx; archToken: uint32): cint {.cdecl,
    importc: "seccomp_arch_exist", dynlib: libname.}



#*
#  Adds an architecture to the filter
#  @param ctx the filter context
#  @param arch_token the architecture token, e.g. SCMP_ARCH_*
#
#  This function adds a new architecture to the given seccomp filter context.
#  Any new rules added after this function successfully returns will be added
#  to this architecture but existing rules will not be added to this
#  architecture.  If the architecture token is SCMP_ARCH_NATIVE then the native
#  architecture will be assumed.  Returns zero on success, negative values on
#  failure.
#
#
proc seccompArchAdd*(ctx: ScmpFilterCtx; archToken: uint32): cint {.cdecl,
    importc: "seccomp_arch_add", dynlib: libname.}



#*
#  Removes an architecture from the filter
#  @param ctx the filter context
#  @param arch_token the architecture token, e.g. SCMP_ARCH_*
#
#  This function removes an architecture from the given seccomp filter context.
#  If the architecture token is SCMP_ARCH_NATIVE then the native architecture
#  will be assumed.  Returns zero on success, negative values on failure.
#
#
proc seccompArchRemove*(ctx: ScmpFilterCtx; archToken: uint32): cint {.cdecl,
    importc: "seccomp_arch_remove", dynlib: libname.}



#*
#  Loads the filter into the kernel
#  @param ctx the filter context
#
#  This function loads the given seccomp filter context into the kernel.  If
#  the filter was loaded correctly, the kernel will be enforcing the filter
#  when this function returns.  Returns zero on success, negative values on
#  error.
#
#
proc seccompLoad*(ctx: ScmpFilterCtx): cint {.cdecl, importc: "seccomp_load",
    dynlib: libname.}



#*
#  Get the value of a filter attribute
#  @param ctx the filter context
#  @param attr the filter attribute name
#  @param value the filter attribute value
#
#  This function fetches the value of the given attribute name and returns it
#  via @value.  Returns zero on success, negative values on failure.
#
#
proc seccompAttrGet*(ctx: ScmpFilterCtx; attr: ScmpFilterAttr;
                     value: ptr uint32): cint {.cdecl,
    importc: "seccomp_attr_get", dynlib: libname.}



#*
#  Set the value of a filter attribute
#  @param ctx the filter context
#  @param attr the filter attribute name
#  @param value the filter attribute value
#
#  This function sets the value of the given attribute.  Returns zero on
#  success, negative values on failure.
#
#
proc seccompAttrSet*(ctx: ScmpFilterCtx; attr: ScmpFilterAttr; value: uint32): cint {.
    cdecl, importc: "seccomp_attr_set", dynlib: libname.}



#*
#  Resolve a syscall number to a name
#  @param arch_token the architecture token, e.g. SCMP_ARCH_*
#  @param num the syscall number
#
#  Resolve the given syscall number to the syscall name for the given
#  architecture; it is up to the caller to free the returned string.  Returns
#  the syscall name on success, NULL on failure.
#
#
proc seccompSyscallResolveNumArch*(archToken: uint32; num: cint): cstring {.
    cdecl, importc: "seccomp_syscall_resolve_num_arch", dynlib: libname.}



#*
#  Resolve a syscall name to a number
#  @param arch_token the architecture token, e.g. SCMP_ARCH_*
#  @param name the syscall name
#
#  Resolve the given syscall name to the syscall number for the given
#  architecture.  Returns the syscall number on success, including negative
#  pseudo syscall numbers (e.g. __PNR_*); returns __NR_SCMP_ERROR on failure.
#
#
proc seccompSyscallResolveNameArch*(archToken: uint32; name: cstring): cint {.
    cdecl, importc: "seccomp_syscall_resolve_name_arch", dynlib: libname.}



#*
#  Resolve a syscall name to a number and perform any rewriting necessary
#  @param arch_token the architecture token, e.g. SCMP_ARCH_*
#  @param name the syscall name
#
#  Resolve the given syscall name to the syscall number for the given
#  architecture and do any necessary syscall rewriting needed by the
#  architecture.  Returns the syscall number on success, including negative
#  pseudo syscall numbers (e.g. __PNR_*); returns __NR_SCMP_ERROR on failure.
#
#
proc seccompSyscallResolveNameRewrite*(archToken: uint32; name: cstring): cint {.
    cdecl, importc: "seccomp_syscall_resolve_name_rewrite", dynlib: libname.}



#*
#  Resolve a syscall name to a number
#  @param name the syscall name
#
#  Resolve the given syscall name to the syscall number.  Returns the syscall
#  number on success, including negative pseudo syscall numbers (e.g. __PNR_*);
#  returns __NR_SCMP_ERROR on failure.
#
#
proc seccompSyscallResolveName*(name: cstring): cint {.cdecl,
    importc: "seccomp_syscall_resolve_name", dynlib: libname.}



#*
#  Set the priority of a given syscall
#  @param ctx the filter context
#  @param syscall the syscall number
#  @param priority priority value, higher value == higher priority
#
#  This function sets the priority of the given syscall; this value is used
#  when generating the seccomp filter code such that higher priority syscalls
#  will incur less filter code overhead than the lower priority syscalls in the
#  filter.  Returns zero on success, negative values on failure.
#
#
proc seccompSyscallPriority*(ctx: ScmpFilterCtx; syscall: cint; priority: uint8): cint {.
    cdecl, importc: "seccomp_syscall_priority", dynlib: libname.}



#*
#  Add a new rule to the filter
#  @param ctx the filter context
#  @param action the filter action
#  @param syscall the syscall number
#  @param arg_cnt the number of argument filters in the argument filter chain
#  @param ... scmp_arg_cmp structs (use of SCMP_ARG_CMP() recommended)
#
#  This function adds a series of new argument/value checks to the seccomp
#  filter for the given syscall; multiple argument/value checks can be
#  specified and they will be chained together (AND'd together) in the filter.
#  If the specified rule needs to be adjusted due to architecture specifics it
#  will be adjusted without notification.  Returns zero on success, negative
#  values on failure.
#
#
proc seccompRuleAdd*(ctx: ScmpFilterCtx; action: uint32; syscall: cint;
                     argCnt: cuint): cint {.varargs, cdecl,
    importc: "seccomp_rule_add", dynlib: libname.}



#*
#  Add a new rule to the filter
#  @param ctx the filter context
#  @param action the filter action
#  @param syscall the syscall number
#  @param arg_cnt the number of elements in the arg_array parameter
#  @param arg_array array of scmp_arg_cmp structs
#
#  This function adds a series of new argument/value checks to the seccomp
#  filter for the given syscall; multiple argument/value checks can be
#  specified and they will be chained together (AND'd together) in the filter.
#  If the specified rule needs to be adjusted due to architecture specifics it
#  will be adjusted without notification.  Returns zero on success, negative
#  values on failure.
#
#


proc seccompRuleAddArray*(ctx: ScmpFilterCtx; action: uint32; syscall: cint;
                          argCnt: cuint; argArray: ptr ScmpArgCmp): cint {.
    cdecl, importc: "seccomp_rule_add_array", dynlib: libname.}



#*
#  Add a new rule to the filter
#  @param ctx the filter context
#  @param action the filter action
#  @param syscall the syscall number
#  @param arg_cnt the number of argument filters in the argument filter chain
#  @param ... scmp_arg_cmp structs (use of SCMP_ARG_CMP() recommended)
#
#  This function adds a series of new argument/value checks to the seccomp
#  filter for the given syscall; multiple argument/value checks can be
#  specified and they will be chained together (AND'd together) in the filter.
#  If the specified rule can not be represented on the architecture the
#  function will fail.  Returns zero on success, negative values on failure.
#
#
proc seccompRuleAddExact*(ctx: ScmpFilterCtx; action: uint32; syscall: cint;
                          argCnt: cuint): cint {.varargs, cdecl,
    importc: "seccomp_rule_add_exact", dynlib: libname.}



#*
#  Add a new rule to the filter
#  @param ctx the filter context
#  @param action the filter action
#  @param syscall the syscall number
#  @param arg_cnt  the number of elements in the arg_array parameter
#  @param arg_array array of scmp_arg_cmp structs
#
#  This function adds a series of new argument/value checks to the seccomp
#  filter for the given syscall; multiple argument/value checks can be
#  specified and they will be chained together (AND'd together) in the filter.
#  If the specified rule can not be represented on the architecture the
#  function will fail.  Returns zero on success, negative values on failure.
#
#
proc seccompRuleAddExactArray*(ctx: ScmpFilterCtx; action: uint32;
                               syscall: cint; argCnt: cuint;
                               argArray: ptr ScmpArgCmp): cint {.cdecl,
    importc: "seccomp_rule_add_exact_array", dynlib: libname.}



#*
#  Generate seccomp Pseudo Filter Code (PFC) and export it to a file
#  @param ctx the filter context
#  @param fd the destination fd
#
#  This function generates seccomp Pseudo Filter Code (PFC) and writes it to
#  the given fd.  Returns zero on success, negative values on failure.
#
#
proc seccompExportPfc*(ctx: ScmpFilterCtx; fd: cint): cint {.cdecl,
    importc: "seccomp_export_pfc", dynlib: libname.}



#*
#  Generate seccomp Berkley Packet Filter (BPF) code and export it to a file
#  @param ctx the filter context
#  @param fd the destination fd
#
#  This function generates seccomp Berkley Packer Filter (BPF) code and writes
#  it to the given fd.  Returns zero on success, negative values on failure.
#
#
proc seccompExportBpf*(ctx: ScmpFilterCtx; fd: cint): cint {.cdecl,
    importc: "seccomp_export_bpf", dynlib: libname.}
#
#  pseudo syscall definitions
#
# NOTE - pseudo syscall values {-1..-99} are reserved

const
  NR_SCMP_ERROR* = - 1
  NR_SCMP_UNDEF* = - 2

# socket syscalls

const
  PNR_socket* = - 101
  PNR_bind* = - 102
  PNR_connect* = - 103
  PNR_listen* = - 104
  PNR_accept* = - 105
  PNR_getsockname* = - 106
  PNR_getpeername* = - 107
  PNR_socketpair* = - 108
  PNR_send* = - 109
  PNR_recv* = - 110
  PNR_sendto* = - 111
  PNR_recvfrom* = - 112
  PNR_shutdown* = - 113
  PNR_setsockopt* = - 114
  PNR_getsockopt* = - 115
  PNR_sendmsg* = - 116
  PNR_recvmsg* = - 117
  PNR_accept4* = - 118
  PNR_recvmmsg* = - 119
  PNR_sendmmsg* = - 120

# ipc syscalls

const
  PNR_semop* = - 201
  PNR_semget* = - 202
  PNR_semctl* = - 203
  PNR_semtimedop* = - 204
  PNR_msgsnd* = - 211
  PNR_msgrcv* = - 212
  PNR_msgget* = - 213
  PNR_msgctl* = - 214
  PNR_shmat* = - 221
  PNR_shmdt* = - 222
  PNR_shmget* = - 223
  PNR_shmctl* = - 224

# single syscalls

const
  PNR_archPrctl* = - 10001

const
  PNR_bdflush* = - 10002
  PNR_break* = - 10003
  PNR_chown32* = - 10004
  PNR_epollCtlOld* = - 10005
  PNR_epollWaitOld* = - 10006
  PNR_fadvise6464* = - 10007
  PNR_fchown32* = - 10008
  PNR_fcntl64* = - 10009
  PNR_fstat64* = - 10010
  PNR_fstatat64* = - 10011
  PNR_fstatfs64* = - 10012
  PNR_ftime* = - 10013
  PNR_ftruncate64* = - 10014
  PNR_getegid32* = - 10015
  PNR_geteuid32* = - 10016
  PNR_getgid32* = - 10017
  PNR_getgroups32* = - 10018
  PNR_getresgid32* = - 10019
  PNR_getresuid32* = - 10020
  PNR_getuid32* = - 10021
  PNR_gtty* = - 10022
  PNR_idle* = - 10023
  PNR_ipc* = - 10024
  PNR_lchown32* = - 10025
  PNR_llseek* = - 10026
  PNR_lock* = - 10027
  PNR_lstat64* = - 10028
  PNR_mmap2* = - 10029
  PNR_mpx* = - 10030
  PNR_newfstatat* = - 10031
  PNR_newselect* = - 10032
  PNR_nice* = - 10033
  PNR_oldfstat* = - 10034
  PNR_oldlstat* = - 10035
  PNR_oldolduname* = - 10036
  PNR_oldstat* = - 10037
  PNR_olduname* = - 10038
  PNR_prof* = - 10039
  PNR_profil* = - 10040
  PNR_readdir* = - 10041
  PNR_security* = - 10042
  PNR_sendfile64* = - 10043
  PNR_setfsgid32* = - 10044
  PNR_setfsuid32* = - 10045
  PNR_setgid32* = - 10046
  PNR_setgroups32* = - 10047
  PNR_setregid32* = - 10048
  PNR_setresgid32* = - 10049
  PNR_setresuid32* = - 10050
  PNR_setreuid32* = - 10051
  PNR_setuid32* = - 10052
  PNR_sgetmask* = - 10053
  PNR_sigaction* = - 10054
  PNR_signal* = - 10055
  PNR_sigpending* = - 10056
  PNR_sigprocmask* = - 10057
  PNR_sigreturn* = - 10058
  PNR_sigsuspend* = - 10059
  PNR_socketcall* = - 10060
  PNR_ssetmask* = - 10061
  PNR_stat64* = - 10062
  PNR_statfs64* = - 10063
  PNR_stime* = - 10064
  PNR_stty* = - 10065
  PNR_truncate64* = - 10066
  PNR_tuxcall* = - 10067
  PNR_ugetrlimit* = - 10068
  PNR_ulimit* = - 10069
  PNR_umount* = - 10070
  PNR_vm86* = - 10071
  PNR_vm86old* = - 10072
  PNR_waitpid* = - 10073
  PNR_createModule* = - 10074
  PNR_getKernelSyms* = - 10075
  PNR_getThreadArea* = - 10076
  PNR_nfsservctl* = - 10077
  PNR_queryModule* = - 10078
  PNR_setThreadArea* = - 10079
  PNR_sysctl* = - 10080
  PNR_uselib* = - 10081
  PNR_vserver* = - 10082
  PNR_armFadvise6464* = - 10083
  PNR_armSyncFileRange* = - 10084
  PNR_pciconfigIobase* = - 10086
  PNR_pciconfigRead* = - 10087
  PNR_pciconfigWrite* = - 10088
  PNR_syncFileRange2* = - 10089
  PNR_syscall* = - 10090
  PNR_afsSyscall* = - 10091
  PNR_fadvise64* = - 10092
  PNR_getpmsg* = - 10093
  PNR_ioperm* = - 10094
  PNR_iopl* = - 10095
  PNR_migratePages* = - 10097
  PNR_modifyLdt* = - 10098
  PNR_putpmsg* = - 10099
  PNR_syncFileRange* = - 10100
  PNR_select* = - 10101
  PNR_vfork* = - 10102
  PNR_cachectl* = - 10103
  PNR_cacheflush* = - 10104

when not defined(NR_cacheflush):
  when defined(ARM_NR_cacheflush):
    const
      NR_cacheflush* = aRM_NR_cacheflush
  else:
    const
      NR_cacheflush* = PNR_cacheflush
const
  PNR_sysmips* = - 10106
  PNR_timerfd* = - 10107
  PNR_time* = - 10108
  PNR_getrandom* = - 10109
  PNR_memfdCreate* = - 10110
  PNR_kexecFileLoad* = - 10111
  PNR_sysfs* = - 10145
  PNR_oldwait4* = - 10146
  PNR_access* = - 10147
  PNR_alarm* = - 10148
  PNR_chmod* = - 10149
  PNR_chown* = - 10150
  PNR_creat* = - 10151
  PNR_dup2* = - 10152
  PNR_epollCreate* = - 10153
  PNR_epollWait* = - 10154
  PNR_eventfd* = - 10155
  PNR_fork* = - 10156
  PNR_futimesat* = - 10157
  PNR_getdents* = - 10158
  PNR_getpgrp* = - 10159
  PNR_inotifyInit* = - 10160
  PNR_lchown* = - 10161
  PNR_link* = - 10162
  PNR_lstat* = - 10163
  PNR_mkdir* = - 10164
  PNR_mknod* = - 10165
  PNR_open* = - 10166
  PNR_pause* = - 10167
  PNR_pipe* = - 10168
  PNR_poll* = - 10169
  PNR_readlink* = - 10170
  PNR_rename* = - 10171
  PNR_rmdir* = - 10172
  PNR_signalfd* = - 10173
  PNR_stat* = - 10174
  PNR_symlink* = - 10175
  PNR_unlink* = - 10176
  PNR_ustat* = - 10177
  PNR_utime* = - 10178
  PNR_utimes* = - 10179
  PNR_getrlimit* = - 10180
  PNR_mmap* = - 10181
  PNR_breakpoint* = - 10182

when not defined(NR_breakpoint):
  when defined(ARM_NR_breakpoint):
    const
      NR_breakpoint* = aRM_NR_breakpoint
  else:
    const
      NR_breakpoint* = PNR_breakpoint
const
  PNR_setTls* = - 10183

when not defined(NR_set_tls):
  when defined(ARM_NR_set_tls):
    const
      NR_setTls* = ARM_NR_setTls
  else:
    const
      NR_setTls* = PNR_setTls
const
  PNR_usr26* = - 10184

when not defined(NR_usr26):
  when defined(ARM_NR_usr26):
    const
      NR_usr26* = aRM_NR_usr26
  else:
    const
      NR_usr26* = PNR_usr26
const
  PNR_usr32* = - 10185

when not defined(NR_usr32):
  when defined(ARM_NR_usr32):
    const
      NR_usr32* = aRM_NR_usr32
  else:
    const
      NR_usr32* = PNR_usr32
const
  PNR_multiplexer* = - 10186
  PNR_rtas* = - 10187
  PNR_spuCreate* = - 10188
  PNR_spuRun* = - 10189
  PNR_subpageProt* = - 10189
  PNR_swapcontext* = - 10190
  PNR_sysDebugSetcontext* = - 10191
  PNR_switchEndian* = - 10191
  PNR_getMempolicy* = - 10192
  PNR_movePages* = - 10193
  PNR_mbind* = - 10194
  PNR_setMempolicy* = - 10195
  PNR_s390RuntimeInstr* = - 10196
  PNR_s390PciMmioRead* = - 10197
  PNR_s390PciMmioWrite* = - 10198
  PNR_membarrier* = - 10199
  PNR_userfaultfd* = - 10200





