import 'dart:async';
import 'dart:ffi';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/js_eval_result.dart';

const REGISTER_PROMISE_FUNCTION = 'FLUTTER_NATIVEJS_REGISTER_PROMISE';

extension HandlePromises on JavascriptRuntime {
  void enableHandlePromises() {
    final fnRegisterPromise = evaluate('''
      var FLUTTER_NATIVEJS_PENDING_PROMISES = {};
      var FLUTTER_NATIVEJS_PENDING_PROMISES_COUNT = -1;
      function $REGISTER_PROMISE_FUNCTION(promise) {
        FLUTTER_NATIVEJS_PENDING_PROMISES_COUNT += 1;
        var idx = FLUTTER_NATIVEJS_PENDING_PROMISES_COUNT;
        FLUTTER_NATIVEJS_PENDING_PROMISES[idx] =
            FLUTTER_NATIVEJS_MakeQuerablePromise(promise);
        return idx;
      }
    ''');
    final fnMakeQPResult = evaluate('''
      function FLUTTER_NATIVEJS_CLEAN_PROMISE(idx) {
        delete FLUTTER_NATIVEJS_PENDING_PROMISES[idx];
      }
      function FLUTTER_NATIVEJS_IS_PENDING_PROMISE(idx) {
        return FLUTTER_NATIVEJS_PENDING_PROMISES[idx].isPending();
      }
      function FLUTTER_NATIVEJS_IS_FULLFILLED_PROMISE(idx) {
        return FLUTTER_NATIVEJS_PENDING_PROMISES[idx].isFulfilled();
      }
      function FLUTTER_NATIVEJS_IS_REJECTED_PROMISE(idx) {
        return FLUTTER_NATIVEJS_PENDING_PROMISES[idx].isRejected();
      }
      function FLUTTER_NATIVEJS_MakeQuerablePromise(promise) {
        if (promise.isResolved) return promise;
        var isPending = true;
        var isRejected = false;
        var isFulfilled = false;
        var value = null;
        var result = promise.then(
          function(v) {
            isFulfilled = true;
            isPending = false;
            value = v;
            return v;
          },
          function(e) {
            isRejected = true;
            isPending = false;
            value = e;
          }
        );
        result.isFulfilled = function() { return isFulfilled; };
        result.isPending = function() { return isPending; };
        result.isRejected = function() { return isRejected; };
        result.getValue = function() { return value; };
        return result;
      }
      FLUTTER_NATIVEJS_MakeQuerablePromise;
    ''');

    if (fnRegisterPromise.isError || fnMakeQPResult.isError) {
      throw StateError('Could not initialize JavaScript promise handling');
    }
    setLocalContextValue('makeQuerablePromise', fnMakeQPResult.rawResult);
    setLocalContextValue('registerPromise', fnRegisterPromise.rawResult);
  }

  bool isPendingPromise(int idx) {
    return evaluate('FLUTTER_NATIVEJS_IS_PENDING_PROMISE($idx)').stringResult ==
        'true';
  }

  bool isFulfilledPromise(int idx) {
    return evaluate(
          'FLUTTER_NATIVEJS_IS_FULLFILLED_PROMISE($idx)',
        ).stringResult ==
        'true';
  }

  Future<JsEvalResult> handlePromise(
    JsEvalResult value, {
    Duration? timeout,
  }) {
    return _doHandlePromise(value, timeout: timeout);
  }

