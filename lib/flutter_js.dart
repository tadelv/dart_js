import 'dart:io';

import 'package:flutter_js/javascript_runtime.dart';

import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

import './quickjs/quickjs_runtime2.dart';
export './quickjs/quickjs_runtime2.dart';

export './extensions/handle_promises.dart';
import './extensions/fetch.dart';
import './extensions/handle_promises.dart';

export 'js_eval_result.dart';
export 'javascript_runtime.dart';

// import condicional to not import ffi libraries when using web as target
// import "something.dart" if (dart.library.io) "other.dart";
// REF:
// - https://medium.com/flutter-community/conditional-imports-across-flutter-and-web-4b88885a886e
// - https://github.com/creativecreatorormaybenot/wakelock/blob/master/wakelock/lib/wakelock.dart
JavascriptRuntime getJavascriptRuntime({
  bool forceJavascriptCoreOnAndroid = false,
  bool xhr = false,
  Map<String, dynamic>? extraArgs = const {},
}) {
  JavascriptRuntime runtime;
  if ((Platform.isAndroid && !forceJavascriptCoreOnAndroid)) {
    int stackSize = extraArgs?['stackSize'] ?? 1024 * 1024;
    runtime = QuickJsRuntime2(stackSize: stackSize);
  } else if (Platform.isWindows) {
    runtime = QuickJsRuntime2();
  } else if (Platform.isLinux) {
    runtime = QuickJsRuntime2();
  } else {
    runtime = JavascriptCoreRuntime();
  }
  if (xhr) runtime.enableFetch();
  runtime.enableHandlePromises();
  return runtime;
}
