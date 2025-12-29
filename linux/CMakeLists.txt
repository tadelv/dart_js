cmake_minimum_required(VERSION 3.10)

# ---------------------------------------------------------------------
# Project / plugin setup
# ---------------------------------------------------------------------

set(PROJECT_NAME "flutter_js")
project(${PROJECT_NAME} LANGUAGES CXX C)

set(PLUGIN_NAME "${PROJECT_NAME}_plugin")

# Let Flutter pick compilers; do NOT hardcode gcc/g++
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------
# Flutter plugin (C++)
# ---------------------------------------------------------------------

add_library(${PLUGIN_NAME} SHARED
  flutter_js_plugin.cc
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
)

# ---------------------------------------------------------------------
# QuickJS C bridge (pure C, built for host arch)
# ---------------------------------------------------------------------
get_filename_component(PLUGIN_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/.."
  ABSOLUTE
)

add_library(quickjs_c_bridge_plugin SHARED
  ${PLUGIN_ROOT}/native/quickjs/upstream/quickjs.c
  ${PLUGIN_ROOT}/native/quickjs/upstream/libquickjs.c
  ${PLUGIN_ROOT}/native/bridge/quickjs_bridge.c
)

target_include_directories(quickjs_c_bridge_plugin PRIVATE
  ${PLUGIN_ROOT}/native/quickjs/upstream
  ${PLUGIN_ROOT}/native/bridge
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
# Bundle install configuration (Flutter standard)
# ---------------------------------------------------------------------

set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

# Install the QuickJS bridge into the bundle
install(
  FILES "$<TARGET_FILE:quickjs_c_bridge_plugin>"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime
)
