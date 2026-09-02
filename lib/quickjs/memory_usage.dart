final class QuickJsMemoryUsage {
  const QuickJsMemoryUsage({
    required this.allocatedBytes,
    required this.memoryUsedBytes,
    required this.allocationCount,
    required this.stringCount,
    required this.objectCount,
    required this.functionCount,
  });

  final int allocatedBytes;
  final int memoryUsedBytes;
  final int allocationCount;
  final int stringCount;
  final int objectCount;
  final int functionCount;

  Map<String, int> toJson() => {
    'allocatedBytes': allocatedBytes,
    'memoryUsedBytes': memoryUsedBytes,
    'allocationCount': allocationCount,
    'stringCount': stringCount,
    'objectCount': objectCount,
    'functionCount': functionCount,
  };
}
