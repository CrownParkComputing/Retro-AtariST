cmake_minimum_required(VERSION 3.22.1)
project(retro_atarist_android LANGUAGES C CXX)

set(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../../")
set(IMGUI_DIR "${REPO_ROOT}/third_party/imgui")
set(FRONTEND_DIR "${REPO_ROOT}/native/frontend")
set(CORE_DIR "${REPO_ROOT}/native/atarist_core")

add_library(atarist_core SHARED IMPORTED)
set_target_properties(atarist_core PROPERTIES
    IMPORTED_LOCATION "${CORE_DIR}/android/prebuilt/${ANDROID_ABI}/libatarist_core.so")

add_library(retro_atarist SHARED
    main.cpp
    "${ANDROID_NDK}/sources/android/native_app_glue/android_native_app_glue.c"
    "${FRONTEND_DIR}/frontend.cpp"
    "${IMGUI_DIR}/imgui.cpp"
    "${IMGUI_DIR}/imgui_draw.cpp"
    "${IMGUI_DIR}/imgui_tables.cpp"
    "${IMGUI_DIR}/imgui_widgets.cpp"
    "${IMGUI_DIR}/backends/imgui_impl_android.cpp"
    "${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp")

target_compile_features(retro_atarist PRIVATE cxx_std_20)
target_compile_definitions(retro_atarist PRIVATE IMGUI_IMPL_OPENGL_ES3)
target_include_directories(retro_atarist PRIVATE
    "${CORE_DIR}/bridge"
    "${FRONTEND_DIR}"
    "${IMGUI_DIR}"
    "${IMGUI_DIR}/backends"
    "${ANDROID_NDK}/sources/android/native_app_glue")
target_link_libraries(retro_atarist PRIVATE
    atarist_core android EGL GLESv3 log)
target_link_options(retro_atarist PRIVATE "-Wl,-z,max-page-size=16384")
