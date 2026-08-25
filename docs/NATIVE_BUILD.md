# Building the native core

```sh
git submodule update --init --recursive
./native/atarist_core/linux/build.sh
```

Output: `native/atarist_core/linux/build/libatarist_core.so`, which is where
`AtariStNativePaths.coreLibraryPath` looks for it. The launcher runs against a
stub core without it and says so in a banner, so this is not needed for UI work.

## How the build is wired, and why it looks inside-out

Hatari is the **top-level CMake project**; this project is injected into it via
`-DCMAKE_PROJECT_INCLUDE=native/atarist_core/embed.cmake`.

The obvious arrangement — our `CMakeLists.txt` on top, `add_subdirectory(vendor/hatari)`
— does not work. Hatari resolves several paths through `${CMAKE_SOURCE_DIR}`,
which means *the top-level source directory*:

* `cmake/config-cmake.h` (its `config.h` template)
* `cmake/` (its `Find*.cmake` modules)
* `tests/*/CMakeLists.txt` (sources listed as `src/file.c`)

Nest Hatari and every one of those starts pointing at our directory instead.
That is not a bug upstream — nobody else embeds it — but it means the nesting
has to go the other way.

`embed.cmake` runs right after Hatari's `project()` call, which is too early to
reference its targets or its `find_package` results, so it `cmake_language(DEFER)`s
an `include()` of `target.cmake` to the end of that directory's processing.
It is an `include`, not an `add_subdirectory`, because CMake refuses to create
a subdirectory during deferred execution. That in turn is why every path in
`target.cmake` is written against `ATARIST_CORE_DIR` — inside an `include`,
`CMAKE_CURRENT_SOURCE_DIR` names the *Hatari* tree.

Requires CMake **3.19+** (for `cmake_language(DEFER)`).

## Object libraries

`libatarist_core` links `Core`, `CoreHmsa`, `Falcon`, `UaeCpu` and `Debug` —
deliberately the same set upstream's own libretro target uses — with `Ui` and
`GuiSdl` replaced by `backend/`. The build runs `--target atarist_core`, so
Hatari's `hatari` executable and its SDL front end are configured but never
compiled.

## SDL2 headers are needed even though no SDL is linked

Hatari's CMake calls `find_package(SDL2)` at configure time, and a few core
headers include SDL type definitions. None of SDL's *code* ends up in the
library. On Linux the distro package is enough. For Android and iOS, point
CMake at SDL2's headers (`-DSDL2_INCLUDE_DIRS=...`); a headers-only checkout of
SDL2 satisfies it.

## Cross-compiling

The 68000 emulator is **generated at build time** by `build68k` and `gencpu`.
Hatari's own CMake already handles building those for the host while the output
is compiled for the target, which is the main reason this project consumes
Hatari's build rather than re-listing its sources.

```sh
export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.1.10909125
./native/atarist_core/android/build.sh arm64-v8a
./native/atarist_core/android/build.sh armeabi-v7a   # 32-bit handhelds
./native/atarist_core/ios/build.sh iphoneos arm64   # never yet run
```

The Android script installs straight into
`flutter_app/android/app/src/main/jniLibs/<abi>/`, where the OS loader picks it
up by bare name. Both ABIs are known to build.

### Five things Android needed

Each of these failed the build outright, and none is obvious from the source:

1. **Hatari's CMake `FATAL_ERROR`s without an SDL package**, even though the
   objects we link reference **zero** SDL symbols (`nm -u ... | grep -c
   '\bSDL_'` → 0). Satisfied with an empty
   `native/atarist_core/cmake-stubs/SDL2Config.cmake`, passed as
   `-DSDL2_DIR=...` — a prefix path expects a `<prefix>/lib/cmake/SDL2/`
   layout, and the NDK toolchain sets `CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY`,
   which confines `find_package` to the sysroot and skips the stub unless it is
   relaxed to `BOTH`.

2. **`-DENABLE_DSP_EMU=0`.** `falcon/dsp_cpu.c` is the only Hatari source that
   genuinely needs an SDL header (`<SDL_timer.h>`, for `SDL_GetTicks`). It is
   the Falcon DSP; no ST or STE title uses it.

3. **`-lpthread` does not exist on Android.** Bionic puts pthread in libc, so
   the link fails with "unable to find library -lpthread". Same on Apple.

