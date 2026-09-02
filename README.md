# Retro-AtariST

Retro-AtariST is a native iOS and Android front end for the **Hatari** Atari ST
emulator. It uses Dear ImGui over Metal on iOS and OpenGL ES on Android; it
contains no Flutter engine, Dart runtime, SDL windowing layer or JIT compiler.

It emulates the **ST**, **Mega ST**, **STE**, **Mega STE**, **TT** and
**Falcon 030**. Hatari runs in-process behind a small C ABI, on its own thread.

## Layout

```
ios/RetroAtariST/        UIKit/Metal application shell and Info.plist
android/                 NativeActivity/OpenGL ES application and Gradle build
native/frontend/         Touch-first Dear ImGui launcher and emulator overlay
native/atarist_core/
  bridge/                Stable C ABI, emulation thread and mailbox
  backend/               Headless implementation of Hatari's UI seam
  ios/                   iOS target integration and RemoteIO audio
third_party/imgui/        Dear ImGui, MIT licensed
vendor/hatari/            Hatari, as an unmodified submodule
```

Each shell owns lifecycle, GPU presentation, physical input and its system
document picker. Machine selection, navigation, media controls and the
in-session display are drawn by the shared C++ ImGui frontend.

The Artwork screen signs into Crown Park Computing RetroMedia, matches local
disk names against the `atarist` catalogue, and caches selected card art.
Sessions are stored in iOS Keychain or Android Keystore-backed encrypted
preferences; passwords are not persisted. iOS exposes artwork only and has no
game-catalogue or game-download calls. Android keeps the authenticated
administrator catalogue and download workflow.

## Building for iOS

Requirements: macOS, Xcode and CMake 3.24 or newer.

```sh
git submodule update --init --recursive
./ios/build.sh iphonesimulator

# Physical device / archive, with signing:
./ios/build.sh iphoneos -DDEVELOPMENT_TEAM=YOUR_TEAM_ID
```

The script generates an Xcode project under `ios/build/<sdk>` and builds the
`RetroAtariST` application. Hatari is linked statically into the bundle. The
68000/68030 CPU core is interpreter-only; Hatari's JIT sources are not built.

## Building for Android

Requirements: Android SDK 36, NDK 28.2 and JDK 17.

```sh
cd android
./gradlew :app:assembleDebug
```

The ARM64 APK is written to
`android/app/build/outputs/apk/debug/app-debug.apk`. It contains the native
NativeActivity shell, shared ImGui frontend, Hatari core, EmuTOS and core demo.

## ROMs and software

At first launch the app installs its bundled **EmuTOS 1.4 UK** image, so the
open desktop can boot without a proprietary ROM or commercial game. If the
library is empty, **Run bundled core demo** starts a project-authored floppy
that visibly checks EmuTOS boot, CPU/frame timing, video and keyboard input.
You can alternatively import a TOS image that you are entitled to use.

Disk images are imported the same way and copied into the app's
`Documents/AtariST/Games` folder. The app accepts ST, MSA, DIM, STX, IPF, IMG
and ZIP media. Its Files folder is exposed through iOS file sharing.

For a local personal build, copy
`ios/RetroAtariST/LocalCredentials.h.example` to `LocalCredentials.h` to opt
into first-run auto-login. The real file is gitignored and must not be used for
a distributable build because its password is compiled into that personal app.
Android personal builds read `retromedia.email` and `retromedia.password` from
the ignored `android/local.properties`; omit both values for distribution.

## Why Hatari and not ASE

The project began from a request to build on
[thebitculture/ase](https://github.com/thebitculture/ase). ASE is a useful
reference, but its C#/.NET core is not suitable for a small native iOS binary.
Hatari is C, mature, accurate and can be linked directly into the application.

## Licence

GPL v2 or later, because the application links Hatari. Dear ImGui is included
under its MIT licence. See `LICENSE` and `THIRD_PARTY_NOTICES.md`; all three
licence files are copied into the application resources.
