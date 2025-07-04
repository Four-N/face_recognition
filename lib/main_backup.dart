// import 'dart:convert';
// import 'dart:math';
// import 'dart:async';

// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// const platform = MethodChannel('com.example.face_auth/biometric');

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   final cameras = await availableCameras();
//   runApp(FaceAuthApp(cameras: cameras));
// }

// class FaceAuthApp extends StatelessWidget {
//   final List<CameraDescription> cameras;
//   const FaceAuthApp({super.key, required this.cameras});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Face + Liveness Auth',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: ConsentScreen(cameras: cameras),
//     );
//   }
// }

// class ConsentScreen extends StatelessWidget {
//   final List<CameraDescription> cameras;
//   const ConsentScreen({super.key, required this.cameras});

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Consent')),
//       body: Center(
//         child: ElevatedButton(
//           child: const Text('ยินยอมให้ใช้ใบหน้าเพื่อยืนยันตัวตน'),
//           onPressed: () {
//             Navigator.pushReplacement(
//               context,
//               MaterialPageRoute(
//                 builder: (_) => RegisterFaceScreen(cameras: cameras),
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// // Enum สำหรับขั้นตอนการแสกน
// enum ScanStep {
//   initializing,
//   faceDetection,
//   removeGlasses,
//   removeMask,
//   lookStraight,
//   turnLeft,
//   turnRight,
//   blink,
//   completed,
//   failed,
//   timeout,
// }

// class RegisterFaceScreen extends StatefulWidget {
//   final List<CameraDescription> cameras;
//   const RegisterFaceScreen({super.key, required this.cameras});

//   @override
//   State<RegisterFaceScreen> createState() => _RegisterFaceScreenState();
// }

// class _RegisterFaceScreenState extends State<RegisterFaceScreen> {
//   CameraController? _controller;
//   bool _isDetecting = false;
//   final faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableClassification: true,
//       enableLandmarks: true,
//       enableContours: true,
//       performanceMode: FaceDetectorMode.accurate,
//     ),
//   );

//   ScanStep _currentStep = ScanStep.initializing;
//   String _instruction = 'กำลังเตรียมกล้อง...';
//   int _blinkCount = 0;
//   bool _faceRegistered = false;
//   final _storage = const FlutterSecureStorage();
//   static const platform = MethodChannel('face_recognition');

//   // ตัวแปรสำหรับจับเวลา
//   Timer? _stepTimer;
//   Timer? _timeoutTimer;
//   int _remainingTime = 10;

//   // ตัวแปรสำหรับเก็บสถานะการตรวจจับ
//   bool _hasDetectedFace = false;
//   bool _hasRemovedGlasses = false;
//   bool _hasRemovedMask = false;
//   bool _hasLookedStraight = false;
//   bool _hasLookedLeft = false;
//   bool _hasLookedRight = false;

//   // ตัวแปรสำหรับเก็บค่าเฉลี่ย
//   List<double> _headYRotations = [];
//   List<double> _leftEyeOpenProbs = [];
//   List<double> _rightEyeOpenProbs = [];

//   // ตัวแปรสำหรับหน้า verification
//   bool _isVerifying = false;
//   String _status = 'กำลังเตรียมกล้อง...';

//   @override
//   void initState() {
//     super.initState();
//     _initializeCamera();
//   }

//   void _initializeCamera() {
//     CameraDescription? frontCamera;
//     try {
//       frontCamera = widget.cameras.firstWhere(
//         (camera) => camera.lensDirection == CameraLensDirection.front,
//       );
//     } catch (e) {
//       if (widget.cameras.isNotEmpty) {
//         frontCamera = widget.cameras.first;
//       }
//     }

//     if (frontCamera != null) {
//       _controller = CameraController(
//         frontCamera,
//         ResolutionPreset.medium,
//         enableAudio: false,
//       );
//       _controller!
//           .initialize()
//           .then((_) {
//             if (!mounted) return;
//             _controller!.startImageStream(_processCameraImage);
//             setState(() {
//               _currentStep = ScanStep.faceDetection;
//               _instruction = 'กรุณาวางใบหน้าในกรอบกล้อง';
//             });
//             _startStepTimer();
//           })
//           .catchError((error) {
//             print('Camera initialization error: $error');
//             setState(() {
//               _currentStep = ScanStep.failed;
//               _instruction = 'ไม่สามารถเข้าถึงกล้องได้';
//             });
//           });
//     } else {
//       setState(() {
//         _currentStep = ScanStep.failed;
//         _instruction = 'ไม่พบกล้อง';
//       });
//     }
//   }

