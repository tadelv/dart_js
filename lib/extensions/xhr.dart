import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/javascript_runtime.dart';
import 'package:http/http.dart' as http;

/*
 * Based on bits and pieces from different OSS sources
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// ignore: non_constant_identifier_names
var _XHR_DEBUG = false;

setXhrDebug(bool value) => _XHR_DEBUG = value;

const HTTP_GET = "get";
const HTTP_POST = "post";
const HTTP_PATCH = "patch";
const HTTP_DELETE = "delete";
const HTTP_PUT = "put";
const HTTP_HEAD = "head";

enum HttpMethod { put, get, post, delete, patch, head }

String _debugSendNativeCallback() {
  if (_XHR_DEBUG) {
    return """console.log("XMLHttpRequest._send_native_callback");
      console.log("arguments");
      console.log(arguments);
      console.log(responseInfo);
      console.log(responseText);
      console.log(error);""";
  } else
    return "";
}

final String xhrJsCode = """
function XMLHttpRequest() {
  this._send_native = XMLHttpRequestExtension_send_native;
  this._httpMethod = null;
  this._url = null;
  this._requestHeaders = [];
  this._responseHeaders = [];
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  this.responseType = "";
  this.onreadystatechange = null;
  this.onloadstart = null;
  this.onprogress = null;
  this.onabort = null;
  this.onerror = null;
  this.onload = null;
  this.onloadend = null;
  this.ontimeout = null;
  this.readyState = 0;
  this.status = 0;
  this.statusText = "";
  this.withCredentials = null;
};
// readystate enum
XMLHttpRequest.UNSENT = 0;
XMLHttpRequest.OPENED = 1;
XMLHttpRequest.HEADERS = 2;
XMLHttpRequest.LOADING = 3;
XMLHttpRequest.DONE = 4;
XMLHttpRequest.prototype.constructor = XMLHttpRequest;
XMLHttpRequest.prototype.open = function(httpMethod, url) {
  this._httpMethod = httpMethod;
  this._url = url;
  this.readyState = XMLHttpRequest.OPENED;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(OPENED)...");
    this.onreadystatechange();
  }
};
XMLHttpRequest.prototype.send = function(data) {
  this.readyState = XMLHttpRequest.LOADING;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(LOADING)...");
    this.onreadystatechange();
  }
  if (typeof this.onloadstart === "function") {
    //console.log("Calling onloadstart()...");
    this.onloadstart();
  }
  var that = this;
  this._send_native(this._httpMethod, this._url, this._requestHeaders, data || null, function(responseInfo, responseText, error) {
    that._send_native_callback(responseInfo, responseText, error);
  }, this);
};
XMLHttpRequest.prototype.abort = function() {
  this.readyState = XMLHttpRequest.UNSENT;
  // Note: this.onreadystatechange() is not supposed to be called according to the XHR specs
}
// responseInfo: {statusCode, statusText, responseHeaders}
XMLHttpRequest.prototype._send_native_callback = function(responseInfo, responseText, error) {
  ${_debugSendNativeCallback()}
  if (this.readyState === XMLHttpRequest.UNSENT) {
    console.log("XHR native callback ignored because the request has been aborted");
    if (typeof this.onabort === "function") {
      //console.log("Calling onabort()...");
      this.onabort();
    }
    return;
  }
  if (this.readyState != XMLHttpRequest.LOADING) {
    // Request was not expected
    console.log("XHR native callback ignored because the current state is not LOADING");
    return;
  }
  // Response info
  // TODO: responseXML?
  this.responseURL = this._url;
  this.status = responseInfo.statusCode;
  this.statusText = responseInfo.statusText;
  this._responseHeaders = responseInfo.responseHeaders || [];
  this.readyState = XMLHttpRequest.DONE;
  // Response
  this.response = null;
  this.responseText = null;
  this.responseXML = null;
  if (error) {
    this.responseText = error;
  } else {
    this.responseText = responseText;
    //console.log('RESPONSE TEXT: ' + responseText);
    switch (this.responseType) {
      case "":
      case "text":
        this.response = this.responseText;
        break;
      case "arraybuffer":
        error = "XHR arraybuffer response is not supported!";
        break;
      case "document":
        this.response = this.responseText;
        this.responseXML = this.responseText;
        break;
      case "json":
        try {
            this.response = JSON.parse(responseText);
        }
        catch (e) {
            error = "Could not parse JSON response: " + responseText;
        }
        break;
      default:
        error = "Unsupported responseType: " + responseInfo.responseType;
    }
  }
  this.readyState = XMLHttpRequest.DONE;
  if (typeof this.onreadystatechange === "function") {
    //console.log("Calling onreadystatechange(DONE)...");
    this.onreadystatechange();
  }
  if (error === "timeout") {
    // Timeout
    console.warn("Got XHR timeout");
    if (typeof this.ontimeout === "function") {
      //console.log("Calling ontimeout()...");
      this.ontimeout();
    }
  } else if (error) {
    // Error
    console.warn("Got XHR error:", error);
    if (typeof this.onerror === "function") {
      //console.log("Calling onerror()...");
      this.onerror();
    }
  } else {
    // Success
    //console.log("XHR success: response =", this.response);
    if (typeof this.onload === "function") {
      //console.log("Calling onload()...");
      this.onload();
    }
  }
  if (typeof this.onloadend === "function") {
    //console.log("Calling onloadend()...");
    this.onloadend();
  }
};
XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
  this._requestHeaders.push([header, value]);
};
XMLHttpRequest.prototype.getAllResponseHeaders = function() {
  var ret = "";
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    ret += keyValue[0] + ": " + keyValue[1] + "\\r\\n";
  }
  return ret;
};
XMLHttpRequest.prototype.getResponseHeader = function(name) {
  var ret = "";
  for (var i = 0; i < this._responseHeaders.length; i++) {
    var keyValue = this._responseHeaders[i];
    if (keyValue[0] !== name) continue;
    if (ret === "") ret += ", ";
    ret += keyValue[1];
  }
  return ret;
};
// XMLHttpRequest.prototype.overrideMimeType = function() {
//   // TODO
// };
this.XMLHttpRequest = XMLHttpRequest;""";

RegExp regexpHeader = RegExp("^([\\w-])+:(?!\\s*\$).+\$");

class XhrPendingCall {
  int? idRequest;
  String? method;
  String? url;
  Map<String, String> headers;
  String? body;

  XhrPendingCall({
    required this.idRequest,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
}

const XHR_PENDING_CALLS_KEY = "xhrPendingCalls";

http.Client? httpClient;

void xhrSetHttpClient(http.Client? client) {
  httpClient = client;
}

extension JavascriptRuntimeXhrExtension on JavascriptRuntime {
  List<dynamic>? getPendingXhrCalls() {
    ensureRuntimeActive();
    return dartContext[XHR_PENDING_CALLS_KEY];
  }

  bool hasPendingXhrCalls() => getPendingXhrCalls()?.isNotEmpty ?? false;

  void clearXhrPendingCalls() {
    ensureRuntimeActive();
    dartContext[XHR_PENDING_CALLS_KEY] = [];
  }

  JavascriptRuntime enableXhr() {
    ensureRuntimeActive();
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    dartContext[XHR_PENDING_CALLS_KEY] = [];
    Timer? pollingTimer;
    var disposed = false;

    void cleanup() {
      disposed = true;
      pollingTimer?.cancel();
      if (pollingTimer != null) unregisterRuntimeTimer(pollingTimer);
      dartContext.remove(XHR_PENDING_CALLS_KEY);
      if (ownsClient) client.close();
    }

    registerDisposeCallback(cleanup);

    Future<void> process(XhrPendingCall pendingCall) async {
      if (disposed || !isRuntimeActive) return;
      try {
        late http.Response response;
        final uri = Uri.parse(pendingCall.url!);
        switch (HttpMethod.values.firstWhere(
          (method) =>
              method.toString().toLowerCase() ==
              'HttpMethod.${pendingCall.method}'.toLowerCase(),
        )) {
          case HttpMethod.head:
            response = await client.head(uri, headers: pendingCall.headers);
            break;
          case HttpMethod.get:
            response = await client.get(uri, headers: pendingCall.headers);
            break;
          case HttpMethod.post:
            response = await client.post(
              uri,
              body: pendingCall.body is String
                  ? pendingCall.body
                  : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.put:
            response = await client.put(
              uri,
              body: pendingCall.body is String
                  ? pendingCall.body
                  : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.patch:
            response = await client.patch(
              uri,
              body: pendingCall.body is String
                  ? pendingCall.body
                  : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.delete:
            response = await client.delete(uri, headers: pendingCall.headers);
            break;
        }
        if (disposed || !isRuntimeActive) return;
        var responseText = utf8.decode(response.bodyBytes);
        try {
          responseText = jsonEncode(json.decode(responseText));
        } on Object {}
        final xhrResult = XmlHttpRequestResponse(
          responseText: responseText,
          responseInfo: XhtmlHttpResponseInfo(
            statusCode: response.statusCode,
            statusText: response.reasonPhrase ?? '',
          ),
        );
        final responseInfo = jsonEncode(xhrResult.responseInfo);
        final callback = '''
(function () {
  const request = globalThis.xhrRequests[${pendingCall.idRequest}];
  delete globalThis.xhrRequests[${pendingCall.idRequest}];
  if (request) {
    request.callback(
      ${jsonEncode(jsonDecode(responseInfo))},
      ${jsonEncode(responseText)},
      ${jsonEncode(xhrResult.error)}
    );
  }
})();''';
        evaluate(callback);
      } on Object catch (error) {
        if (isRuntimeActive) {
          final callback = '''
(function () {
  const request = globalThis.xhrRequests[${pendingCall.idRequest}];
  delete globalThis.xhrRequests[${pendingCall.idRequest}];
  if (request) {
    request.callback(
      {statusCode: 0, statusText: "", responseHeaders: []},
      null,
      ${jsonEncode(error.toString())}
    );
  }
})();''';
          evaluate(callback);
          if (_XHR_DEBUG) {
            print('XHR request failed: $error');
          }
        }
      }
    }

    pollingTimer = Timer.periodic(Duration(milliseconds: 40), (timer) {
      if (disposed || !isRuntimeActive) return;
      final pendingCalls = List<dynamic>.from(getPendingXhrCalls() ?? const []);
      clearXhrPendingCalls();
      for (final element in pendingCalls) {
        unawaited(process(element as XhrPendingCall));
      }
    });
    registerRuntimeTimer(pollingTimer);

    final evalXhrSendNative = this.evaluate("""
    var xhrRequests = {};
    var idRequest = -1;
    function XMLHttpRequestExtension_send_native() {
      idRequest += 1;
      var cb = arguments[4];
      var context = arguments[5];
      xhrRequests[idRequest] = {
        callback: function(responseInfo, responseText, error) {
          cb(responseInfo, responseText, error);
        }
      };
      var args = [];
      args[0] = arguments[0];
      args[1] = arguments[1];
      args[2] = arguments[2];
      args[3] = arguments[3];
      args[4] = idRequest;
      sendMessage('SendNative', JSON.stringify(args));
    }
    """);

    final evalXhrResult = this.evaluate(xhrJsCode);
    setLocalContextValue('enableXhr', evalXhrResult.rawResult);
    setLocalContextValue('xhrSendNative', evalXhrSendNative.rawResult);
    if (_XHR_DEBUG) print('RESULT evalXhrResult: $evalXhrResult');

    this.onMessageVoid('SendNative', (arguments) {
      final method = arguments[0] as String?;
      final url = arguments[1] as String?;
      final headersList = arguments[2] as List<dynamic>;
      final body = arguments[3] as String?;
      final idRequest = arguments[4] as int?;
      final headers = <String, String>{};
      for (final header in headersList) {
        headers[header[0] as String] = header[1] as String;
      }
      (dartContext[XHR_PENDING_CALLS_KEY] as List<dynamic>).add(
        XhrPendingCall(
          idRequest: idRequest,
          method: method,
          url: url,
          headers: headers,
          body: body,
        ),
      );
    });
    return this;
  }
}

class XhtmlHttpResponseInfo {
  final int? statusCode;
  final String? statusText;
  final List<List<String>> responseHeaders = [];

  XhtmlHttpResponseInfo({
    this.statusCode,
    this.statusText,
  });

  void addResponseHeaders(String name, String value) {
    responseHeaders.add([name, value]);
  }

  Map<String, Object?> toJson() {
    return {
      "statusCode": statusCode,
      "statusText": statusText,
      "responseHeaders": jsonEncode(responseHeaders)
    };
  }
}

class XmlHttpRequestResponse {
  final String? responseText;
  final String? error; // should be timeout in case of timeout
  final XhtmlHttpResponseInfo? responseInfo;

  XmlHttpRequestResponse({this.responseText, this.responseInfo, this.error});

  Map<String, Object?> toJson() {
    return {
      'responseText': responseText,
      'responseInfo': responseInfo!.toJson(),
      'error': error
    };
  }
}
