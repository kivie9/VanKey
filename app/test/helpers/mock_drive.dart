import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Một file trong Drive giả.
class MockDriveFile {
  MockDriveFile(this.id, this.name, this.bytes, this.created);
  final String id;
  final String name;
  Uint8List bytes;
  final int created;
  bool trashed = false;
  String get md5Hex => md5.convert(bytes).toString();
}

/// Máy chủ Google Drive v3 giả (chỉ những gì `DriveSync` dùng): liệt kê, tải, tạo đa phần, ghi đè nội dung.
/// Chỉ nhận đúng một access token ([validToken]); token khác bị 401.
class MockDrive {
  MockDrive._(this._server);

  final HttpServer _server;
  final files = <String, MockDriveFile>{};
  String validToken = 'good';
  int requests = 0;
  int _seq = 0;

  /// Lỗi đưa vào lần lượt cho các yêu cầu kế tiếp: (mã trạng thái, lý do Google).
  final injected = <(int, String)>[];

  /// Chạy ngay trước khi áp dụng một lần ghi nội dung (để giả lập máy khác ghi chen vào khoảng hở).
  void Function(MockDriveFile file)? beforePatch;

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<MockDrive> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final d = MockDrive._(server);
    unawaited(server.forEach(d._handle));
    return d;
  }

  Future<void> stop() => _server.close(force: true);

  MockDriveFile put(String name, Uint8List bytes) {
    final f = MockDriveFile('file${++_seq}', name, bytes, _seq);
    files[f.id] = f;
    return f;
  }

  void _json(HttpResponse res, int status, Object body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  void _error(HttpResponse res, int status, String reason) =>
      _json(res, status, {'error': {'code': status, 'message': 'giả lập $status $reason', 'errors': [{'reason': reason}]}});

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      requests++;
      final body = await req.fold<BytesBuilder>(BytesBuilder(copy: false), (b, d) => b..add(d));
      final bytes = body.takeBytes();
      if (req.headers.value('authorization') != 'Bearer $validToken') {
        _error(res, 401, 'authError');
        return;
      }
      if (injected.isNotEmpty) {
        final (status, reason) = injected.removeAt(0);
        _error(res, status, reason);
        return;
      }
      final path = req.uri.path;
      final q = req.uri.queryParameters;

      if (req.method == 'GET' && path == '/drive/v3/files') {
        final m = RegExp(r"name = '(.*?)'").firstMatch(q['q'] ?? '');
        final name = m?.group(1);
        final list = [
          for (final f in files.values)
            if (!f.trashed && (name == null || f.name == name))
              {'id': f.id, 'md5Checksum': f.md5Hex, 'createdTime': '2026-01-01T00:00:${f.created.toString().padLeft(2, '0')}Z'}
        ];
        _json(res, 200, {'files': list});
        return;
      }
      final one = RegExp(r'^/drive/v3/files/([^/]+)$').firstMatch(path);
      if (req.method == 'GET' && one != null) {
        final f = files[one.group(1)];
        if (f == null) {
          _error(res, 404, 'notFound');
          return;
        }
        res.statusCode = 200;
        res.add(f.bytes);
        return;
      }
      if (req.method == 'POST' && path == '/upload/drive/v3/files') {
        final ct = req.headers.contentType;
        final boundary = ct?.parameters['boundary'];
        if (boundary == null) {
          _error(res, 400, 'badRequest');
          return;
        }
        final (meta, media) = _parseMultipart(bytes, boundary);
        final f = put('${meta['name']}', media);
        _json(res, 200, {'id': f.id});
        return;
      }
      final up = RegExp(r'^/upload/drive/v3/files/([^/]+)$').firstMatch(path);
      if (req.method == 'PATCH' && up != null) {
        final f = files[up.group(1)];
        if (f == null) {
          _error(res, 404, 'notFound');
          return;
        }
        beforePatch?.call(f);
        f.bytes = Uint8List.fromList(bytes);
        _json(res, 200, {'id': f.id});
        return;
      }
      _error(res, 404, 'notFound');
    } finally {
      await res.close();
    }
  }

  /// Tách thân multipart/related thành (metadata JSON, nội dung nhị phân).
  (Map<String, dynamic>, Uint8List) _parseMultipart(Uint8List data, String boundary) {
    final delim = latin1.encode('--$boundary');
    final starts = <int>[];
    for (var i = 0; i <= data.length - delim.length; i++) {
      var ok = true;
      for (var j = 0; j < delim.length; j++) {
        if (data[i + j] != delim[j]) {
          ok = false;
          break;
        }
      }
      if (ok) starts.add(i);
    }
    Uint8List part(int n) {
      final from = starts[n] + delim.length;
      final to = starts[n + 1];
      final seg = data.sublist(from, to);
      // bỏ "\r\n" đầu, tiêu đề, dòng trống; bỏ "\r\n" cuối
      var k = 0;
      for (var i = 0; i < seg.length - 3; i++) {
        if (seg[i] == 13 && seg[i + 1] == 10 && seg[i + 2] == 13 && seg[i + 3] == 10) {
          k = i + 4;
          break;
        }
      }
      return Uint8List.fromList(seg.sublist(k, seg.length - 2));
    }

    final meta = jsonDecode(utf8.decode(part(0))) as Map<String, dynamic>;
    return (meta, part(1));
  }
}
