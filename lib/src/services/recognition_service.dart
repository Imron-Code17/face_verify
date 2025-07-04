// ignore_for_file: unnecessary_null_comparison, curly_braces_in_flow_control_structures

import 'package:camera/camera.dart';
import 'package:face_verify/src/data/models/recognition_model.dart';
import 'package:face_verify/src/data/models/user_model.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Enhanced [RecognitionService] with improved accuracy and performance
class EnhancedRecognitionService {
  /// Strict threshold for high accuracy (lower = more strict)
  final double threshold;

  /// Confidence threshold for face quality assessment
  final double qualityThreshold;

  /// Maximum number of faces to process (performance optimization)
  final int maxFacesToProcess;

  /// Minimum face size ratio (relative to image size)
  final double minFaceSizeRatio;

  final int sensorOrientation;
  final List<UserModel> users;
  int rotationCompensation;

  bool isRecognized = false;
  RecognitionModel recognitionModel = RecognitionModel();
  UserModel? recognizedUser;

  /// Enhanced face recognition with multiple validation layers
  EnhancedRecognitionService({
    required this.rotationCompensation,
    required this.sensorOrientation,
    required this.users,
    this.threshold = 1.0,
    this.qualityThreshold = 0.6,
    this.maxFacesToProcess = 3,
    this.minFaceSizeRatio = 0.04,
  }) {
    log('Enhanced Recognition Service initialized:');
    log('  - Threshold: $threshold');
    log('  - Quality Threshold: $qualityThreshold');
    log('  - Max Faces: $maxFacesToProcess');
    log('  - Min Face Size: ${minFaceSizeRatio * 100}%');
  }

  bool _isMatchWithAdaptiveThreshold(double distance, bool isFromCamera) {
    double adaptiveThreshold = threshold;

    // ADAPTIVE THRESHOLD: Camera images biasanya lebih noisy
    if (isFromCamera) {
      adaptiveThreshold = threshold * 1.3; // 30% lebih toleran untuk camera
      log('📸 Camera image detected, adaptive threshold: $adaptiveThreshold');
    }

    bool isMatch = distance >= 0 && distance < adaptiveThreshold;
    log('🎯 Adaptive match: $distance < $adaptiveThreshold = $isMatch');

    return isMatch;
  }

  /// Perform enhanced face recognition with multiple validation layers
  bool performFaceRecognition({
    CameraImage? cameraImageFrame,
    img.Image? localImageFrame,
    required List<Face> faces,
    required Set<UserModel> recognitions,
  }) {
    recognitions.clear();
    isRecognized = false;
    recognizedUser = null;

    if (users.isEmpty) {
      log('❌ No registered users available');
      return false;
    }

    // Process image
    img.Image? processedImage = _processInputImage(
      cameraImageFrame: cameraImageFrame,
      localImageFrame: localImageFrame,
    );

    if (processedImage == null) {
      log('❌ Failed to process input image');
      return false;
    }

    // Filter and validate faces
    List<Face> validFaces = _filterValidFaces(faces, processedImage);

    if (validFaces.isEmpty) {
      log('❌ No valid faces found for recognition');
      return false;
    }

    log('🔍 Processing ${validFaces.length} valid faces');

    // Process each valid face
    bool anyFaceRecognized = false;
    List<RecognitionResult> results = [];

    for (Face face in validFaces) {
      RecognitionResult? result = _processSingleFace(
        face: face,
        image: processedImage,
        isFromCamera: cameraImageFrame != null,
      );

      if (result != null) {
        results.add(result);

        if (result.isMatch) {
          recognitions.add(result.user);
          anyFaceRecognized = true;
          log('✅ Face recognized: ${result.user.name} (confidence: ${result.confidence.toStringAsFixed(3)})');
        }
      }
    }

    // Apply additional validation for multiple faces
    if (results.length > 1) {
      anyFaceRecognized = _validateMultipleFaces(results, recognitions);
    }

    isRecognized = anyFaceRecognized;

    if (anyFaceRecognized) {
      log('🎉 Recognition completed: ${recognitions.length} faces recognized');
    } else {
      log('❌ No faces recognized after validation');
    }

    return anyFaceRecognized;
  }

