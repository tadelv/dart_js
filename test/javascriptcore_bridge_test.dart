import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/extensions/handle_promises.dart';
import 'package:flutter_js/extensions/xhr.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/js_eval_result.dart';
import 'package:test/test.dart';

void main() {
  final supported = Platform.isMacOS || Platform.isIOS;
  final skipReason =
      supported ? false : 'requires JavaScriptCore on macOS or iOS';

  test(
    'JavaScriptCore bridge validates input and contains failures',
    () async {
      final runtime = JavascriptCoreRuntime();
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
        expect(runtime.convertValue<Map<String, dynamic>>(response), {
          'value': 42,
        });

        final voidResult = runtime.evaluate('sendMessage("void", "{}")');
        expect(voidResult.isError, isFalse);
        expect(voidResult.stringResult, 'undefined');
        expect(fireAndForgetCalls, 1);

        final futureResult = runtime.evaluate(
          'sendMessage("voidFuture", "{}")',
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
    'JavaScriptCore deferred requests resolve, reject, and time out',
    () async {
      final runtime = JavascriptCoreRuntime();
      try {
        runtime.enableHandlePromises();
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
        expect(runtime.pendingRequestCount, 0);

        final rejectedPromise = runtime.evaluate(
          'sendMessage("reject", "{}")',
        );
        await expectLater(
          runtime.handlePromise(rejectedPromise, timeout: Duration(seconds: 1)),
          throwsA(isA<StateError>()),
        );
        expect(runtime.pendingRequestCount, 0);

        final timeoutPromise = runtime.evaluate(
          'sendMessage("timeout", "{}")',
        );
        await expectLater(
          runtime.handlePromise(timeoutPromise, timeout: Duration(seconds: 1)),
          throwsA(isA<StateError>()),
        );
        expect(runtime.pendingRequestCount, 0);
      } finally {
        runtime.dispose();
      }
    },
    skip: skipReason,
  );

  test(
    'JavaScriptCore routes channels by native context',
    () {
      final first = JavascriptCoreRuntime();
      final second = JavascriptCoreRuntime();
      final replacement = JavascriptCoreRuntime();
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
    'JavaScriptCore protects retained values and releases them on disposal',
    () {
      final runtime = JavascriptCoreRuntime();
      try {
        runtime.enableHandlePromises();
        final initialCount = runtime.protectedValueCount;
        final first = runtime.evaluate('(function() {})').rawResult as Pointer;
        final second = runtime.evaluate('(function() {})').rawResult as Pointer;

        runtime.setLocalContextValue('value', first);
        expect(runtime.protectedValueCount, initialCount + 1);
        runtime.setLocalContextValue('value', second);
        expect(runtime.protectedValueCount, initialCount + 1);
        runtime.removeLocalContextValue('value');
        expect(runtime.protectedValueCount, initialCount);

        runtime.retainValue(first);
        runtime.retainValue(first);
        expect(runtime.protectedValueCount, initialCount + 1);
        runtime.releaseValue(first);
        expect(runtime.protectedValueCount, initialCount + 1);
        runtime.releaseValue(first);
        expect(runtime.protectedValueCount, initialCount);
      } finally {
        runtime.dispose();
      }
    },
    skip: skipReason,
  );

  test(
    'JavaScriptCore disposal is terminal and cancels pending work',
    () async {
      final runtime = JavascriptCoreRuntime();
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
      expect(runtime.pendingRequestCount, 0);
      expect(runtime.protectedValueCount, 0);
      expect(runtime.context.pointer, nullptr);
      expect(() => runtime.evaluate('1'), throwsA(isA<StateError>()));
      expect(() => runtime.evaluateAsync('1'), throwsA(isA<StateError>()));
      expect(() => runtime.executePendingJob(), throwsA(isA<StateError>()));
      expect(
        () => runtime.callFunction(null, null),
        throwsA(isA<StateError>()),
      );
      expect(() => runtime.setupBridge('late', (dynamic args) => null),
          throwsA(isA<StateError>()));
      expect(
        () => runtime.retainValue(Pointer.fromAddress(1)),
        throwsA(isA<StateError>()),
      );
      expect(
        () => runtime.setLocalContextValue('late', null),
        throwsA(isA<StateError>()),
      );
      expect(() => runtime.enableHandlePromises(), throwsA(isA<StateError>()));
      expect(() => runtime.enableXhr(), throwsA(isA<StateError>()));
      expect(() => runtime.setInspectable(false), throwsA(isA<StateError>()));
      expect(
        () => runtime.convertValue<dynamic>(JsEvalResult('1', nullptr)),
        throwsA(isA<StateError>()),
      );
      expect(
        () => runtime.jsonStringify(JsEvalResult('1', nullptr)),
        throwsA(isA<StateError>()),
      );
    },
    skip: skipReason,
  );
}
