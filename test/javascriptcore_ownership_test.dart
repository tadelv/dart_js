import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_js/javascriptcore/jscore/js_string.dart';
import 'package:flutter_js/javascriptcore/jscore/js_value.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/javascriptcore/binding/js_string_ref.dart'
    as JSStringRef;
import 'package:test/test.dart';

void main() {
  final supported = Platform.isMacOS || Platform.isIOS;

  test(
    'JavaScriptCore string ownership paths',
    () {
      final runtime = JavascriptCoreRuntime();
      try {
        final cString = 'legacy'.toNativeUtf8();
        final legacyPointer =
            JSStringRef.jSStringCreateWithUTF8CString(cString);
        malloc.free(cString);
        final legacy = JSString(legacyPointer);
        expect(legacy.isOwned, isTrue);
        legacy.release();
        expect(legacy.pointer, nullptr);

        final owned = JSString.fromString('owned');
        final ownedPointer = owned.pointer;
        final borrowed = JSString.borrowed(ownedPointer);
        expect(owned.isOwned, isTrue);
        expect(borrowed.isOwned, isFalse);
        borrowed.release();
        expect(owned.string, 'owned');
        owned.release();
        expect(owned.pointer, nullptr);
        expect(owned.isOwned, isFalse);
        owned.release();

        final retained = JSString.fromString('retained');
        retained.retain();
        retained.release();
        expect(retained.pointer, nullptr);

        final array = JSStringPointer.array(['first', 'second']);
        array.release();
        array.release();
        expect(array.pointer, nullptr);

        final valuePointer = JSValuePointer();
        valuePointer.release();
        valuePointer.release();
        expect(valuePointer.pointer, nullptr);

        expect(
          () => JSString.withStrings(['throw'], (_) {
            throw StateError('callback failed');
          }),
          throwsStateError,
        );

        final noSource = runtime.evaluate('1 + 1');
        expect(noSource.stringResult, '2');
        final withSource = runtime.evaluate('2 + 2', sourceUrl: 'ownership.js');
        expect(withSource.stringResult, '4');

        final objectResult = runtime.evaluate('({answer: 42, label: "ok"})');
        final object = JSValue(
          runtime.context,
          objectResult.rawResult,
        ).toObject();
        expect(object.hasProperty('answer'), isTrue);
        expect(object.getProperty('answer').string, '42');
        final propertyNames = object.copyPropertyNames();
        try {
          final names = List.generate(
            propertyNames.count,
            propertyNames.propertyNameArrayGetNameAtIndex,
          );
          expect(names, containsAll(['answer', 'label']));
        } finally {
          propertyNames.release();
        }
        expect(jsonDecode(runtime.jsonStringify(objectResult)), {
          'answer': 42,
          'label': 'ok',
        });

        final jsonValue = JSValue.makeFromJSONString(
          runtime.context,
          '{"value": 7}',
        );
        final jsonString = jsonValue.createJSONString(indent: 0);
        try {
          expect(jsonDecode(jsonString.string!), {'value': 7});
        } finally {
          jsonString.release();
        }
        expect(JSValue.makeString(runtime.context, 'value').string, 'value');

        final name = JSString.fromString('ownership-test');
        runtime.context.setName(name);
        final copiedName = runtime.context.copyName();
        expect(copiedName.string, 'ownership-test');
        copiedName.release();
        name.release();

        final iterations = int.tryParse(
              Platform.environment['JSC_OWNERSHIP_ITERATIONS'] ?? '',
            ) ??
            1;
        final payload = 'x' * 2048;
        for (var i = 0; i < iterations; i++) {
          final result = runtime.evaluate(
            '({stateUpdate: "$payload", iteration: $i})',
            sourceUrl: i.isEven ? 'ownership.js' : null,
          );
          expect(jsonDecode(runtime.jsonStringify(result))['iteration'], i);
        }
      } finally {
        runtime.dispose();
      }
    },
    skip: supported ? false : 'requires JavaScriptCore on macOS or iOS',
  );
}