//   void _startStepTimer() {
//     _remainingTime = 10;
//     _stepTimer?.cancel();
//     _timeoutTimer?.cancel();

//     _stepTimer = Timer.periodic(Duration(seconds: 1), (timer) {
//       if (!mounted) return;
//       setState(() {
//         _remainingTime--;
//       });

//       if (_remainingTime <= 0) {
//         _handleTimeout();
//       }
//     });
//   }

//   void _handleTimeout() {
//     _stepTimer?.cancel();
//     _timeoutTimer?.cancel();

//     setState(() {
//       _currentStep = ScanStep.timeout;
//       _instruction = 'หมดเวลา กรุณาลองใหม่อีกครั้ง';
//     });

//     _showTimeoutDialog();
//   }

//   void _showTimeoutDialog() {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             title: Text('หมดเวลา'),
//             content: Text('การสแกนใบหน้าหมดเวลา กรุณาลองใหม่อีกครั้ง'),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   _resetScan();
//                 },
//                 child: Text('ลองใหม่'),
//               ),
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   Navigator.pop(context);
//                 },
//                 child: Text('ยกเลิก'),
//               ),
//             ],
//           ),
//     );
//   }

//   void _resetScan() {
//     _stepTimer?.cancel();
//     _timeoutTimer?.cancel();

//     setState(() {
//       _currentStep = ScanStep.faceDetection;
//       _instruction = 'กรุณาวางใบหน้าในกรอบกล้อง';
//       _blinkCount = 0;
//       _faceRegistered = false;
//       _hasDetectedFace = false;
//       _hasRemovedGlasses = false;
//       _hasRemovedMask = false;
//       _hasLookedStraight = false;
//       _hasLookedLeft = false;
//       _hasLookedRight = false;
//       _headYRotations.clear();
//       _leftEyeOpenProbs.clear();
//       _rightEyeOpenProbs.clear();
//     });

//     _startStepTimer();
//   }

//   void _moveToNextStep() {
//     _stepTimer?.cancel();

//     switch (_currentStep) {
//       case ScanStep.faceDetection:
//         setState(() {
//           _currentStep = ScanStep.removeGlasses;
//           _instruction = 'กรุณาถอดแว่นตา (หากมี)';
//         });
//         break;
//       case ScanStep.removeGlasses:
//         setState(() {
//           _currentStep = ScanStep.removeMask;
//           _instruction = 'กรุณาถอดหน้ากากอนามัย (หากมี)';
//         });
//         break;
//       case ScanStep.removeMask:
//         setState(() {
//           _currentStep = ScanStep.lookStraight;
//           _instruction = 'กรุณามองตรงไปที่กล้อง';
//         });
//         break;
//       case ScanStep.lookStraight:
//         setState(() {
//           _currentStep = ScanStep.turnLeft;
//           _instruction = 'กรุณาหันหน้าไปทางซ้าย';
//         });
//         break;
//       case ScanStep.turnLeft:
//         setState(() {
//           _currentStep = ScanStep.turnRight;
//           _instruction = 'กรุณาหันหน้าไปทางขวา';
//         });
//         break;
//       case ScanStep.turnRight:
//         setState(() {
//           _currentStep = ScanStep.blink;
//           _instruction = 'กรุณากระพริบตา 2 ครั้ง';
//         });
//         break;
//       case ScanStep.blink:
//         _completeScan();
//         break;
//       default:
//         break;
//     }

//     if (_currentStep != ScanStep.completed) {
//       _startStepTimer();
//     }
//   }

//   void _completeScan() async {
//     _stepTimer?.cancel();
//     _timeoutTimer?.cancel();

//     setState(() {
//       _currentStep = ScanStep.completed;
//       _instruction = 'กำลังประมวลผล...';
//     });

//     final authResult = await _authenticateBiometric();
//     if (!authResult) {
//       setState(() {
//         _currentStep = ScanStep.failed;
//         _instruction = 'ยืนยันตัวตน Biometric ล้มเหลว';
//       });
//       return;
//     }

