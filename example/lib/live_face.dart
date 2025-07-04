import 'dart:developer';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// [LiveFace] class is responsible for displaying the camera feed and capturing images.
class LiveFace extends StatefulWidget {
  /// [cameraDescription] Camera description to be used for the camera feed.
  final CameraDescription? cameraDescription;

  /// [resolutionPreset] Resolution preset for the camera feed. default is [ResolutionPreset.medium].
  final ResolutionPreset resolutionPreset;

  /// [frameSkipCount] The number of frames to be skipped before processing the next frame. default is 10.
  final int frameSkipCount;

  /// [onImageCaptured] Callback function that will be called when an image is captured.
  final Function(File?)? onImageCaptured;

  /// [onImageForFaceDetection] Callback function for face detection processing.
  final Function(File?)? onImageForFaceDetection;

  /// [loadingWidget] A custom loading widget to be displayed while the camera is initializing.
  final Widget? loadingWidget;

  /// [LiveFace] class is responsible for displaying the camera feed and capturing images.
  const LiveFace({
    super.key,
    this.cameraDescription,
    this.resolutionPreset = ResolutionPreset.medium,
    this.frameSkipCount = 10,
    this.onImageCaptured,
    this.onImageForFaceDetection,
    this.loadingWidget,
  });

  @override
  State<LiveFace> createState() => _LiveFaceState();
}

class _LiveFaceState extends State<LiveFace> with WidgetsBindingObserver {
  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  File? _capturedImage;
  bool isInitialized = false;
  bool isBusy = false;
  int frameCount = 0;

  // Internal listeners
  Function(File?)? _onImageCaptured;
  Function(File?)? _onImageForFaceDetection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Setup internal listeners
    _setupListeners();

    // Initialize camera
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  /// Setup internal listeners for image capture and face detection
  void _setupListeners() {
    // Setup listener untuk mendapatkan foto
    _onImageCaptured = widget.onImageCaptured ??
        (File? image) {
          log('Image captured: ${image?.path}');
          // Trigger face detection listener
          if (_onImageForFaceDetection != null) {
            _onImageForFaceDetection!(image);
          }
        };

    // Setup listener untuk face detection
    _onImageForFaceDetection = widget.onImageForFaceDetection ??
        (File? image) {
          log('Ready for face detection: ${image?.path}');
          // Process image for face detection
          _processCapturedImage(image);
        };
  }

