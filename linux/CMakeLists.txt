cmake_minimum_required(VERSION 3.10)
project(flutter_js_plugin LANGUAGES C CXX)

# ---------------------------------------------------------------------
# Flutter plugin core (REQUIRED BY FLUTTER)
# ---------------------------------------------------------------------
set(PLUGIN_NAME "flutter_js_plugin")

add_library(${PLUGIN_NAME} SHARED
  flutter_js_plugin.cc
)

apply_standard_settings(${PLUGIN_NAME})

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_LIST_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
)

target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  POSITION_INDEPENDENT_CODE ON
)
# ---------------------------------------------------------------------
# Patch quickjs.h to remove 'static inline' from JS_NewString
# ---------------------------------------------------------------------
set(QUICKJS_HEADER "${CMAKE_CURRENT_LIST_DIR}/quickjs/upstream/quickjs.h")

file(READ "${QUICKJS_HEADER}" QUICKJS_H_CONTENTS)

string(REPLACE
  "static inline JSValue JS_NewString"
  "JSValue JS_NewString"
  QUICKJS_H_CONTENTS
  "${QUICKJS_H_CONTENTS}"
)

file(WRITE "${QUICKJS_HEADER}" "${QUICKJS_H_CONTENTS}")

# ---------------------------------------------------------------------
# Add JS_IsPromise to quickjs if missing
# ---------------------------------------------------------------------
set(QUICKJS_C "${CMAKE_CURRENT_LIST_DIR}/quickjs/upstream/quickjs.c")
set(QUICKJS_H "${CMAKE_CURRENT_LIST_DIR}/quickjs/upstream/quickjs.h")

file(READ "${QUICKJS_H}" QUICKJS_H_CONTENTS)
if(NOT QUICKJS_H_CONTENTS MATCHES "JS_IsPromise")
  file(APPEND "${QUICKJS_H}" "\nBOOL JS_IsPromise(JSContext *ctx, JSValueConst val);\n")
endif()

file(READ "${QUICKJS_C}" QUICKJS_C_CONTENTS)
if(NOT QUICKJS_C_CONTENTS MATCHES "JS_IsPromise")
  file(APPEND "${QUICKJS_C}" "\nBOOL JS_IsPromise(JSContext* ctx, JSValueConst val)\n{\n    JSObject *p;\n    if (JS_VALUE_GET_TAG(val) != JS_TAG_OBJECT)\n        return FALSE;\n    p = JS_VALUE_GET_OBJ(val);\n    return p->class_id == JS_CLASS_PROMISE;\n}\n")
endif()

# ---------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------
set(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# ---------------------------------------------------------------------
# QuickJS + bridge + FIXUP (single .so)
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
  # -std=gnu11
)

target_compile_definitions(quickjs_c_bridge_plugin PRIVATE
  CONFIG_VERSION=\"2024-01-13\"
)

set_target_properties(quickjs_c_bridge_plugin PROPERTIES
  OUTPUT_NAME "quickjs_c_bridge_plugin"
  POSITION_INDEPENDENT_CODE ON
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

target_link_libraries(quickjs_c_bridge_plugin PRIVATE
  m
  dl
  pthread
)

# ---------------------------------------------------------------------
# Tell Flutter to bundle the shared library
# ---------------------------------------------------------------------
set(flutter_qjs_bundled_libraries
  "$<TARGET_FILE:quickjs_c_bridge_plugin>"
  PARENT_SCOPE
)

# ---------------------------------------------------------------------
# Install into Flutter bundle/lib
# ---------------------------------------------------------------------
set(BUILD_BUNDLE_DIR "${CMAKE_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "" FORCE)
endif()

set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(
  FILES "$<TARGET_FILE:quickjs_c_bridge_plugin>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
