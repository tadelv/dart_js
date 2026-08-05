import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/javascriptcore/jscore/js_value.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/js_eval_result.dart';
import 'package:test/test.dart';

void expectError(JsEvalResult result, String expected) {
  expect(result.isError, isTrue);
  expect(result.stringResult, contains(expected));
  expect(result.rawResult, isNot(nullptr));
}

void main() {
  final supported = Platform.isMacOS || Platform.isIOS;

  test(
    'JavaScriptCore exception state and conversion paths',
    () {
      final runtime = JavascriptCoreRuntime();
      try {
        final successfulErrorText =
            runtime.evaluate('"ERROR: this is a successful string"');
        expect(successfulErrorText.isError, isFalse);
        expect(
          successfulErrorText.stringResult,
          'ERROR: this is a successful string',
        );
        expect(successfulErrorText.rawResult, isNot(nullptr));

        final numberResult = runtime.evaluate('42');
        expect(numberResult.isError, isFalse);
        expect(runtime.convertValue<int>(numberResult), 42);

        final objectResult = runtime.evaluate('({answer: 42})');
        expect(objectResult.isError, isFalse);
        expect(runtime.convertValue<Map<String, dynamic>>(objectResult), {
          'answer': 42,
        });

        final hostileResult = runtime.evaluate('''
          ({
            answer: 42,
            toString() { throw "failed"; }
          })
        ''');
        expect(hostileResult.isError, isFalse);
        expect(
          runtime.convertValue<Map<String, dynamic>>(hostileResult),
          {'answer': 42},
        );

        final hostileFunction = runtime.evaluate('''
          (function() {
            return {
              answer: 42,
              toString() { throw "failed"; }
            };
          })
        ''');
        final hostileCall = runtime.callFunction(
          hostileFunction.rawResult,
          runtime.evaluate('undefined').rawResult,
        );
        expect(hostileCall.isError, isFalse);
        expect(runtime.convertValue<Map<String, dynamic>>(hostileCall), {
          'answer': 42,
        });

        for (final entry in <String, String>{
          'throw "failed";': 'failed',
          'throw 1;': '1',
          'throw true;': 'true',
          'throw null;': 'null',
          'throw undefined;': 'undefined',
        }.entries) {
          expectError(runtime.evaluate(entry.key), entry.value);
        }
        final symbolThrow = runtime.evaluate('throw Symbol("failed");');
        expect(symbolThrow.isError, isTrue);
        expect(symbolThrow.stringResult, isNotEmpty);
        expect(symbolThrow.rawResult, isNot(nullptr));

        expectError(runtime.evaluate('throw new Error("failed");'), 'failed');
        expectError(
          runtime.evaluate(
            'throw {message: "failed", stack: "custom stack"};',
          ),
          'custom stack',
        );
        final hostile = runtime.evaluate('''
          throw {
            get message() { throw "message getter failed"; },
            get stack() { throw "stack getter failed"; },
            toString() { return "original exception"; }
          };
        ''');
        expectError(hostile, 'original exception');

        final throwingToString = runtime.evaluate('''
          throw { toString() { throw "toString failed"; } };
        ''');
        expectError(throwingToString, 'JavaScript exception');
        expect(
            throwingToString.stringResult, isNot(contains('toString failed')));

        final syntaxError = runtime.evaluate('(');
        expectError(syntaxError, '');
        expect(syntaxError.stringResult, isNotEmpty);
        final sourceSyntaxError =
            runtime.evaluate('(', sourceUrl: 'syntax-error.js');
        expectError(sourceSyntaxError, '');
        expect(sourceSyntaxError.stringResult, contains('syntax-error.js'));

        final throwingFunction =
            runtime.evaluate('(function() { throw "failed call"; })');
        final throwingCall = runtime.callFunction(
          throwingFunction.rawResult,
          runtime.evaluate('undefined').rawResult,
        );
        expectError(throwingCall, 'failed call');

        final nonFunctionCall = runtime.callFunction(
          objectResult.rawResult,
          runtime.evaluate('undefined').rawResult,
        );
        expect(nonFunctionCall.isError, isTrue);

        final successfulFunction = runtime.evaluate(
          '(function() { return "ERROR: successful call"; })',
        );
        final successfulCall = runtime.callFunction(
          successfulFunction.rawResult,
          runtime.evaluate('undefined').rawResult,
        );
        expect(successfulCall.isError, isFalse);
        expect(successfulCall.stringResult, 'ERROR: successful call');

        final hostilePromise = runtime.evaluate('''
          ({
            get then() { throw "then failed"; },
            catch: function() {}
          })
        ''');
        expect(hostilePromise.isError, isFalse);
        expect(hostilePromise.isPromise, isFalse);

        final fractional =
            runtime.convertValue<double>(runtime.evaluate('1.5'));
        expect(fractional, 1.5);
        final nan = runtime.convertValue<double>(runtime.evaluate('NaN'));
        expect(nan!.isNaN, isTrue);
        final positiveInfinity =
            runtime.convertValue<double>(runtime.evaluate('Infinity'));
        expect(positiveInfinity, double.infinity);
        final negativeInfinity =
            runtime.convertValue<double>(runtime.evaluate('-Infinity'));
        expect(negativeInfinity, double.negativeInfinity);
        final negativeZero =
            runtime.convertValue<double>(runtime.evaluate('-0'));
        expect(negativeZero, 0);
        expect(negativeZero!.isNegative, isTrue);

        final symbol = runtime.evaluate('Symbol("number")');
        final numberException = JSValuePointer();
        try {
          final value = JSValue(runtime.context, symbol.rawResult);
          expect(value.toNumber(exception: numberException).isNaN, isTrue);
          expect(numberException.pointer.value, isNot(nullptr));
        } finally {
          numberException.release();
        }

        final cyclic = runtime.evaluate('''
          (function() {
            var value = {};
            value.self = value;
            return value;
          })()
        ''');
        expect(() => runtime.convertValue<dynamic>(cyclic), throwsStateError);
        expect(() => runtime.jsonStringify(cyclic), throwsStateError);

        final errorResult = runtime.evaluate('throw "failed conversion";');
        expect(
          () => runtime.convertValue<dynamic>(errorResult),
          throwsStateError,
        );
        expect(() => runtime.jsonStringify(errorResult), throwsStateError);

        final iterations = int.tryParse(
              Platform.environment['JSC_EXCEPTION_STRESS_ITERATIONS'] ?? '',
            ) ??
            4;
        for (var i = 0; i < iterations; i++) {
          switch (i % 4) {
            case 0:
              expect(runtime.evaluate('"success $i"').isError, isFalse);
            case 1:
              expectError(runtime.evaluate('throw "failed $i";'), 'failed');
            case 2:
              expectError(runtime.evaluate('('), '');
            case 3:
              expectError(
                runtime.evaluate('throw {message: "object $i"};'),
                'object',
              );
          }
        }
      } finally {
        runtime.dispose();
      }
    },
    skip: supported ? false : 'requires JavaScriptCore on macOS or iOS',
  );
}