//     final result = await _getFaceResultFromNative();
//     if (result != null &&
//         result['liveness'] == true &&
//         result['vector'] is List) {
//       final vector = List<double>.from(result['vector']);
//       await _storage.write(key: 'face_vector', value: jsonEncode(vector));
//       await _storage.write(key: 'liveness_passed', value: 'true');

//       setState(() {
//         _faceRegistered = true;
//         _instruction = 'สำเร็จ! บันทึกใบหน้าเรียบร้อยแล้ว';
//       });

//       _showSuccessDialog(1.0);
//     } else {
//       setState(() {
//         _currentStep = ScanStep.failed;
//         _instruction = 'ไม่สามารถบันทึกข้อมูลใบหน้าได้';
//       });
//     }
//   }

//   void _showSuccessDialog(double similarity) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             title: Row(
//               children: [
//                 Icon(Icons.check_circle, color: Colors.green),
//                 SizedBox(width: 8),
//                 Text('สำเร็จ'),
//               ],
//             ),
//             content: Text('บันทึกข้อมูลใบหน้าและยืนยันตัวตนเรียบร้อยแล้ว'),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                 },
//                 child: Text('ตกลง'),
//               ),
//             ],
//           ),
//     );
//   }

//   Future<Map<String, dynamic>?> _getFaceResultFromNative() async {
//     try {
//       final result = await platform.invokeMethod('scanFace');
//       if (result != null && result is Map) {
//         return Map<String, dynamic>.from(result);
//       }
//     } catch (e) {}
//     return null;
//   }

//   Future<bool> _authenticateBiometric() async {
//     try {
//       final bool didAuthenticate = await platform.invokeMethod('authenticate');
//       return didAuthenticate;
//     } on PlatformException catch (_) {
//       return false;
//     }
//   }

//   void _processCameraImage(CameraImage image) async {
//     if (_isDetecting || _isVerifying) return;
//     _isDetecting = true;

//     try {
//       final inputImage = _convertCameraImage(
//         image,
//         _controller?.description.sensorOrientation ?? 0,
//       );

//       if (inputImage != null) {
//         final faces = await faceDetector.processImage(inputImage);

//         if (faces.isNotEmpty) {
//           if (!_isVerifying) {
//             _isVerifying = true;
//             _timeoutTimer?.cancel();

//             setState(() {
//               _status = 'กำลังตรวจสอบใบหน้า...';
//             });

//             await _performVerification();
//           }
//         } else {
//           setState(() => _status = 'ไม่พบใบหน้าในกล้อง');
//         }
//       }
//     } catch (e) {
//       print('Error: $e');
//       setState(() => _status = 'เกิดข้อผิดพลาดในการประมวลผลภาพ');
//     }

//     _isDetecting = false;
//   }

//   Future<void> _performVerification() async {
//     try {
//       final result = await _getFaceResultFromNative();
//       final storedJson = await _storage.read(key: 'face_vector');
//       final livenessPassed =
//           (await _storage.read(key: 'liveness_passed')) == 'true';

//       if (storedJson == null) {
//         setState(() {
//           _status = 'ยังไม่มีข้อมูลใบหน้าที่ลงทะเบียน';
//           _isVerifying = false;
//         });
//         return;
//       }

//       if (!livenessPassed) {
//         setState(() {
//           _status = 'ข้อมูลใบหน้าไม่ผ่านการตรวจสอบ Liveness';
//           _isVerifying = false;
//         });
//         return;
//       }

//       if (result == null ||
//           result['liveness'] != true ||
//           result['vector'] == null) {
//         setState(() {
//           _status = 'Liveness ไม่ผ่าน หรือไม่สามารถดึงข้อมูลใบหน้าได้';
//           _isVerifying = false;
//         });
//         return;
//       }

//       final newVector = List<double>.from(result['vector']);
//       final storedVector = List<double>.from(jsonDecode(storedJson));
//       final similarity = _cosineSimilarity(storedVector, newVector);

//       setState(() {
//         _isVerifying = false;
//       });

//       if (similarity > 0.8) {
//         _showSuccessDialog(similarity);
//       } else {
//         _showFailureDialog(similarity);
//       }
//     } catch (e) {
//       setState(() {
//         _status = 'เกิดข้อผิดพลาดในการตรวจสอบ';
//         _isVerifying = false;
//       });
//     }
//   }

