// lib/core/models/qr_result.dart
class QrResult {
  final String value;
  final bool found;
  final Map<String, dynamic>? data;
  final int x;
  final int y;
  final int w;
  final int h;

  QrResult({
    required this.value,
    required this.found,
    this.data,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  Map<String, dynamic> toJson() => {
        'value': value,
        'found': found,
        'data': data,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
      };

  factory QrResult.fromJson(Map<String, dynamic> json) {
    return QrResult(
      value: json['value'] as String? ?? '',
      found: json['found'] as bool? ?? false,
      data: json['data'] as Map<String, dynamic>?,
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      w: json['w'] as int? ?? 0,
      h: json['h'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    return 'QrResult(value: "$value", found: $found, pos: [$x,$y,$w,$h])';
  }
}