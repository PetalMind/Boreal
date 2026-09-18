cmake_minimum_required(VERSION 3.20)

project(PolicePursuitRadar LANGUAGES CXX)

if(NOT WIN32)
    message(WARNING "PolicePursuitRadar targets the 32-bit Windows GTA SA executable. Use an i686 MinGW or MSVC x86 toolchain.")
endif()

set(PLUGIN_SDK_DIR "" CACHE PATH "Path to a checkout of DK22Pac/plugin-sdk")
if(NOT PLUGIN_SDK_DIR OR NOT EXISTS "${PLUGIN_SDK_DIR}/shared/plugin.h")
    message(FATAL_ERROR "Set PLUGIN_SDK_DIR to the plugin-sdk checkout before configuring.")
endif()

file(GLOB_RECURSE PLUGIN_SDK_SOURCES CONFIGURE_DEPENDS
    "${PLUGIN_SDK_DIR}/shared/*.cpp"
    "${PLUGIN_SDK_DIR}/hooking/*.cpp"
    "${PLUGIN_SDK_DIR}/safetyhook/*.cpp"
    "${PLUGIN_SDK_DIR}/plugin_sa/game_sa/*.cpp"
)

file(GLOB MOD_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
add_library(PolicePursuitRadar SHARED ${MOD_SOURCES} ${PLUGIN_SDK_SOURCES})

target_compile_features(PolicePursuitRadar PRIVATE cxx_std_23)
target_compile_definitions(PolicePursuitRadar PRIVATE
    GTASA=1
    PLUGIN_SGV_10US=1
    RW=1
    _DX9_SDK_INSTALLED
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_include_directories(PolicePursuitRadar PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${PLUGIN_SDK_DIR}/plugin_sa"
    "${PLUGIN_SDK_DIR}/plugin_sa/game_sa"
    "${PLUGIN_SDK_DIR}/plugin_sa/game_sa/enums"
    "${PLUGIN_SDK_DIR}/plugin_sa/game_sa/rw"
    "${PLUGIN_SDK_DIR}/shared"
    "${PLUGIN_SDK_DIR}/shared/game"
    "${PLUGIN_SDK_DIR}/shared/dxsdk"
    "${PLUGIN_SDK_DIR}/safetyhook"
)

set_target_properties(PolicePursuitRadar PROPERTIES
    PREFIX ""
    OUTPUT_NAME "PolicePursuitRadar"
    SUFFIX ".asi"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dist"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/dist"
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib"
)

if(MINGW)
    target_compile_options(PolicePursuitRadar PRIVATE
        -fpermissive
        -fcommon
        -fms-extensions
        -Wno-invalid-offsetof
        -Wno-microsoft-include
    )
    target_link_options(PolicePursuitRadar PRIVATE -static-libgcc -static-libstdc++)
endif()

if(MSVC)
    set_property(TARGET PolicePursuitRadar PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
    target_compile_options(PolicePursuitRadar PRIVATE /EHsc /permissive-)
endif()

target_link_libraries(PolicePursuitRadar PRIVATE d3d9 version psapi shlwapi)
