cmake_minimum_required(VERSION 3.10)
project(quickjs_c_bridge LANGUAGES C CXX)

set(PLUGIN_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}/..")
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
)

target_link_libraries(quickjs_c_bridge_plugin PRIVATE
  m
  dl
  pthread
)
