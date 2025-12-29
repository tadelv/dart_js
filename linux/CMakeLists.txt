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

# ---------------------------------------------------------------------
# Compute absolute path to the plugin package root
# ---------------------------------------------------------------------
# CMAKE_CURRENT_LIST_DIR points to:
# flutter/ephemeral/.plugin_symlinks/flutter_js/linux
# We want the actual package root:
# get_filename_component(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
set(PLUGIN_PACKAGE_DIR "flutter/ephemeral/.plugin_symlinks/flutter_js/linux")
# ---------------------------------------------------------------------
# QuickJS engine sources (upstream)
# ---------------------------------------------------------------------
set(QUICKJS_ENGINE_SRC
  "${PLUGIN_PACKAGE_DIR}/linux/quickjs/upstream/quickjs.c"
  "${PLUGIN_PACKAGE_DIR}/linux/quickjs/upstream/libquickjs.c"
)

# ---------------------------------------------------------------------
# QuickJS bridge source (only the required cpp file)
# ---------------------------------------------------------------------
set(QUICKJS_BRIDGE_SRC
  "${PLUGIN_PACKAGE_DIR}/linux/quickjs/bridge/cxx/libfastdev_quickjs_runtime.cpp"
)

# ---------------------------------------------------------------------
# Build the combined QuickJS shared library
# ---------------------------------------------------------------------
add_library(quickjs_c_bridge_plugin SHARED
  ${QUICKJS_ENGINE_SRC}
  ${QUICKJS_BRIDGE_SRC}
)

target_include_directories(quickjs_c_bridge_plugin PRIVATE
  "${PLUGIN_PACKAGE_DIR}/linux/quickjs/upstream"
  "${PLUGIN_PACKAGE_DIR}/linux/quickjs/bridge/cxx"
)

target_link_libraries(quickjs_c_bridge_plugin
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

install(
  FILES "$<TARGET_FILE:quickjs_c_bridge_plugin>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