//   void _showFailureDialog(double similarity) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             title: Row(
//               children: [
//                 Icon(Icons.error, color: Colors.red, size: 32),
//                 SizedBox(width: 12),
//                 Text('ยืนยันตัวตนไม่สำเร็จ'),
//               ],
//             ),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(Icons.face, size: 64, color: Colors.red),
//                 SizedBox(height: 16),
//                 Text(
//                   'ไม่สามารถยืนยันตัวตนได้ ❌',
//                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'ความแม่นยำ: ${(similarity * 100).toStringAsFixed(1)}%',
//                   style: TextStyle(fontSize: 16, color: Colors.grey[600]),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'กรุณาลองใหม่อีกครั้ง',
//                   style: TextStyle(fontSize: 14, color: Colors.grey[600]),
//                 ),
//               ],
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   _resetVerification();
//                 },
//                 child: Text('ลองใหม่', style: TextStyle(fontSize: 16)),
//               ),
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   Navigator.pop(context);
//                 },
//                 child: Text('ยกเลิก', style: TextStyle(fontSize: 16)),
//               ),
//             ],
//           ),
//     );
//   }

//   void _resetVerification() {
//     _timeoutTimer?.cancel();
//     setState(() {
//       _status = 'พร้อมสแกนใบหน้าเพื่อยืนยันตัวตน';
//       _isVerifying = false;
//     });
//     _startStepTimer();
//   }

//   InputImage? _convertCameraImage(CameraImage image, int rotation) {
//     try {
//       // ตรวจสอบ format ที่รองรับ
//       final inputImageFormat = InputImageFormatValue.fromRawValue(
//         image.format.raw,
//       );
//       if (inputImageFormat == null) {
//         print('Unsupported image format: ${image.format.raw}');
//         return null;
//       }

//       // สร้าง bytes array
//       final allBytes = WriteBuffer();
//       for (final plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();

//       final Size imageSize = Size(
//         image.width.toDouble(),
//         image.height.toDouble(),
//       );

//       final inputImageRotation =
//           InputImageRotationValue.fromRawValue(rotation) ??
//           InputImageRotation.rotation0deg;

//       final inputImageMetadata = InputImageMetadata(
//         size: imageSize,
//         rotation: inputImageRotation,
//         format: inputImageFormat,
//         bytesPerRow:
//             image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
//       );

//       return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
//     } catch (e) {
//       print('Error converting camera image: $e');
//       return null;
//     }
//   }

//   double _cosineSimilarity(List<double> v1, List<double> v2) {
//     double dot = 0;
//     double normA = 0;
//     double normB = 0;
//     for (int i = 0; i < v1.length; i++) {
//       dot += v1[i] * v2[i];
//       normA += v1[i] * v1[i];
//       normB += v2[i] * v2[i];
//     }
//     return dot / (sqrt(normA) * sqrt(normB));
//   }

//   @override
//   void dispose() {
//     _timeoutTimer?.cancel();
//     _controller?.dispose();
//     faceDetector.close();
//     super.dispose();
//   }

//   void _goToVerify() {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) => VerifyFaceScreen(cameras: widget.cameras),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_controller == null || !_controller!.value.isInitialized) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('ลงทะเบียนใบหน้า')),
//         body: Center(
//           child:
//               _currentStep == ScanStep.failed
//                   ? Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(
//                         Icons.camera_alt_outlined,
//                         size: 64,
//                         color: Colors.grey,
//                       ),
//                       SizedBox(height: 16),
//                       Text(_instruction, style: TextStyle(fontSize: 18)),
//                     ],
//                   )
//                   : CircularProgressIndicator(),
//         ),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('ลงทะเบียนใบหน้า'),
//         backgroundColor: _getStepColor(),
//       ),
//       body: Stack(
//         children: [
//           // Camera Preview
//           CameraPreview(_controller!),

//           // Face Detection Overlay
//           if (_currentStep != ScanStep.completed &&
//               _currentStep != ScanStep.failed)
//             Positioned.fill(child: CustomPaint(painter: FaceOverlayPainter())),

