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
cmake_minimum_required(VERSION 3.10)

set(QUICKJS_ROOT "${CMAKE_CURRENT_LIST_DIR}")
set(QUICKJS_SRC_DIR "${QUICKJS_ROOT}/upstream")
set(QUICKJS_BRIDGE_DIR "${QUICKJS_ROOT}/bridge/cxx")

file(STRINGS "${QUICKJS_SRC_DIR}/VERSION" QUICKJS_VERSION)

set(QUICKJS_HEADER "${QUICKJS_SRC_DIR}/quickjs.h")
set(QUICKJS_C "${QUICKJS_SRC_DIR}/quickjs.c")
set(QUICKJS_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/qjs_engine_generated")
file(MAKE_DIRECTORY "${QUICKJS_GENERATED_DIR}")

file(READ "${QUICKJS_HEADER}" QUICKJS_H_CONTENTS)
if(NOT QUICKJS_H_CONTENTS MATCHES "JS_IsPromise")
  string(APPEND QUICKJS_H_CONTENTS "\n#ifdef __cplusplus\nextern \"C\" {\n#endif\nJS_BOOL JS_IsPromise(JSContext *ctx, JSValueConst val);\n#ifdef __cplusplus\n}\n#endif\n")
endif()
file(WRITE "${QUICKJS_GENERATED_DIR}/quickjs.h" "${QUICKJS_H_CONTENTS}")

file(READ "${QUICKJS_C}" QUICKJS_C_CONTENTS)
if(NOT QUICKJS_C_CONTENTS MATCHES "JS_IsPromise")
  string(APPEND QUICKJS_C_CONTENTS "\nBOOL JS_IsPromise(JSContext* ctx, JSValueConst val)\n{\n    JSObject *p;\n    if (JS_VALUE_GET_TAG(val) != JS_TAG_OBJECT)\n        return FALSE;\n    p = JS_VALUE_GET_OBJ(val);\n    return p->class_id == JS_CLASS_PROMISE;\n}\n")
endif()
file(WRITE "${QUICKJS_GENERATED_DIR}/quickjs.c" "${QUICKJS_C_CONTENTS}")
file(COPY
  "${QUICKJS_SRC_DIR}/cutils.h"
  "${QUICKJS_SRC_DIR}/list.h"
  "${QUICKJS_SRC_DIR}/libregexp.h"
  "${QUICKJS_SRC_DIR}/libunicode.h"
  "${QUICKJS_SRC_DIR}/dtoa.h"
  "${QUICKJS_SRC_DIR}/quickjs-atom.h"
  "${QUICKJS_SRC_DIR}/quickjs-opcode.h"
  DESTINATION "${QUICKJS_GENERATED_DIR}"
)

# The C++ bridge includes "quickjs.h". Give it a mirror include dir containing
# only the (patched) engine header — exposing the whole upstream tree on the
# C++ include path would let libc++'s <version> shadow the bare VERSION file
# and break the build. The engine .c files resolve their headers from their
# own directory.
set(QUICKJS_ENGINE_SOURCES
  "${QUICKJS_SRC_DIR}/cutils.c"
  "${QUICKJS_SRC_DIR}/libregexp.c"
  "${QUICKJS_SRC_DIR}/libunicode.c"
  "${QUICKJS_GENERATED_DIR}/quickjs.c"
  "${QUICKJS_SRC_DIR}/dtoa.c"
  "${QUICKJS_BRIDGE_DIR}/libfastdev_quickjs_runtime.cpp"
)

set(QUICKJS_ENGINE_INCLUDE_DIRS
  "${QUICKJS_GENERATED_DIR}"
)

set(QUICKJS_ENGINE_DEFS
  CONFIG_VERSION="${QUICKJS_VERSION}"
)
