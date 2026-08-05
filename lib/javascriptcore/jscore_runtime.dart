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
      final jsValueRef = JSString.withStrings(
          [js, sourceUrl],
          (strings) => jSEvaluateScript(
              _globalContext,
              strings[0],
              nullptr,
              strings[1],
              1,
              exception.pointer));

      String result;

      final exceptionValue = exception.getValue(context);
      bool isPromise = false;
      if (exceptionValue.isObject) {
        result =
            'ERROR: ${exceptionValue.toObject().getProperty("message").string} \n  at ${exceptionValue.toObject().getProperty("stack").string}';
      } else {
        result = _getJsValue(jsValueRef);
        final resultValue = JSValue(context, jsValueRef);

        isPromise = resultValue.isObject &&
            resultValue.toObject().getProperty('then').isObject &&
            resultValue.toObject().getProperty('catch').isObject;
      }

      return JsEvalResult(
        result,
        exceptionValue.isObject
            ? exceptionValue.toObject().pointer
            : jsValueRef,
        isError: result.startsWith('ERROR:'),
        isPromise: isPromise,
      );
    } finally {
      exception.release();
    }
  }

  @override
  void dispose() {
    context.exception.release();
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

  String _getJsValue(Pointer jsValueRef) {
    if (jSValueIsNull(_globalContext, jsValueRef) == 1) {
      return 'null';
    } else if (jSValueIsUndefined(_globalContext, jsValueRef) == 1) {
      return 'undefined';
    }
    final resultJsString = JSString.owned(
        jSValueToStringCopy(_globalContext, jsValueRef, nullptr));
    try {
      return resultJsString.string ?? 'null';
    } finally {
      resultJsString.release();
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
    final functionObj = JSValue(context, fn ?? nullptr).toObject();
    final arguments = JSValuePointer(obj);
    final exception = JSValuePointer();
    try {
      final result = functionObj.callAsFunction(
        functionObj,
        arguments,
        exception: exception,
      );
      final exceptionValue = exception.getValue(context);
      bool isPromise = false;

      if (exceptionValue.isObject) {
        throw Exception(
            'ERROR: ${exceptionValue.toObject().getProperty("message").string}');
      } else {
        isPromise = result.isObject &&
            result.toObject().getProperty('then').isObject &&
            result.toObject().getProperty('catch').isObject;
      }

      return JsEvalResult(
        _getJsValue(result.pointer),
        exceptionValue.isObject
            ? exceptionValue.toObject().pointer
            : result.pointer,
        isPromise: isPromise,
      );
    } finally {
      arguments.release();
      exception.release();
    }
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    if (jSValueIsNull(_globalContext, jsValue.rawResult) == 1) {
      return null;
    } else if (jSValueIsString(_globalContext, jsValue.rawResult) == 1) {
      return _getJsValue(jsValue.rawResult) as T;
    } else if (jSValueIsBoolean(_globalContext, jsValue.rawResult) == 1) {
      return (_getJsValue(jsValue.rawResult) == "true") as T;
    } else if (jSValueIsNumber(_globalContext, jsValue.rawResult) == 1) {
      String valueString = _getJsValue(jsValue.rawResult);

      if (valueString.contains(".")) {
        try {
          return double.parse(valueString) as T;
        } on TypeError {
          print('Failed to cast $valueString... returning null');
          return null;
        }
      } else {
        try {
          return int.parse(valueString) as T;
        } on TypeError {
          print('Failed to cast $valueString... returning null');
          return null;
        }
      }
    } else if (jSValueIsObject(_globalContext, jsValue.rawResult) == 1 ||
        jSValueIsArray(_globalContext, jsValue.rawResult) == 1) {
      final objValue = JSValue(context, jsValue.rawResult);
      final serialized = objValue.createJSONString();
      try {
        final string = serialized.string;
        return string == null ? null : jsonDecode(string);
      } finally {
        serialized.release();
      }
    } else {
      return null;
    }
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    final objValue = JSValue(context, jsValue.rawResult);
    final serialized = objValue.createJSONString();
    try {
      return serialized.string!;
    } finally {
      serialized.release();
    }
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    return Future.value(evaluate(code, sourceUrl: sourceUrl));
  }
}
