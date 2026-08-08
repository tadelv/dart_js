/*
 * @Description: isolate
 * @Author: ekibun
 * @Date: 2020-10-02 13:49:03
 * @LastEditors: ekibun
 * @LastEditTime: 2020-10-03 22:21:31
 */
part of './quickjs_runtime2.dart';

typedef dynamic _Decode(Map obj);
List<_Decode> _decoders = [
  JSError._decode,
  IsolateFunction._decode,
];

abstract class _IsolateEncodable {
  Map _encode();
}

dynamic _encodeData(dynamic data, {Map<dynamic, dynamic>? cache}) {
  if (cache == null) cache = Map();
  if (cache.containsKey(data)) return cache[data];
  if (data is Error || data is Exception)
    return _encodeData(JSError(data), cache: cache);
  if (data is _IsolateEncodable) return data._encode();
  if (data is List) {
    final ret = [];
    cache[data] = ret;
    for (int i = 0; i < data.length; ++i) {
      ret.add(_encodeData(data[i], cache: cache));
    }
    return ret;
  }
  if (data is Map) {
    final ret = {};
    cache[data] = ret;
    for (final entry in data.entries) {
      ret[_encodeData(entry.key, cache: cache)] =
          _encodeData(entry.value, cache: cache);
    }
    return ret;
  }
  if (data is Future) {
    final futurePort = ReceivePort();
    data.then((value) {
      futurePort.first.then((port) {
        futurePort.close();
        (port as SendPort).send(_encodeData(value));
      });
    }, onError: (e) {
      futurePort.first.then((port) {
        futurePort.close();
        (port as SendPort).send({#error: _encodeData(e)});
      });
    });
    return {
      #jsFuturePort: futurePort.sendPort,
    };
  }
  return data;
}

dynamic _decodeData(dynamic data, {Map<dynamic, dynamic>? cache}) {
  if (cache == null) cache = Map();
  if (cache.containsKey(data)) return cache[data];
  if (data is List) {
    final ret = [];
    cache[data] = ret;
    for (int i = 0; i < data.length; ++i) {
      ret.add(_decodeData(data[i], cache: cache));
    }
    return ret;
  }
  if (data is Map) {
    for (final decoder in _decoders) {
      final decodeObj = decoder(data);
      if (decodeObj != null) return decodeObj;
    }
    if (data.containsKey(#jsFuturePort)) {
      SendPort port = data[#jsFuturePort];
      final futurePort = ReceivePort();
      port.send(futurePort.sendPort);
      final futureCompleter = Completer();
      futureCompleter.future.catchError((e) {});
      futurePort.first.then((value) {
        futurePort.close();
        if (value is Map && value.containsKey(#error)) {
          futureCompleter.completeError(_decodeData(value[#error]));
        } else {
          futureCompleter.complete(_decodeData(value));
        }
      });
      return futureCompleter.future;
    }
    final ret = {};
    cache[data] = ret;
    for (final entry in data.entries) {
      ret[_decodeData(entry.key, cache: cache)] =
          _decodeData(entry.value, cache: cache);
    }
    return ret;
  }
  return data;
}

void _runJsIsolate(Map spawnMessage) async {
  SendPort sendPort = spawnMessage[#port];
  ReceivePort port = ReceivePort();
  sendPort.send(port.sendPort);
  final qjs = QuickJsRuntime2(
    stackSize: spawnMessage[#stackSize] ?? 1024 * 1024,
    hostPromiseRejectionHandler: (reason) {
      sendPort.send({
        #type: #hostPromiseRejection,
        #reason: _encodeData(reason),
      });
    },
    moduleHandler: (name) {
      final ptr = calloc<Pointer<Utf8>>();
      ptr.value = Pointer.fromAddress(ptr.address);
      sendPort.send({
        #type: #module,
        #name: name,
        #ptr: ptr.address,
      });
      while (ptr.value.address == ptr.address) sleep(Duration(microseconds: 1));
      final ret = ptr.value;
      malloc.free(ptr);
      if (ret.address == -1) throw JSError('Module Not found');
      final retString = ret.toDartString();
      malloc.free(ret);
      return retString;
    },
  );
  port.listen((msg) async {
    var data;
    SendPort? msgPort = msg[#port];
    try {
      switch (msg[#type]) {
        case #evaluate:
          data = qjs.evaluate(
            msg[#command],
            name: msg[#name],
            evalFlags: msg[#flag],
          );
          break;
        case #close:
          data = false;
          qjs.port.close();
          qjs.close();
          port.close();
          data = true;
          break;
      }
      if (msgPort != null) msgPort.send(_encodeData(data));
    } catch (e) {
      if (msgPort != null)
        msgPort.send({
          #error: _encodeData(e),
        });
    }
  });
  await qjs.dispatch();
}

typedef _JsAsyncModuleHandler = Future<String> Function(String name);

class _IsolateSession {
  final ready = Completer<SendPort>();
  final failure = Completer<void>();
  final closedError = StateError('QuickJS isolate closed');
  bool closing = false;

  _IsolateSession() {
    ready.future.ignore();
    failure.future.ignore();
  }
}

class IsolateQjs {
  _IsolateSession? _session;

  /// Max stack size for quickjs.
  final int? stackSize;

  /// Asynchronously handler to manage js module.
  final _JsAsyncModuleHandler? moduleHandler;

  /// Handler function to manage js module.
  final _JsHostPromiseRejectionHandler? hostPromiseRejectionHandler;

  /// Quickjs engine runing on isolate thread.
  ///
  /// Pass handlers to implement js-dart interaction and resolving modules. The `methodHandler` is
  /// used in isolate, so **the handler function must be a top-level function or a static method**.
  IsolateQjs({
    this.moduleHandler,
    this.stackSize,
    this.hostPromiseRejectionHandler,
  });

  _ensureEngine() {
    if (_session != null) return;
    final session = _IsolateSession();
    final port = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    var portsClosed = false;
    _session = session;

    void closePorts() {
      if (portsClosed) return;
      portsClosed = true;
      port.close();
      errorPort.close();
      exitPort.close();
    }

    void fail(Object error, [StackTrace? stack]) {
      if (!session.ready.isCompleted) {
        session.ready.completeError(error, stack ?? StackTrace.current);
      }
      if (!session.failure.isCompleted) {
        session.failure.completeError(error, stack ?? StackTrace.current);
      }
      if (identical(_session, session)) _session = null;
      closePorts();
    }

    port.listen((msg) async {
      if (msg is SendPort && !session.ready.isCompleted) {
        session.ready.complete(msg);
        return;
      }
      if (msg is! Map) return;
      switch (msg[#type]) {
        case #hostPromiseRejection:
          try {
            final err = _decodeData(msg[#reason]);
            if (hostPromiseRejectionHandler != null) {
              hostPromiseRejectionHandler!(err);
            } else {
              print('unhandled promise rejection: $err');
            }
          } catch (e) {
            print('host Promise Rejection Handler error: $e');
          }
          break;
        case #module:
          final ptr = Pointer<Pointer>.fromAddress(msg[#ptr]);
          try {
            ptr.value = (await moduleHandler!(msg[#name])).toNativeUtf8();
          } catch (e) {
            ptr.value = Pointer.fromAddress(-1);
          }
          break;
      }
    });
    errorPort.listen((message) {
      if (message is List && message.isNotEmpty) {
        fail(JSError(message.first, message.length > 1 ? message[1] : null));
      } else {
        fail(JSError(message));
      }
    });
    exitPort.listen((_) {
      fail(session.closing ? session.closedError : JSError('isolate exited'));
    });

    Future<void> spawn() async {
      try {
        await Isolate.spawn(
          _runJsIsolate,
          {
            #port: port.sendPort,
            #stackSize: stackSize,
          },
          errorsAreFatal: true,
          onError: errorPort.sendPort,
          onExit: exitPort.sendPort,
        );
      } catch (error, stack) {
        fail(JSError(error, stack), stack);
      }
    }

    unawaited(spawn());
  }

  Future<dynamic> _waitForResponse(
    _IsolateSession session,
    ReceivePort responsePort,
  ) async {
    try {
      return await Future.any<dynamic>([
        responsePort.first,
        session.failure.future,
      ]);
    } finally {
      responsePort.close();
    }
  }

  /// Free Runtime and close isolate thread that can be recreate when evaluate again.
  close() {
    final session = _session;
    _session = null;
    if (session == null) return;
    session.closing = true;
    final ret = session.ready.future.then((sendPort) async {
      final closePort = ReceivePort();
      sendPort.send({
        #type: #close,
        #port: closePort.sendPort,
      });
      late final dynamic result;
      try {
        result = await _waitForResponse(session, closePort);
      } catch (error) {
        if (identical(error, session.closedError)) return true;
        rethrow;
      }
      if (result is Map && result.containsKey(#error))
        throw _decodeData(result[#error]);
      return _decodeData(result);
    });
    return ret;
  }

  /// Evaluate js script.
  Future<dynamic> evaluate(
    String command, {
    String? name,
    int? evalFlags,
  }) async {
    _ensureEngine();
    final session = _session!;
    final sendPort = await session.ready.future;
    final evaluatePort = ReceivePort();
    sendPort.send({
      #type: #evaluate,
      #command: command,
      #name: name,
      #flag: evalFlags,
      #port: evaluatePort.sendPort,
    });
    final result = await _waitForResponse(session, evaluatePort);
    if (result is Map && result.containsKey(#error))
      throw _decodeData(result[#error]);
    return _decodeData(result);
  }
}
