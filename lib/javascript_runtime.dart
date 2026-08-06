import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'js_eval_result.dart';
import 'package:meta/meta.dart';

typedef JavascriptMessageCallback = FutureOr<dynamic> Function(dynamic args);

class JavascriptChannelRegistration {
  final JavascriptMessageCallback callback;
  final bool fireAndForget;
  final Duration timeout;

  const JavascriptChannelRegistration({
    required this.callback,
    required this.fireAndForget,
    required this.timeout,
  });
}

enum JavascriptRuntimeLifecycle { active, disposing, disposed }

class FlutterJsPlatformEmpty extends JavascriptRuntime {
  @override
  JsEvalResult callFunction(Pointer<NativeType> fn, Pointer<NativeType> obj) {
    throw UnimplementedError();
  }

  @override
  T? convertValue<T>(JsEvalResult jsValue) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}

  @override
  JsEvalResult evaluate(String code, {String? sourceUrl}) {
    throw UnimplementedError();
  }

  @override
  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl}) {
    throw UnimplementedError();
  }

  @override
  int executePendingJob() {
    throw UnimplementedError();
  }

  @override
  String getEngineInstanceId() {
    throw UnimplementedError();
  }

  @override
  void initChannelFunctions() {
    throw UnimplementedError();
  }

  @override
  String jsonStringify(JsEvalResult jsValue) {
    throw UnimplementedError();
  }

  @override
  bool setupBridge(
    String channelName,
    JavascriptMessageCallback fn, {
    bool fireAndForget = false,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError();
  }

  @override
  void setInspectable(bool inspectable) {
    throw UnimplementedError();
  }
}

abstract class JavascriptRuntime {
  static bool debugEnabled = false;

  @protected
  JavascriptRuntime init() {
    initChannelFunctions();
    _setupConsoleLog();
    _setupSetTimeout();
    return this;
  }

  final Map<String, dynamic> _localContext = {};

  Map<String, dynamic> get localContext => _localContext;

  final Map<String, dynamic> dartContext = {};

  void dispose();

  final Map<String, JavascriptChannelRegistration> channelFunctions = {};

  JavascriptRuntimeLifecycle _lifecycle = JavascriptRuntimeLifecycle.active;
  final Set<void Function()> _disposeCallbacks = {};
  final Set<Timer> _runtimeTimers = {};

  bool get isRuntimeActive => _lifecycle == JavascriptRuntimeLifecycle.active;

  void ensureRuntimeActive() {
    if (!isRuntimeActive) {
      throw StateError('JavaScript runtime is not active');
    }
  }

  bool beginDispose() {
    if (_lifecycle != JavascriptRuntimeLifecycle.active) return false;
    _lifecycle = JavascriptRuntimeLifecycle.disposing;
    return true;
  }

  void finishDispose() {
    _lifecycle = JavascriptRuntimeLifecycle.disposed;
  }

  void registerDisposeCallback(void Function() callback) {
    ensureRuntimeActive();
    _disposeCallbacks.add(callback);
  }

  void unregisterDisposeCallback(void Function() callback) {
    _disposeCallbacks.remove(callback);
  }

  @visibleForTesting
  int get disposeCallbackCount => _disposeCallbacks.length;

  void registerRuntimeTimer(Timer timer) {
    ensureRuntimeActive();
    _runtimeTimers.add(timer);
  }

  void unregisterRuntimeTimer(Timer timer) {
    _runtimeTimers.remove(timer);
  }

  void cancelRuntimeTimers() {
    final timers = List<Timer>.of(_runtimeTimers);
    _runtimeTimers.clear();
    for (final timer in timers) {
      timer.cancel();
    }
  }

  void runDisposeCallbacks() {
    final callbacks = List<void Function()>.of(_disposeCallbacks);
    _disposeCallbacks.clear();
    for (final callback in callbacks) {
      try {
        callback();
      } catch (error) {
        if (debugEnabled) print('Runtime cleanup failed: $error');
      }
    }
  }

  void setLocalContextValue(String key, dynamic value) {
    localContext[key] = value;
  }

  void removeLocalContextValue(String key) {
    localContext.remove(key);
  }

  void clearLocalContext() {
    localContext.clear();
  }

