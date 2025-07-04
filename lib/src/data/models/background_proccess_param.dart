import 'package:face_verify/face_verify.dart';

class BackgroundProcessParams {
  final String imagePath;
  final String username;
  final String cameraDescription; // Serialize camera description

  BackgroundProcessParams({
    required this.imagePath,
    required this.username,
    required this.cameraDescription,
  });
}

// Result model untuk background processing
class BackgroundProcessResult {
  final String? croppedImagePath;
  final List<UserModel>? newUsers; // Ganti dengan tipe yang sesuai
  final String? error;

  BackgroundProcessResult({
    this.croppedImagePath,
    this.newUsers,
    this.error,
  });
}
