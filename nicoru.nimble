# Package

version       = "0.1.0"
author        = "fox0430"
description   = "A container runtime written in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["nicoru"]


# Dependencies

requires "nim >= 1.4.8"
requires "https://github.com/def-/nim-syscall >= 0.1"
requires "seccomp >= 0.2.1"