4. **API 26, not Flutter's default 24** — AAudio is 26+. The app's `minSdk` is
   raised to match; lowering it again without giving the sink a
   runtime-loaded fallback would crash on load for 24/25 users rather than
   merely running silent. `AAudioStreamBuilder_setUsage` is 28+ and is
   deliberately not called, to avoid pushing the floor higher for a routing
   hint.

5. **Strip the result.** Hatari's CMake emits debug info even in Release: the
   arm64 library is ~83MB unstripped and ~18MB stripped. The build script
   strips it and keeps `libatarist_core.unstripped.so` in the build tree for
   symbolication.

### Audio backends

One sink is compiled per target (`target.cmake` picks):

| target | sink | notes |
|---|---|---|
| Linux/Windows/macOS | `audio_sink_sdl.c` | SDL is already linked there via Hatari's own `find_package` |
| Android | `audio_sink_aaudio.c` | AAudio: NDK, plain C, no C++ runtime |
| iOS / macOS | `audio_sink_ios.m` | RemoteIO Audio Unit — **written but never compiled**, see below |

`atarist_core_audio_backend()` reports which one is live, and the About screen
shows it, so silence is diagnosable.

`audio_sink_ios.m` is Objective-C for one reason: **AVAudioSession**. The Audio
Unit half is pure C, but without configuring the session first, iOS silences an
app that has not asked whenever the ringer switch is on — inaudible for half
your users, with no error anywhere. It asks for `Playback` with
`MixWithOthers`: audible regardless of the switch, without stopping whatever
the user already had playing.

Two things to watch on the first real build, both classic RemoteIO mistakes:
the stream format goes on **bus 0, scope Input** ("the input to the output
bus"), and the format is **interleaved** stereo, so the render callback gets
one buffer carrying both channels rather than two.

### No JIT, on every target

The 68000 core is the interpreted one — Hatari's `src/cpu/CMakeLists.txt`
never compiles its `jit/` directory. Verify after any build:

```sh
llvm-nm -D --undefined-only libatarist_core.so | grep -E 'mprotect|mmap|__clear_cache|pthread_jit'
```

Empty is required. This is what keeps iOS App Store distribution possible at
all — W^X/JIT is forbidden there for non-browsers. **Do not enable Hatari's
JIT for Falcon speed without accepting that iOS is then off the table.**

## Verifying a build

```sh
nm -D --defined-only .../libatarist_core.so | grep -c ' T '
```

Must be **25** — the `atarist_core_*` entry points and nothing else. See
ARCHITECTURE.md for why that matters on Android.

A missing optional dependency does **not** fail the link; it fails at `dlopen`
with something like `undefined symbol: udev_new`, which reads as a broken
library rather than a missing `-l`. `target.cmake` mirrors Hatari's own
optional-dependency list to prevent that.

## Hatari argument traps

The bridge configures Hatari through its command line (see ARCHITECTURE.md).
Four things about that are not obvious, and each one presented as "the game
does not launch" rather than as an argument mistake:

1. **`--configfile` must come FIRST.** Its handler calls
   `Configuration_Load()`, which overwrites the *whole* of `ConfigureParams`
   from that file. Emitted last, it silently undid every option before it.
   The tell was two log lines one apart:

   ```
   INFO : Inserted disk '.../1943.st' to drive A:.
   INFO : Floppy A: has been removed from drive.
   ```

2. **`--configfile` needs the file to already exist.** It is checked with
   `CHECK_FILE`, so naming a path where the config *will* live fails parameter
   parsing, and Hatari prints its usage and exits inside `Main_Init`. The
   bridge creates an empty one first; Hatari fills it in.

3. **The joystick options are `--joy0` / `--joy1`, not `--joystick0`.** The
   option table lists them as `--joy<port>` and the parser takes the port from
   the last character of the option string itself
   (`port = opt[strlen(opt)-1] - '0'`).

4. **`--monitor` is not cosmetic.** TOS reads the monitor type at boot and
   picks its screen mode from it. Without it the machine can come up in
   ST-HIGH: a 640x400 two-colour desktop in which no game runs. It boots, it
   draws, and the game never appears.

A useful debugging note: Hatari logs to **stderr** (unbuffered) while a test
harness usually prints to **stdout** (block-buffered when piped). All of
Hatari's lines therefore appear *before* the harness's, whatever order they
actually happened in. That cost an hour chasing an "eject" that was really
happening at shutdown.
