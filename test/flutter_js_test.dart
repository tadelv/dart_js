import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/extensions/fetch.dart';
import 'package:flutter_js/extensions/xhr.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:test/test.dart';

void main() {
  late JavascriptRuntime jsRuntime;

  // Need setup environment variable LIBQUICKJSC_PATH = './windows/shared/quickjs_c_bridge.dll'
  setUp(() {
    print(Platform.environment);
    jsRuntime = getJavascriptRuntime();
  });

  tearDown(() {
    try {
      jsRuntime.dispose();
    } on Error catch (_) {}
  });

  test('evaluate javascript', () {
    print(Platform.environment);
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
    final object = jsRuntime.evaluate('({ answer: 42 })');

    expect(
      jsRuntime.callFunction(function.rawResult, value.rawResult).rawResult,
      equals(42),
    );
    expect(jsRuntime.convertValue<int>(value), equals(21));
    expect(jsRuntime.jsonStringify(object), equals('{"answer":42}'));
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
