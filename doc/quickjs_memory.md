# QuickJS Android memory measurements

Run the release harness on a connected Android device:

```bash
cd example
flutter run --release -d <device-id> -t lib/quickjs_memory_harness.dart
```

Each `QUICKJS_MEMORY` log line records QuickJS allocated bytes, memory used,
allocation/object/string/function counts, and Dart's process RSS. Ignore the
first two warm-up samples and compare the remaining batches for a sustained
slope.

Capture Android PSS/RSS beside the harness samples:

```bash
adb shell dumpsys meminfo io.abner.flutter_js_example
```

Repeat the command after warm-up, after the final batch, and after the lifecycle
samples. A flat QuickJS series with rising PSS/RSS points outside the QuickJS
heap; rising QuickJS counters identify engine or retained-runtime allocations.
