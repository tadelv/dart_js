import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/binding/js_object_ref.dart'
    as jsObject;
import 'package:flutter_js/javascriptcore/flutter_jscore.dart';
import 'package:flutter_js/javascriptcore/jscore_bindings.dart';
import 'package:flutter_js/js_eval_result.dart';

class JavascriptCoreRuntime extends JavascriptRuntime {
  late Pointer _contextGroup;
  late Pointer _globalContext;
  late JSContext context;
  late Pointer _globalObject;

  int executePendingJob() {
    evaluate('(function(){})();');
    return 0;
  }

  String? onMessageFunctionName;
  String? sendMessageFunctionName;

  JavascriptCoreRuntime() {
    _contextGroup = jSContextGroupCreate();
    _globalContext = jSGlobalContextCreateInGroup(_contextGroup, nullptr);
    _globalObject = jSContextGetGlobalObject(_globalContext);

    context = JSContext(_globalContext);

    _sendMessageDartFunc = _sendMessage;

    JSString.withStrings(['sendMessage'], (strings) {
      final functionObject = jSObjectMakeFunctionWithCallback(
          _globalContext, strings[0], Pointer.fromFunction(sendMessageBridgeFunction));
      jSObjectSetProperty(
          _globalContext,
          _globalObject,
          strings[0],
          functionObject,
          jsObject.JSPropertyAttributes.kJSPropertyAttributeNone,
          nullptr);
    });

    init();
  }

  @override
  void initChannelFunctions() {
    JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()] = {};
  }

  @override
  JsEvalResult evaluate(String js, {String? sourceUrl}) {
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
    jSGlobalContextRelease(_globalContext);
    jSContextGroupRelease(_contextGroup);
  }

  @override
  String getEngineInstanceId() => hashCode.abs().toString();

  /// Works only for iOS & MacOS.
  @override
  void setInspectable(bool inspectable) {
    if (Platform.isIOS || Platform.isMacOS) {
      try {
        context.setInspectable(inspectable);
      } on Error {
        print('Could not set inspectable to $inspectable');
      }
    }
  }

  @override
  bool setupBridge(String channelName, Function(dynamic args) fn) {
    final channelFunctionCallbacks =
        JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()]!;

    if (channelFunctionCallbacks.keys.contains(channelName)) return false;

    channelFunctionCallbacks[channelName] = fn;

    return true;
  }

  static Pointer sendMessageBridgeFunction(
      Pointer ctx,
      Pointer function,
      Pointer thisObject,
      int argumentCount,
      Pointer<Pointer> arguments,
      Pointer<Pointer> exception) {
    if (_sendMessageDartFunc != null) {
      return _sendMessageDartFunc!(
          ctx, function, thisObject, argumentCount, arguments, exception);
    }
    return nullptr;
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
        if (message != null || stack != null) {
          final formattedMessage = message ?? 'JavaScript exception';
          final formattedStack = stack == null ? '' : '\n  at $stack';
          return 'ERROR: $formattedMessage$formattedStack';
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

  static jsObject.JSObjectCallAsFunctionCallbackDart? _sendMessageDartFunc;

  Pointer _sendMessage(
      Pointer ctx,
      Pointer function,
      Pointer thisObject,
      int argumentCount,
      Pointer<Pointer> arguments,
      Pointer<Pointer> exception) {
    final channelFunctions =
        JavascriptRuntime.channelFunctionsRegistered[getEngineInstanceId()]!;

    String channelName = _getJsValue(arguments[0]);
    String message = _getJsValue(arguments[1]);

    if (channelFunctions.containsKey(channelName)) {
      final result = channelFunctions[channelName]!.call(jsonDecode(message));
      try {
        if (result is Future) {
          return _constructPromiseFor(result);
        }
        final encoded = json.encode(result);
        return JSValue.makeFromJSONString(context, encoded).pointer;
      } catch (err) {
        print(
            'Could not encode return value of message on channel $channelName to json... returning null');
      }
    } else {
      print('No channel $channelName registered');
    }

    return nullptr;
  }

  Pointer<NativeType> _constructPromiseFor(Future future) {
    final id = future.hashCode;
    final script = ('var __JSC_promise_result$id = {};' +
            'new Promise(function(resolve, reject) { __JSC_promise_result$id.resolve = resolve;' +
            ' __JSC_promise_result$id.reject = reject;});');

    final jsValueRef = JSString.withStrings(
        [script],
        (strings) => jSEvaluateScript(
            _globalContext, strings[0], nullptr, nullptr, 1, nullptr));

    future.then((value) {
      final encoded = json.encode(value);
      evaluate(
          '__JSC_promise_result$id.resolve($encoded); __JSC_promise_result$id = null;');
    }).catchError((error) {
      evaluate(
          '__JSC_promise_result$id.reject("$error"); __JSC_promise_result$id = null;');
    });
    return jsValueRef;
  }

  @override
  JsEvalResult callFunction(Pointer<NativeType>? fn, Pointer<NativeType>? obj) {
    if (fn == null || fn == nullptr) {
      return _nativeError('ERROR: Cannot call a null JavaScript function');
    }
    if (obj == null || obj == nullptr) {
      return _nativeError(
          'ERROR: Cannot call a JavaScript function with a null argument');
    }

    final functionValue = JSValue(context, fn);
    if (!functionValue.isObject) {
      return _nativeError('ERROR: JavaScript function reference is not an object');
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
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }
}
