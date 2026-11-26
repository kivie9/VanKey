/// Lọc, sắp xếp và gom nhóm mục. Dùng chung cho bố cục điện thoại và bố cục máy tính.
library;

import '../core/vault/models.dart';
import '../core/vault/services.dart';
import 'i18n.dart';
import 'labels.dart';
import 'vault_controller.dart';

/// Mục có mã 2FA: tab 2FA chỉ hiện các mục này.
bool hasCode(Item i) => i.totp != null && i.totp!.secret.isNotEmpty;

/// Tab Kho không hiện mục loại "Mã 2FA" (đã có tab riêng). Mục loại 2FA hỏng, không có khóa, vẫn hiện ở Kho để không bị ẩn mất.
bool inVault(Item i) => i.type != ItemType.totp || !hasCode(i);

/// Hai dòng chữ của một tài khoản nằm trong nhóm xếp chồng. Tên mục trùng tên dịch vụ thì lặp lại vô ích:
/// đưa tên đăng nhập lên dòng chính. Tên tự đặt ("FB bán hàng") thì giữ ở dòng chính.
(String, String) stackedLabels(Item item, String serviceName) {
  final account = item.subtitle;
  final repeated = normalizeName(item.title) == normalizeName(serviceName) && account.isNotEmpty;
  final main = repeated ? account : item.title;
  return (main, [if (!repeated && account.isNotEmpty) account, if (item.group.isNotEmpty) item.group].join(' · '));
}

void sortItems(List<Item> items, SortBy by) => items.sort((a, b) => switch (by) {
      SortBy.name => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      SortBy.updated => b.updatedAt.compareTo(a.updatedAt),
      SortBy.created => b.createdAt.compareTo(a.createdAt),
    });

/// Các nhóm theo thứ tự hiển thị (nhóm "Chưa gắn thẻ" nằm cuối). Không gom thì trả về một nhóm tên rỗng.
List<(String, List<Item>)> groupItems(List<Item> items, GroupBy by) {
  final groups = <String, List<Item>>{};
  for (final i in items) {
    final key = switch (by) {
      GroupBy.group => i.group.isEmpty ? tr('Chưa gắn thẻ') : i.group,
      GroupBy.type => L.type(i.type),
      GroupBy.none => '',
    };
    groups.putIfAbsent(key, () => []).add(i);
  }
  final untagged = tr('Chưa gắn thẻ');
  final names = groups.keys.toList()..sort((a, b) => a == untagged ? 1 : (b == untagged ? -1 : a.compareTo(b)));
  return [for (final n in names) (n, groups[n]!)];
}
