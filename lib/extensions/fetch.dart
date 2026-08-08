import 'package:flutter_js/javascript_runtime.dart';
import 'package:flutter_js/extensions/xhr.dart';

const fetchJsCode = r'''
globalThis.fetch = function fetch(url, options) {
  options = options || {};
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    const keys = [];
    const all = [];
    const headers = {};
    const response = () => ({
      ok: (request.status / 100 | 0) == 2,
      statusText: request.statusText,
      status: request.status,
      url: request.responseURL,
      text: () => Promise.resolve(request.responseText),
      json: () => {
        try {
          return Promise.resolve(JSON.parse(request.responseText));
        } catch (_) {
          return Promise.resolve(request.responseText);
        }
      },
      blob: () => Promise.resolve(new Blob([request.response])),
      clone: response,
      headers: {
        keys: () => keys,
        entries: () => all,
        get: name => headers[name.toLowerCase()],
        has: name => name.toLowerCase() in headers
      }
    });

    request.open(options.method || 'get', url, true);
    request.onload = () => {
      request.getAllResponseHeaders().replace(
        /^(.*?):[^\S\n]*([\s\S]*?)$/gm,
        (_, key, value) => {
          key = key.toLowerCase();
          keys.push(key);
          all.push([key, value]);
          headers[key] = headers[key] ? `${headers[key]},${value}` : value;
        }
      );
      resolve(response());
    };
    request.onerror = reject;
    request.withCredentials = options.credentials == 'include';

    if (options.headers) {
      if (options.headers.constructor.name == 'Object') {
        for (const name in options.headers) {
          request.setRequestHeader(name, options.headers[name]);
        }
      } else {
        for (const header of options.headers) {
          request.setRequestHeader(header[0], header[1]);
        }
      }
    }

    request.send(options.body || null);
  });
};
''';

var _fetchDebug = false;

setFetchDebug(bool value) => _fetchDebug = value;

extension JavascriptRuntimeFetchExtension on JavascriptRuntime {
  JavascriptRuntime enableFetch() {
    ensureRuntimeActive();
    if (evaluate('typeof fetch').stringResult == 'function') return this;
    enableXhr();
    final result = evaluate(fetchJsCode);
    if (result.isError) throw StateError(result.stringResult);
    return this;
  }
}

void debug(String message) {
  if (_fetchDebug) {
    print('JavascriptRuntimeFetchExtension: $message');
  }
}
