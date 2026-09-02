import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_js/quickjs/ffi.dart';
import 'package:test/test.dart';

void expectSuccessful(JsEvalResult result) {
  expect(result.isError, isFalse, reason: result.stringResult);
}

QuickJsMemoryUsage runBatch(QuickJsRuntime2 runtime, String script) {
  expectSuccessful(runtime.evaluate(script));
  runtime.runGC();
  return runtime.memoryUsage;
}

void expectPlateau(
  QuickJsMemoryUsage first,
  QuickJsMemoryUsage second, {
  int byteSlack = 256 * 1024,
}) {
  expect(
    second.memoryUsedBytes,
    lessThanOrEqualTo(first.memoryUsedBytes + byteSlack),
  );
  expect(second.objectCount, lessThanOrEqualTo(first.objectCount + 32));
}

void main() {
  final supported = Platform.isAndroid || Platform.isLinux;

  group(
    'QuickJS memory diagnostics',
    () {
      test('reports runtime allocation counters', () {
        final runtime = QuickJsRuntime2();
        try {
          final usage = runtime.memoryUsage;

          expect(usage.allocatedBytes, greaterThan(0));
          expect(usage.memoryUsedBytes, greaterThan(0));
          expect(usage.allocationCount, greaterThan(0));
          expect(usage.stringCount, greaterThan(0));
          expect(usage.objectCount, greaterThan(0));
          expect(usage.functionCount, greaterThan(0));
        } finally {
          runtime.dispose();
        }
      });

      test('collects unreachable cyclic objects', () {
        final runtime = QuickJsRuntime2();
        try {
          runtime.runGC();
          final baseline = runtime.memoryUsage;
          expectSuccessful(
            runtime.evaluate('''
            (function () {
              for (var i = 0; i < 4000; i++) {
                var left = {};
                var right = {};
                left.right = right;
                right.left = left;
              }
              return 0;
            })()
          '''),
          );
          final allocated = runtime.memoryUsage;

          runtime.runGC();
          final collected = runtime.memoryUsage;

          expect(allocated.objectCount, greaterThan(baseline.objectCount));
          expect(
            collected.objectCount,
            lessThanOrEqualTo(baseline.objectCount + 32),
          );
        } finally {
          runtime.dispose();
        }
      });

      test('large btoa-style concatenation stays fast and reclaimable', () {
        final runtime = QuickJsRuntime2();
        try {
          final stopwatch = Stopwatch()..start();
          final result = runtime.evaluate('''
            (function () {
              var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
              var input = 'x'.repeat(2 * 1024 * 1024);
              var output = '';
              for (var i = 0; i < input.length; i += 3) {
                var a = input.charCodeAt(i);
                var b = input.charCodeAt(i + 1);
                var c = input.charCodeAt(i + 2);
                var bits = (a << 16) | ((b || 0) << 8) | (c || 0);
                output += alphabet[(bits >> 18) & 63];
                output += alphabet[(bits >> 12) & 63];
                output += i + 1 < input.length ? alphabet[(bits >> 6) & 63] : '=';
                output += i + 2 < input.length ? alphabet[bits & 63] : '=';
              }
              return output.length;
            })()
          ''');
          stopwatch.stop();

          expectSuccessful(result);
          expect(result.rawResult, equals(2796204));
          expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
          runtime.runGC();
          expect(
            runtime.memoryUsage.memoryUsedBytes,
            lessThan(8 * 1024 * 1024),
          );
        } finally {
          runtime.dispose();
        }
      });

      test('repeated state updates reach a memory plateau', () {
        final runtime = QuickJsRuntime2();
        runtime.onMessage(
          'StateUpdate',
          (dynamic state) => (state as Map<String, dynamic>)['iteration'],
        );
        const workload = '''
          (function () {
            var payload = 'x'.repeat(8 * 1024);
            for (var i = 0; i < 250; i++) {
              var result = sendMessage('StateUpdate', JSON.stringify({
                stateUpdate: payload,
                iteration: i
              }));
              if (result !== i) throw new Error('state update mismatch');
            }
            return 0;
          })()
        ''';

        try {
          runBatch(runtime, workload);
          final first = runBatch(runtime, workload);
          final second = runBatch(runtime, workload);

          expectPlateau(first, second);
        } finally {
          runtime.dispose();
        }
      });

      test('large bidirectional channel payloads reach a memory plateau', () {
        final runtime = QuickJsRuntime2();
        runtime.onMessage('MemoryEcho', (dynamic payload) => payload);
        const workload = '''
          (function () {
            var payload = 'x'.repeat(1024 * 1024);
            for (var i = 0; i < 4; i++) {
              var result = sendMessage('MemoryEcho', JSON.stringify(payload));
              if (result.length !== payload.length) {
                throw new Error('channel payload mismatch');
              }
            }
            return 0;
          })()
        ''';

        try {
          runBatch(runtime, workload);
          final first = runBatch(runtime, workload);
          final second = runBatch(runtime, workload);

          expectPlateau(first, second, byteSlack: 512 * 1024);
        } finally {
          runtime.dispose();
        }
      });

      test('runtime lifecycle releases bridge state', () {
        final baseline = runtimeOpaques.length;

        for (var i = 0; i < 12; i++) {
          final runtime = QuickJsRuntime2();
          try {
            expectSuccessful(
              runtime.evaluate(
                'Promise.resolve($i).then(function (value) { return value; })',
              ),
            );
            runtime.executePendingJob();
          } finally {
            runtime.dispose();
          }
          expect(runtimeOpaques.length, baseline);
        }
      });
    },
    skip: supported ? false : 'requires the Android/Linux source build',
  );
}
