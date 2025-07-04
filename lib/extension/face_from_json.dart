import 'dart:math';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'rect_to_json.dart' as r;

class FaceJsons {
  static Face fromJson(Map<String, dynamic> json) {
    return Face(
      boundingBox: r.RectJsons.fromJson(json['rect']),
      headEulerAngleX: (json['headEulerAngleX'] as num?)?.toDouble(),
      headEulerAngleY: (json['headEulerAngleY'] as num?)?.toDouble(),
      headEulerAngleZ: (json['headEulerAngleZ'] as num?)?.toDouble(),
      leftEyeOpenProbability:
          (json['leftEyeOpenProbability'] as num?)?.toDouble(),
      rightEyeOpenProbability:
          (json['rightEyeOpenProbability'] as num?)?.toDouble(),
      smilingProbability: (json['smilingProbability'] as num?)?.toDouble(),
      trackingId: json['trackingId'] as int?,
      landmarks: (json['landmarks'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              FaceLandmarkType.values.firstWhere((e) => e.name == key,
                  orElse: () => FaceLandmarkType.noseBase),
              value != null
                  ? FaceLandmark(
                      type: FaceLandmarkType.values
                          .firstWhere((e) => e.name == key),
                      position: Point<int>(value[0], value[1]),
                    )
                  : null,
            ),
          ) ??
          {},
      contours: (json['contours'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              FaceContourType.values.firstWhere((e) => e.name == key,
                  orElse: () => FaceContourType.face),
              value != null
                  ? FaceContour(
                      type: FaceContourType.values
                          .firstWhere((e) => e.name == key),
                      points: (value as List)
                          .map<Point<int>>((p) => Point<int>(p[0], p[1]))
                          .toList(),
                    )
                  : null,
            ),
          ) ??
          {},
    );
  }
}
