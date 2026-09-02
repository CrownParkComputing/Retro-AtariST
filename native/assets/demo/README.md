# Retro-AtariST core demo

`retro-atarist-core-demo.st` is a project-authored, redistributable Atari ST
floppy image. It boots `AUTO/COREDEMO.PRG`, displays a moving colour marker and
waits for keyboard input before returning to the EmuTOS desktop. This gives a
new installation a visible CPU, video, boot-ROM and input check without an
Atari TOS ROM or commercial software.

The source is `core-demo.s`. Rebuild the image with `./build.sh`; the only build
dependencies are vasm/vlink and mtools. The generated disk is FAT12, 80 tracks,
two sides and nine sectors per track.

Copyright (C) 2026 Crown Park Computing. Distributed under GNU GPL version 2 or
later, matching Retro-AtariST and Hatari.