//           // Top Status Bar
//           Positioned(
//             top: 20,
//             left: 20,
//             right: 20,
//             child: Container(
//               padding: EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.black.withOpacity(0.7),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Row(
//                 children: [
//                   Icon(_getStepIcon(), color: _getStepColor(), size: 24),
//                   SizedBox(width: 12),
//                   Expanded(
//                     child: Text(
//                       _instruction,
//                       style: TextStyle(color: Colors.white, fontSize: 16),
//                     ),
//                   ),
//                   if (_currentStep != ScanStep.completed &&
//                       _currentStep != ScanStep.failed &&
//                       _currentStep != ScanStep.timeout)
//                     Container(
//                       padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       decoration: BoxDecoration(
//                         color: _remainingTime <= 3 ? Colors.red : Colors.orange,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: Text(
//                         '$_remainingTime s',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//           ),

//           // Bottom Button
//           Positioned(
//             bottom: 60,
//             left: 40,
//             right: 40,
//             child: ElevatedButton(
//               onPressed: _faceRegistered ? _goToVerify : null,
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: _faceRegistered ? Colors.green : Colors.grey,
//                 padding: EdgeInsets.symmetric(vertical: 16),
//               ),
//               child: Text(
//                 'ไปยังหน้ายืนยันตัวตน',
//                 style: TextStyle(fontSize: 16),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Color _getStepColor() {
//     switch (_currentStep) {
//       case ScanStep.completed:
//         return Colors.green;
//       case ScanStep.failed:
//       case ScanStep.timeout:
//         return Colors.red;
//       default:
//         return Colors.blue;
//     }
//   }

//   IconData _getStepIcon() {
//     switch (_currentStep) {
//       case ScanStep.faceDetection:
//         return Icons.face;
//       case ScanStep.removeGlasses:
//         return Icons.remove_red_eye;
//       case ScanStep.removeMask:
//         return Icons.masks;
//       case ScanStep.lookStraight:
//         return Icons.visibility;
//       case ScanStep.turnLeft:
//         return Icons.arrow_back;
//       case ScanStep.turnRight:
//         return Icons.arrow_forward;
//       case ScanStep.blink:
//         return Icons.remove_red_eye_outlined;
//       case ScanStep.completed:
//         return Icons.check_circle;
//       case ScanStep.failed:
//       case ScanStep.timeout:
//         return Icons.error;
//       default:
//         return Icons.camera_alt;
//     }
//   }
// }

// // Custom Painter สำหรับวาดกรอบใบหน้า
// class FaceOverlayPainter extends CustomPainter {
//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint =
//         Paint()
//           ..color = Colors.white
//           ..style = PaintingStyle.stroke
//           ..strokeWidth = 3.0;

//     final center = Offset(size.width / 2, size.height / 2);
//     final ovalRect = Rect.fromCenter(
//       center: center,
//       width: size.width * 0.7,
//       height: size.height * 0.5,
//     );

//     canvas.drawOval(ovalRect, paint);

//     // วาดเส้นมุม
//     final cornerLength = 30.0;
//     final corners = [
//       ovalRect.topLeft,
//       ovalRect.topRight,
//       ovalRect.bottomLeft,
//       ovalRect.bottomRight,
//     ];

//     for (final corner in corners) {
//       // วาดเส้นมุม
//       if (corner == ovalRect.topLeft) {
//         canvas.drawLine(corner, corner + Offset(cornerLength, 0), paint);
//         canvas.drawLine(corner, corner + Offset(0, cornerLength), paint);
//       } else if (corner == ovalRect.topRight) {
//         canvas.drawLine(corner, corner + Offset(-cornerLength, 0), paint);
//         canvas.drawLine(corner, corner + Offset(0, cornerLength), paint);
//       } else if (corner == ovalRect.bottomLeft) {
//         canvas.drawLine(corner, corner + Offset(cornerLength, 0), paint);
//         canvas.drawLine(corner, corner + Offset(0, -cornerLength), paint);
//       } else if (corner == ovalRect.bottomRight) {
//         canvas.drawLine(corner, corner + Offset(-cornerLength, 0), paint);
//         canvas.drawLine(corner, corner + Offset(0, -cornerLength), paint);
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }

// // VerifyFaceScreen - หน้าสำหรับยืนยันตัวตน
// class VerifyFaceScreen extends StatefulWidget {
//   final List<CameraDescription> cameras;
//   const VerifyFaceScreen({super.key, required this.cameras});

