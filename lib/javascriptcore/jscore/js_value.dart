import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../binding/js_value_ref.dart' as JSValueRef;
import '../flutter_jscore.dart';

/// enum JSType
/// A constant identifying the type of a JSValue.
enum JSType {
  /// The unique undefined value.
  kJSTypeUndefined,

  /// The unique null value.
  kJSTypeNull,

  /// A primitive boolean value, one of true or false.
  kJSTypeBoolean,

  /// A primitive number value.
  kJSTypeNumber,

  /// A primitive string value.
  kJSTypeString,

  /// An object value (meaning that this JSValueRef is a JSObjectRef).
  kJSTypeObject,

  /// A primitive symbol value.
  kJSTypeSymbol
}

/// enum JSTypedArrayType
/// A constant identifying the Typed Array type of a JSObjectRef.
enum JSTypedArrayType {
  /// Int8Array
  kJSTypedArrayTypeInt8Array,

  /// Int16Array
  kJSTypedArrayTypeInt16Array,

  /// Int32Array
  kJSTypedArrayTypeInt32Array,

  /// Uint8Array
  kJSTypedArrayTypeUint8Array,

  /// Uint8ClampedArray
  kJSTypedArrayTypeUint8ClampedArray,

  /// Uint16Array
  kJSTypedArrayTypeUint16Array,

  /// Uint32Array
  kJSTypedArrayTypeUint32Array,

  /// Float32Array
  kJSTypedArrayTypeFloat32Array,

  /// Float64Array
  kJSTypedArrayTypeFloat64Array,

  /// ArrayBuffer
  kJSTypedArrayTypeArrayBuffer,

  /// Not a Typed Array
  kJSTypedArrayTypeNone,
}

/// A JavaScript value. The base type for all JavaScript values, and polymorphic functions on them.
class JSValue {
  /// enum JSType to C enum
  static int jSTypeToCEnum(JSType type) {
    switch (type) {
      case JSType.kJSTypeNull:
        return JSValueRef.JSType.kJSTypeNull;
      case JSType.kJSTypeBoolean:
        return JSValueRef.JSType.kJSTypeBoolean;
      case JSType.kJSTypeNumber:
        return JSValueRef.JSType.kJSTypeNumber;
      case JSType.kJSTypeString:
        return JSValueRef.JSType.kJSTypeString;
      case JSType.kJSTypeObject:
        return JSValueRef.JSType.kJSTypeObject;
      case JSType.kJSTypeSymbol:
        return JSValueRef.JSType.kJSTypeSymbol;
      default:
        return JSValueRef.JSType.kJSTypeUndefined;
    }
  }

  /// C enum to enum JSType
  static JSType cEnumToJSType(int typeCode) {
    switch (typeCode) {
      case JSValueRef.JSType.kJSTypeNull:
        return JSType.kJSTypeNull;
      case JSValueRef.JSType.kJSTypeBoolean:
        return JSType.kJSTypeBoolean;
      case JSValueRef.JSType.kJSTypeNumber:
        return JSType.kJSTypeNumber;
      case JSValueRef.JSType.kJSTypeString:
        return JSType.kJSTypeString;
      case JSValueRef.JSType.kJSTypeObject:
        return JSType.kJSTypeObject;
      case JSValueRef.JSType.kJSTypeSymbol:
        return JSType.kJSTypeSymbol;
      default:
        return JSType.kJSTypeUndefined;
    }
  }

