import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:test/test.dart';

void main() {
  late JavascriptRuntime jsRuntime;

  setUp(() {
    jsRuntime = getJavascriptRuntime();
    jsRuntime.enableHandlePromises();
  });

  tearDown(() {
    try {
      jsRuntime.dispose();
    } on Error catch (_) {}
  });

  test('setTimeout fires once and forwards extra arguments', () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        setTimeout((a, b) => resolve(a + b), 5, 'hello ', 'world');
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(jsonDecode(result.stringResult), 'hello world');
  });

  test('clearTimeout cancels a pending timeout', () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        var cancelled = false;
        var id = setTimeout(() => {
          cancelled = true;
          resolve('fired');
        }, 10);
        clearTimeout(id);
        setTimeout(() => resolve(cancelled ? 'fired' : 'cancelled'), 40);
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(jsonDecode(result.stringResult), 'cancelled');
  });

  test('clearing unknown or already-cleared handles is harmless', () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        clearTimeout(999);
        clearInterval(999);
        var id = setTimeout(() => resolve('bad'), 5);
        clearTimeout(id);
        clearTimeout(id);
        setTimeout(() => resolve('ok'), 20);
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(jsonDecode(result.stringResult), 'ok');
  });

  test('setInterval fires repeatedly until cleared', () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        var count = 0;
        var id = setInterval((step) => {
          count += step;
          if (count >= 6) {
            clearInterval(id);
            // Resolve after a delay longer than the interval period: a stray
            // tick after clearInterval would raise count and fail the assert.
            setTimeout(() => resolve(count), 20);
          }
        }, 5, 2);
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(result.stringResult, '6');
  });

  test('a timer callback can schedule and cancel other timers', () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        var inner = setTimeout(() => resolve('inner'), 10);
        setTimeout(() => {
          clearTimeout(inner);
          setTimeout(() => resolve('nested'), 5);
        }, 5);
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(jsonDecode(result.stringResult), 'nested');
  });

  test('missing, negative, fractional and string delays do not fail', () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        var count = 0;
        function tick() {
          count += 1;
          if (count === 4) resolve('coerced');
        }
        setTimeout(tick);
        setTimeout(tick, -5);
        setTimeout(tick, '2');
        setTimeout(tick, 1.5);
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(jsonDecode(result.stringResult), 'coerced');
  });

  test('two runtimes have independent timer namespaces', () async {
    final runtimeA = getJavascriptRuntime();
    final runtimeB = getJavascriptRuntime();
    try {
      runtimeA.enableHandlePromises();
      runtimeB.enableHandlePromises();
      final handleA = runtimeA.evaluate('setTimeout(function(){}, 100)');
      final handleB = runtimeB.evaluate('setTimeout(function(){}, 100)');
      expect(jsonDecode(handleA.stringResult), 0);
      expect(jsonDecode(handleB.stringResult), 0);

      runtimeB.dispose();

      final promise = await runtimeA.evaluateAsync('''
        new Promise((resolve) => {
          setTimeout(() => resolve('alive'), 5);
        })
      ''');
      final result = await runtimeA.handlePromise(promise);
      expect(jsonDecode(result.stringResult), 'alive');
    } finally {
      runtimeA.dispose();
      runtimeB.dispose();
    }
  });

  test(
      'a throwing one-shot callback does not leak bookkeeping or break later timers',
      () async {
    final promise = await jsRuntime.evaluateAsync('''
      new Promise((resolve) => {
        setTimeout(() => { throw new Error('boom'); }, 5);
        setTimeout(() => {
          var leaked = Object.keys(__NATIVE_FLUTTER_JS__timerCallbacks).length;
          setTimeout(() => resolve(leaked === 0 ? 'clean' : 'leaked:' + leaked), 5);
        }, 20);
      })
    ''');
    final result = await jsRuntime.handlePromise(promise);
    expect(jsonDecode(result.stringResult), 'clean');
  });

  test('dispose cancels outstanding timers and no callbacks run', () async {
    var timeoutFired = false;
    var intervalTicks = 0;
    jsRuntime.onMessageVoid('TimerProbe', (dynamic args) {
      timeoutFired = true;
    });
    jsRuntime.onMessageVoid('IntervalProbe', (dynamic args) {
      intervalTicks += 1;
    });
    jsRuntime.evaluate('''
      setTimeout(() => sendMessage('TimerProbe', JSON.stringify(['fired'])), 20);
      setInterval(() => sendMessage('IntervalProbe', JSON.stringify(['tick'])), 5);
    ''');
    jsRuntime.dispose();
    await Future.delayed(const Duration(milliseconds: 80));
    expect(timeoutFired, isFalse);
    expect(intervalTicks, 0);
  });

  test('repeated create/dispose cycles with pending timers stay safe',
      () async {
    for (var i = 0; i < 3; i++) {
      final runtime = getJavascriptRuntime();
      var fired = false;
      runtime.onMessageVoid('TimerProbe', (dynamic args) {
        fired = true;
      });
      runtime.evaluate('''
        setTimeout(() => sendMessage('TimerProbe', JSON.stringify(['fired'])), 10);
      ''');
      runtime.dispose();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(fired, isFalse);
    }
  });
}
