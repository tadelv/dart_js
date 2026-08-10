cmake_minimum_required(VERSION 3.10)
project(quickjs_c_bridge LANGUAGES C CXX)

# ---------------------------------------------------------------------
# Standalone build of the QuickJS + C++ bridge shared library.
#
# The Flutter plugin build (../CMakeLists.txt) compiles the same sources
# inline into libquickjs_c_bridge_plugin.so and bundles it with the app.
# This project exists so CI can rebuild the library from source and
# verify the committed prebuilt artifact (libquickjs_c_bridge_plugin.so
# in this directory) is not stale. Linux is the only platform that ships
# a committed binary, so source/binary drift here breaks consumers at
# runtime (undefined symbol on FFI lookup).
#
# KEEP IN SYNC with the quickjs_c_bridge_plugin target in ../CMakeLists.txt
# (sources, include dirs, flags, defines, link libraries).
# ---------------------------------------------------------------------

set(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}/..")

# ---------------------------------------------------------------------
# Add JS_IsPromise to quickjs if missing
# ---------------------------------------------------------------------
set(QUICKJS_C "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/quickjs.c")
set(QUICKJS_H "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/quickjs.h")

file(READ "${QUICKJS_H}" QUICKJS_H_CONTENTS)
if(NOT QUICKJS_H_CONTENTS MATCHES "JS_IsPromise")
  file(APPEND "${QUICKJS_H}" "\n#ifdef __cplusplus\nextern \"C\" {\n#endif\nJS_BOOL JS_IsPromise(JSContext *ctx, JSValueConst val);\n#ifdef __cplusplus\n}\n#endif\n")
endif()

file(READ "${QUICKJS_C}" QUICKJS_C_CONTENTS)
if(NOT QUICKJS_C_CONTENTS MATCHES "JS_IsPromise")
  file(APPEND "${QUICKJS_C}" "\nBOOL JS_IsPromise(JSContext* ctx, JSValueConst val)\n{\n    JSObject *p;\n    if (JS_VALUE_GET_TAG(val) != JS_TAG_OBJECT)\n        return FALSE;\n    p = JS_VALUE_GET_OBJ(val);\n    return p->class_id == JS_CLASS_PROMISE;\n}\n")
endif()

# ---------------------------------------------------------------------
# QuickJS + bridge (single .so)
# ---------------------------------------------------------------------
add_library(quickjs_c_bridge_plugin SHARED
  # QuickJS engine
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/cutils.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libregexp.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libunicode.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/quickjs.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/dtoa.c"

  # C++ bridge
  "${PLUGIN_PACKAGE_DIR}/quickjs/bridge/cxx/libfastdev_quickjs_runtime.cpp"
)

target_include_directories(quickjs_c_bridge_plugin PRIVATE
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream"
  "${PLUGIN_PACKAGE_DIR}/quickjs/bridge/cxx"
)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
target_compile_options(quickjs_c_bridge_plugin PRIVATE
  -fPIC
)

target_compile_definitions(quickjs_c_bridge_plugin PRIVATE
  CONFIG_VERSION=\"2024-01-13\"
)

set_target_properties(quickjs_c_bridge_plugin PROPERTIES
  OUTPUT_NAME "quickjs_c_bridge_plugin"
  POSITION_INDEPENDENT_CODE ON
)

target_link_libraries(quickjs_c_bridge_plugin PRIVATE
  m
  dl
  pthread
)
