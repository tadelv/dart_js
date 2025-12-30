cmake_minimum_required(VERSION 3.10)
project(flutter_js_plugin LANGUAGES C CXX)

# ---------------------------------------------------------------------
# Flutter plugin core (Dart↔C++ glue)
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

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17 -DANDROID_STL=c++_static -DDEBUGGER_SERVER_PORT=${DEBUGGER_SERVER_PORT}")
#set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-error=incompatible-pointer-types-discards-qualifiers")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-int-conversion")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-unused-variable")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-unused-but-set-variable")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
# set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-maybe-uninitialized")

# ---------------------------------------------------------------------
# Compute absolute path to the plugin package root
# ---------------------------------------------------------------------
# CMAKE_CURRENT_LIST_DIR points to:
# flutter/ephemeral/.plugin_symlinks/flutter_js/linux
# We want the actual package root:
# get_filename_component(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
set(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}")


add_library(quickjs STATIC
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/cutils.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libregexp.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libunicode.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/quickjs.c"
)

target_compile_definitions(quickjs PRIVATE CONFIG_VERSION=\"2024-01-13\")
target_compile_options(quickjs PRIVATE -std=gnu11)

# ---------------------------------------------------------------------
# QuickJS engine sources (upstream)
# ---------------------------------------------------------------------
set(QUICKJS_ENGINE_SRC
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/cutils.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libregexp.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libunicode.c"
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/quickjs.c"
)

# ---------------------------------------------------------------------
# QuickJS bridge source (only the required cpp file)
# ---------------------------------------------------------------------
set(QUICKJS_BRIDGE_SRC
  "${PLUGIN_PACKAGE_DIR}/quickjs/bridge/cxx/libfastdev_quickjs_runtime.cpp"
)

# ---------------------------------------------------------------------
# Build the combined QuickJS shared library
# ---------------------------------------------------------------------
add_library(quickjs_c_bridge_plugin SHARED
  # ${QUICKJS_ENGINE_SRC}
  ${QUICKJS_BRIDGE_SRC}
)

target_include_directories(quickjs_c_bridge_plugin PRIVATE
  "${PLUGIN_PACKAGE_DIR}/quickjs/upstream"
  # "${PLUGIN_PACKAGE_DIR}/quickjs/bridge/cxx"
)

target_compile_options(quickjs_c_bridge_plugin PRIVATE "-fPIC")

target_compile_options(quickjs_c_bridge_plugin  PRIVATE "-DCONFIG_VERSION=\"1.0.0\"")

target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

# Ensure QuickJS is usable inside a shared library
set_target_properties(quickjs PROPERTIES
  POSITION_INDEPENDENT_CODE ON
)

target_link_libraries(quickjs_c_bridge_plugin
  PRIVATE
    -Wl,--whole-archive
    quickjs
    -Wl,--no-whole-archive
    m
    dl
    pthread
)

set_target_properties(quickjs_c_bridge_plugin PROPERTIES
  OUTPUT_NAME "quickjs_c_bridge_plugin"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# ---------------------------------------------------------------------
# Tell Flutter to bundle the QuickJS shared library
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

set(QUICKJSC_BRIDGE "libquickjs_c_bridge_plugin.so")
set(QUICKJSC_BRIDGE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/shared/${QUICKJSC_BRIDGE}")
install(CODE "file(REMOVE_RECURSE \"${INSTALL_BUNDLE_LIB_DIR}/${QUICKJSC_BRIDGE}\")" COMPONENT Runtime)
install(
  FILES "$<TARGET_FILE:quickjs_c_bridge_plugin>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
