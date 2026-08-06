import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/binding/js_object_ref.dart'
    as jsObject;
import 'package:flutter_js/javascriptcore/flutter_jscore.dart';
import 'package:flutter_js/javascriptcore/jscore_bindings.dart';
import 'package:flutter_js/js_eval_result.dart';

class JavascriptCoreRuntime extends JavascriptRuntime {
  static final Map<int, JavascriptCoreRuntime> _runtimesByContext = {};

  Pointer _contextGroup = nullptr;
  Pointer _globalContext = nullptr;
  JSContext context = JSContext(nullptr);
  Pointer _globalObject = nullptr;
  late final String _engineInstanceId;
  final Map<String, dynamic> _localContext = {};
  late final Map<String, dynamic> _localContextView =
      UnmodifiableMapView(_localContext);
  final Map<int, _ProtectedValue> _protectedValues = {};
  final Map<int, _PendingRequest> _pendingRequests = {};
  int _nextRequestId = 0;

  int executePendingJob() {
    ensureRuntimeActive();
    evaluate('(function(){})();');
    return 0;
  }

  String? onMessageFunctionName;
  String? sendMessageFunctionName;

  JavascriptCoreRuntime() {
    _contextGroup = jSContextGroupCreate();
    if (_contextGroup == nullptr) {
      throw StateError('JavaScriptCore could not create a context group');
    }
    _globalContext = jSGlobalContextCreateInGroup(_contextGroup, nullptr);
    if (_globalContext == nullptr) {
      jSContextGroupRelease(_contextGroup);
      _contextGroup = nullptr;
      throw StateError('JavaScriptCore could not create a global context');
    }
    _globalObject = jSContextGetGlobalObject(_globalContext);
    if (_globalObject == nullptr) {
      jSGlobalContextRelease(_globalContext);
      jSContextGroupRelease(_contextGroup);
      _globalContext = nullptr;
      _contextGroup = nullptr;
      throw StateError('JavaScriptCore could not create a global object');
    }

    context = JSContext(_globalContext);
    _engineInstanceId = _globalContext.address.toString();
    _runtimesByContext[_globalContext.address] = this;
    try {
      JSString.withStrings(['sendMessage'], (strings) {
        final functionObject = jSObjectMakeFunctionWithCallback(
          _globalContext,
          strings[0],
          Pointer.fromFunction(sendMessageBridgeFunction),
        );
        jSObjectSetProperty(
          _globalContext,
          _globalObject,
          strings[0],
          functionObject,
          jsObject.JSPropertyAttributes.kJSPropertyAttributeNone,
          nullptr,
        );
      });
      init();
    } catch (_) {
      _runtimesByContext.remove(_globalContext.address);
      final globalContext = _globalContext;
      final contextGroup = _contextGroup;
      _globalContext = nullptr;
      _contextGroup = nullptr;
      _globalObject = nullptr;
      context = JSContext(nullptr);
      jSGlobalContextRelease(globalContext);
      jSContextGroupRelease(contextGroup);
      rethrow;
    }
  }

  @override
  void initChannelFunctions() {}

  @override
  JsEvalResult evaluate(String js, {String? sourceUrl}) {
    ensureRuntimeActive();
    final exception = JSValuePointer();
    try {
      final resultRef = JSString.withStrings(
          [js, sourceUrl],
          (strings) => jSEvaluateScript(_globalContext, strings[0], nullptr,
              strings[1], 1, exception.pointer));

      final exceptionRef = exception.pointer.value;
      if (exceptionRef != nullptr) {
        return _nativeError(_formatException(exceptionRef), exceptionRef);
      }
      if (resultRef == nullptr) {
        return _nativeError(
          'ERROR: JavaScriptCore returned a null result without an exception',
        );
      }
      return JsEvalResult(
        _getJsValue(resultRef),
        resultRef,
        isError: false,
        isPromise: _isPromise(resultRef),
      );
    } finally {
      exception.release();
    }
  }