  Future<JsEvalResult> _doHandlePromise(
    JsEvalResult value, {
    Duration? timeout,
  }) {
    ensureRuntimeActive();
    if (value.stringResult.contains("Instance of 'Future")) {
      return _handleDartFuture(value, timeout);
    }
    if (value.stringResult != '[object Promise]') return Future.value(value);

    final fnRegisterPromiseFunction = evaluate(REGISTER_PROMISE_FUNCTION);
    if (fnRegisterPromiseFunction.isError) {
      throw StateError(fnRegisterPromiseFunction.stringResult);
    }
    final registerResult = callFunction(
      fnRegisterPromiseFunction.rawResult,
      value.rawResult,
    );
    if (registerResult.isError) {
      throw StateError(registerResult.stringResult);
    }
    final idxPromise = int.parse(registerResult.stringResult);
    final completer = Completer<JsEvalResult>();
    final retainedPromise =
        value.rawResult is Pointer ? value.rawResult as Pointer : null;
    if (retainedPromise != null) retainValue(retainedPromise);
    Timer? pollTimer;
    Timer? timeoutTimer;
    var completed = false;
    late void Function() cleanup;

    cleanup = () {
      if (completed) return;
      completed = true;
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      if (pollTimer != null) unregisterRuntimeTimer(pollTimer);
      if (timeoutTimer != null) unregisterRuntimeTimer(timeoutTimer);
      if (retainedPromise != null) releaseValue(retainedPromise);
      unregisterDisposeCallback(cleanup);
    };

    void completeError(Object error) {
      cleanup();
      if (!completer.isCompleted) completer.completeError(error);
    }

    void completeResult(JsEvalResult result) {
      cleanup();
      if (!completer.isCompleted) completer.complete(result);
    }

    registerDisposeCallback(
      () => completeError(StateError('JavaScript runtime disposed')),
    );
    if (timeout != null) {
      timeoutTimer = Timer(
        timeout,
        () => completeError(TimeoutException('JavaScript promise timed out')),
      );
      registerRuntimeTimer(timeoutTimer);
    }
    pollTimer = Timer.periodic(Duration(milliseconds: 20), (_) {
      if (!isRuntimeActive) {
        completeError(StateError('JavaScript runtime disposed'));
        return;
      }
      try {
        executePendingJob();
        if (!isPendingPromise(idxPromise)) {
          final result = evaluate(
            'JSON.stringify(FLUTTER_NATIVEJS_PENDING_PROMISES[$idxPromise].getValue())',
          );
          final isFulfilled = isFulfilledPromise(idxPromise);
          evaluate('FLUTTER_NATIVEJS_CLEAN_PROMISE($idxPromise);');
          if (isFulfilled) {
            completeResult(result);
          } else {
            completeError(StateError(result.stringResult));
          }
        }
      } catch (error) {
        completeError(error);
      }
    });
    registerRuntimeTimer(pollTimer);
    return completer.future;
  }

  Future<JsEvalResult> _handleDartFuture(
    JsEvalResult value,
    Duration? timeout,
  ) {
    final completer = Completer<JsEvalResult>();
    Timer? pollTimer;
    Timer? timeoutTimer;
    var completed = false;
    late void Function() cleanup;

    cleanup = () {
      if (completed) return;
      completed = true;
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      if (pollTimer != null) unregisterRuntimeTimer(pollTimer);
      if (timeoutTimer != null) unregisterRuntimeTimer(timeoutTimer);
      unregisterDisposeCallback(cleanup);
    };

    void completeError(Object error) {
      cleanup();
      if (!completer.isCompleted) completer.completeError(error);
    }

    registerDisposeCallback(
      () => completeError(StateError('JavaScript runtime disposed')),
    );
    if (timeout != null) {
      timeoutTimer = Timer(
        timeout,
        () => completeError(TimeoutException('JavaScript promise timed out')),
      );
      registerRuntimeTimer(timeoutTimer);
    }
    pollTimer = Timer.periodic(Duration(milliseconds: 20), (_) {
      if (!isRuntimeActive) {
        completeError(StateError('JavaScript runtime disposed'));
        return;
      }
      try {
        executePendingJob();
      } catch (error) {
        completeError(error);
      }
    });
    registerRuntimeTimer(pollTimer);
    (value.rawResult as Future<dynamic>).then<void>(
      (dynamic result) {
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(JsEvalResult('$result', value.rawResult));
        }
      },
      onError: (Object error, StackTrace stack) => completeError(error),
    );
    return completer.future;
  }
}
