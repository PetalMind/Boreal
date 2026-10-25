cmake_minimum_required(VERSION 3.24)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/manifest.json" MOD_MANIFEST)
string(JSON MOD_VERSION GET "${MOD_MANIFEST}" version)

project(QuestTrackerHUDSE VERSION "${MOD_VERSION}" LANGUAGES CXX)

find_package(CommonLibSSE CONFIG REQUIRED)

add_commonlibsse_plugin(${PROJECT_NAME}
    NAME "QuestTrackerHUDSE"
    AUTHOR "Boreal"
    VERSION "${PROJECT_VERSION}"
    USE_ADDRESS_LIBRARY
    SOURCES
        src/Plugin.cpp
        src/QuestData.cpp
)

target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_23)
target_precompile_headers(${PROJECT_NAME} PRIVATE src/PCH.h)