  @override
  void dispose() {
    if (!beginDispose()) return;
    _runtimesByContext.remove(_globalContext.address);
    try {
      _runCleanup(
        'Pending JavaScript request cleanup failed',
        () => _cancelPendingRequests('JavaScript runtime disposed'),
      );
      _runCleanup('Runtime timer cleanup failed', cancelRuntimeTimers);
      _runCleanup('Runtime callback cleanup failed', runDisposeCallbacks);
      _runCleanup('Runtime state cleanup failed', clearRuntimeState);
      _runCleanup('JavaScript value cleanup failed', _releaseAllValues);
      _runCleanup('JavaScript global context cleanup failed', () {
        final globalContext = _globalContext;
        try {
          if (globalContext != nullptr) {
            jSGlobalContextRelease(globalContext);
          }
        } finally {
          _globalContext = nullptr;
        }
      });
      context = JSContext(nullptr);
      _globalObject = nullptr;
      _runCleanup('JavaScript context group cleanup failed', () {
        final contextGroup = _contextGroup;
        try {
          if (contextGroup != nullptr) {
            jSContextGroupRelease(contextGroup);
          }
        } finally {
          _contextGroup = nullptr;
        }
      });
    } finally {
      finishDispose();
    }
  }

  void _runCleanup(String message, void Function() cleanup) {
    try {
      cleanup();
    } catch (error) {
      if (JavascriptRuntime.debugEnabled) {
        print('$message: $error');
      }
    }
  }

  @override
  String getEngineInstanceId() => _engineInstanceId;

