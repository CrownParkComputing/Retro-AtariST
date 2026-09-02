#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
assembler="${VASM:-vasmm68k_mot}"
linker="${VLINK:-vlink}"
object="$here/core-demo.o"
program="$here/COREDEMO.PRG"
image="$here/retro-atarist-core-demo.st"

"$assembler" -m68000 -Fvobj -quiet -o "$object" "$here/core-demo.s"
"$linker" -b ataritos -nostdlib -s -o "$program" "$object"
dd if=/dev/zero of="$image" bs=1024 count=720 status=none
mformat -a -t 80 -h 2 -n 9 -i "$image" ::
MTOOLS_NO_VFAT=1 mmd -i "$image" ::AUTO
MTOOLS_NO_VFAT=1 mcopy -i "$image" -pm "$program" ::AUTO/COREDEMO.PRG
rm -f "$object" "$program"