  /// enum JSTypedArrayType to C enum
  static int jSTypedArrayTypeToCEnum(JSTypedArrayType type) {
    switch (type) {
      case JSTypedArrayType.kJSTypedArrayTypeInt8Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeInt8Array;
      case JSTypedArrayType.kJSTypedArrayTypeInt16Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeInt16Array;
      case JSTypedArrayType.kJSTypedArrayTypeInt32Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeInt32Array;
      case JSTypedArrayType.kJSTypedArrayTypeUint8Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint8Array;
      case JSTypedArrayType.kJSTypedArrayTypeUint8ClampedArray:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint8ClampedArray;
      case JSTypedArrayType.kJSTypedArrayTypeUint16Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint16Array;
      case JSTypedArrayType.kJSTypedArrayTypeUint32Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint32Array;
      case JSTypedArrayType.kJSTypedArrayTypeFloat32Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeFloat32Array;
      case JSTypedArrayType.kJSTypedArrayTypeFloat64Array:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeFloat64Array;
      case JSTypedArrayType.kJSTypedArrayTypeArrayBuffer:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeArrayBuffer;
      default:
        return JSValueRef.JSTypedArrayType.kJSTypedArrayTypeNone;
    }
  }

  /// C enum to enum JSTypedArrayType
  static JSTypedArrayType cEnumToJSTypedArrayType(int typeCode) {
    switch (typeCode) {
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeInt8Array:
        return JSTypedArrayType.kJSTypedArrayTypeInt8Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeInt16Array:
        return JSTypedArrayType.kJSTypedArrayTypeInt16Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeInt32Array:
        return JSTypedArrayType.kJSTypedArrayTypeInt32Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint8Array:
        return JSTypedArrayType.kJSTypedArrayTypeUint8Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint8ClampedArray:
        return JSTypedArrayType.kJSTypedArrayTypeUint8ClampedArray;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint16Array:
        return JSTypedArrayType.kJSTypedArrayTypeUint16Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeUint32Array:
        return JSTypedArrayType.kJSTypedArrayTypeUint32Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeFloat32Array:
        return JSTypedArrayType.kJSTypedArrayTypeFloat32Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeFloat64Array:
        return JSTypedArrayType.kJSTypedArrayTypeFloat64Array;
      case JSValueRef.JSTypedArrayType.kJSTypedArrayTypeArrayBuffer:
        return JSTypedArrayType.kJSTypedArrayTypeArrayBuffer;
      default:
        return JSTypedArrayType.kJSTypedArrayTypeNone;
    }
  }

  /// JavaScript context
  final JSContext context;

  /// C pointer
  final Pointer pointer;

  JSValue(this.context, this.pointer);

  void _ensurePointer() {
    if (pointer == nullptr) {
      throw StateError('JavaScript value reference is null');
    }
  }

  /// Creates a JavaScript value of the undefined type.
  JSValue.makeUndefined(this.context)
      : this.pointer = JSValueRef.jSValueMakeUndefined(context.pointer);

  /// Creates a JavaScript value of the null type.
  JSValue.makeNull(this.context)
      : this.pointer = JSValueRef.jSValueMakeNull(context.pointer);

  /// Creates a JavaScript value of the boolean type.
  /// [boolean] The bool to assign to the newly created JSValue.
  JSValue.makeBoolean(this.context, bool boolean)
      : this.pointer = JSValueRef.jSValueMakeBoolean(
            context.pointer, boolean == true ? 1 : 0);

  /// Creates a JavaScript value of the number type.
  /// [number] The double to assign to the newly created JSValue.
  JSValue.makeNumber(this.context, double number)
      : this.pointer = JSValueRef.jSValueMakeNumber(context.pointer, number);

  /// Creates a JavaScript value of the string type.
  /// [string] The double to assign to the newly created JSValue.
  JSValue.makeString(this.context, String string)
      : this.pointer = JSString.withStrings(
            [string],
            (strings) => JSValueRef.jSValueMakeString(
                context.pointer, strings[0]));

  /// Creates a JavaScript value of the symbol type.
  /// [description] A description of the newly created symbol value.
  JSValue.makeSymbol(this.context, String description)
      : this.pointer = JSString.withStrings(
            [description],
            (strings) => JSValueRef.jSValueMakeSymbol(
                context.pointer, strings[0]));

  /// Creates a JavaScript value from a JSON formatted string.
  /// [string] The JSString containing the JSON string to be parsed.
  JSValue.makeFromJSONString(this.context, String string)
      : this.pointer = JSString.withStrings(
            [string],
            (strings) => JSValueRef.jSValueMakeFromJSONString(
                context.pointer, strings[0]));

