import 'dart:convert';
import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Chuẩn hóa passphrase: **Unicode NFKC** rồi UTF-8.
///
/// Bắt buộc, vì tiếng Việt có chữ tổ hợp (ví dụ `ệ` có thể là một ký tự dựng sẵn hoặc `e` + hai dấu rời),
/// và bàn phím/hệ điều hành khác nhau cho ra dạng khác nhau. Không chuẩn hóa thì cùng một passphrase
/// có thể mở được trên máy này mà không mở được trên máy kia.
Uint8List normalizePassphrase(String passphrase) =>
    Uint8List.fromList(utf8.encode(unorm.nfkc(passphrase)));
