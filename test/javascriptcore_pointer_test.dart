import 'dart:ffi';

import 'package:flutter_js/javascriptcore/jscore/js_context.dart';
import 'package:flutter_js/javascriptcore/jscore/js_object.dart';
import 'package:flutter_js/javascriptcore/jscore/js_string.dart';
import 'package:flutter_js/javascriptcore/jscore/js_value.dart';
import 'package:test/test.dart';

void main() {
  final context = JSContext(nullptr);

  test('native pointer slots and arrays release deterministically', () {
    final value = JSValue(context, Pointer.fromAddress(0x101));
    final valueSlot = JSValuePointer();
    expect(valueSlot.pointer.value, nullptr);
    valueSlot.pointer.value = value.pointer;
    expect(valueSlot.getValue(context).pointer, value.pointer);
    valueSlot.reset();
    expect(valueSlot.pointer.value, nullptr);
    valueSlot.release();
    expect(valueSlot.pointer, nullptr);
    valueSlot.release();

    final valueArray = JSValuePointer.array([value]);
    final valueReference = valueArray.pointer[0];
    valueArray.release();
    expect(valueArray.pointer, nullptr);
    expect(value.pointer, valueReference);
    valueArray.release();

    final emptyValueArray = JSValuePointer.array([]);
    expect(emptyValueArray.count, 0);
    expect(emptyValueArray.pointer, nullptr);
    emptyValueArray.release();
    emptyValueArray.release();

    final object = JSObject(context, Pointer.fromAddress(0x202));
    final objectSlot = JSObjectPointer();
    expect(objectSlot.pointer.value, nullptr);
    objectSlot.pointer.value = object.pointer;
    objectSlot.reset();
    expect(objectSlot.pointer.value, nullptr);
    objectSlot.release();
    expect(objectSlot.pointer, nullptr);
    objectSlot.release();

    final objectArray = JSObjectPointer.array([object]);
    final objectReference = objectArray.pointer[0];
    objectArray.release();
    expect(objectArray.pointer, nullptr);
    expect(object.pointer, objectReference);
    objectArray.release();

    final emptyObjectArray = JSObjectPointer.array([]);
    expect(emptyObjectArray.count, 0);
    expect(emptyObjectArray.pointer, nullptr);
    emptyObjectArray.release();
    emptyObjectArray.release();

    final stringSlot = JSStringPointer(Pointer.fromAddress(0x303));
    expect(stringSlot.pointer.value, Pointer.fromAddress(0x303));
    stringSlot.release();
    expect(stringSlot.pointer, nullptr);
    stringSlot.release();

    final emptyStringArray = JSStringPointer.array([]);
    expect(emptyStringArray.count, 0);
    expect(emptyStringArray.pointer, nullptr);
    emptyStringArray.release();
    emptyStringArray.release();
  });
}