  /// Value type
  JSType get type {
    _ensurePointer();
    int typeCode = JSValueRef.jSValueGetType(context.pointer, pointer);
    return cEnumToJSType(typeCode);
  }

  /// Tests whether a JavaScript value's type is the undefined type.
  bool get isUndefined {
    _ensurePointer();
    return JSValueRef.jSValueIsUndefined(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the null type.
  bool get isNull {
    _ensurePointer();
    return JSValueRef.jSValueIsNull(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the boolean type.
  bool get isBoolean {
    _ensurePointer();
    return JSValueRef.jSValueIsBoolean(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the number type.
  bool get isNumber {
    _ensurePointer();
    return JSValueRef.jSValueIsNumber(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the string type.
  bool get isString {
    _ensurePointer();
    return JSValueRef.jSValueIsString(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the symbol type.
  bool get isSymbol {
    _ensurePointer();
    return JSValueRef.jSValueIsSymbol(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the object type.
  bool get isObject {
    _ensurePointer();
    return JSValueRef.jSValueIsObject(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value is an array.
  bool get isArray {
    _ensurePointer();
    return JSValueRef.jSValueIsArray(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value is a date.
  bool get isDate {
    _ensurePointer();
    return JSValueRef.jSValueIsDate(context.pointer, pointer) == 1;
  }

  /// Tests whether a JavaScript value's type is the symbol type.
  /// [jsClass] The JSClass to test against.
  bool isObjectOfClass(JSClass jsClass) {
    _ensurePointer();
    return JSValueRef.jSValueIsObjectOfClass(
            context.pointer, pointer, jsClass.pointer) ==
        1;
  }

  /// Returns a JavaScript value's Typed Array type.
  JSTypedArrayType getTypedArrayType({
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    exception?.reset();
    int typeCode = JSValueRef.jSValueGetTypedArrayType(
        context.pointer, pointer, exception?.pointer ?? nullptr);
    return cEnumToJSTypedArrayType(typeCode);
  }

  /// Tests whether two JavaScript values are equal, as compared by the JS == operator.
  bool isEqual(
    JSValue other, {
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    other._ensurePointer();
    exception?.reset();
    return JSValueRef.jSValueIsEqual(context.pointer, pointer, other.pointer,
            exception?.pointer ?? nullptr) ==
        1;
  }

  /// Tests whether a JavaScript value is an object constructed by a given constructor, as compared by the JS instanceof operator.
  bool isInstanceOfConstructor(
    JSObject constructor, {
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    exception?.reset();
    return JSValueRef.jSValueIsInstanceOfConstructor(context.pointer, pointer,
            constructor.pointer, exception?.pointer ?? nullptr) ==
        1;
  }

  /// Creates a JavaScript string containing the JSON serialized representation of a JS value.
  /// The returned JSString is owned by the caller and must be released.
  /// [indent] The number of spaces to indent when nesting.  If 0, the resulting JSON will not contains newlines.  The size of the indent is clamped to 10 spaces.
  /// [exception] A pointer to a JSValueRef in which to store an exception, if any. Pass NULL if you do not care to store an exception.
  JSString createJSONString({
    int indent = 4,
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    exception?.reset();
    return JSString.owned(JSValueRef.jSValueCreateJSONString(
        context.pointer, pointer, indent, exception?.pointer ?? nullptr));
  }

  /// Converts a JavaScript value to boolean and returns the resulting boolean.
  bool get toBoolean {
    _ensurePointer();
    return JSValueRef.jSValueToBoolean(context.pointer, pointer) == 1;
  }

  /// Converts a JavaScript value to number and returns the resulting number.
  /// [exception] A pointer to a JSValueRef in which to store an exception, if any. Pass NULL if you do not care to store an exception.
  double toNumber({
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    exception?.reset();
    return JSValueRef.jSValueToNumber(
        context.pointer, pointer, exception?.pointer ?? nullptr);
  }

  /// Converts a JavaScript value to number and returns the resulting string.
  String? get string {
    _ensurePointer();
    final exception = JSValuePointer();
    JSString? jsString;
    try {
      jsString = toStringCopy(exception: exception);
      if (exception.pointer.value != nullptr) {
        throw StateError('JavaScript value string conversion threw');
      }
      if (jsString.pointer == nullptr) {
        throw StateError('JavaScript value string conversion returned null');
      }
      final value = jsString.string;
      if (value == null) {
        throw StateError('JavaScript value string conversion returned null');
      }
      return value;
    } finally {
      jsString?.release();
      exception.release();
    }
  }

  /// Converts a JavaScript value to string and copies the result into a JavaScript string.
  /// The returned JSString is owned by the caller and must be released.
  /// [exception] A pointer to a JSValueRef in which to store an exception, if any. Pass NULL if you do not care to store an exception.
  JSString toStringCopy({
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    exception?.reset();
    return JSString.owned(JSValueRef.jSValueToStringCopy(
        context.pointer, pointer, exception?.pointer ?? nullptr));
  }

  /// Converts a JavaScript value to object and returns the resulting object.
  /// [exception] A pointer to a JSValueRef in which to store an exception, if any. Pass NULL if you do not care to store an exception.
  JSObject toObject({
    JSValuePointer? exception,
  }) {
    _ensurePointer();
    exception?.reset();
    return JSObject(
        context,
        JSValueRef.jSValueToObject(
            context.pointer, pointer, exception?.pointer ?? nullptr));
  }

  /// Protects a JavaScript value from garbage collection.
  /// Use this method when you want to store a JSValue in a global or on the heap, where the garbage collector will not be able to discover your reference to it.
  ///
  /// A value may be protected multiple times and must be unprotected an equal number of times before becoming eligible for garbage collection.
  void protect() {
    _ensurePointer();
    JSValueRef.jSValueProtect(context.pointer, pointer);
  }

  /// Protects a JavaScript value from garbage collection.
  /// Use this method when you want to store a JSValue in a global or on the heap, where the garbage collector will not be able to discover your reference to it.
  ///
  /// A value may be protected multiple times and must be unprotected an equal number of times before becoming eligible for garbage collection.
  void unProtect() {
    _ensurePointer();
    JSValueRef.jSValueUnprotect(context.pointer, pointer);
  }

  /// Tests whether two JavaScript values are strict equal, as compared by the JS === operator.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! JSValue || runtimeType != other.runtimeType) return false;
    _ensurePointer();
    other._ensurePointer();
    return JSValueRef.jSValueIsStrictEqual(
            context.pointer, pointer, other.pointer) ==
        1;
  }

  @override
  int get hashCode => context.hashCode ^ pointer.hashCode;
}

/// JSValueRef pointer
class JSValuePointer {
  /// C pointer
  Pointer<Pointer> _pointer;

  /// Pointer array count
  final int count;

  bool _released = false;

  Pointer<Pointer> get pointer => _pointer;

  JSValuePointer([Pointer? value])
      : this.count = 1,
        this._pointer = malloc.call<Pointer>(1) {
    _pointer.value = value ?? nullptr;
  }

  /// JSValueRef array
  JSValuePointer.array(List<JSValue> array)
      : this.count = array.length,
        this._pointer = array.isEmpty
            ? Pointer<Pointer>.fromAddress(0)
            : malloc.call<Pointer>(array.length) {
    for (int i = 0; i < array.length; i++) {
      _pointer[i] = array[i].pointer;
    }
  }

  void release() {
    if (_released) return;
    _released = true;
    final pointer = _pointer;
    _pointer = Pointer<Pointer>.fromAddress(0);
    if (pointer != nullptr) {
      malloc.free(pointer);
    }
  }

  void reset() {
    if (_released) return;
    for (var i = 0; i < count; i++) {
      _pointer[i] = nullptr;
    }
  }

  /// Get JSValue
  /// [index] Array index
  JSValue getValue(JSContext context, [int index = 0]) {
    return JSValue(context, _pointer[index]);
  }
}
