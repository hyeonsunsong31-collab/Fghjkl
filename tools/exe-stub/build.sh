#!/bin/sh
# Rebuilds the Windows launcher embedded in Jarvis.swiftpm/Sources/Core/Studio/Convert/ExeStub.swift.
# Needs mingw-w64 (Ubuntu: apt-get install mingw-w64). The output is deterministic.
set -e
cd "$(dirname "$0")"
x86_64-w64-mingw32-windres stub.rc -O coff -o stub.res
x86_64-w64-mingw32-gcc -Os -s -nostdlib -nostartfiles -ffreestanding -fno-stack-protector -fno-builtin \
  -fno-asynchronous-unwind-tables -fno-ident -Wall -Wno-unused-parameter \
  -Wl,--entry=start -Wl,--subsystem,windows -Wl,--no-insert-timestamp -Wl,--gc-sections \
  -o stub.exe stub.c stub.res -lkernel32 -lshell32 -luser32
rm -f stub.res
ls -l stub.exe
sha256sum stub.exe
