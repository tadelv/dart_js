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
  JsEvalResult callFunction(dynamic fn, dynamic obj) {
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
  final Map<String, Timer> _runtimeTimerRecords = {};

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
    _runtimeTimerRecords.clear();
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

  JsEvalResult callFunction(dynamic fn, dynamic obj);

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
      var __NATIVE_FLUTTER_JS__timerCount = -1;
      var __NATIVE_FLUTTER_JS__timerCallbacks = {};

      function __NATIVE_FLUTTER_JS__coerceDelay(delay) {
        var d = +delay;
        if (isNaN(d) || d < 0) d = 0;
        if (d > 2147483647) d = 2147483647;
        return d;
      }

      function setTimeout(fn, delay) {
        var args = Array.prototype.slice.call(arguments, 2);
        __NATIVE_FLUTTER_JS__timerCount += 1;
        var id = '' + __NATIVE_FLUTTER_JS__timerCount;
        __NATIVE_FLUTTER_JS__timerCallbacks[id] = {
          fn: fn,
          args: args,
          interval: false
        };
        sendMessage('SetTimer', JSON.stringify({
          id: id,
          delay: __NATIVE_FLUTTER_JS__coerceDelay(delay),
          interval: false
        }));
        return id;
      }

      function clearTimeout(id) {
        if (id === undefined || id === null) return;
        var key = '' + id;
        if (__NATIVE_FLUTTER_JS__timerCallbacks[key] !== undefined) {
          delete __NATIVE_FLUTTER_JS__timerCallbacks[key];
          sendMessage('ClearTimer', JSON.stringify({ id: key }));
        }
      }

      function setInterval(fn, delay) {
        var args = Array.prototype.slice.call(arguments, 2);
        __NATIVE_FLUTTER_JS__timerCount += 1;
        var id = '' + __NATIVE_FLUTTER_JS__timerCount;
        __NATIVE_FLUTTER_JS__timerCallbacks[id] = {
          fn: fn,
          args: args,
          interval: true
        };
        sendMessage('SetTimer', JSON.stringify({
          id: id,
          delay: __NATIVE_FLUTTER_JS__coerceDelay(delay),
          interval: true
        }));
        return id;
      }

      function clearInterval(id) {
        clearTimeout(id);
      }

      1
    """);
    onMessageVoid('SetTimer', (dynamic args) {
      final id = args['id'] as String;
      final delay = (args['delay'] as num).clamp(0, 2147483647).toInt();
      final interval = args['interval'] as bool? ?? false;
      late Timer timer;
      if (interval) {
        timer = Timer.periodic(Duration(milliseconds: delay), (_) {
          _fireTimerCallback(id);
        });
      } else {
        timer = Timer(Duration(milliseconds: delay), () {
          unregisterRuntimeTimer(timer);
          _runtimeTimerRecords.remove(id);
          _fireTimerCallback(id);
        });
      }
      _runtimeTimerRecords[id] = timer;
      registerRuntimeTimer(timer);
    });
    onMessageVoid('ClearTimer', (dynamic args) {
      final id = args['id'] as String;
      final timer = _runtimeTimerRecords.remove(id);
      if (timer != null) {
        unregisterRuntimeTimer(timer);
        timer.cancel();
      }
    });
  }

  void _fireTimerCallback(String id) {
    if (!isRuntimeActive) return;
    evaluate("""
      var entry = __NATIVE_FLUTTER_JS__timerCallbacks["$id"];
      if (entry) {
        if (!entry.interval) {
          delete __NATIVE_FLUTTER_JS__timerCallbacks["$id"];
        }
        entry.fn.apply(null, entry.args);
      }
    """);
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
