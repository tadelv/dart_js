import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../binding/js_string_ref.dart' as JSStringRef;

/// A UTF16 character buffer. The fundamental string representation in JavaScript.
class JSString {
  /// C pointer
  Pointer _pointer;
  int _ownedReferences;

  Pointer get pointer => _pointer;

  bool get isOwned => _ownedReferences > 0;

  /// Wraps a raw pointer as borrowed. Use owned for Create/Copy results.
  JSString(Pointer pointer) : this.borrowed(pointer);

  /// Wraps a caller-owned JSStringRef.
  JSString.owned(Pointer pointer)
      : _pointer = pointer,
        _ownedReferences = pointer == nullptr ? 0 : 1;

  /// Wraps a borrowed JSStringRef without taking ownership.
  JSString.borrowed(Pointer pointer)
      : _pointer = pointer,
        _ownedReferences = 0;

  /// Creates a JavaScript string from dart String.
  /// [string] The dart String.
  JSString.fromString(String? string)
      : _pointer = nullptr,
        _ownedReferences = 0 {
    if (string == null) return;

    final cString = string.toNativeUtf8();
    try {
      _pointer = JSStringRef.jSStringCreateWithUTF8CString(cString);
      _ownedReferences = _pointer == nullptr ? 0 : 1;
    } finally {
      malloc.free(cString);
    }
  }

  /// Creates owned strings for the callback and releases them afterward.
  static T withStrings<T>(
      Iterable<String?> values, T Function(List<Pointer> pointers) callback) {
    final strings = <JSString>[];
    try {
      for (final value in values) {
        strings.add(JSString.fromString(value));
      }
      return callback(
          strings.map((string) => string.pointer).toList(growable: false));
    } finally {
      for (final string in strings) {
        string.release();
      }
    }
  }

  /// Retains a JavaScript string.
  /// [@result] (JSStringRef) A JSString that is the same as string.
  void retain() {
    if (_pointer == nullptr) return;

    _pointer = JSStringRef.jSStringRetain(_pointer);
    if (_pointer != nullptr) {
      _ownedReferences += 1;
    }
  }

  /// Releases all owned references once and makes repeated cleanup safe.
  void release() {
    if (_pointer == nullptr || _ownedReferences == 0) return;

    for (var i = 0; i < _ownedReferences; i++) {
      JSStringRef.jSStringRelease(_pointer);
    }
    _ownedReferences = 0;
    _pointer = nullptr;
  }

  /// Returns the number of Unicode characters in a JavaScript string.
  int get length {
    return JSStringRef.jSStringGetLength(_pointer);
  }

  /// Returns dart String
  String? get string {
    if (_pointer == nullptr) return null;
    var cString = JSStringRef.jSStringGetCharactersPtr(_pointer);
    if (cString == nullptr) {
      return null;
    }
    int cStringLength = JSStringRef.jSStringGetLength(_pointer);
    return String.fromCharCodes(Uint16List.view(
        cString.cast<Uint16>().asTypedList(cStringLength).buffer,
        0,
        cStringLength));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JSString &&
          runtimeType == other.runtimeType &&
          JSStringRef.jSStringIsEqual(_pointer, other.pointer) == 1 ||
      other is String && string == other;

  @override
  int get hashCode => _pointer.hashCode;
}

/// JSStringRef pointer
class JSStringPointer {
  /// C pointer
  Pointer<Pointer> _pointer;

  /// Pointer array count
  final int count;

  final List<JSString> _ownedStrings;
  bool _released = false;

  Pointer<Pointer> get pointer => _pointer;

  JSStringPointer([Pointer? value])
      : this.count = 1,
        this._pointer = malloc.call<Pointer>(1),
        this._ownedStrings = <JSString>[] {
    _pointer.value = value ?? nullptr;
  }

  /// JSStringRef array
  JSStringPointer.array(List<String> array)
      : this.count = array.length,
        this._pointer = array.isEmpty
            ? Pointer<Pointer>.fromAddress(0)
            : malloc.call<Pointer>(array.length),
        this._ownedStrings = <JSString>[] {
    try {
      for (int i = 0; i < array.length; i++) {
        final string = JSString.fromString(array[i]);
        _ownedStrings.add(string);
        _pointer[i] = string.pointer;
      }
    } catch (_) {
      release();
      rethrow;
    }
  }

  void release() {
    if (_released) return;
    _released = true;

    for (final string in _ownedStrings) {
      string.release();
    }
    if (_pointer != nullptr) {
      malloc.free(_pointer);
      _pointer = Pointer<Pointer>.fromAddress(0);
    }
  }

  /// Get JSValue
  /// [index] Array index
  JSString getValue([int index = 0]) {
    return JSString.borrowed(pointer[index]);
  }
}
