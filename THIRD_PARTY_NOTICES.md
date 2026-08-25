# Third-party notices

## Hatari

The Atari ST/STE/TT/Falcon emulation in this app is **Hatari**, by the Hatari
team, used under the **GNU General Public Licence version 2 or later**.

* Source: https://github.com/hatari/hatari
* Vendored at `vendor/hatari` as a git submodule, **unmodified**. This project
  adds its own UI backend (`native/atarist_core/backend/`) alongside Hatari's
  SDL one rather than patching any Hatari source file, so the exact upstream
  revision this app was built from is the submodule's recorded commit.

Because this app links Hatari, the app as a whole is distributed under the
GPL v2 or later. The full licence text is in `LICENSE`.

## Not included

* **TOS** -- the Atari ST's operating system ROM. Copyrighted by Atari and
  supplied by the user.
* **Commercial games.** The app plays disk images already on the user's device
  and does not download, link to, or help locate any.

## Referenced but not used

**ASE (Atari System Emulator)**, by The Bit Culture, GPL v3 --
https://github.com/thebitculture/ase. This project was started from a request
to build on ASE and consulted it as a reference, but ships none of its code:
ASE is C#/.NET, which cannot be bridged into Flutter on mobile. See the README.