//   @override
//   State<VerifyFaceScreen> createState() => _VerifyFaceScreenState();
// }

// class _VerifyFaceScreenState extends State<VerifyFaceScreen> {
//   CameraController? _controller;
//   bool _isDetecting = false;
//   final faceDetector = FaceDetector(
//     options: FaceDetectorOptions(
//       enableClassification: false,
//       performanceMode: FaceDetectorMode.fast,
//     ),
//   );
//   final _storage = const FlutterSecureStorage();
//   String _status = 'พร้อมสแกนใบหน้าเพื่อยืนยันตัวตน';
//   static const platform = MethodChannel('face_recognition');

//   Timer? _timeoutTimer;
//   int _remainingTime = 10;
//   bool _isVerifying = false;

//   @override
//   void initState() {
//     super.initState();
//     _initializeCamera();
//   }

//   void _initializeCamera() {
//     CameraDescription? frontCamera;
//     try {
//       frontCamera = widget.cameras.firstWhere(
//         (camera) => camera.lensDirection == CameraLensDirection.front,
//       );
//     } catch (e) {
//       if (widget.cameras.isNotEmpty) {
//         frontCamera = widget.cameras.first;
//       }
//     }

//     if (frontCamera != null) {
//       _controller = CameraController(
//         frontCamera,
//         ResolutionPreset.medium,
//         enableAudio: false,
//       );
//       _controller!
//           .initialize()
//           .then((_) {
//             if (!mounted) return;
//             _controller!.startImageStream(_processCameraImage);
//             setState(() {});
//             _startTimeout();
//           })
//           .catchError((error) {
//             print('Camera initialization error: $error');
//             setState(() {
//               _status = 'ไม่สามารถเข้าถึงกล้องได้';
//             });
//           });
//     } else {
//       setState(() {
//         _status = 'ไม่พบกล้อง';
//       });
//     }
//   }

//   void _startTimeout() {
//     _remainingTime = 10;
//     _timeoutTimer = Timer.periodic(Duration(seconds: 1), (timer) {
//       if (!mounted) return;
//       setState(() {
//         _remainingTime--;
//       });

//       if (_remainingTime <= 0) {
//         _handleTimeout();
//       }
//     });
//   }

//   void _handleTimeout() {
//     _timeoutTimer?.cancel();
//     setState(() {
//       _status = 'หมดเวลา กรุณาลองใหม่อีกครั้ง';
//       _isVerifying = false;
//     });

//     _showTimeoutDialog();
//   }

//   void _showTimeoutDialog() {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             title: Text('หมดเวลา'),
//             content: Text('การยืนยันตัวตนหมดเวลา กรุณาลองใหม่อีกครั้ง'),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   _resetVerification();
//                 },
//                 child: Text('ลองใหม่'),
//               ),
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   Navigator.pop(context);
//                 },
//                 child: Text('ยกเลิก'),
//               ),
//             ],
//           ),
//     );
//   }

//   void _resetVerification() {
//     _timeoutTimer?.cancel();
//     setState(() {
//       _status = 'พร้อมสแกนใบหน้าเพื่อยืนยันตัวตน';
//       _isVerifying = false;
//     });
//     _startTimeout();
//   }

//   void _processCameraImage(CameraImage image) async {
//     if (_isDetecting || _isVerifying) return;
//     _isDetecting = true;

//     try {
//       final inputImage = _convertCameraImage(
//         image,
//         _controller?.description.sensorOrientation ?? 0,
//       );

//       if (inputImage != null) {
//         final faces = await faceDetector.processImage(inputImage);

//         if (faces.isNotEmpty) {
//           if (!_isVerifying) {
//             _isVerifying = true;
//             _timeoutTimer?.cancel();

//             setState(() {
//               _status = 'กำลังตรวจสอบใบหน้า...';
//             });

//             await _performVerification();
//           }
//         } else {
//           setState(() => _status = 'ไม่พบใบหน้าในกล้อง');
//         }
//       }
//     } catch (e) {
//       print('Error: $e');
//       setState(() => _status = 'เกิดข้อผิดพลาดในการประมวลผลภาพ');
//     }

//     _isDetecting = false;
//   }

//   Future<Map<String, dynamic>?> _getFaceResultFromNative() async {
//     try {
//       final result = await platform.invokeMethod('scanFace');
//       if (result != null && result is Map) {
//         return Map<String, dynamic>.from(result);
//       }
//     } catch (e) {}
//     return null;
//   }

