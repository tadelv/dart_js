# QuickJS engine build fragment — single source of truth for the JS engine on
# every platform that uses the C++ bridge (Android + Linux).
#
# The engine is the vendored upstream QuickJS tree under quickjs/upstream
# (currently 2026-06-04; see quickjs/upstream/VERSION) plus the C++ bridge
# (quickjs/bridge/cxx/libfastdev_quickjs_runtime.cpp). Keeping the sources and
# patches here — instead of copied into each platform CMakeLists — prevents
# platform drift of the engine version (Android was stuck on QuickJS 2021-03-27
# while Linux ran 2025-09-13; the old engine's flat-string concat made Decaid's
# btoa polyfill O(n^2) on multi-MB inputs).
#
# The bridge includes "quickjs.h" and is compiled against this patched header
# on every platform, so JS_NewString (static inline upstream) is inlined and
# needs no exported symbol. This mirrors the Linux ABI alignment on master.
#
# Defines for the caller:
#   QUICKJS_ENGINE_SOURCES      - .c/.cpp files to compile into the engine lib
#   QUICKJS_ENGINE_INCLUDE_DIRS - include path for the C++ bridge
#   QUICKJS_ENGINE_DEFS         - compile definitions (CONFIG_VERSION)
#
# Patches are applied idempotently to quickjs/upstream/quickjs.{h,c} in place:
#   * JS_IsPromise is added if missing (upstream lacks the export). The header
#     declaration is extern "C" with JS_BOOL so the C++ bridge links to the C
#     definition.

cmake_minimum_required(VERSION 3.10)

set(QUICKJS_ROOT "${CMAKE_CURRENT_LIST_DIR}")
set(QUICKJS_SRC_DIR "${QUICKJS_ROOT}/upstream")
set(QUICKJS_BRIDGE_DIR "${QUICKJS_ROOT}/bridge/cxx")

file(STRINGS "${QUICKJS_SRC_DIR}/VERSION" QUICKJS_VERSION)

# ---- add JS_IsPromise to quickjs if missing ----
set(QUICKJS_HEADER "${QUICKJS_SRC_DIR}/quickjs.h")
set(QUICKJS_C "${QUICKJS_SRC_DIR}/quickjs.c")

file(READ "${QUICKJS_HEADER}" QUICKJS_H_CONTENTS)
if(NOT QUICKJS_H_CONTENTS MATCHES "JS_IsPromise")
  file(APPEND "${QUICKJS_HEADER}" "\n#ifdef __cplusplus\nextern \"C\" {\n#endif\nJS_BOOL JS_IsPromise(JSContext *ctx, JSValueConst val);\n#ifdef __cplusplus\n}\n#endif\n")
endif()

file(READ "${QUICKJS_C}" QUICKJS_C_CONTENTS)
if(NOT QUICKJS_C_CONTENTS MATCHES "JS_IsPromise")
  file(APPEND "${QUICKJS_C}" "\nBOOL JS_IsPromise(JSContext* ctx, JSValueConst val)\n{\n    JSObject *p;\n    if (JS_VALUE_GET_TAG(val) != JS_TAG_OBJECT)\n        return FALSE;\n    p = JS_VALUE_GET_OBJ(val);\n    return p->class_id == JS_CLASS_PROMISE;\n}\n")
endif()

# The C++ bridge includes "quickjs.h". Give it a mirror include dir containing
# only the (patched) engine header — exposing the whole upstream tree on the
# C++ include path would let libc++'s <version> shadow the bare VERSION file
# and break the build. The engine .c files resolve their headers from their
# own directory.
set(_ENGINE_CPP_INCLUDE "${CMAKE_CURRENT_BINARY_DIR}/qjs_engine_include")
file(MAKE_DIRECTORY "${_ENGINE_CPP_INCLUDE}")
configure_file("${QUICKJS_HEADER}" "${_ENGINE_CPP_INCLUDE}/quickjs.h" COPYONLY)

set(QUICKJS_ENGINE_SOURCES
  "${QUICKJS_SRC_DIR}/cutils.c"
  "${QUICKJS_SRC_DIR}/libregexp.c"
  "${QUICKJS_SRC_DIR}/libunicode.c"
  "${QUICKJS_SRC_DIR}/quickjs.c"
  "${QUICKJS_SRC_DIR}/dtoa.c"
  "${QUICKJS_BRIDGE_DIR}/libfastdev_quickjs_runtime.cpp"
)

set(QUICKJS_ENGINE_INCLUDE_DIRS
  "${_ENGINE_CPP_INCLUDE}"
)

set(QUICKJS_ENGINE_DEFS
  CONFIG_VERSION="${QUICKJS_VERSION}"
)
