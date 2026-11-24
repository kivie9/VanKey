import '../errors.dart';

/// Đồng hồ lai (Hybrid Logical Clock): `<mili-giây>:<bộ đếm>:<id thiết bị>`.
///
/// So sánh theo `(ms, counter, node)`, một thứ tự **toàn phần và xác định**, nên mọi thiết bị
/// đều chọn cùng một bản thắng khi gộp, bất kể lệch giờ giữa các máy.
final class Hlc implements Comparable<Hlc> {
  const Hlc(this.ms, this.counter, this.node);

  /// Nhỏ hơn mọi HLC thật (dùng cho giá trị thiếu/hỏng).
  static const zero = Hlc(0, 0, '');

  static final _nodePattern = RegExp(r'^[A-Za-z0-9_\-]+$');

  final int ms;
  final int counter;
  final String node;

  static bool isValidNode(String node) => _nodePattern.hasMatch(node);

  /// Đọc từ chuỗi. Chuỗi hỏng → [Hlc.zero] (coi như cổ nhất) thay vì ném lỗi, để file hỏng nhẹ vẫn gộp được.
  factory Hlc.parse(String? s) {
    if (s == null) return zero;
    final a = s.indexOf(':');
    final b = a < 0 ? -1 : s.indexOf(':', a + 1);
    if (a < 0 || b < 0) return zero;
    final ms = int.tryParse(s.substring(0, a));
    final counter = int.tryParse(s.substring(a + 1, b));
    final node = s.substring(b + 1);
    if (ms == null || counter == null || ms < 0 || counter < 0 || !isValidNode(node)) return zero;
    return Hlc(ms, counter, node);
  }

  @override
  int compareTo(Hlc other) {
    if (ms != other.ms) return ms.compareTo(other.ms);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  bool operator >(Hlc o) => compareTo(o) > 0;
  bool operator <(Hlc o) => compareTo(o) < 0;

  @override
  bool operator ==(Object other) => other is Hlc && other.ms == ms && other.counter == counter && other.node == node;

  @override
  int get hashCode => Object.hash(ms, counter, node);

  @override
  String toString() => '$ms:$counter:$node';
}

/// Bộ sinh HLC của **một thiết bị**.
final class HlcClock {
  HlcClock({required this.node, int Function()? nowMs, Hlc? last})
      : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _last = last ?? Hlc.zero {
    if (!Hlc.isValidNode(node)) {
      throw const InvalidInputException('id thiết bị chỉ gồm chữ, số, gạch ngang và gạch dưới');
    }
  }

  final String node;
  final int Function() _nowMs;
  Hlc _last;

  Hlc get last => _last;

  /// HLC mới, **luôn lớn hơn** mọi HLC đã sinh hoặc đã thấy trước đó.
  Hlc next() {
    final now = _nowMs();
    if (now > _last.ms) {
      _last = Hlc(now, 0, node);
    } else {
      _last = Hlc(_last.ms, _last.counter + 1, node);
    }
    return _last;
  }

  /// Ghi nhận một HLC từ thiết bị khác để lần [next] sau luôn lớn hơn nó.
  void observe(Hlc remote) {
    if (remote > _last) _last = Hlc(remote.ms, remote.counter, node);
  }
}
