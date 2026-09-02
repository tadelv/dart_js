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
# Paths
# ---------------------------------------------------------------------
set(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# ---------------------------------------------------------------------
# QuickJS engine: sources/patches shared with the Android build via
# quickjs/engine.cmake (single source of truth; do not edit engines here).
# ---------------------------------------------------------------------
include("${PLUGIN_PACKAGE_DIR}/quickjs/engine.cmake")

add_library(quickjs_c_bridge_plugin SHARED ${QUICKJS_ENGINE_SOURCES})

target_include_directories(quickjs_c_bridge_plugin PRIVATE
  ${QUICKJS_ENGINE_INCLUDE_DIRS}
)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
target_compile_options(quickjs_c_bridge_plugin PRIVATE
  -fPIC
)

target_compile_definitions(quickjs_c_bridge_plugin PRIVATE
  ${QUICKJS_ENGINE_DEFS}
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
