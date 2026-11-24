/// Các lỗi của lõi VanKey. Thông điệp **không bao giờ** chứa bí mật (khóa, passphrase, nội dung kho).
sealed class VaultException implements Exception {
  const VaultException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Sai khóa/passphrase, hoặc dữ liệu đã bị sửa (AEAD không xác thực được).
final class AuthenticationFailedException extends VaultException {
  const AuthenticationFailedException([super.message = 'Xác thực thất bại: sai khóa hoặc dữ liệu đã bị sửa']);
}

/// File kho hỏng, cắt cụt, hoặc sai định dạng.
final class CorruptVaultException extends VaultException {
  const CorruptVaultException(super.message);
}

/// File kho có version mới hơn bản app này hiểu được.
final class UnsupportedVersionException extends VaultException {
  const UnsupportedVersionException(super.message);
}

/// Tham số KDF nằm ngoài khoảng cho phép (chống bị hạ tham số hoặc file độc làm cạn bộ nhớ).
final class WeakKdfParametersException extends VaultException {
  const WeakKdfParametersException(super.message);
}

/// File nhập khẩu đã được mã hóa bởi chính ứng dụng nguồn (cần xuất lại bản không mã hóa từ ứng dụng đó).
final class EncryptedImportException extends VaultException {
  const EncryptedImportException([super.message = 'File sao lưu này đã được mã hóa bởi ứng dụng nguồn']);
}

/// Đầu vào của người gọi không hợp lệ (độ dài khóa sai, recovery key sai định dạng...).
final class InvalidInputException extends VaultException {
  const InvalidInputException(super.message);
}
