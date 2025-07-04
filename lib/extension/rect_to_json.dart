import 'dart:ui';

class RectJsons {
  static Rect fromJson(Map<String, dynamic> json) => Rect.fromLTRB(
        json['left'].toDouble(),
        json['top'].toDouble(),
        json['right'].toDouble(),
        json['bottom'].toDouble(),
      );

  static Map<String, dynamic> toJson(Rect rect) => {
        'left': rect.left,
        'top': rect.top,
        'right': rect.right,
        'bottom': rect.bottom,
      };
}
