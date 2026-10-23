# nhl2k8 - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(nhl2k8 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(generated/rexglue.cmake)

# Sources
set(NHL2K8_SOURCES
    src/main.cpp
)

# Optional: embed the game's own icon into the exe. The icon is the game's
# artwork, so it is not part of this project. Run the game once, copy the
# nhl2k8.ico it writes next to the exe into res/, then rebuild.
if(WIN32 AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/res/nhl2k8.ico")
    enable_language(RC)
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/nhl2k8_icon.rc"
         "1 ICON \"${CMAKE_CURRENT_SOURCE_DIR}/res/nhl2k8.ico\"\n")
    list(APPEND NHL2K8_SOURCES "${CMAKE_CURRENT_BINARY_DIR}/nhl2k8_icon.rc")
endif()

if(WIN32)
    add_executable(nhl2k8 WIN32 ${NHL2K8_SOURCES})
else()
    add_executable(nhl2k8 ${NHL2K8_SOURCES})
endif()

rexglue_setup_target(nhl2k8)
