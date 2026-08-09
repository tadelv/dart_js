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

include(CTest)
if(BUILD_TESTING)
  add_executable(value_wrapper_ownership_test
    "${PLUGIN_PACKAGE_DIR}/quickjs/bridge/cxx/tests/value_wrapper_ownership_test.cpp"
    "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/cutils.c"
    "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libregexp.c"
    "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/libunicode.c"
    "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/quickjs.c"
    "${PLUGIN_PACKAGE_DIR}/quickjs/upstream/dtoa.c"
  )
  target_include_directories(value_wrapper_ownership_test PRIVATE
    ${QUICKJS_ENGINE_INCLUDE_DIRS}
  )
  target_compile_definitions(value_wrapper_ownership_test PRIVATE
    ${QUICKJS_ENGINE_DEFS}
  )
  target_link_libraries(value_wrapper_ownership_test PRIVATE
    m
    dl
    pthread
  )
  add_test(NAME value_wrapper_ownership COMMAND value_wrapper_ownership_test)
endif()
