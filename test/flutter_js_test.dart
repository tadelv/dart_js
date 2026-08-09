import 'dart:convert';

import 'package:flutter_js/extensions/fetch.dart';
import 'package:flutter_js/extensions/xhr.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/quickjs/ffi.dart';
import 'package:test/test.dart';

void main() {
  late JavascriptRuntime jsRuntime;

  // Need setup environment variable LIBQUICKJSC_PATH = './windows/shared/quickjs_c_bridge.dll'
  setUp(() {
    jsRuntime = getJavascriptRuntime();
  });

  tearDown(() {
    try {
      jsRuntime.dispose();
    } on Error catch (_) {}
  });

  test('evaluate javascript', () {
    final result = jsRuntime.evaluate('Math.pow(5,3)');
    print('${result.rawResult}, ${result.stringResult}');
    print(
        '${result.rawResult.runtimeType}, ${result.stringResult.runtimeType}');
    expect(result.rawResult, equals(125));
    expect(result.stringResult, equals('125'));
  });

  test('QuickJS releases retained values before closing its context', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final result = jsRuntime.evaluate('({ answer: 42 })');
    jsRuntime.setLocalContextValue('retained', result.rawResult);

    (jsRuntime as QuickJsRuntime2).close();

    expect(jsRuntime.localContext, isEmpty);
    expect(jsRuntime.evaluate('21 * 2').rawResult, equals(42));
  });

  test('QuickJS removes runtime state when closing', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final initialRuntimeCount = runtimeOpaques.length;
    final runtime = QuickJsRuntime2();

    try {
      expect(runtimeOpaques.length, initialRuntimeCount + 1);
      runtime.close();
      expect(runtimeOpaques.length, initialRuntimeCount);
    } finally {
      runtime.dispose();
    }
  });

  test('QuickJS interrupts execution after its timeout', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final runtime = QuickJsRuntime2(timeout: 20);

    try {
      final stopwatch = Stopwatch()..start();
      final result = runtime.evaluate('while (true) {}');

      expect(result.isError, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    } finally {
      runtime.dispose();
    }
  });

  test('QuickJS interrupts infinite microtask drains after its timeout', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final runtime = QuickJsRuntime2(
      timeout: 20,
      hostPromiseRejectionHandler: (_) {},
    );

    try {
      runtime.evaluate('''
        Promise.resolve().then(function loop() {
          Promise.resolve().then(loop);
        });
      ''');
      final stopwatch = Stopwatch()..start();

      runtime.executePendingJob();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    } finally {
      runtime.dispose();
    }
  });

  test('xhr option installs fetch synchronously', () {
    final runtime = getJavascriptRuntime(xhr: true);

    try {
      expect(runtime.evaluate('typeof fetch').stringResult, equals('function'));
      expect(
        runtime.evaluate('typeof XMLHttpRequest').stringResult,
        equals('function'),
      );
    } finally {
      runtime.dispose();
    }
  });

  test('handlePromise reports non-JSON values', () async {
    final promise = jsRuntime.evaluate('Promise.resolve(() => 42)');

    await expectLater(
      jsRuntime.handlePromise(
        promise,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
  });

  test('QuickJS implements the runtime value contract', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final function = jsRuntime.evaluate('(value) => value * 2');
    final value = jsRuntime.evaluate('21');
    final object = jsRuntime.evaluate(
      'globalThis.obj = { answer: 42 }; globalThis.obj',
    );
    final sameObject = jsRuntime.evaluate(
      '(value) => value === globalThis.obj',
    );
    final error = jsRuntime.evaluate('throw "boom"');

    expect(
      jsRuntime.callFunction(function.rawResult, value.rawResult).rawResult,
      equals(42),
    );
    expect(
      jsRuntime.callFunction(sameObject.rawResult, object.rawResult).rawResult,
      isTrue,
    );
    expect(jsRuntime.convertValue<int>(value), equals(21));
    expect(() => jsRuntime.convertValue<String>(error), throwsStateError);
    expect(jsRuntime.jsonStringify(object), equals('{"answer":42}'));
  });

  test('QuickJS normalizes primitive function exceptions', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final function = jsRuntime.evaluate('() => { throw "boom"; }');

    final result = jsRuntime.callFunction(function.rawResult, null);

    expect(result.isError, isTrue);
    expect(result.rawResult, equals('boom'));
    expect(result.stringResult, equals('boom'));
  });

  test('QuickJS applies native JSON semantics', () {
    if (jsRuntime is! QuickJsRuntime2) return;
    final object = jsRuntime.evaluate('''
      ({
        omitted: undefined,
        kept: null,
        nonFinite: Infinity,
        fn: function () {}
      })
    ''');
    final transformed = jsRuntime.evaluate('''
      ({ toJSON: function () { return { answer: 42 }; } })
    ''');
    final cyclic = jsRuntime.evaluate('''
      var value = {};
      value.self = value;
      value;
    ''');

    expect(
      jsRuntime.jsonStringify(object),
      equals('{"kept":null,"nonFinite":null}'),
    );
    expect(jsRuntime.jsonStringify(transformed), equals('{"answer":42}'));
    expect(() => jsRuntime.jsonStringify(cyclic), throwsStateError);
  });

  test('IsolateQjs closes and restarts its worker', () async {
    final runtime = IsolateQjs();

    final first = await runtime
        .evaluate('21 * 2')
        .timeout(const Duration(seconds: 2)) as JsEvalResult;
    expect(first.rawResult, equals(42));
    expect(
      await runtime.close().timeout(const Duration(seconds: 2)),
      isTrue,
    );

    final second = await runtime
        .evaluate('6 * 7')
        .timeout(const Duration(seconds: 2)) as JsEvalResult;
    expect(second.rawResult, equals(42));
    expect(
      await runtime.close().timeout(const Duration(seconds: 2)),
      isTrue,
    );
  });

  test('leak test', () async {
    final jsRt = getJavascriptRuntime();
    jsRt.evaluate('''
    delay = (delayInms) => {
      return new Promise((resolve) => setTimeout(resolve, delayInms));
    }
    ''');
    jsRt.evaluate('''
    async function asyncTest(del = 30) {
      try {
        console.log(`Starting \$\{del\}...`);
        while (del > 0) {
          console.log(del);
          await delay(1000);
          del--;
        }
        console.log(`Done \$\{del\}`);
        return `Done \$\{del\}`;
      } catch (e) {
        console.log(`Error in asyncTest: \$\{e\}`);
        return "Error";
      }
    }
    ''');
    await jsRt.enableFetch();
    jsRt.enableHandlePromises();
    jsRt.enableXhr();
    final promise = await jsRt.evaluateAsync('asyncTest(2)');
    jsRt.executePendingJob();
    JsEvalResult asyncResult = await jsRt.handlePromise(promise);
    print('${asyncResult.stringResult}, ${asyncResult.stringResult}');
    jsRt.dispose();
  });
}
