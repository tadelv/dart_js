cmake_minimum_required(VERSION 3.10)
project(fastdev_quickjs_runtime LANGUAGES C CXX)

# Engine = vendored upstream QuickJS (2026-06-04) + C++ bridge. Shared with the
# Linux build via linux/quickjs/engine.cmake so every platform runs the same
# engine version (previously Android was pinned to QuickJS 2021-03-27).
include("${CMAKE_CURRENT_SOURCE_DIR}/../linux/quickjs/engine.cmake")

add_library(fastdev_quickjs_runtime SHARED ${QUICKJS_ENGINE_SOURCES})

target_compile_features(fastdev_quickjs_runtime PRIVATE cxx_std_17)
target_compile_options(fastdev_quickjs_runtime PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-std=gnu11>
    $<$<COMPILE_LANGUAGE:C>:-Wno-int-conversion>
)
target_compile_definitions(fastdev_quickjs_runtime PRIVATE ${QUICKJS_ENGINE_DEFS})
target_include_directories(fastdev_quickjs_runtime PRIVATE ${QUICKJS_ENGINE_INCLUDE_DIRS})
target_link_libraries(fastdev_quickjs_runtime PRIVATE log m)
