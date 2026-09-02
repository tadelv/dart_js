import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_js/flutter_js.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuickJsMemoryHarnessApp());
}

class QuickJsMemoryHarnessApp extends StatelessWidget {
  const QuickJsMemoryHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: QuickJsMemoryHarness());
  }
}

class QuickJsMemoryHarness extends StatefulWidget {
  const QuickJsMemoryHarness({super.key});

  @override
  State<QuickJsMemoryHarness> createState() => _QuickJsMemoryHarnessState();
}

class _QuickJsMemoryHarnessState extends State<QuickJsMemoryHarness> {
  List<String> _samples = const [];
  String _status = 'Running';

  @override
  void initState() {
    super.initState();
    Future<void>(_run);
  }

  void _evaluate(QuickJsRuntime2 runtime, String script) {
    final result = runtime.evaluate(script);
    if (result.isError) throw StateError(result.stringResult);
  }

  void _record(String name, [QuickJsRuntime2? runtime]) {
    final sample = jsonEncode({
      'name': name,
      'rssBytes': ProcessInfo.currentRss,
      if (runtime != null) ...runtime.memoryUsage.toJson(),
    });
    debugPrint('QUICKJS_MEMORY $sample');
    if (mounted) setState(() => _samples = [..._samples, sample]);
  }

  Future<void> _run() async {
    try {
      final runtime = QuickJsRuntime2();
      runtime.onMessage('MemoryEcho', (dynamic value) => value);
      runtime.onMessage(
        'StateUpdate',
        (dynamic value) => (value as Map<String, dynamic>)['iteration'],
      );
      try {
        _evaluate(runtime, '''
          (function () {
            var alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
            var input = 'x'.repeat(4 * 1024 * 1024);
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
        runtime.runGC();
        _record('btoa', runtime);

        for (var batch = 0; batch < 10; batch++) {
          _evaluate(runtime, '''
            (function () {
              var state = 'x'.repeat(8 * 1024);
              for (var i = 0; i < 500; i++) {
                sendMessage('StateUpdate', JSON.stringify({
                  stateUpdate: state,
                  iteration: i
                }));
              }
              var payload = 'x'.repeat(1024 * 1024);
              for (var j = 0; j < 4; j++) {
                sendMessage('MemoryEcho', JSON.stringify(payload));
              }
              for (var k = 0; k < 2000; k++) {
                var left = {};
                var right = {};
                left.right = right;
                right.left = left;
              }
              return 0;
            })()
          ''');
          runtime.runGC();
          _record('batch-$batch', runtime);
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } finally {
        runtime.dispose();
      }

      _record('after-main-dispose');
      for (var cycle = 0; cycle < 10; cycle++) {
        final runtime = QuickJsRuntime2();
        try {
          _evaluate(runtime, 'Promise.resolve($cycle)');
          runtime.executePendingJob();
        } finally {
          runtime.dispose();
        }
        _record('lifecycle-$cycle');
      }
      if (mounted) setState(() => _status = 'Complete');
    } catch (error, stackTrace) {
      debugPrint('$error\n$stackTrace');
      if (mounted) setState(() => _status = 'Failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('QuickJS Memory: $_status')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _samples.length,
        itemBuilder: (context, index) => SelectableText(_samples[index]),
      ),
    );
  }
}
