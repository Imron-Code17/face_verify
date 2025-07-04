import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'rect_to_json.dart' as r;

extension FaceJson on Face {
  Map<String, dynamic> toJson() => {
        'rect': r.RectJson.toJson(boundingBox),
        'headEulerAngleX': headEulerAngleX,
        'headEulerAngleY': headEulerAngleY,
        'headEulerAngleZ': headEulerAngleZ,
        'leftEyeOpenProbability': leftEyeOpenProbability,
        'rightEyeOpenProbability': rightEyeOpenProbability,
        'smilingProbability': smilingProbability,
        'trackingId': trackingId,
        'landmarks': landmarks.map((key, value) => MapEntry(key.name,
            value == null ? null : [value.position.x, value.position.y])),
        'contours': contours.map((key, value) =>
            MapEntry(key.name, value?.points.map((p) => [p.x, p.y]).toList())),
      };
}