//   Future<void> _performVerification() async {
//     try {
//       final result = await _getFaceResultFromNative();
//       final storedJson = await _storage.read(key: 'face_vector');
//       final livenessPassed =
//           (await _storage.read(key: 'liveness_passed')) == 'true';

//       if (storedJson == null) {
//         setState(() {
//           _status = 'ยังไม่มีข้อมูลใบหน้าที่ลงทะเบียน';
//           _isVerifying = false;
//         });
//         return;
//       }

//       if (!livenessPassed) {
//         setState(() {
//           _status = 'ข้อมูลใบหน้าไม่ผ่านการตรวจสอบ Liveness';
//           _isVerifying = false;
//         });
//         return;
//       }

//       if (result == null ||
//           result['liveness'] != true ||
//           result['vector'] == null) {
//         setState(() {
//           _status = 'Liveness ไม่ผ่าน หรือไม่สามารถดึงข้อมูลใบหน้าได้';
//           _isVerifying = false;
//         });
//         return;
//       }

//       final newVector = List<double>.from(result['vector']);
//       final storedVector = List<double>.from(jsonDecode(storedJson));
//       final similarity = _cosineSimilarity(storedVector, newVector);

//       setState(() {
//         _isVerifying = false;
//       });

//       if (similarity > 0.8) {
//         _showSuccessDialog(similarity);
//       } else {
//         _showFailureDialog(similarity);
//       }
//     } catch (e) {
//       setState(() {
//         _status = 'เกิดข้อผิดพลาดในการตรวจสอบ';
//         _isVerifying = false;
//       });
//     }
//   }

//   void _showSuccessDialog(double similarity) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             title: Row(
//               children: [
//                 Icon(Icons.check_circle, color: Colors.green, size: 32),
//                 SizedBox(width: 12),
//                 Text('ยืนยันตัวตนสำเร็จ'),
//               ],
//             ),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(Icons.face, size: 64, color: Colors.green),
//                 SizedBox(height: 16),
//                 Text(
//                   'ยืนยันตัวตนผ่าน! 🎉',
//                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'ความแม่นยำ: ${(similarity * 100).toStringAsFixed(1)}%',
//                   style: TextStyle(fontSize: 16, color: Colors.grey[600]),
//                 ),
//               ],
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   Navigator.pop(context);
//                 },
//                 child: Text('ตกลง', style: TextStyle(fontSize: 16)),
//               ),
//             ],
//           ),
//     );
//   }

