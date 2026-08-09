import 'dart:io';

import 'package:flutter_js/javascriptcore/jscore/js_context.dart';
import 'package:test/test.dart';

void main() {
  test(
    'creates a JavaScriptCore context with an implicit group',
    () {
      final context = JSContext.createInGroup();
      try {
        expect(context.evaluate('21 * 2').toNumber(), 42);
      } finally {
        context.release();
      }
    },
    skip: Platform.isMacOS || Platform.isIOS
        ? false
        : 'requires JavaScriptCore on macOS or iOS',
  );
}
