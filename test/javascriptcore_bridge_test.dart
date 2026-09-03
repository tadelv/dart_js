import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/extensions/fetch.dart';
import 'package:flutter_js/extensions/handle_promises.dart';
import 'package:flutter_js/extensions/xhr.dart';
import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/js_eval_result.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _TestHttpClient extends http.BaseClient {
  _TestHttpClient({this.responseBody = '{"value":42}'});

  final String responseBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(responseBody)),
      200,
      reasonPhrase: 'OK',
      headers: {'x-test': 'first', 'x-mode': 'active'},
    );
  }
}

void main() {
  final usesJavaScriptCore = Platform.isMacOS || Platform.isIOS;
  final supported = usesJavaScriptCore || Platform.isWindows;
  final skipReason = supported ? false : 'requires JavaScriptCore or QuickJS';

  JavascriptRuntime createRuntime() {
    return usesJavaScriptCore ? JavascriptCoreRuntime() : QuickJsRuntime2();
  }

  test(
    'JavaScript bridge validates input and contains failures',
    () async {
      final runtime = createRuntime();
      try {
        var fireAndForgetCalls = 0;
        runtime.onMessage('echo', (dynamic args) => args);
        runtime.onMessage('throwString', (dynamic args) {
          throw 'callback failed';
        });
        runtime.onMessageVoid('void', (dynamic args) {
          fireAndForgetCalls += 1;
        });
        runtime.onMessageVoid('voidFuture', (dynamic args) {
          return Future<void>.error('async callback failed');
        });

        for (final script in <String>[
          'sendMessage()',
          'sendMessage("echo")',
          'sendMessage(1, "{}")',
          'sendMessage("echo", {})',
          'sendMessage("echo", "not json")',
          'sendMessage("missing", "{}")',
        ]) {
          expect(runtime.evaluate(script).isError, isTrue, reason: script);
        }

        final callbackError = runtime.evaluate(
          'sendMessage("throwString", "{}")',
        );
        expect(callbackError.isError, isTrue);
        expect(callbackError.stringResult, contains('callback failed'));

        final response = runtime.evaluate(
          'sendMessage("echo", "{\\"value\\":42}")',
        );
        expect(response.isError, isFalse);
        if (usesJavaScriptCore) {
          expect(runtime.convertValue<Map<String, dynamic>>(response), {
            'value': 42,
          });
        } else {
          expect(response.rawResult, {'value': 42});
        }

        final voidResult = runtime.evaluate(
          'typeof sendMessage("void", "{}")',
        );
        expect(voidResult.isError, isFalse);
        expect(voidResult.stringResult, 'undefined');
        expect(fireAndForgetCalls, 1);

        final futureResult = runtime.evaluate(
          'typeof sendMessage("voidFuture", "{}")',
        );
        expect(futureResult.isError, isFalse);
        expect(futureResult.stringResult, 'undefined');
        await Future<void>.delayed(Duration.zero);

        final iterations = int.tryParse(
              Platform.environment['JSC_BRIDGE_STRESS_ITERATIONS'] ?? '',
            ) ??
            4;
        for (var i = 0; i < iterations; i++) {
          expect(
              runtime.evaluate('sendMessage("void", "{}")').isError, isFalse);
        }
      } finally {
        runtime.dispose();
      }
    },
    skip: skipReason,
  );

  test(
    'XHR request entries are removed before user callbacks',
    () async {
      final runtime = createRuntime();
      final client = _TestHttpClient();
      xhrSetHttpClient(client);
      try {
        runtime.enableXhr();
        final pending = runtime.evaluate('''
          var xhr = new XMLHttpRequest();
          xhr.open('GET', 'https://example.test');
          xhr.onload = function() { throw 'callback failed'; };
          xhr.send();
          Object.keys(xhrRequests).length;
        ''');
        expect(pending.stringResult, '1');

        await Future<void>.delayed(Duration(milliseconds: 200));
        expect(
          runtime.evaluate('Object.keys(xhrRequests).length').stringResult,
          '0',
        );
      } finally {
        runtime.dispose();
        xhrSetHttpClient(null);
        client.close();
      }
    },
    skip: skipReason,
  );

  test(
    'XHR preserves response headers',
    () async {
      final runtime = createRuntime();
      final client = _TestHttpClient();
      xhrSetHttpClient(client);
      try {
        runtime.enableXhr();
        runtime.evaluate('''
          var xhrHeaderResult = null;
          var xhr = new XMLHttpRequest();
          xhr.open('GET', 'https://example.test');
          xhr.onload = function() {
            var all = xhr.getAllResponseHeaders().toLowerCase();
            xhrHeaderResult = {
              all: all.indexOf('x-test: first\\r\\n') !== -1 &&
                  all.indexOf('x-mode: active\\r\\n') !== -1,
              one: xhr.getResponseHeader('X-Test')
            };
          };
          xhr.send();
        ''');

        await Future<void>.delayed(Duration(milliseconds: 200));
        expect(
          jsonDecode(
            runtime.evaluate('JSON.stringify(xhrHeaderResult)').stringResult,
          ),
          {'all': true, 'one': 'first'},
        );
      } finally {
        runtime.dispose();
        xhrSetHttpClient(null);
        client.close();
      }
    },
    skip: skipReason,
  );

  test(
    'XHR preserves decoded response text',
    () async {
      const responseBody = '{\n  "value": 42\n}';
      final runtime = createRuntime();
      final client = _TestHttpClient(responseBody: responseBody);
      xhrSetHttpClient(client);
      try {
        runtime.enableXhr();
        runtime.evaluate('''
          var xhrResponseText = null;
          var xhr = new XMLHttpRequest();
          xhr.open('GET', 'https://example.test');
          xhr.onload = function() { xhrResponseText = xhr.responseText; };
          xhr.send();
        ''');

        await Future<void>.delayed(Duration(milliseconds: 200));
        expect(
          jsonDecode(
            runtime.evaluate('JSON.stringify(xhrResponseText)').stringResult,
          ),
          responseBody,
        );
      } finally {
        runtime.dispose();
        xhrSetHttpClient(null);
        client.close();
      }
    },
    skip: skipReason,
  );

  test(
    'fetch rejects invalid JSON response bodies',
    () async {
      final runtime = usesJavaScriptCore
          ? JavascriptCoreRuntime()
          : QuickJsRuntime2(hostPromiseRejectionHandler: (_) {});
      final client = _TestHttpClient(responseBody: 'not json');
      xhrSetHttpClient(client);
      try {
        runtime.enableFetch();
        runtime.enableHandlePromises();
        final promise = runtime.evaluate('''
          fetch('https://example.test')
              .then(function(response) { return response.json(); })
              .then(
                function() { return 'fulfilled'; },
                function() { return 'rejected'; }
              );
        ''');

        expect(promise.isPromise, isTrue);
        final result = await runtime.handlePromise(
          promise,
          timeout: Duration(seconds: 1),
        );
        expect(
          jsonDecode(result.stringResult),
          'rejected',
        );
      } finally {
        runtime.dispose();
        xhrSetHttpClient(null);
        client.close();
      }
    },
    skip: skipReason,
  );

  test(
    'JavaScript bridge deferred requests resolve, reject, and time out',
    () async {
      final runtime = createRuntime();
      try {
        runtime.enableHandlePromises();
        final initialDisposeCallbackCount = runtime.disposeCallbackCount;
        runtime.onMessage(
          'resolve',
          (dynamic args) => Future<dynamic>.delayed(
            Duration(milliseconds: 1),
            () => <String, dynamic>{'value': 42},
          ),
        );
        runtime.onMessage(
          'reject',
          (dynamic args) => Future<dynamic>.error('rejected'),
        );
        runtime.onMessage(
          'timeout',
          (dynamic args) => Completer<dynamic>().future,
          timeout: Duration(milliseconds: 20),
        );

        final resolvedPromise = runtime.evaluate(
          'sendMessage("resolve", "{}")',
        );
        expect(resolvedPromise.isPromise, isTrue);
        final resolved = await runtime.handlePromise(
          resolvedPromise,
          timeout: Duration(seconds: 1),
        );
        expect(jsonDecode(resolved.stringResult), {'value': 42});
        if (runtime is JavascriptCoreRuntime) {
          expect(runtime.pendingRequestCount, 0);
          expect(
            runtime
                .evaluate(
                  'Object.keys(FLUTTER_NATIVEJS_PENDING_PROMISES).length',
                )
                .stringResult,
            '0',
          );
        }
        expect(runtime.disposeCallbackCount, initialDisposeCallbackCount);

        final rejectedPromise = runtime.evaluate(
          'sendMessage("reject", "{}")',
        );
        await expectLater(
          runtime.handlePromise(rejectedPromise, timeout: Duration(seconds: 1)),
          throwsA(isA<StateError>()),
        );
        if (runtime is JavascriptCoreRuntime) {
          expect(runtime.pendingRequestCount, 0);
          expect(
            runtime
                .evaluate(
                  'Object.keys(FLUTTER_NATIVEJS_PENDING_PROMISES).length',
                )
                .stringResult,
            '0',
          );
        }
        expect(runtime.disposeCallbackCount, initialDisposeCallbackCount);

        final timeoutPromise = runtime.evaluate(
          'sendMessage("timeout", "{}")',
        );
        final timeoutResult = runtime.handlePromise(timeoutPromise,
            timeout: Duration(seconds: 1));
        await expectLater(
          timeoutResult,
          throwsA(
            usesJavaScriptCore ? isA<StateError>() : isA<TimeoutException>(),
          ),
        );
        if (runtime is JavascriptCoreRuntime) {
          expect(runtime.pendingRequestCount, 0);
          expect(
            runtime
                .evaluate(
                  'Object.keys(FLUTTER_NATIVEJS_PENDING_PROMISES).length',
                )
                .stringResult,
            '0',
          );
        }
        expect(runtime.disposeCallbackCount, initialDisposeCallbackCount);
      } finally {
        runtime.dispose();
      }
    },
    skip: skipReason,
  );

  test(
    'JavaScript bridge keeps channels isolated by runtime',
    () {
      final first = createRuntime();
      final second = createRuntime();
      final replacement = createRuntime();
      try {
        first.onMessage('same', (dynamic args) => 'first');
        second.onMessage('same', (dynamic args) => 'second');

        expect(
            first.evaluate('sendMessage("same", "{}")').stringResult, 'first');
        expect(second.evaluate('sendMessage("same", "{}")').stringResult,
            'second');

        first.dispose();
        expect(second.evaluate('1 + 1').stringResult, '2');
        final missing = replacement.evaluate('sendMessage("same", "{}")');
        expect(missing.isError, isTrue);
      } finally {
        first.dispose();
        second.dispose();
        replacement.dispose();
      }
    },
    skip: skipReason,
  );

  test(
    'JavaScript runtime releases retained context values',
    () {
      final runtime = createRuntime();
      try {
        runtime.enableHandlePromises();
        final initialCount = runtime is JavascriptCoreRuntime
            ? runtime.protectedValueCount
            : null;
        final first = runtime.evaluate('(function() {})').rawResult;
        final second = runtime.evaluate('(function() {})').rawResult;

        runtime.setLocalContextValue('value', first);
        expect(runtime.localContext['value'], same(first));
        if (runtime is JavascriptCoreRuntime) {
          expect(runtime.protectedValueCount, initialCount! + 1);
          expect(
            () => runtime.localContext['bypass'] = first,
            throwsA(isA<UnsupportedError>()),
          );
        }
        runtime.setLocalContextValue('value', second);
        expect(runtime.localContext['value'], same(second));
        if (runtime is JavascriptCoreRuntime) {
          expect(runtime.protectedValueCount, initialCount! + 1);
          expect(
            () => runtime.localContext.remove('value'),
            throwsA(isA<UnsupportedError>()),
          );
        }
        runtime.removeLocalContextValue('value');
        expect(runtime.localContext.containsKey('value'), isFalse);

        if (runtime is JavascriptCoreRuntime) {
          final pointer = first as Pointer;
          runtime.retainValue(pointer);
          runtime.retainValue(pointer);
          expect(runtime.protectedValueCount, initialCount! + 1);
          runtime.releaseValue(pointer);
          expect(runtime.protectedValueCount, initialCount + 1);
          runtime.releaseValue(pointer);
          expect(runtime.protectedValueCount, initialCount);
        }
      } finally {
        runtime.dispose();
      }
    },
    skip: skipReason,
  );

  test(
    'JavaScript runtime disposal is terminal and cancels pending work',
    () async {
      final runtime = createRuntime();
      runtime.enableHandlePromises();
      runtime.onMessage(
        'pending',
        (dynamic args) => Completer<dynamic>().future,
      );
      final promise = runtime.evaluate('sendMessage("pending", "{}")');
      final handled = runtime.handlePromise(
        promise,
        timeout: Duration(seconds: 1),
      );
      runtime.dispose();
      runtime.dispose();

      await expectLater(handled, throwsA(isA<StateError>()));
      if (runtime is JavascriptCoreRuntime) {
        expect(runtime.pendingRequestCount, 0);
        expect(runtime.protectedValueCount, 0);
        expect(runtime.context.pointer, nullptr);
      }
      expect(() => runtime.evaluate('1'), throwsA(isA<StateError>()));
      expect(() => runtime.evaluateAsync('1'), throwsA(isA<StateError>()));
      expect(() => runtime.executePendingJob(), throwsA(isA<StateError>()));
      expect(() => runtime.setupBridge('late', (dynamic args) => null),
          throwsA(isA<StateError>()));
      expect(() => runtime.enableHandlePromises(), throwsA(isA<StateError>()));
      expect(() => runtime.enableXhr(), throwsA(isA<StateError>()));
      if (runtime is JavascriptCoreRuntime) {
        expect(
          () => runtime.callFunction(null, null),
          throwsA(isA<StateError>()),
        );
        expect(
          () => runtime.retainValue(Pointer.fromAddress(1)),
          throwsA(isA<StateError>()),
        );
        expect(
          () => runtime.setLocalContextValue('late', null),
          throwsA(isA<StateError>()),
        );
        expect(
          () => runtime.setInspectable(false),
          throwsA(isA<StateError>()),
        );
        expect(
          () => runtime.convertValue<dynamic>(JsEvalResult('1', nullptr)),
          throwsA(isA<StateError>()),
        );
      }
      expect(
        () => runtime.jsonStringify(JsEvalResult('1', nullptr)),
        throwsA(isA<StateError>()),
      );
    },
    skip: skipReason,
  );
}