  /// Initialize camera with permission check
  Future<void> _initializeCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        log('Camera permission denied');
        return;
      }

      log('Camera permission granted');

      // Get available cameras
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        log('No cameras available');
        return;
      }

      // Use provided camera or find front camera
      CameraDescription selectedCamera =
          widget.cameraDescription ?? cameras.first;

      if (widget.cameraDescription == null) {
        for (var camera in cameras) {
          if (camera.lensDirection == CameraLensDirection.front) {
            selectedCamera = camera;
            break;
          }
        }
      }

      // Initialize camera controller
      cameraController = CameraController(
        selectedCamera,
        widget.resolutionPreset,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 // for Android
            : ImageFormatGroup.bgra8888, // for iOS
        enableAudio: false,
      );

      await cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        isInitialized = true;
      });

      log('Camera initialized successfully');

      // Start image stream for continuous processing (optional)
      _startImageStream();
    } catch (e) {
      log('Error initializing camera: $e');
    }
  }

  /// Start image stream for continuous processing
  void _startImageStream() {
    if (cameraController != null && cameraController!.value.isInitialized) {
      cameraController!.startImageStream((image) async {
        try {
          frameCount++;
          if (frameCount % widget.frameSkipCount == 0) {
            if (!isBusy) {
              isBusy = true;

              // Process camera frame here if needed
              // This is where you can add continuous face detection
              await _processCameraFrame(image);

              isBusy = false;
            }
          }
        } catch (e) {
          log('Error processing camera frame: $e');
          isBusy = false;
        }
      });
    }
  }

  /// Process camera frame for continuous detection
  Future<void> _processCameraFrame(CameraImage image) async {
    // TODO: Add continuous face detection here
    // This method can be used for real-time face detection
    // without capturing the image
    log('Processing camera frame...');
  }

  /// Dispose camera resources
  Future<void> _disposeCamera() async {
    await cameraController?.dispose();
    cameraController = null;
    setState(() {
      isInitialized = false;
    });
  }

  /// Capture image and trigger listeners
  Future<void> _captureImage() async {
    if (cameraController != null && cameraController!.value.isInitialized) {
      try {
        final XFile image = await cameraController!.takePicture();
        final File imageFile = File(image.path);

        setState(() {
          _capturedImage = imageFile;
        });

        log('Image captured: ${image.path}');

        // Trigger listeners
        if (_onImageCaptured != null) {
          _onImageCaptured!(imageFile);
        }

        // Notify about captured image
        _notifyImageCaptured(imageFile);
      } catch (e) {
        log('Error capturing image: $e');
      }
    }
  }

  /// Notify listeners about captured image
  void _notifyImageCaptured(File imageFile) {
    log('Notifying listeners about captured image: ${imageFile.path}');

    // Process captured image for face detection
    _processCapturedImage(imageFile);
  }

  /// Process captured image for face detection
  void _processCapturedImage(File? imageFile) {
    if (imageFile == null) return;

    log('Processing captured image for face detection...');

    // TODO: Integrate dengan face detector
    // Contoh implementasi dengan ML Kit:
    _detectFacesInImage(imageFile);
  }

  /// Detect faces in captured image
  void _detectFacesInImage(File imageFile) {
    log('Face detection placeholder - Image: ${imageFile.path}');

    // TODO: Implementasi actual face detection
    // Contoh dengan ML Kit:
    /*
    final inputImage = InputImage.fromFile(imageFile);
    final faceDetector = GoogleMlKit.vision.faceDetector();
    final faces = await faceDetector.processImage(inputImage);
    
    for (Face face in faces) {
      final Rect boundingBox = face.boundingBox;
      log('Face detected: ${boundingBox.toString()}');
    }
    */
  }

  /// Switch between front and back camera
  Future<void> _switchCamera() async {
    if (cameras.length <= 1) return;

    try {
      // Find different camera
      CameraDescription newCamera = cameras.first;
      for (var camera in cameras) {
        if (camera.lensDirection !=
            cameraController!.description.lensDirection) {
          newCamera = camera;
          break;
        }
      }

      // Dispose current controller
      await cameraController?.dispose();

      // Initialize new controller
      cameraController = CameraController(
        newCamera,
        widget.resolutionPreset,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
        enableAudio: false,
      );

      await cameraController!.initialize();

      if (mounted) {
        setState(() {});
        _startImageStream();
      }

      log('Camera switched to: ${newCamera.lensDirection}');
    } catch (e) {
      log('Error switching camera: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Size screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: true,
      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Live Camera'),
            actions: [
              if (cameras.length > 1)
                IconButton(
                  onPressed: _switchCamera,
                  icon: const Icon(Icons.switch_camera),
                ),
            ],
          ),
          body: _buildBody(screenSize),
        ),
      ),
    );
  }

  Widget _buildBody(Size screenSize) {
    // Show captured image if available
    if (_capturedImage != null) {
      return _buildCapturedImageView();
    }

    // Show camera preview if initialized
    if (isInitialized && cameraController != null) {
      return _buildCameraView(screenSize);
    }

    // Show loading
    return _buildLoadingView();
  }

  Widget _buildCapturedImageView() {
    return Center(
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Image.file(
            _capturedImage!,
            width: double.maxFinite,
            fit: BoxFit.fitWidth,
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() => _capturedImage = null);
                log('Resetting for new capture');
              },
              child: const Text(
                'Capture Again',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView(Size screenSize) {
    return Stack(
      children: [
        // Camera preview
        SizedBox.expand(
          child: CameraPreview(cameraController!),
        ),

        // Capture button
        Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey.shade300,
                  width: 4,
                ),
              ),
              child: IconButton(
                onPressed: _captureImage,
                icon: const Icon(
                  Icons.camera_alt,
                  size: 30,
                  color: Colors.black,
                ),
                iconSize: 60,
              ),
            ),
          ),
        ),

        // Status indicator
        if (isBusy)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Processing...',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return widget.loadingWidget ??
        const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initializing camera...'),
            ],
          ),
        );
  }

  // Public methods for external access
  void setImageCaptureListener(Function(File?) listener) {
    _onImageCaptured = listener;
  }

  void setFaceDetectionListener(Function(File?) listener) {
    _onImageForFaceDetection = listener;
  }
}