  /// Works only for iOS & MacOS.
  @override
  void setInspectable(bool inspectable) {
    ensureRuntimeActive();
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        context.setInspectable(inspectable);
      } on Error {
        print('Could not set inspectable to $inspectable');
      }
    }
  }

  static Pointer sendMessageBridgeFunction(
      Pointer ctx,
      Pointer function,
      Pointer thisObject,
      int argumentCount,
      Pointer<Pointer> arguments,
      Pointer<Pointer> exception) {
    try {
      if (ctx == nullptr) return Pointer.fromAddress(0);
      final runtime = _runtimesByContext[ctx.address];
      if (runtime == null) return Pointer.fromAddress(0);
      if (!runtime.isRuntimeActive) {
        return JavascriptCoreRuntime._returnBridgeError(
          ctx,
          exception,
          'JavaScript runtime is not active',
        );
      }
      return runtime._sendMessage(
        ctx,
        function,
        thisObject,
        argumentCount,
        arguments,
        exception,
      );
    } catch (error, stackTrace) {
      if (JavascriptRuntime.debugEnabled) {
        print('$error\n$stackTrace');
      }
      final runtime = ctx == nullptr ? null : _runtimesByContext[ctx.address];
      if (runtime != null) {
        return JavascriptCoreRuntime._returnBridgeError(
          ctx,
          exception,
          'JavaScript bridge callback failed',
          error,
        );
      }
      return Pointer.fromAddress(0);
    }
  }

  JsEvalResult _nativeError(String message, [Pointer? rawResult]) {
    return JsEvalResult(message, rawResult ?? nullptr, isError: true);
  }

  String _getJsValue(Pointer jsValueRef) {
    if (jsValueRef == nullptr) {
      throw StateError('JavaScript value result is null');
    }
    final value = JSValue(context, jsValueRef);
    if (value.isNull) return 'null';
    if (value.isUndefined) return 'undefined';

    return _tryString(value) ?? '[${_valueType(value)}]';
  }

  JSValue? _readProperty(JSObject object, String propertyName) {
    final exception = JSValuePointer();
    try {
      final value = object.getProperty(propertyName, exception: exception);
      if (exception.pointer.value != nullptr || value.pointer == nullptr) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    } finally {
      exception.release();
    }
  }

  String? _readStringProperty(JSObject object, String propertyName) {
    try {
      final value = _readProperty(object, propertyName);
      if (value == null ||
          value.isNull ||
          value.isUndefined ||
          !value.isString) {
        return null;
      }
      return _tryString(value);
    } catch (_) {
      return null;
    }
  }

  num? _readNumberProperty(JSObject object, String propertyName) {
    try {
      final value = _readProperty(object, propertyName);
      if (value == null ||
          value.isNull ||
          value.isUndefined ||
          !value.isNumber) {
        return null;
      }
      return value.toNumber();
    } catch (_) {
      return null;
    }
  }

  String? _tryString(JSValue value) {
    try {
      if (value.isNull) return 'null';
      if (value.isUndefined) return 'undefined';

      final exception = JSValuePointer();
      JSString? resultString;
      try {
        resultString = value.toStringCopy(exception: exception);
        if (exception.pointer.value != nullptr ||
            resultString.pointer == nullptr) {
          return null;
        }
        return resultString.string;
      } catch (_) {
        return null;
      } finally {
        resultString?.release();
        exception.release();
      }
    } catch (_) {
      return null;
    }
  }

  String _valueType(JSValue value) {
    try {
      return value.type.name;
    } catch (_) {
      return 'unknown';
    }
  }

  String _formatException(Pointer exceptionRef) {
    if (exceptionRef == nullptr) {
      return 'ERROR: JavaScript exception (unknown)';
    }
    try {
      final value = JSValue(context, exceptionRef);
      if (value.isObject) {
        final object = JSObject(context, exceptionRef);
        final message = _readStringProperty(object, 'message');
        final stack = _readStringProperty(object, 'stack');
        final sourceURL = _readStringProperty(object, 'sourceURL');
        final line = _readNumberProperty(object, 'line');
        if (message != null || stack != null || sourceURL != null) {
          final formattedMessage = message ?? 'JavaScript exception';
          // Syntax errors carry no stack; the source location lives in
          // the sourceURL and line properties.
          final location = stack ??
              (sourceURL == null
                  ? null
                  : line == null
                      ? sourceURL
                      : line % 1 == 0
                          ? '$sourceURL:${line.toInt()}'
                          : '$sourceURL:$line');
          final formattedLocation = location == null ? '' : '\n  at $location';
          return 'ERROR: $formattedMessage$formattedLocation';
        }
      }
      final fallback = _tryString(value);
      if (fallback != null) return 'ERROR: $fallback';
      return 'ERROR: JavaScript exception (${_valueType(value)})';
    } catch (_) {
      return 'ERROR: JavaScript exception (unknown)';
    }
  }

  bool _isPromise(Pointer resultRef) {
    try {
      final value = JSValue(context, resultRef);
      if (!value.isObject) return false;
      final object = JSObject(context, resultRef);
      final then = _readProperty(object, 'then');
      if (then == null || !then.isObject) return false;
      final catchProperty = _readProperty(object, 'catch');
      return catchProperty != null && catchProperty.isObject;
    } catch (_) {
      return false;
    }
  }

  @override
  void retainValue(Pointer pointer) {
    ensureRuntimeActive();
    _retainValue(pointer);
  }

  @override
  void releaseValue(Pointer pointer) {
    _releaseValue(pointer);
  }

  @override
  Map<String, dynamic> get localContext => _localContextView;

  @override
  void setLocalContextValue(String key, dynamic value) {
    ensureRuntimeActive();
    final previous = _localContext[key];
    if (value is Pointer && value != nullptr) {
      _retainValue(value);
    }
    _localContext[key] = value;
    if (previous is Pointer && previous != nullptr) {
      _releaseValue(previous);
    }
  }

  @override
  void removeLocalContextValue(String key) {
    ensureRuntimeActive();
    final previous = _localContext.remove(key);
    if (previous is Pointer && previous != nullptr) {
      _releaseValue(previous);
    }
  }

  @override
  void clearLocalContext() {
    final values = List<dynamic>.of(_localContext.values);
    _localContext.clear();
    for (final value in values) {
      if (value is Pointer && value != nullptr) {
        _releaseValue(value);
      }
    }
  }

  void _retainValue(Pointer pointer) {
    if (pointer == nullptr) return;
    final retained = _protectedValues[pointer.address];
    if (retained != null) {
      retained.count += 1;
      return;
    }
    JSValue(context, pointer).protect();
    _protectedValues[pointer.address] = _ProtectedValue(pointer);
  }

  void _releaseValue(Pointer pointer) {
    final retained = _protectedValues[pointer.address];
    if (retained == null) return;
    retained.count -= 1;
    if (retained.count > 0) return;
    _protectedValues.remove(pointer.address);
    try {
      JSValue(context, retained.pointer).unProtect();
    } catch (error) {
      if (JavascriptRuntime.debugEnabled) {
        print('JavaScript value cleanup failed: $error');
      }
    }
  }

  void _releaseAllValues() {
    final retainedValues = List<_ProtectedValue>.of(_protectedValues.values);
    _protectedValues.clear();
    for (final retained in retainedValues) {
      try {
        JSValue(context, retained.pointer).unProtect();
      } catch (error) {
        if (JavascriptRuntime.debugEnabled) {
          print('JavaScript value cleanup failed: $error');
        }
      }
    }
  }

  @visibleForTesting
  int get protectedValueCount => _protectedValues.length;

  @visibleForTesting
  int get pendingRequestCount => _pendingRequests.length;

  Pointer _sendMessage(
      Pointer ctx,
      Pointer function,
      Pointer thisObject,
      int argumentCount,
      Pointer<Pointer> arguments,
      Pointer<Pointer> exception) {
    if (ctx != _globalContext) {
      return JavascriptCoreRuntime._returnBridgeError(
        ctx,
        exception,
        'JavaScript callback context does not belong to this runtime',
      );
    }
    if (argumentCount < 2 || arguments == nullptr) {
      return JavascriptCoreRuntime._returnBridgeError(
        ctx,
        exception,
        'sendMessage requires a channel and message',
      );
    }
    final channelRef = arguments[0];
    final messageRef = arguments[1];
    if (channelRef == nullptr || messageRef == nullptr) {
      return JavascriptCoreRuntime._returnBridgeError(
        ctx,
        exception,
        'sendMessage arguments must be strings',
      );
    }

    final channelValue = JSValue(context, channelRef);
    final messageValue = JSValue(context, messageRef);
    if (!channelValue.isString || !messageValue.isString) {
      return JavascriptCoreRuntime._returnBridgeError(
        ctx,
        exception,
        'sendMessage arguments must be strings',
      );
    }
    final channelName = _getJsValue(channelRef);
    final message = _getJsValue(messageRef);
    final registration = channelFunctions[channelName];
    if (registration == null) {
      return JavascriptCoreRuntime._returnBridgeError(
        ctx,
        exception,
        'Unknown JavaScript channel: $channelName',
      );
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
      return JSValue.makeUndefined(context).pointer;
    }
    if (result is Future) {
      return _createPendingPromise(result, registration.timeout, exception);
    }
    final encoded = json.encode(result);
    final value = JSValue.makeFromJSONString(context, encoded);
    if (value.pointer == nullptr) {
      return JavascriptCoreRuntime._returnBridgeError(
        ctx,
        exception,
        'JavaScript channel response encoding failed',
      );
    }
    return value.pointer;
  }

  Pointer _createPendingPromise(
    Future<dynamic> future,
    Duration timeout,
    Pointer<Pointer> exception,
  ) {
    final resolve = JSObjectPointer();
    final reject = JSObjectPointer();
    var retainedResolve = false;
    var retainedReject = false;
    Pointer? resolveRef;
    Pointer? rejectRef;
    _PendingRequest? pending;
    Timer? timer;
    try {
      if (exception != nullptr) exception.value = nullptr;
      final promise = jsObject.jSObjectMakeDeferredPromise(
        _globalContext,
        resolve.pointer,
        reject.pointer,
        exception,
      );
      if (exception != nullptr && exception.value != nullptr) {
        throw StateError(_formatException(exception.value));
      }
      final resolved = resolve.pointer.value;
      final rejected = reject.pointer.value;
      resolveRef = resolved;
      rejectRef = rejected;
      if (promise == nullptr || resolved == nullptr || rejected == nullptr) {
        throw StateError('JavaScriptCore returned a null deferred promise');
      }
      _retainValue(resolved);
      retainedResolve = true;
      _retainValue(rejected);
      retainedReject = true;
      final request = _PendingRequest(
        id: _nextRequestId++,
        resolve: resolved,
        reject: rejected,
      );
      pending = request;
      _pendingRequests[request.id] = request;
      timer = Timer(
          timeout,
          () => _settlePendingFailure(
                request,
                TimeoutException('JavaScript channel request timed out'),
              ));
      request.timer = timer;
      registerRuntimeTimer(timer);
      future.then<void>(
        (value) => _settlePendingSuccess(request, value),
        onError: (Object error, StackTrace stack) =>
            _settlePendingFailure(request, error),
      );
      return promise;
    } catch (_) {
      if (pending != null) {
        _pendingRequests.remove(pending.id);
      }
      timer?.cancel();
      if (timer != null) unregisterRuntimeTimer(timer);
      if (retainedResolve && resolveRef != null) _releaseValue(resolveRef);
      if (retainedReject && rejectRef != null) _releaseValue(rejectRef);
      rethrow;
    } finally {
      resolve.release();
      reject.release();
    }
  }

  void _settlePendingSuccess(_PendingRequest pending, dynamic value) {
    if (!_claimPending(pending)) return;
    try {
      Pointer valueRef;
      try {
        final encoded = json.encode(value);
        valueRef = JSValue.makeFromJSONString(context, encoded).pointer;
        if (valueRef == nullptr) {
          throw StateError('JavaScript channel response encoding failed');
        }
      } catch (error) {
        _settleClaimedPendingFailure(pending, error);
        return;
      }
      if (!_invokeSettlement(pending.resolve, valueRef)) {
        _settleClaimedPendingFailure(
          pending,
          StateError('JavaScript promise resolution failed'),
        );
      }
    } finally {
      _releasePendingValues(pending);
    }
  }

  void _settlePendingFailure(_PendingRequest pending, Object error) {
    if (!_claimPending(pending)) return;
    try {
      _settleClaimedPendingFailure(pending, error);
    } finally {
      _releasePendingValues(pending);
    }
  }

  void _settleClaimedPendingFailure(_PendingRequest pending, Object error) {
    final errorRef = _makeErrorValue(error);
    if (errorRef == nullptr || !_invokeSettlement(pending.reject, errorRef)) {
      if (JavascriptRuntime.debugEnabled) {
        print('JavaScript promise rejection failed: $error');
      }
    }
  }

  bool _claimPending(_PendingRequest pending) {
    if (pending.completed ||
        !identical(_pendingRequests[pending.id], pending)) {
      return false;
    }
    pending.completed = true;
    _pendingRequests.remove(pending.id);
    final timer = pending.timer;
    if (timer != null) {
      timer.cancel();
      unregisterRuntimeTimer(timer);
    }
    return true;
  }

  bool _invokeSettlement(Pointer function, Pointer value) {
    final arguments = JSValuePointer.array([JSValue(context, value)]);
    final exception = JSValuePointer();
    try {
      final result = JSObject(context, function).callAsFunction(
        null,
        arguments,
        exception: exception,
      );
      if (exception.pointer.value != nullptr) return false;
      return result.pointer != nullptr;
    } finally {
      arguments.release();
      exception.release();
    }
  }

  Pointer _makeErrorValue(Object error) {
    final message = JSValue.makeString(context, _safeErrorText(error));
    final arguments = JSValuePointer.array([message]);
    try {
      final errorObject = jsObject.jSObjectMakeError(
        _globalContext,
        arguments.count,
        arguments.pointer,
        nullptr,
      );
      return errorObject == nullptr ? message.pointer : errorObject;
    } finally {
      arguments.release();
    }
  }

  void _releasePendingValues(_PendingRequest pending) {
    _releaseValue(pending.resolve);
    _releaseValue(pending.reject);
  }

  void _cancelPendingRequests(String reason) {
    final pendingRequests = List<_PendingRequest>.of(_pendingRequests.values);
    for (final pending in pendingRequests) {
      try {
        _settlePendingFailure(pending, StateError(reason));
      } catch (error) {
        if (JavascriptRuntime.debugEnabled) {
          print('Pending JavaScript request cleanup failed: $error');
        }
      }
    }
  }

  static Pointer _returnBridgeError(
    Pointer ctx,
    Pointer<Pointer> exception,
    String category, [
    Object? error,
  ]) {
    if (ctx == nullptr) return Pointer.fromAddress(0);
    final context = JSContext(ctx);
    if (exception != nullptr) exception.value = nullptr;
    try {
      final message = JSValue.makeString(
        context,
        '$category: ${_safeErrorText(error)}',
      );
      final arguments = JSValuePointer.array([message]);
      try {
        final errorObject = jsObject.jSObjectMakeError(
          ctx,
          arguments.count,
          arguments.pointer,
          nullptr,
        );
        if (errorObject != nullptr && exception != nullptr) {
          exception.value = errorObject;
        }
      } finally {
        arguments.release();
      }
    } catch (_) {}
    try {
      return JSValue.makeUndefined(context).pointer;
    } catch (_) {
      return Pointer.fromAddress(0);
    }
  }

  static String _safeErrorText(Object? error) {
    if (error == null) return 'unknown failure';
    try {
      return error.toString();
    } catch (_) {
      return 'unknown failure';
    }
  }

  @override
  JsEvalResult callFunction(Pointer<NativeType>? fn, Pointer<NativeType>? obj) {
    ensureRuntimeActive();
    if (fn == null || fn == nullptr) {
      return _nativeError('ERROR: Cannot call a null JavaScript function');
    }
    if (obj == null || obj == nullptr) {
      return _nativeError(
          'ERROR: Cannot call a JavaScript function with a null argument');
    }

    final functionValue = JSValue(context, fn);
    if (!functionValue.isObject) {
      return _nativeError(
          'ERROR: JavaScript function reference is not an object');
    }
    final functionObj = JSObject(context, fn);
    final arguments = JSValuePointer.array([JSValue(context, obj)]);
    final exception = JSValuePointer();
    try {
      final result = functionObj.callAsFunction(
        functionObj,
        arguments,
        exception: exception,
      );
      final exceptionRef = exception.pointer.value;
      if (exceptionRef != nullptr) {
        return _nativeError(_formatException(exceptionRef), exceptionRef);
      }
      if (result.pointer == nullptr) {
        return _nativeError(
          'ERROR: JavaScriptCore returned a null call result without an exception',
        );
      }
      return JsEvalResult(
        _getJsValue(result.pointer),
        result.pointer,
        isError: false,
        isPromise: _isPromise(result.pointer),
      );
    } finally {
      arguments.release();
      exception.release();
    }
  }

  Pointer _requireRawResult(JsEvalResult jsValue) {
    if (jsValue.isError) {
      throw StateError('Cannot convert a JavaScript error result');
    }
    if (jsValue.rawResult is! Pointer) {
      throw StateError('JavaScript result is not a native value reference');
    }
    final rawResult = jsValue.rawResult as Pointer;
    if (rawResult == nullptr) {
      throw StateError('JavaScript result reference is null');
    }
    return rawResult;
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    ensureRuntimeActive();
    final rawResult = _requireRawResult(jsValue);
    final value = JSValue(context, rawResult);
    if (value.isNull) {
      return null;
    }
    if (value.isString) {
      return _getJsValue(rawResult) as T;
    }
    if (value.isBoolean) {
      return value.toBoolean as T;
    }
    if (value.isNumber) {
      final exception = JSValuePointer();
      try {
        final number = value.toNumber(exception: exception);
        final exceptionRef = exception.pointer.value;
        if (exceptionRef != nullptr) {
          throw StateError(_formatException(exceptionRef));
        }
        if (number.isFinite &&
            number.truncateToDouble() == number &&
            !(number == 0 && number.isNegative)) {
          return number.toInt() as T;
        }
        return number as T;
      } finally {
        exception.release();
      }
    }
    if (!value.isObject && !value.isArray) return null;

    final exception = JSValuePointer();
    JSString? serialized;
    try {
      serialized = value.createJSONString(exception: exception);
      final exceptionRef = exception.pointer.value;
      if (exceptionRef != nullptr) {
        throw StateError(_formatException(exceptionRef));
      }
      if (serialized.pointer == nullptr) {
        throw StateError('JavaScript JSON serialization returned null');
      }
      final string = serialized.string;
      if (string == null) {
        throw StateError('JavaScript JSON serialization returned null');
      }
      return jsonDecode(string) as T;
    } finally {
      serialized?.release();
      exception.release();
    }
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    ensureRuntimeActive();
    final rawResult = _requireRawResult(jsValue);
    final value = JSValue(context, rawResult);
    final exception = JSValuePointer();
    JSString? serialized;
    try {
      serialized = value.createJSONString(exception: exception);
      final exceptionRef = exception.pointer.value;
      if (exceptionRef != nullptr) {
        throw StateError(_formatException(exceptionRef));
      }
      if (serialized.pointer == nullptr) {
        throw StateError('JavaScript JSON serialization returned null');
      }
      final string = serialized.string;
      if (string == null) {
        throw StateError('JavaScript JSON serialization returned null');
      }
      return string;
    } finally {
      serialized?.release();
      exception.release();
    }
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    ensureRuntimeActive();
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }
}

class _ProtectedValue {
  final Pointer pointer;
  int count = 1;

  _ProtectedValue(this.pointer);
}

class _PendingRequest {
  final int id;
  final Pointer resolve;
  final Pointer reject;
  Timer? timer;
  bool completed = false;

  _PendingRequest({
    required this.id,
    required this.resolve,
    required this.reject,
  });
}