  /// Process input image with optimization
  img.Image? _processInputImage({
    CameraImage? cameraImageFrame,
    img.Image? localImageFrame,
  }) {
    img.Image? image;

    if (cameraImageFrame != null) {
      image = Platform.isIOS
          ? _convertBGRA8888ToImage(cameraImageFrame)
          : _convertNV21(cameraImageFrame);

      if (image == null) return null;

      // Apply rotation compensation
      if (Platform.isIOS) {
        image = img.copyRotate(image, angle: sensorOrientation);
      } else if (Platform.isAndroid) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
        image = img.copyRotate(image, angle: rotationCompensation);
      }
    } else if (localImageFrame != null) {
      image = localImageFrame;
    }

    return image;
  }

  /// Filter faces based on quality and size criteria
  List<Face> _filterValidFaces(List<Face> faces, img.Image image) {
    List<Face> validFaces = [];
    double minFaceSize = math.min(image.width, image.height) * minFaceSizeRatio;

    for (Face face in faces) {
      // Size validation
      if (face.boundingBox.width < minFaceSize ||
          face.boundingBox.height < minFaceSize) {
        log('⚠️ Face too small: ${face.boundingBox.width}x${face.boundingBox.height}');
        continue;
      }

      // PERBAIKAN: Validasi bounding box yang lebih fleksibel
      if (!_isValidBoundingBox(face.boundingBox, image)) {
        log('⚠️ Invalid bounding box: ${face.boundingBox}');
        continue;
      }

      // Quality validation
      double faceQuality = _calculateFaceQuality(face);
      if (faceQuality < qualityThreshold) {
        log('⚠️ Face quality too low: ${faceQuality.toStringAsFixed(3)}');
        continue;
      }

      validFaces.add(face);
      log('✅ Valid face: ${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}, quality: ${faceQuality.toStringAsFixed(3)}');
    }

    // Sort by face size (largest first) and limit processing
    validFaces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));

    return validFaces.take(maxFacesToProcess).toList();
  }

  /// Calculate face quality score based on various factors
  double _calculateFaceQuality(Face face) {
    double quality = 1.0;

    // Head pose validation (penalize extreme angles)
    if (face.headEulerAngleY != null) {
      double yawAngle = face.headEulerAngleY!.abs();
      if (yawAngle > 30) {
        quality -= 0.3;
      } else if (yawAngle > 15) quality -= 0.1;
    }

    if (face.headEulerAngleZ != null) {
      double rollAngle = face.headEulerAngleZ!.abs();
      if (rollAngle > 30) {
        quality -= 0.3;
      } else if (rollAngle > 15) quality -= 0.1;
    }

    // Smile probability (neutral faces work better for recognition)
    if (face.smilingProbability != null) {
      double smileProbability = face.smilingProbability!;
      if (smileProbability > 0.8) quality -= 0.1; // Very high smile
    }

    // Eye open probability
    if (face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null) {
      double leftEyeOpen = face.leftEyeOpenProbability!;
      double rightEyeOpen = face.rightEyeOpenProbability!;

      if (leftEyeOpen < 0.5 || rightEyeOpen < 0.5) {
        quality -= 0.4; // Eyes closed significantly hurts recognition
      }
    }

    return math.max(0.0, quality);
  }

  /// PERBAIKAN: Check if bounding box is valid (dengan toleransi)
  bool _isValidBoundingBox(Rect boundingBox, img.Image image) {
    // Cek apakah bounding box memiliki ukuran yang valid
    if (boundingBox.width <= 0 || boundingBox.height <= 0) {
      log('❌ Invalid dimensions: ${boundingBox.width}x${boundingBox.height}');
      return false;
    }

    // Hitung area overlap dengan image bounds
    double left = math.max(0, boundingBox.left);
    double top = math.max(0, boundingBox.top);
    double right = math.min(image.width.toDouble(), boundingBox.right);
    double bottom = math.min(image.height.toDouble(), boundingBox.bottom);

    // Cek apakah masih ada area yang valid setelah clamping
    if (right <= left || bottom <= top) {
      log('❌ No valid area after clamping');
      return false;
    }

    // Hitung persentase area yang masih valid
    double validWidth = right - left;
    double validHeight = bottom - top;
    double validArea = validWidth * validHeight;
    double originalArea = boundingBox.width * boundingBox.height;
    double overlapRatio = validArea / originalArea;

    // Minimal 70% dari bounding box harus berada dalam image bounds
    bool isValid = overlapRatio >= 0.7;

    log('📊 BoundingBox validation:');
    log('   Original: ${boundingBox.left.toInt()}, ${boundingBox.top.toInt()}, ${boundingBox.right.toInt()}, ${boundingBox.bottom.toInt()}');
    log('   Clamped: ${left.toInt()}, ${top.toInt()}, ${right.toInt()}, ${bottom.toInt()}');
    log('   Overlap ratio: ${(overlapRatio * 100).toStringAsFixed(1)}%');
    log('   Valid: $isValid');

    return isValid;
  }

  /// Process a single face for recognition
  RecognitionResult? _processSingleFace({
    required Face face,
    required img.Image image,
    bool isFromCamera = false,
  }) {
    try {
      // Crop face
      img.Image? croppedFace = _cropFaceEnhanced(
        image: image,
        face: face,
      );

      if (croppedFace == null) {
        log('❌ Failed to crop face');
        return null;
      }

      // Enhanced preprocessing berdasarkan source
      croppedFace = _preprocessFace(croppedFace, isFromCamera);

      // Perform recognition
      recognizedUser = recognitionModel.recognize(
        users: users,
        croppedFace: croppedFace,
        location: face.boundingBox,
        face: face,
      );

      if (recognizedUser == null) {
        log('❌ Recognition model returned null');
        return null;
      }

      double distance = recognizedUser!.distance;
      double confidence = _calculateConfidence(distance);

      log('🔍 Recognition result: ${recognizedUser!.name}');
      log('   Distance: ${distance.toStringAsFixed(4)}');
      log('   Confidence: ${confidence.toStringAsFixed(4)}');
      log('   Threshold: $threshold');
      log('   Source: ${isFromCamera ? "Camera" : "Gallery"}');

      // ADAPTIVE MATCHING
      bool isMatch = _isMatchWithAdaptiveThreshold(distance, isFromCamera);

      String matchQuality = _getMatchQuality(distance);
      log('   Match Quality: $matchQuality');
      log('   Is Match: $isMatch');

      return RecognitionResult(
        user: recognizedUser!,
        distance: distance,
        confidence: confidence,
        isMatch: isMatch,
        faceQuality: _calculateFaceQuality(face),
      );
    } catch (e) {
      log('❌ Error processing face: $e');
      return null;
    }
  }

  /// Helper: Interpretasi kualitas match untuk FaceNet
  String _getMatchQuality(double distance) {
    if (distance < 0.4) return "Excellent Match";
    if (distance < 0.6) return "Very Good Match";
    if (distance < 0.8) return "Good Match";
    if (distance < 1.0) return "Fair Match";
    if (distance < 1.2) return "Poor Match";
    return "Very Poor Match";
  }

  /// PERBAIKAN: Enhanced face cropping dengan safe clamping
  img.Image? _cropFaceEnhanced({
    required img.Image image,
    required Face face,
  }) {
    try {
      Rect boundingBox = face.boundingBox;

      // Apply intelligent padding based on face landmarks
      double paddingFactor = 0.2; // 20% padding

      // Adjust padding based on face angle
      if (face.headEulerAngleY != null) {
        double yawAngle = face.headEulerAngleY!.abs();
        if (yawAngle > 20) {
          paddingFactor += 0.1; // More padding for angled faces
        }
      }

      double padding =
          math.min(boundingBox.width, boundingBox.height) * paddingFactor;

      // SAFE CLAMPING: Pastikan koordinat selalu dalam bounds
      int left = (boundingBox.left - padding).clamp(0, image.width - 1).toInt();
      int top = (boundingBox.top - padding).clamp(0, image.height - 1).toInt();
      int right =
          (boundingBox.right + padding).clamp(left + 1, image.width).toInt();
      int bottom =
          (boundingBox.bottom + padding).clamp(top + 1, image.height).toInt();

      int width = right - left;
      int height = bottom - top;

      // Validasi final
      if (width <= 0 || height <= 0) {
        log('❌ Invalid crop dimensions after clamping: ${width}x$height');
        return null;
      }

      // Minimum size check
      if (width < 32 || height < 32) {
        log('❌ Cropped face too small: ${width}x$height');
        return null;
      }

      log('✅ Cropping face: x=$left, y=$top, w=$width, h=$height');

      return img.copyCrop(
        image,
        x: left,
        y: top,
        width: width,
        height: height,
      );
    } catch (e) {
      log('❌ Error cropping face: $e');
      return null;
    }
  }

  /// Preprocess face for better recognition
  img.Image _preprocessFace(img.Image face, bool isFromCamera) {
    face = img.copyResize(
      face,
      width: 160,
      height: 160,
      interpolation: img.Interpolation.cubic,
    );

    if (isFromCamera) {
      // EXTRA PROCESSING untuk camera images

      // 1. Noise reduction lebih agresif
      face = img.gaussianBlur(face, radius: 1);

      // 2. Contrast enhancement
      face = img.adjustColor(
        face,
        contrast: 1.15, // Lebih tinggi dari gallery
        brightness: 1.05,
        gamma: 0.95,
      );

      // 3. Histogram equalization
      face = img.normalize(face, min: 0, max: 255);

      log('📸 Applied camera-specific preprocessing');
    } else {
      // Standard processing untuk gallery images
      face = img.adjustColor(
        face,
        contrast: 1.05,
        brightness: 1.02,
        gamma: 0.98,
      );
      face = img.gaussianBlur(face, radius: 1);
    }

    return face;
  }

  /// Calculate confidence score from distance
  double _calculateConfidence(double distance) {
    if (distance < 0) return 0.0;

    // FaceNet typical distance ranges:
    // 0.0 - 0.6: Same person (very high confidence)
    // 0.6 - 1.0: Likely same person (medium confidence)
    // 1.0 - 1.4: Possibly same person (low confidence)
    // 1.4+: Different person (very low confidence)

    double maxDistance = 1.4; // Typical FaceNet max useful distance
    double confidence = math.max(0.0, 1.0 - (distance / maxDistance));

    // Alternative: More aggressive confidence calculation
    // double confidence = math.max(0.0, (1.2 - distance) / 1.2);

    return confidence;
  }

  /// Validate multiple faces to prevent false positives
  bool _validateMultipleFaces(
      List<RecognitionResult> results, Set<UserModel> recognitions) {
    // Remove duplicates and keep only highest confidence matches
    Map<String, RecognitionResult> bestMatches = {};

    for (RecognitionResult result in results) {
      if (result.isMatch) {
        String userId = result.user.id.toString();
        if (!bestMatches.containsKey(userId) ||
            result.confidence > bestMatches[userId]!.confidence) {
          bestMatches[userId] = result;
        }
      }
    }

    // Clear and add validated recognitions
    recognitions.clear();
    for (RecognitionResult result in bestMatches.values) {
      recognitions.add(result.user);
    }

    return recognitions.isNotEmpty;
  }

  // Camera image conversion methods (unchanged)
  img.Image _convertBGRA8888ToImage(CameraImage cameraImage) {
    final plane = cameraImage.planes[0];
    var iosBytesOffset = 28;
    return img.Image.fromBytes(
      width: cameraImage.width,
      height: cameraImage.height,
      bytes: plane.bytes.buffer,
      rowStride: plane.bytesPerRow,
      bytesOffset: iosBytesOffset,
      order: img.ChannelOrder.bgra,
    );
  }

  img.Image _convertNV21(CameraImage image) {
    final width = image.width.toInt();
    final height = image.height.toInt();
    Uint8List yuv420sp = image.planes[0].bytes;
    final outImg = img.Image(height: height, width: width);
    final int frameSize = width * height;

    for (int j = 0, yp = 0; j < height; j++) {
      int uvp = frameSize + (j >> 1) * width, u = 0, v = 0;
      for (int i = 0; i < width; i++, yp++) {
        int y = (0xff & yuv420sp[yp]) - 16;
        if (y < 0) y = 0;
        if ((i & 1) == 0) {
          v = (0xff & yuv420sp[uvp++]) - 128;
          u = (0xff & yuv420sp[uvp++]) - 128;
        }
        int y1192 = 1192 * y;
        int r = (y1192 + 1634 * v);
        int g = (y1192 - 833 * v - 400 * u);
        int b = (y1192 + 2066 * u);

        if (r < 0) {
          r = 0;
        } else if (r > 262143) r = 262143;
        if (g < 0) {
          g = 0;
        } else if (g > 262143) g = 262143;
        if (b < 0) {
          b = 0;
        } else if (b > 262143) b = 262143;

        outImg.setPixelRgb(i, j, ((r << 6) & 0xff0000) >> 16,
            ((g >> 2) & 0xff00) >> 8, (b >> 10) & 0xff);
      }
    }
    return outImg;
  }

  void dispose() {
    recognitionModel.close();
  }
}

/// Helper class for recognition results
class RecognitionResult {
  final UserModel user;
  final double distance;
  final double confidence;
  final bool isMatch;
  final double faceQuality;

  RecognitionResult({
    required this.user,
    required this.distance,
    required this.confidence,
    required this.isMatch,
    required this.faceQuality,
  });
}
