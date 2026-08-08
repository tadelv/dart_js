cmake_minimum_required(VERSION 3.10)
project(fastdev_quickjs_runtime LANGUAGES C CXX)

set(BRIDGE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../linux/quickjs/bridge/cxx")
set(QUICKJS_DIR "${BRIDGE_DIR}/quickjs")
file(STRINGS "${QUICKJS_DIR}/VERSION" QUICKJS_VERSION)

add_library(fastdev_quickjs_runtime SHARED
    "${BRIDGE_DIR}/libfastdev_quickjs_runtime.cpp"
    "${QUICKJS_DIR}/cutils.c"
    "${QUICKJS_DIR}/libregexp.c"
    "${QUICKJS_DIR}/libunicode.c"
    "${QUICKJS_DIR}/quickjs.c"
)

target_compile_features(fastdev_quickjs_runtime PRIVATE cxx_std_17)
target_compile_options(fastdev_quickjs_runtime PRIVATE
    $<$<COMPILE_LANGUAGE:C>:-Wno-int-conversion>
)
target_compile_definitions(fastdev_quickjs_runtime PRIVATE
    CONFIG_VERSION="${QUICKJS_VERSION}"
)
target_include_directories(fastdev_quickjs_runtime PRIVATE "${BRIDGE_DIR}")
target_link_libraries(fastdev_quickjs_runtime PRIVATE log m)
