cmake_minimum_required(VERSION 3.20)

project(BorealLegacyGraphics VERSION 0.1.0 LANGUAGES CXX)

if(NOT WIN32)
    message(WARNING "BorealLegacyGraphics is a Windows PE DLL. Use an i686 MinGW-w64 toolchain when configuring this target.")
endif()

add_library(boreal_legacy_graphics SHARED
    src/blg_d3d11.cpp
    src/blg_log.cpp
    src/ddraw_proxy.cpp
)

target_include_directories(boreal_legacy_graphics
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_compile_features(boreal_legacy_graphics PRIVATE cxx_std_20)
target_compile_definitions(boreal_legacy_graphics PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_link_libraries(boreal_legacy_graphics PRIVATE kernel32 user32 uuid)

if(MINGW)
    target_link_options(boreal_legacy_graphics PRIVATE
        "-static"
        "-static-libgcc"
        "-static-libstdc++"
        "-Wl,-Bstatic"
        "-lwinpthread"
        "-Wl,--kill-at"
    )
endif()

set_target_properties(boreal_legacy_graphics PROPERTIES
    OUTPUT_NAME ddraw
    PREFIX ""
    SUFFIX ".dll"
)
