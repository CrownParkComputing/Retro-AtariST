# libatarist_core -- Hatari's emulation core plus this project's UI backend
# and dart:ffi bridge, as one shared library.
#
# This file is NOT a CMakeLists. It is include()d into Hatari's own top-level
# directory scope by embed.cmake -- read that first; it explains why the
# nesting goes this way round, and why this is an include rather than an
# add_subdirectory. The practical consequence is that everything Hatari's CMake
# worked out (config.h, ZLIB_FOUND, the generated 68000 emulator, the
# cross-compilation rules for its code generators) is already in scope here.
#
# Because it is included rather than added as a subdirectory, CMAKE_CURRENT_*
# refers to HATARI's directory, not this one. Every path below therefore goes
# through ATARIST_CORE_DIR, which embed.cmake sets. A bare relative source path
# here would be silently resolved against the Hatari tree.
#
# The object-library set below is deliberately the same one upstream's own
# libretro target uses -- Core, CoreHmsa, Falcon, UaeCpu, Debug -- with Ui and
# GuiSdl replaced by our backend/.

# Derived here rather than taken from embed.cmake: variables set during
# CMAKE_PROJECT_INCLUDE do not survive into deferred execution, so relying on
# one produced an empty path and a "cannot find source file /backend/screen.c".
# CMAKE_CURRENT_LIST_DIR is the directory of THIS file even when it is
# include()d into someone else's scope, which is exactly what is wanted.
get_filename_component(ATARIST_CORE_DIR "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
set(HATARI_TOP "${CMAKE_SOURCE_DIR}")

set(BACKEND_SOURCES
	"${ATARIST_CORE_DIR}/backend/screen.c"
	"${ATARIST_CORE_DIR}/backend/audio.c"
	"${ATARIST_CORE_DIR}/backend/timing.c"
	"${ATARIST_CORE_DIR}/backend/gui_event.c"
	"${ATARIST_CORE_DIR}/backend/keymap.c"
	"${ATARIST_CORE_DIR}/backend/joy_ui.c"
	"${ATARIST_CORE_DIR}/backend/statusbar.c"
	"${ATARIST_CORE_DIR}/backend/dialogs.c"
	"${ATARIST_CORE_DIR}/backend/microphone.c")

# Exactly one audio sink is compiled in. SDL only where SDL is already being
# linked anyway (desktop); everywhere else the null sink keeps the build
# working and the emulator silent until a native sink is written.
if(ANDROID)
	# AAudio: in the NDK, plain C, no new dependency beyond libaaudio itself.
	set(AUDIO_SINK "${ATARIST_CORE_DIR}/bridge/audio_sink_aaudio.c")
elseif(APPLE)
	# RemoteIO Audio Unit. Objective-C only because AVAudioSession is: without
	# configuring the session, iOS silences the app whenever the ringer switch
	# is on, with no error anywhere.
	set(AUDIO_SINK "${ATARIST_CORE_DIR}/bridge/audio_sink_ios.m")
elseif(SDL2_LIBRARIES)
	set(AUDIO_SINK "${ATARIST_CORE_DIR}/bridge/audio_sink_sdl.c")
else()
	# Builds and runs silent rather than failing to link, so a new platform
	# is never blocked on its audio backend.
	set(AUDIO_SINK "${ATARIST_CORE_DIR}/bridge/audio_sink_null.c")
endif()

set(BRIDGE_SOURCES
	"${ATARIST_CORE_DIR}/bridge/atarist_bridge.c"
	"${AUDIO_SINK}")

add_library(atarist_core SHARED
	${BACKEND_SOURCES}
	${BRIDGE_SOURCES}
	$<TARGET_OBJECTS:Core>
	$<TARGET_OBJECTS:CoreHmsa>
	$<TARGET_OBJECTS:Falcon>
	$<TARGET_OBJECTS:UaeCpu>
	$<TARGET_OBJECTS:Debug>)

set_target_properties(atarist_core PROPERTIES
	C_STANDARD 11
	C_STANDARD_REQUIRED ON)

target_include_directories(atarist_core PRIVATE
	"${ATARIST_CORE_DIR}/bridge"
	"${HATARI_TOP}/src"
	"${HATARI_TOP}/src/includes"
	"${HATARI_TOP}/src/debug"
	"${HATARI_TOP}/src/falcon"
	"${HATARI_TOP}/src/cpu"
	# config.h is generated into the build tree, not the source tree.
	"${CMAKE_BINARY_DIR}")

# pthread is a separate library on glibc but is part of libc on Android's
# bionic, where -lpthread does not exist at all ("ld.lld: error: unable to
# find library -lpthread"). Apple's libSystem is the same story.
target_link_libraries(atarist_core PRIVATE m)
if(NOT ANDROID AND NOT APPLE)
	target_link_libraries(atarist_core PRIVATE pthread)
endif()

# Mirrors the optional-dependency list in Hatari's own src/CMakeLists.txt.
# Kept in that order and with the same variable names so a diff against
# upstream is readable when a new dependency appears there.
#
# Missing one of these does NOT fail the link -- the symbols come from Hatari's
# object files, which link fine -- it fails at dlopen with
# "undefined symbol: udev_new", which looks like a broken library rather than a
# missing -l. That is exactly how this list was found to be incomplete.
if(Math_FOUND AND NOT APPLE)
	target_link_libraries(atarist_core PRIVATE ${MATH_LIBRARY})
endif()
if(Readline_FOUND)
	target_link_libraries(atarist_core PRIVATE ${READLINE_LIBRARY})
endif()
if(ZLIB_FOUND)
	target_link_libraries(atarist_core PRIVATE ${ZLIB_LIBRARY})
endif()
if(LibArchive_FOUND)
	target_link_libraries(atarist_core PRIVATE ${LibArchive_LIBRARIES})
endif()
if(PNG_FOUND)
	target_link_libraries(atarist_core PRIVATE ${PNG_LIBRARY})
endif()
if(X11_FOUND)
	target_link_libraries(atarist_core PRIVATE ${X11_LIBRARIES})
endif()
if(PortMidi_FOUND)
	target_link_libraries(atarist_core PRIVATE ${PORTMIDI_LIBRARY})
endif()
if(CapsImage_FOUND)
	target_link_libraries(atarist_core PRIVATE ${CAPSIMAGE_LIBRARY})
endif()
if(Udev_FOUND)
	target_link_libraries(atarist_core PRIVATE ${UDEV_LIBRARY})
endif()
if(Capstone_FOUND)
	target_link_libraries(atarist_core PRIVATE ${CAPSTONE_LIBRARY})
endif()
if(ANDROID)
	target_link_libraries(atarist_core PRIVATE aaudio)
endif()
if(APPLE)
	# Frameworks, not -l: AudioToolbox provides the Audio Unit API and
	# AVFoundation the session. Both are present on iOS and macOS.
	target_link_libraries(atarist_core PRIVATE
		"-framework AudioToolbox"
		"-framework AVFoundation"
		"-framework Foundation")
	set_source_files_properties("${ATARIST_CORE_DIR}/bridge/audio_sink_ios.m"
		PROPERTIES COMPILE_FLAGS "-fobjc-arc")
endif()

# A few Hatari core sources include SDL headers for their type definitions even
# though this library links no SDL code at all.
if(SDL2_INCLUDE_DIRS)
	target_include_directories(atarist_core PRIVATE ${SDL2_INCLUDE_DIRS})
endif()
if(SDL2_LIBRARIES)
	target_link_libraries(atarist_core PRIVATE ${SDL2_LIBRARIES})
endif()

# Only the atarist_core_* entry points are exported. Everything else -- and
# "everything else" here is the whole of Hatari, thousands of symbols with
# names as generic as `main`, `select` and `debug` -- stays local.
#
# This is not tidiness. On Android the app, Flutter's engine and every plugin
# .so share one symbol namespace, and an exported `main` or `select` from an
# emulator core is a genuinely vicious source of crashes in unrelated code.
# macOS/iOS use a two-level namespace and are safe either way, but hiding
# costs nothing there.
if(NOT APPLE AND NOT WIN32)
	target_link_options(atarist_core PRIVATE
		"-Wl,--version-script=${ATARIST_CORE_DIR}/atarist_core.map")
endif()

set_target_properties(atarist_core PROPERTIES
	C_VISIBILITY_PRESET hidden
	VISIBILITY_INLINES_HIDDEN ON)
