// Copyright (c) 2025 Badieh Nader.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_verify/face_verify.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    Permission.camera.request();
    cameras = await availableCameras();
  } catch (e) {
    log('Error getting cameras: $e');
    cameras = [];
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enhanced Face Recognition Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<UserModel> users = [];
  bool isLoading = false;
  OptimizedFaceCropper faceCropper = OptimizedFaceCropper();
  List<String> tempCroppedFiles = []; // Track temp files for cleanup

  @override
  void dispose() {
    faceCropper.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _cleanupTempFiles() async {
    if (tempCroppedFiles.isNotEmpty) {
      tempCroppedFiles.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Enhanced Face Recognition'),
        actions: [
          if (users.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.face_retouching_natural),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // builder: (context) => EnhancedCheckinPage(users: users),
                    builder: (context) => DetectionView(
                      users: users,
                      cameraDescription: cameras[1],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Processing face registration...'),
                  ],
                ),
              ),

            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.face, size: 48, color: Colors.blue),
                    const SizedBox(height: 8),
                    const Text(
                      'Enhanced Face Recognition',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (users.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EnhancedCheckinPage(users: users),
                    ),
                  );
                },
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('Start Face Recognition'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
              ),

            ElevatedButton.icon(
              onPressed: () {
                _registerUsers();
              },
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('Add Face Recognition'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // Users List
            Expanded(
              child: users.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_add, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No users registered yet',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap "Register New User" to add your first user',
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              const Icon(Icons.people, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(
                                'Registered Users (${users.length})',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) => Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.file(
                                    File(users[index].image ?? ''),
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.person,
                                          size: 30,
                                          color: Colors.grey,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                title: Text(
                                  users[index].name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('ID: ${users[index].id}'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => _removeUser(index),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registerUsers() async {
    if (cameras.isEmpty) {
      _showErrorDialog('No cameras available');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      log('📸 Image captured: ${image.path}');

      // Use the optimized face cropper
      final croppedImagePath = await faceCropper.detectAndCropFace(image.path);

      if (croppedImagePath == null) {
        setState(() {
          isLoading = false;
        });
        _showErrorDialog(
            'No face detected in the image. Please try again with a clear face photo.');
        return;
      }

      // Track temp file for cleanup
      tempCroppedFiles.add(croppedImagePath);

      log('✂️ Face cropped successfully: $croppedImagePath');

      String username = 'user-${users.length + 1}';

      // Prepare registration input
      RegisterUserInputModel registerInput = RegisterUserInputModel(
        name: username,
        imagePath: croppedImagePath,
      );

      // Register the user
      final newUsers = await registerUsers(
        registerUserInputs: [registerInput],
        cameraDescription: cameras.first,
      );

      final encodeData = json.encode(newUsers.first.toJson());
      log('✅ User registered successfully: $encodeData');

      setState(() {
        users.addAll(newUsers);
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('✅ Successfully registered: $username'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      log('🎉 User registered successfully: $username');
    } catch (e, s) {
      log('❌ Error registering user: $e');
      log('Stack trace: $s');

      setState(() {
        isLoading = false;
      });

      if (mounted) {
        _showErrorDialog('Error registering user: ${e.toString()}');
      }
    }
  }

  Future<String?> _showNameInputDialog() async {
    String? name;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enter User Name'),
        content: TextField(
          onChanged: (value) => name = value,
          decoration: const InputDecoration(
            hintText: 'Enter full name...',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (name != null && name!.trim().isNotEmpty) {
                Navigator.pop(context, name!.trim());
              }
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  void _removeUser(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove User'),
        content:
            Text('Are you sure you want to remove "${users[index].name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                users.removeAt(index);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('User removed successfully'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// Enhanced Check-in Page
class EnhancedCheckinPage extends StatefulWidget {
  const EnhancedCheckinPage({super.key, required this.users});

  final List<UserModel> users;

  @override
  State<EnhancedCheckinPage> createState() => _EnhancedCheckinPageState();
}

class _EnhancedCheckinPageState extends State<EnhancedCheckinPage> {
  late FaceDetectorService faceDetectorService;
  late EnhancedRecognitionService recognitionService;
  Set<UserModel> recognitions = {};
  bool isProcessing = false;
  String? lastRecognitionResult;
  Uint8List? _croppedImage;
  OptimizedFaceCropper faceCropper = OptimizedFaceCropper();
  List<String> tempCroppedFiles = [];

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    faceDetectorService.dispose();
    recognitionService.dispose();
    faceCropper.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _cleanupTempFiles() async {
    if (tempCroppedFiles.isNotEmpty) {
      tempCroppedFiles.clear();
    }
  }

  void _initializeServices() {
    try {
      CameraDescription cameraToUse;
      if (cameras.isNotEmpty) {
        cameraToUse = cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
      } else {
        cameraToUse = const CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        );
      }

      faceDetectorService = FaceDetectorService(
        cameraDescription: cameraToUse,
        faceDetectorPerformanceMode: FaceDetectorMode.accurate,
      );

      recognitionService = EnhancedRecognitionService(
        users: widget.users,
        rotationCompensation: faceDetectorService.rotationCompensation ?? 0,
        sensorOrientation: cameraToUse.sensorOrientation,
        threshold: 0.73, // Optimized threshold
        qualityThreshold: 0.73, // Face quality threshold
        maxFacesToProcess: 3, // Process up to 3 faces
        minFaceSizeRatio: 0.05, // Minimum face size
      );

      log('🔧 Services initialized successfully');
    } catch (e) {
      log('❌ Error initializing services: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Recognition Check-in'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Status Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Text(
                            'System Status',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Registered Users:'),
                          Text(
                            '${widget.users.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Recognition Accuracy:'),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Enhanced',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Recognition Button
              if (widget.users.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(Icons.warning, size: 48, color: Colors.orange),
                        SizedBox(height: 16),
                        Text(
                          'No Users Registered',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Please register users first before starting face recognition.',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    if (isProcessing)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'Processing face recognition...',
                                style: TextStyle(fontSize: 16),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Please wait while we analyze the face',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              const Icon(Icons.camera_alt,
                                  size: 48, color: Colors.blue),
                              const SizedBox(height: 16),
                              const Text(
                                'Ready for Face Recognition',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Take a photo to check if the person is registered',
                                style: TextStyle(color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _checkUser,
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Start Face Recognition'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32, vertical: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 20),

              // Cropped Image Display
              if (_croppedImage != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Detected Face',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _croppedImage!,
                            height: 200,
                            width: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Recognition Result
              if (lastRecognitionResult != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              lastRecognitionResult!.contains('recognized')
                                  ? Icons.check_circle
                                  : Icons.error,
                              color:
                                  lastRecognitionResult!.contains('recognized')
                                      ? Colors.green
                                      : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Recognition Result',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: lastRecognitionResult!.contains('recognized')
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lastRecognitionResult!,
                            style: TextStyle(
                              fontSize: 16,
                              color:
                                  lastRecognitionResult!.contains('recognized')
                                      ? Colors.green[700]
                                      : Colors.red[700],
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              // Recognized Users
              if (recognitions.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.people, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Recognized Users',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ...recognitions.map((user) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: Image.file(
                                      File(user.image ?? ''),
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          width: 50,
                                          height: 50,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[300],
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.person,
                                              size: 30),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          user.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'ID: ${user.id}',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.check_circle,
                                      color: Colors.green),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _checkUser() async {
    if (widget.users.isEmpty) {
      _showMessage('No users registered yet!');
      return;
    }

    setState(() {
      isProcessing = true;
      lastRecognitionResult = null;
      recognitions.clear();
    });

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null) {
        setState(() {
          isProcessing = false;
        });
        return;
      }

      log('📸 Check-in image captured: ${image.path}');

      // Use optimized face cropper
      final croppedImagePath = await faceCropper.detectAndCropFace(image.path);

      if (croppedImagePath == null) {
        setState(() {
          isProcessing = false;
          lastRecognitionResult =
              'No face detected in the image. Please try again.';
        });
        return;
      }

      // Track temp file
      tempCroppedFiles.add(croppedImagePath);

      // Perform face detection
      final faces = await faceDetectorService.doFaceDetection(
        faceDetectorSource: FaceDetectorSource.localImage,
        localImage: File(croppedImagePath),
      );

      if (faces.isEmpty) {
        setState(() {
          isProcessing = false;
          lastRecognitionResult = 'No faces detected in the processed image';
        });
        return;
      }

      log('🔍 Detected ${faces.length} face(s) for recognition');

      // Load and display cropped image
      final imageBytes = await File(croppedImagePath).readAsBytes();
      _croppedImage = imageBytes;
      final decodedImage = img.decodeImage(imageBytes);

      if (decodedImage == null) {
        setState(() {
          isProcessing = false;
          lastRecognitionResult = 'Failed to decode processed image';
        });
        return;
      }

      // Perform enhanced face recognition
      final isRecognized = recognitionService.performFaceRecognition(
        localImageFrame: decodedImage,
        recognitions: recognitions,
        faces: faces,
      );

      setState(() {
        isProcessing = false;
        if (isRecognized && recognitions.isNotEmpty) {
          String recognizedNames =
              recognitions.map((user) => user.name).join(', ');
          lastRecognitionResult = '✅ User(s) recognized: $recognizedNames';
          log('🎉 Recognition successful: $recognizedNames');
        } else {
          lastRecognitionResult =
              '❌ User not recognized - person not found in database';
          log('❌ Recognition failed - no matches found');
        }
      });
    } catch (e, s) {
      log('❌ Error during face recognition: $e');
      log('Stack trace: $s');

      setState(() {
        isProcessing = false;
        lastRecognitionResult = 'Error during recognition: ${e.toString()}';
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
