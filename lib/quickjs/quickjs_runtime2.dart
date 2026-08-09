/* START PARTS IMPORT QJS ENGINE */
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_js/flutter_js.dart';

import 'ffi.dart';

export 'ffi.dart' show JSEvalFlag, JSRef;

part './isolate.dart';
part './object.dart';
part './wrapper.dart';

/// Handler function to manage js module.
typedef _JsModuleHandler = String Function(String name);

/// Handler to manage unhandled promise rejection.
typedef _JsHostPromiseRejectionHandler = void Function(dynamic reason);

final _quickJsResultFinalizer =
    Finalizer<_JSObject>((nativeResult) => nativeResult.destroy());
final _quickJsNativeResults = Expando<_JSObject>();
final _quickJsNativeValues = Expando<_JSObject>();

/// Quickjs engine for flutter.
class QuickJsRuntime2 extends JavascriptRuntime {
  Pointer<JSRuntime>? _rt;
  Pointer<JSContext>? _ctx;

  /// Max stack size for quickjs.
  int stackSize;

  final int? timeout;

  /// Max memory for quickjs.
  final int? memoryLimit;

  /// Message Port for event loop. Close it to stop dispatching event loop.
  ReceivePort port = ReceivePort();

  /// Handler function to manage js module.
  final _JsModuleHandler? moduleHandler;

  /// Handler function to manage js module.
  final _JsHostPromiseRejectionHandler? hostPromiseRejectionHandler;

  QuickJsRuntime2({
    this.moduleHandler,
    this.stackSize = 1024 * 1024,
    this.timeout,
    this.memoryLimit,
    this.hostPromiseRejectionHandler,
  }) {
    this.init();
  }

  _ensureEngine() {
    if (_rt != null) return;
    final rt = jsNewRuntime((ctx, type, ptr) {
      try {
        switch (type) {
          case JSChannelType.METHON:
            final pdata = ptr.cast<Pointer<JSValue>>();
            final argc = pdata[1].cast<Int32>().value;
            final pargs = [];
            for (var i = 0; i < argc; ++i) {
              pargs.add(_jsToDart(
                ctx,
                Pointer.fromAddress(
                  pdata[2].address + sizeOfJSValue * i,
                ),
              ));
            }
            final JSInvokable func = _jsToDart(
              ctx,
              pdata[3],
            );
            return _dartToJs(
                ctx,
                func.invoke(
                  pargs,
                  _jsToDart(ctx, pdata[0]),
                ));
          case JSChannelType.MODULE:
            if (moduleHandler == null) throw JSError('No ModuleHandler');
            final ret = moduleHandler!(
              ptr.cast<Utf8>().toDartString(),
            ).toNativeUtf8();
            Future.microtask(() {
              malloc.free(ret);
            });
            return ret.cast();
          case JSChannelType.PROMISE_TRACK:
            final err = _parseJSException(ctx, ptr);
            if (hostPromiseRejectionHandler != null) {
              hostPromiseRejectionHandler!(err);
            } else {
              print('unhandled promise rejection: $err');
            }
            return nullptr;
          case JSChannelType.FREE_OBJECT:
            final rt = ctx.cast<JSRuntime>();
            _DartObject.fromAddress(rt, ptr.address)?.free();
            return nullptr;
        }
        throw JSError('call channel with wrong type');
      } catch (e) {
        if (type == JSChannelType.FREE_OBJECT) {
          print('DartObject release error: $e');
          return nullptr;
        }
        if (type == JSChannelType.MODULE) {
          print('host Promise Rejection Handler error: $e');
          return nullptr;
        }
        final throwObj = _dartToJs(ctx, e);
        final err = jsThrow(ctx, throwObj);
        jsFreeValue(ctx, throwObj);
        if (type == JSChannelType.MODULE) {
          jsFreeValue(ctx, err);
          return nullptr;
        }
        return err;
      }
    }, timeout ?? 0, port);
    final stackSize = this.stackSize;
    if (stackSize > 0) jsSetMaxStackSize(rt, stackSize);
    final memoryLimit = this.memoryLimit ?? 0;
    if (memoryLimit > 0) jsSetMemoryLimit(rt, memoryLimit);
    _rt = rt;
    _ctx = jsNewContext(rt);
  }

  /// Free Runtime and Context which can be recreate when evaluate again.
  close() {
    final rt = _rt;
    final ctx = _ctx;
    if (rt == null) {
      _rt = null;
      _ctx = null;
      if (ctx != null) jsFreeContext(ctx);
      localContext.clear();
      return;
    }
    _executePendingJob();
    try {
      for (final obj in localContext.values) {
        JSRef.freeRecursive(obj);
      }
      localContext.clear();
      jsReleaseRuntimeRefs(rt);
      if (ctx != null) jsFreeContext(ctx);
      jsFreeRuntime(rt);
    } on String catch (e) {
      throw JSError(e);
    } finally {
      _rt = null;
      _ctx = null;
      localContext.clear();
    }
  }

  void _executePendingJob() {
    final rt = _rt;
    final ctx = _ctx;
    if (rt == null || ctx == null) return;
    jsResetRuntimeTimeout(rt);
    while (true) {
      int err = jsExecutePendingJob(rt);
      if (err <= 0) {
        if (err < 0) print(_parseJSException(ctx));
        break;
      }
    }
  }

