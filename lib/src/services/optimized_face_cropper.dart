import 'dart:io';
import 'dart:typed_data';
import 'dart:developer';
import 'dart:ui';
import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// OptimizedFaceCropper dengan background processing menggunakan isolate
class OptimizedFaceCropper {
  final FaceDetector _faceDetector;
  final StreamController<CropResult> _resultController;
  final Queue<CropTask> _taskQueue;

  // Isolate untuk background processing
  Isolate? _backgroundIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isIsolateReady = false;

  Timer? _processingTimer;
  bool _isProcessing = false;

  // Performance settings
  int maxQueueSize = 3;
  int processingInterval = 300; // ms

  OptimizedFaceCropper()
      : _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: true,
            enableLandmarks: true,
            enableClassification: true,
            enableTracking: true,
            minFaceSize: 0.1,
            performanceMode: FaceDetectorMode.accurate,
          ),
        ),
        _resultController = StreamController<CropResult>.broadcast(),
        _taskQueue = Queue<CropTask>();

  /// Stream untuk hasil cropping
  Stream<CropResult> get cropResults => _resultController.stream;

  /// Inisialisasi background processing dengan isolate
  Future<void> initialize() async {
    await _initializeIsolate();
    _startBackgroundProcessing();
  }

  /// Inisialisasi isolate untuk background processing
  Future<void> _initializeIsolate() async {
    try {
      _receivePort = ReceivePort();

      // Spawn isolate
      _backgroundIsolate = await Isolate.spawn(
        _isolateEntryPoint,
        _receivePort!.sendPort,
      );

      // Listen untuk mendapatkan SendPort dari isolate
      _receivePort!.listen((message) {
        if (message is SendPort) {
          _sendPort = message;
          _isIsolateReady = true;
          log('Background isolate initialized successfully');
        } else if (message is CropResult) {
          // Hasil dari isolate
          _resultController.add(message);
        } else if (message is String && message.startsWith('error:')) {
          log('Isolate error: $message');
        }
      });

      // Tunggu sampai isolate siap
      int attempts = 0;
      while (!_isIsolateReady && attempts < 50) {
        await Future.delayed(Duration(milliseconds: 100));
        attempts++;
      }

      if (!_isIsolateReady) {
        throw Exception('Failed to initialize isolate after 5 seconds');
      }
    } catch (e) {
      log('Error initializing isolate: $e');
      rethrow;
    }
  }

  /// Entry point untuk isolate
  static void _isolateEntryPoint(SendPort mainSendPort) {
    // ReceivePort untuk isolate
    final isolateReceivePort = ReceivePort();

    // Kirim SendPort ke main isolate
    mainSendPort.send(isolateReceivePort.sendPort);

    // Listen untuk task dari main isolate
    isolateReceivePort.listen((message) async {
      if (message is IsolateTask) {
        try {
          final result = await _processTaskInIsolate(message);
          mainSendPort.send(result);
        } catch (e) {
          mainSendPort.send('error: $e');
        }
      }
    });
  }

  /// Process task di dalam isolate
  static Future<CropResult> _processTaskInIsolate(IsolateTask task) async {
    try {
      final startTime = DateTime.now().millisecondsSinceEpoch;

      // Load image
      final File imageFile = File(task.imagePath);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);

      if (originalImage == null) {
        return CropResult(
          success: false,
          taskId: task.taskId,
          message: 'Failed to decode image',
          timestamp: task.timestamp,
        );
      }

      // Process faces
      final List<FaceData> faces = task.faces;
      if (faces.isEmpty) {
        return CropResult(
          success: false,
          taskId: task.taskId,
          message: 'No faces detected',
          timestamp: task.timestamp,
        );
      }

      // Get largest face
      final FaceData largestFace = faces.reduce((a, b) =>
          a.boundingBox.width * a.boundingBox.height >
                  b.boundingBox.width * b.boundingBox.height
              ? a
              : b);

      // Crop face
      final img.Image? croppedFace = _cropFaceInIsolate(
        originalImage,
        largestFace,
      );

      if (croppedFace == null) {
        return CropResult(
          success: false,
          taskId: task.taskId,
          message: 'Failed to crop face',
          timestamp: task.timestamp,
        );
      }

      // Save cropped image
      final String croppedImagePath =
          _generateCroppedImagePathInIsolate(task.imagePath);
      final File croppedFile = File(croppedImagePath);
      await croppedFile.writeAsBytes(img.encodeJpg(croppedFace, quality: 85));

      final processingTime = DateTime.now().millisecondsSinceEpoch - startTime;

      return CropResult(
        success: true,
        taskId: task.taskId,
        croppedImagePath: croppedImagePath,
        faceCount: faces.length,
        message: 'Face cropped successfully',
        timestamp: task.timestamp,
        processingTime: processingTime,
      );
    } catch (e) {
      return CropResult(
        success: false,
        taskId: task.taskId,
        message: 'Processing error: $e',
        timestamp: task.timestamp,
      );
    }
  }

  /// Crop face di dalam isolate
  static img.Image? _cropFaceInIsolate(img.Image image, FaceData face) {
    try {
      final RectData boundingBox = face.boundingBox;

      double centerX = boundingBox.left + (boundingBox.width / 2);
      double centerY = boundingBox.top + (boundingBox.height / 2);

      double adjustedWidth = boundingBox.width;
      double adjustedHeight = boundingBox.height;

      // Use landmarks if available
      if (face.landmarks.isNotEmpty) {
        final leftEye = face.landmarks['leftEye'];
        final rightEye = face.landmarks['rightEye'];
        final noseBase = face.landmarks['noseBase'];
        final bottomMouth = face.landmarks['bottomMouth'];

        if (leftEye != null && rightEye != null) {
          final eyeDistance = (rightEye.x - leftEye.x).abs();

          adjustedWidth = eyeDistance * 1.6;
          adjustedHeight = adjustedWidth * 1.1;

          if (noseBase != null && bottomMouth != null) {
            final double faceAreaCenterY = (leftEye.y + rightEye.y) / 2;
            final double mouthY = bottomMouth.y;
            centerY = faceAreaCenterY + ((mouthY - faceAreaCenterY) * 0.3);
          }
        }
      }

      // Use contours if available
      if (face.contours.isNotEmpty) {
        final faceContour = face.contours['face'];
        if (faceContour != null && faceContour.isNotEmpty) {
          // Find bounding box from contour points
          double minX = faceContour.first.x;
          double maxX = faceContour.first.x;
          double minY = faceContour.first.y;
          double maxY = faceContour.first.y;

          for (final point in faceContour) {
            minX = minX < point.x ? minX : point.x;
            maxX = maxX > point.x ? maxX : point.x;
            minY = minY < point.y ? minY : point.y;
            maxY = maxY > point.y ? maxY : point.y;
          }

          // Very minimal padding
          final double padding = ((maxX - minX) * 0.03);

          final int cropLeft =
              (minX - padding).clamp(0, image.width - 1).toInt();
          final int cropTop =
              (minY - padding).clamp(0, image.height - 1).toInt();
          final int cropRight = (maxX + padding).clamp(0, image.width).toInt();
          final int cropBottom =
              (maxY + padding).clamp(0, image.height).toInt();

          final int cropWidth = cropRight - cropLeft;
          final int cropHeight = cropBottom - cropTop;

          if (cropWidth > 0 && cropHeight > 0) {
            img.Image croppedFace = img.copyCrop(
              image,
              x: cropLeft,
              y: cropTop,
              width: cropWidth,
              height: cropHeight,
            );

            croppedFace = img.copyResize(
              croppedFace,
              width: 160,
              height: 160,
              interpolation: img.Interpolation.cubic,
            );

            return _enhanceImageInIsolate(croppedFace);
          }
        }
      }

      // Fallback to bounding box method
      final double cropMarginX = adjustedWidth * 0.05;
      final double cropMarginY = adjustedHeight * 0.08;

      final double finalWidth = adjustedWidth + (cropMarginX * 2);
      final double finalHeight = adjustedHeight + (cropMarginY * 2);

      final int cropLeft =
          (centerX - (finalWidth / 2)).clamp(0, image.width - 1).toInt();
      final int cropTop =
          (centerY - (finalHeight / 2)).clamp(0, image.height - 1).toInt();
      final int cropRight =
          (cropLeft + finalWidth).clamp(0, image.width).toInt();
      final int cropBottom =
          (cropTop + finalHeight).clamp(0, image.height).toInt();

      final int cropWidth = cropRight - cropLeft;
      final int cropHeight = cropBottom - cropTop;

      if (cropWidth <= 0 || cropHeight <= 0) {
        return null;
      }

      img.Image croppedFace = img.copyCrop(
        image,
        x: cropLeft,
        y: cropTop,
        width: cropWidth,
        height: cropHeight,
      );

      croppedFace = img.copyResize(
        croppedFace,
        width: 160,
        height: 160,
        interpolation: img.Interpolation.cubic,
      );

      return _enhanceImageInIsolate(croppedFace);
    } catch (e) {
      return null;
    }
  }

  /// Enhance image di isolate
  static img.Image _enhanceImageInIsolate(img.Image image) {
    return img.adjustColor(
      image,
      contrast: 1.1,
      brightness: 1.05,
      saturation: 0.95,
    );
  }

  /// Generate cropped image path di isolate
  static String _generateCroppedImagePathInIsolate(String originalPath) {
    final String directory = File(originalPath).parent.path;
    final String filename = File(originalPath).uri.pathSegments.last;
    final String nameWithoutExtension = filename.split('.').first;
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    return '$directory/cropped_${nameWithoutExtension}_$timestamp.jpg';
  }

  /// Detects faces and crops them (Background Version dengan isolate)
  Future<void> detectAndCropFaceBackground(String imagePath,
      {String? taskId}) async {
    if (!_isIsolateReady) {
      log('Isolate not ready, initializing...');
      await initialize();
    }

    try {
      // Face detection di main thread (cepat)
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _resultController.add(CropResult(
          success: false,
          taskId: taskId ?? DateTime.now().millisecondsSinceEpoch.toString(),
          message: 'No faces detected',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ));
        return;
      }

      // Convert Face objects ke FaceData untuk isolate
      final List<FaceData> faceDataList =
          faces.map((face) => FaceData.fromFace(face)).toList();

      // Tambah task ke queue
      _addCropTask(CropTask(
        imagePath: imagePath,
        taskId: taskId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        faces: faceDataList,
      ));
    } catch (e) {
      log('Error in detectAndCropFaceBackground: $e');
      _resultController.add(CropResult(
        success: false,
        taskId: taskId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        message: 'Error: $e',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  /// Tambah task ke queue
  void _addCropTask(CropTask task) {
    // Batasi ukuran queue
    if (_taskQueue.length >= maxQueueSize) {
      _taskQueue.removeFirst(); // Remove oldest task
    }

    _taskQueue.add(task);
  }

  /// Background processing loop
  void _startBackgroundProcessing() {
    _processingTimer = Timer.periodic(
      Duration(milliseconds: processingInterval),
      (timer) => _processQueue(),
    );
  }

  /// Process queue di background
  Future<void> _processQueue() async {
    if (_isProcessing ||
        _taskQueue.isEmpty ||
        !_isIsolateReady ||
        _sendPort == null) {
      return;
    }

    _isProcessing = true;

    try {
      // Ambil task terbaru (skip yang lama)
      CropTask task = _taskQueue.removeLast();
      _taskQueue.clear(); // Clear queue untuk performa

      // Kirim task ke isolate
      final isolateTask = IsolateTask(
        imagePath: task.imagePath,
        taskId: task.taskId,
        timestamp: task.timestamp,
        faces: task.faces,
      );

      _sendPort!.send(isolateTask);
    } catch (e) {
      log('Error processing queue: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Original synchronous method (untuk backward compatibility)
  Future<String?> detectAndCropFace(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        log('No faces detected in image');
        return null;
      }

      // Convert ke FaceData
      final List<FaceData> faceDataList =
          faces.map((face) => FaceData.fromFace(face)).toList();

      // Process dengan compute untuk menghindari blocking UI
      final cropResult = await compute(
          _cropFaceCompute,
          CropInput(
            imagePath: imagePath,
            faces: faceDataList,
          ));

      return cropResult?.croppedImagePath;
    } catch (e) {
      log('Error in detectAndCropFace: $e');
      return null;
    }
  }

  /// Batch process multiple images
  Future<void> batchCropFacesBackground(List<String> imagePaths,
      {String? batchId}) async {
    for (int i = 0; i < imagePaths.length; i++) {
      final taskId = '${batchId ?? 'batch'}_$i';
      await detectAndCropFaceBackground(imagePaths[i], taskId: taskId);
    }
  }

  /// Clean up resources
  void dispose() {
    _processingTimer?.cancel();
    _faceDetector.close();
    _resultController.close();

    // Clean up isolate
    if (_backgroundIsolate != null) {
      _backgroundIsolate!.kill(priority: Isolate.immediate);
      _backgroundIsolate = null;
    }

    if (_receivePort != null) {
      _receivePort!.close();
      _receivePort = null;
    }
  }
}

/// Compute function untuk fallback
Future<CropData?> _cropFaceCompute(CropInput input) async {
  try {
    final File imageFile = File(input.imagePath);
    final Uint8List imageBytes = await imageFile.readAsBytes();
    final img.Image? originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) {
      return null;
    }

    final FaceData largestFace = input.faces.reduce((a, b) =>
        a.boundingBox.width * a.boundingBox.height >
                b.boundingBox.width * b.boundingBox.height
            ? a
            : b);

    final img.Image? croppedFace = OptimizedFaceCropper._cropFaceInIsolate(
      originalImage,
      largestFace,
    );

    if (croppedFace == null) {
      return null;
    }

    final String croppedImagePath =
        OptimizedFaceCropper._generateCroppedImagePathInIsolate(
            input.imagePath);
    final File croppedFile = File(croppedImagePath);
    await croppedFile.writeAsBytes(img.encodeJpg(croppedFace, quality: 85));

    return CropData(
      croppedImagePath: croppedImagePath,
      faceCount: input.faces.length,
    );
  } catch (e) {
    return null;
  }
}

/// Data classes
class CropTask {
  final String imagePath;
  final String taskId;
  final int timestamp;
  final List<FaceData> faces;

  CropTask({
    required this.imagePath,
    required this.taskId,
    required this.timestamp,
    required this.faces,
  });
}

class IsolateTask {
  final String imagePath;
  final String taskId;
  final int timestamp;
  final List<FaceData> faces;

  IsolateTask({
    required this.imagePath,
    required this.taskId,
    required this.timestamp,
    required this.faces,
  });
}

class CropInput {
  final String imagePath;
  final List<FaceData> faces;

  CropInput({
    required this.imagePath,
    required this.faces,
  });
}

class CropData {
  final String croppedImagePath;
  final int faceCount;

  CropData({
    required this.croppedImagePath,
    required this.faceCount,
  });
}

class CropResult {
  final bool success;
  final String taskId;
  final String? croppedImagePath;
  final int? faceCount;
  final String message;
  final int timestamp;
  final int? processingTime;

  CropResult({
    required this.success,
    required this.taskId,
    this.croppedImagePath,
    this.faceCount,
    required this.message,
    required this.timestamp,
    this.processingTime,
  });
}

/// Serializable Face Data untuk isolate
class FaceData {
  final RectData boundingBox;
  final Map<String, PointData> landmarks;
  final Map<String, List<PointData>> contours;

  FaceData({
    required this.boundingBox,
    required this.landmarks,
    required this.contours,
  });

  factory FaceData.fromFace(Face face) {
    final Map<String, PointData> landmarks = {};
    face.landmarks.forEach((key, value) {
      landmarks[key.toString()] = PointData(
          x: value?.position.x.toDouble() ?? 0,
          y: value?.position.y.toDouble() ?? 0);
    });

    final Map<String, List<PointData>> contours = {};
    face.contours.forEach((key, value) {
      contours[key.toString()] = value?.points
              .map((p) => PointData(x: p.x.toDouble(), y: p.y.toDouble()))
              .toList() ??
          [];
    });

    return FaceData(
      boundingBox: RectData(
        left: face.boundingBox.left,
        top: face.boundingBox.top,
        width: face.boundingBox.width,
        height: face.boundingBox.height,
      ),
      landmarks: landmarks,
      contours: contours,
    );
  }
}

class RectData {
  final double left;
  final double top;
  final double width;
  final double height;

  RectData({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

class PointData {
  final double x;
  final double y;

  PointData({required this.x, required this.y});
}

/// Queue implementation
class Queue<T> {
  final List<T> _items = [];

  void add(T item) => _items.add(item);
  T removeFirst() => _items.removeAt(0);
  T removeLast() => _items.removeLast();
  void clear() => _items.clear();
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;
}
