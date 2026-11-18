cmake_minimum_required(VERSION 3.16)
project(rade_c C)

set(CMAKE_C_STANDARD 11)

# Build opus with FARGAN/LPCNet support
include(cmake/BuildOpus.cmake)

add_subdirectory(src)

# Optional ctests, they need a radae checkout and build (see test/ctests.cmake)
set(RADAE_DIR "" CACHE PATH "radae checkout, enables the ctests")
set(RADAE_BUILD_DIR "" CACHE PATH "radae build directory (default RADAE_DIR/build)")
if(RADAE_DIR)
    enable_testing()
    include(test/ctests.cmake)
endif()