  /// Dispatch JavaScript Event loop.
  Future<void> dispatch() async {
    //await for (final _ in port) {
    _executePendingJob();
    //}
  }

  JsEvalResult _consumeResult(
    Pointer<JSContext> ctx,
    Pointer<JSValue> jsValue,
  ) {
    if (jsIsException(jsValue) != 0) {
      jsFreeValue(ctx, jsValue);
      final exception = _parseJSException(ctx);
      return JsEvalResult(exception.toString(), exception, isError: true);
    }
    final nativeResult = _JSObject(ctx, jsValue);
    try {
      final result = _jsToDart(ctx, jsValue);
      final evalResult = JsEvalResult(
        result?.toString() ?? 'null',
        result,
        isPromise: result is Future,
      );
      _quickJsNativeResults[evalResult] = nativeResult;
      final nativeOwner = result == null ||
              result is num ||
              result is String ||
              result is bool ||
              result is _JSObject
          ? evalResult
          : result as Object;
      if (!identical(nativeOwner, evalResult)) {
        _quickJsNativeValues[nativeOwner] = nativeResult;
      }
      _quickJsResultFinalizer.attach(nativeOwner, nativeResult);
      return evalResult;
    } catch (_) {
      nativeResult.destroy();
      rethrow;
    } finally {
      jsFreeValue(ctx, jsValue);
    }
  }

  @override
  void setInspectable(bool inspectable) {
    // Nothing to do.
  }

  /// Evaluate js script.
  JsEvalResult evaluate(
    String command, {
    String? name,
    int? evalFlags,
    String? sourceUrl,
  }) {
    ensureRuntimeActive();
    _ensureEngine();
    final ctx = _ctx!;
    final jsval = jsEval(
      ctx,
      command,
      sourceUrl ?? name ?? '<eval>',
      evalFlags ?? JSEvalFlag.GLOBAL,
    );

    return _consumeResult(ctx, jsval);
  }

  @override
  JsEvalResult callFunction(dynamic fn, dynamic obj) {
    ensureRuntimeActive();
    if (fn is! JSInvokable) {
      throw ArgumentError.value(fn, 'fn', 'Expected a JavaScript function');
    }
    try {
      if (fn is _JSFunction) {
        final nativeObj =
            obj == null || obj is num || obj is String || obj is bool
                ? null
                : _quickJsNativeValues[obj as Object];
        final argument = nativeObj?._ctx == fn._ctx && nativeObj?._val != null
            ? nativeObj
            : obj;
        final result = fn._invoke([argument]);
        return _consumeResult(fn._ctx!, result);
      }
      final result = fn.invoke([obj]);
      return JsEvalResult(
        result?.toString() ?? 'null',
        result,
        isPromise: result is Future,
      );
    } catch (error) {
      return JsEvalResult(error.toString(), error, isError: true);
    }
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    ensureRuntimeActive();
    if (jsValue.isError) {
      throw StateError('Cannot convert a JavaScript error result');
    }
    return jsValue.rawResult as T?;
  }

  @override
  void dispose() {
    if (!beginDispose()) return;
    try {
      port.close(); // stop dispatch loop
      cancelRuntimeTimers();
      runDisposeCallbacks();
      close(); // close engine
    } on JSError catch (e) {
      print(e); // catch reference leak exception
    } finally {
      channelFunctions.clear();
      clearDartContext();
      finishDispose();
    }
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }

  @override
  int executePendingJob() {
    ensureRuntimeActive();
    this.dispatch();
    return 0;
  }

  @override
  String getEngineInstanceId() {
    return this.hashCode.toString();
  }

  @override
  void initChannelFunctions() {
    final setToGlobalObject =
        evaluate("(key, val) => { this[key] = val; }").rawResult;
    setLocalContextValue('setToGlobalObject', setToGlobalObject);
    (setToGlobalObject as JSInvokable).invoke([
      'sendMessage',
      (String channelName, String message) {
        final registration = channelFunctions[channelName];
        if (registration == null) {
          throw StateError('Unknown JavaScript channel: $channelName');
        }

        final result = registration.callback(jsonDecode(message));
        if (registration.fireAndForget) {
          if (result is Future) {
            unawaited(result.then<void>((_) {},
                onError: (Object error, StackTrace stack) {
              if (JavascriptRuntime.debugEnabled) {
                print('Fire-and-forget channel failed: $error');
              }
            }));
          }
          return null;
        }
        return result;
      }
    ]);
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    ensureRuntimeActive();
    final ctx = _ctx!;
    final nativeResult = _quickJsNativeResults[jsValue];
    if (nativeResult == null ||
        nativeResult._ctx != ctx ||
        nativeResult._val == null) {
      throw StateError('JavaScript result is not an active native value');
    }
    final serialized = jsJSONStringify(ctx, nativeResult._val!);
    try {
      if (jsIsException(serialized) != 0) {
        throw StateError(_parseJSException(ctx).toString());
      }
      if (jsValueGetTag(serialized) == JSTag.UNDEFINED) {
        throw StateError('JavaScript JSON serialization returned undefined');
      }
      return jsToCString(ctx, serialized);
    } finally {
      jsFreeValue(ctx, serialized);
    }
  }
}