  void clearDartContext() {
    dartContext.clear();
  }

  void clearRuntimeState() {
    channelFunctions.clear();
    clearLocalContext();
    clearDartContext();
  }

  void retainValue(Pointer pointer) {}

  void releaseValue(Pointer pointer) {}

  JsEvalResult evaluate(String code, {String? sourceUrl});

  Future<JsEvalResult> evaluateAsync(String code, {String? sourceUrl});

  JsEvalResult callFunction(Pointer fn, Pointer obj);

  T? convertValue<T>(JsEvalResult jsValue);

  String jsonStringify(JsEvalResult jsValue);

  @protected
  void initChannelFunctions();

  int executePendingJob();

  void _setupConsoleLog() {
    evaluate("""
    var console = {
      log: function() {
        sendMessage('ConsoleLog', JSON.stringify(['log', ...arguments]));
      },
      warn: function() {
        sendMessage('ConsoleLog', JSON.stringify(['info', ...arguments]));
      },
      error: function() {
        sendMessage('ConsoleLog', JSON.stringify(['error', ...arguments]));
      }
    }""");
    onMessageVoid('ConsoleLog', (dynamic args) {
      final output = (args as List<dynamic>).skip(1).join(' ');
      print(output);
    });
  }

  void _setupSetTimeout() {
    evaluate("""
      var __NATIVE_FLUTTER_JS__setTimeoutCount = -1;
      var __NATIVE_FLUTTER_JS__setTimeoutCallbacks = {};
      function setTimeout(fnTimeout, timeout) {
        // console.log('Set Timeout Called');
        try {
        __NATIVE_FLUTTER_JS__setTimeoutCount += 1;
          var timeoutIndex = '' + __NATIVE_FLUTTER_JS__setTimeoutCount;
          __NATIVE_FLUTTER_JS__setTimeoutCallbacks[timeoutIndex] =  fnTimeout;
          ;
          // console.log(typeof(sendMessage));
          // console.log('BLA');
          sendMessage('SetTimeout', JSON.stringify({ timeoutIndex, timeout}));
            
        } catch (e) {
          console.error('ERROR HERE',e.message);
        }
      };
      1
    """);
    //print('SET TIMEOUT EVAL RESULT: $setTImeoutResult');
    onMessageVoid('SetTimeout', (dynamic args) {
      final duration = args['timeout'] as int? ?? 0;
      final idx = args['timeoutIndex'] as String;
      late Timer timer;
      timer = Timer(Duration(milliseconds: duration), () {
        unregisterRuntimeTimer(timer);
        if (!isRuntimeActive) return;
        evaluate("""
          __NATIVE_FLUTTER_JS__setTimeoutCallbacks[$idx].call();
          delete __NATIVE_FLUTTER_JS__setTimeoutCallbacks[$idx];
        """);
      });
      registerRuntimeTimer(timer);
    });
  }

  sendMessage({
    required String channelName,
    required List<String> args,
    String? uuid,
  }) {
    if (uuid != null) {
      evaluate(
          "DART_TO_QUICKJS_CHANNEL_sendMessage('$channelName', '${jsonEncode(args)}', '$uuid');");
    } else {
      evaluate(
          "DART_TO_QUICKJS_CHANNEL_sendMessage('$channelName', '${jsonEncode(args)}');");
    }
  }

  bool onMessage(
    String channelName,
    JavascriptMessageCallback fn, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    return setupBridge(channelName, fn, timeout: timeout);
  }

  bool onMessageVoid(
    String channelName,
    FutureOr<void> Function(dynamic args) fn,
  ) {
    return setupBridge(
      channelName,
      (args) => Future<void>.sync(() => fn(args)),
      fireAndForget: true,
    );
  }

  bool setupBridge(
    String channelName,
    JavascriptMessageCallback fn, {
    bool fireAndForget = false,
    Duration timeout = const Duration(seconds: 30),
  }) {
    ensureRuntimeActive();
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (channelFunctions.containsKey(channelName)) return false;
    channelFunctions[channelName] = JavascriptChannelRegistration(
      callback: fn,
      fireAndForget: fireAndForget,
      timeout: timeout,
    );
    return true;
  }

  String getEngineInstanceId();

  void setInspectable(bool inspectable);
}