//   void _showFailureDialog(double similarity) {
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             title: Row(
//               children: [
//                 Icon(Icons.error, color: Colors.red, size: 32),
//                 SizedBox(width: 12),
//                 Text('ยืนยันตัวตนไม่สำเร็จ'),
//               ],
//             ),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(Icons.face, size: 64, color: Colors.red),
//                 SizedBox(height: 16),
//                 Text(
//                   'ไม่สามารถยืนยันตัวตนได้ ❌',
//                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'ความแม่นยำ: ${(similarity * 100).toStringAsFixed(1)}%',
//                   style: TextStyle(fontSize: 16, color: Colors.grey[600]),
//                 ),
//                 SizedBox(height: 8),
//                 Text(
//                   'กรุณาลองใหม่อีกครั้ง',
//                   style: TextStyle(fontSize: 14, color: Colors.grey[600]),
//                 ),
//               ],
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   _resetVerification();
//                 },
//                 child: Text('ลองใหม่', style: TextStyle(fontSize: 16)),
//               ),
//               TextButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   Navigator.pop(context);
//                 },
//                 child: Text('ยกเลิก', style: TextStyle(fontSize: 16)),
//               ),
//             ],
//           ),
//     );
//   }

//   InputImage? _convertCameraImage(CameraImage image, int rotation) {
//     try {
//       // ตรวจสอบ format ที่รองรับ
//       final inputImageFormat = InputImageFormatValue.fromRawValue(
//         image.format.raw,
//       );
//       if (inputImageFormat == null) {
//         print('Unsupported image format: ${image.format.raw}');
//         return null;
//       }

//       // สร้าง bytes array
//       final allBytes = WriteBuffer();
//       for (final plane in image.planes) {
//         allBytes.putUint8List(plane.bytes);
//       }
//       final bytes = allBytes.done().buffer.asUint8List();

//       final Size imageSize = Size(
//         image.width.toDouble(),
//         image.height.toDouble(),
//       );

//       final inputImageRotation =
//           InputImageRotationValue.fromRawValue(rotation) ??
//           InputImageRotation.rotation0deg;

//       final inputImageMetadata = InputImageMetadata(
//         size: imageSize,
//         rotation: inputImageRotation,
//         format: inputImageFormat,
//         bytesPerRow:
//             image.planes.isNotEmpty ? image.planes[0].bytesPerRow : image.width,
//       );

//       return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
//     } catch (e) {
//       print('Error converting camera image: $e');
//       return null;
//     }
//   }

//   double _cosineSimilarity(List<double> v1, List<double> v2) {
//     double dot = 0;
//     double normA = 0;
//     double normB = 0;
//     for (int i = 0; i < v1.length; i++) {
//       dot += v1[i] * v2[i];
//       normA += v1[i] * v1[i];
//       normB += v2[i] * v2[i];
//     }
//     return dot / (sqrt(normA) * sqrt(normB));
//   }

//   @override
//   void dispose() {
//     _timeoutTimer?.cancel();
//     _controller?.dispose();
//     faceDetector.close();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_controller == null || !_controller!.value.isInitialized) {
//       return Scaffold(
//         appBar: AppBar(title: const Text('ยืนยันตัวตนด้วยใบหน้า')),
//         body: Center(
//           child:
//               _status == 'ไม่พบกล้อง' || _status == 'ไม่สามารถเข้าถึงกล้องได้'
//                   ? Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(
//                         Icons.camera_alt_outlined,
//                         size: 64,
//                         color: Colors.grey,
//                       ),
//                       SizedBox(height: 16),
//                       Text(_status, style: TextStyle(fontSize: 18)),
//                     ],
//                   )
//                   : CircularProgressIndicator(),
//         ),
//       );
//     }

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('ยืนยันตัวตนด้วยใบหน้า'),
//         backgroundColor: _isVerifying ? Colors.orange : Colors.blue,
//       ),
//       body: Stack(
//         children: [
//           // Camera Preview
//           CameraPreview(_controller!),

//           // Face Detection Overlay
//           Positioned.fill(child: CustomPaint(painter: FaceOverlayPainter())),

//           // Top Status Bar
//           Positioned(
//             top: 20,
//             left: 20,
//             right: 20,
//             child: Container(
//               padding: EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.black.withOpacity(0.7),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Row(
//                 children: [
//                   Icon(
//                     _isVerifying
//                         ? Icons.refresh
//                         : Icons.face_retouching_natural,
//                     color: _isVerifying ? Colors.orange : Colors.blue,
//                     size: 24,
//                   ),
//                   SizedBox(width: 12),
//                   Expanded(
//                     child: Text(
//                       _status,
//                       style: TextStyle(color: Colors.white, fontSize: 16),
//                     ),
//                   ),
//                   if (!_isVerifying && _remainingTime > 0)
//                     Container(
//                       padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                       decoration: BoxDecoration(
//                         color: _remainingTime <= 3 ? Colors.red : Colors.orange,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: Text(
//                         '$_remainingTime s',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                   if (_isVerifying)
//                     SizedBox(
//                       width: 20,
//                       height: 20,
//                       child: CircularProgressIndicator(
//                         strokeWidth: 2,
//                         valueColor: AlwaysStoppedAnimation<Color>(
//                           Colors.orange,
//                         ),
//                       ),
//                     ),
//                 ],
//               ),
//             ),
//           ),

//           // Instructions
//           Positioned(
//             bottom: 100,
//             left: 20,
//             right: 20,
//             child: Container(
//               padding: EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: Colors.black.withOpacity(0.6),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Column(
//                 children: [
//                   Text(
//                     'วิธีใช้:',
//                     style: TextStyle(
//                       color: Colors.white,
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   SizedBox(height: 8),
//                   Text(
//                     '1. วางใบหน้าในกรอบกล้อง\n2. มองตรงไปที่กล้อง\n3. รอให้ระบบตรวจสอบ',
//                     style: TextStyle(color: Colors.white70, fontSize: 14),
//                     textAlign: TextAlign.center,
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
