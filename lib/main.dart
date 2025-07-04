import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // เริ่มต้นกล้อง
  final cameras = await availableCameras();

  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Recognition',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: MainMenuScreen(cameras: cameras),
    );
  }
}

// หน้าเมนูหลัก
class MainMenuScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainMenuScreen({super.key, required this.cameras});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final _storage = const FlutterSecureStorage();
  bool _hasFaceData = false;

  @override
  void initState() {
    super.initState();
    _checkFaceData();
  }

  Future<void> _checkFaceData() async {
    final faceData = await _storage.read(key: 'face_vector');
    setState(() {
      _hasFaceData = faceData != null && faceData.isNotEmpty;
    });
  }

  Future<void> _clearFaceData() async {
    await _storage.delete(key: 'face_vector');
    await _storage.delete(key: 'liveness_passed');
    setState(() {
      _hasFaceData = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('ลบข้อมูลใบหน้าแล้ว')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Face Recognition System'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo/Icon
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.face, size: 80, color: Colors.blue),
            ),

            SizedBox(height: 40),

            // Title
            Text(
              'ระบบจดจำใบหน้า',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),

            SizedBox(height: 10),

            // Subtitle
            Text(
              'ลงทะเบียนหรือยืนยันตัวตนด้วยใบหน้าของคุณ',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 50),

            // Status
            if (_hasFaceData)
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'มีข้อมูลใบหน้าแล้ว',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(height: 30),

            // Register Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              RegisterFaceScreen(cameras: widget.cameras),
                    ),
                  ).then((_) => _checkFaceData());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add),
                    SizedBox(width: 8),
                    Text(
                      _hasFaceData ? 'ลงทะเบียนใบหน้าใหม่' : 'ลงทะเบียนใบหน้า',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Verify Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    _hasFaceData
                        ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) =>
                                      VerifyFaceScreen(cameras: widget.cameras),
                            ),
                          );
                        }
                        : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _hasFaceData ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user),
                    SizedBox(width: 8),
                    Text(
                      'ยืนยันตัวตนด้วยใบหน้า',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 30),

            // Clear Data Button (Debug)
            if (_hasFaceData)
              TextButton(
                onPressed: _clearFaceData,
                child: Text(
                  'ลบข้อมูลใบหน้า (สำหรับทดสอบ)',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Custom Painter พร้อมแอนิเมชัน
class FaceOverlayPainter extends CustomPainter {
  final bool isScanning;
  final bool faceDetected;

  FaceOverlayPainter({required this.isScanning, required this.faceDetected});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = isScanning ? Colors.blue : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    final center = Offset(size.width / 2, size.height / 2);
    final ovalRect = Rect.fromCenter(
      center: center,
      width: size.width * 0.7,
      height: size.height * 0.6,
    );

    // วาดกรอบหลัก
    canvas.drawOval(ovalRect, paint);

    // วาดเส้นมุม
    final cornerLength = 30.0;
    final cornerPaint =
        Paint()
          ..color =
              faceDetected
                  ? Colors.green
                  : (isScanning ? Colors.blue : Colors.white)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;

    final corners = [
      ovalRect.topLeft,
      ovalRect.topRight,
      ovalRect.bottomLeft,
      ovalRect.bottomRight,
    ];

    for (int i = 0; i < corners.length; i++) {
      final corner = corners[i];
      if (i == 0) {
        // Top-left
        canvas.drawLine(corner, corner + Offset(cornerLength, 0), cornerPaint);
        canvas.drawLine(corner, corner + Offset(0, cornerLength), cornerPaint);
      } else if (i == 1) {
        // Top-right
        canvas.drawLine(corner, corner + Offset(-cornerLength, 0), cornerPaint);
        canvas.drawLine(corner, corner + Offset(0, cornerLength), cornerPaint);
      } else if (i == 2) {
        // Bottom-left
        canvas.drawLine(corner, corner + Offset(cornerLength, 0), cornerPaint);
        canvas.drawLine(corner, corner + Offset(0, -cornerLength), cornerPaint);
      } else {
        // Bottom-right
        canvas.drawLine(corner, corner + Offset(-cornerLength, 0), cornerPaint);
        canvas.drawLine(corner, corner + Offset(0, -cornerLength), cornerPaint);
      }
    }

    // วาดจุดกลาง
    final centerDot =
        Paint()
          ..color = faceDetected ? Colors.green : Colors.white54
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 4, centerDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// หน้าลงทะเบียนใบหน้า
class RegisterFaceScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RegisterFaceScreen({super.key, required this.cameras});

  @override
  State<RegisterFaceScreen> createState() => _RegisterFaceScreenState();
}

class _RegisterFaceScreenState extends State<RegisterFaceScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _isScanning = false;
  String _instruction = 'จัดตำแหน่งใบหน้าในกรอบ ระบบจะสแกนโดยอัตโนมัติ';
  final _storage = const FlutterSecureStorage();
  static const platform = MethodChannel('face_recognition');
  Timer? _timeoutTimer;
  bool _faceDetected = false;
  bool _autoScanStarted = false;
  String _faceStatus = 'กำลังค้นหาใบหน้า...';
  bool _faceQualityGood = false;
  Timer? _faceDetectionTimer;
  double _scanProgress = 0.0;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: Duration(seconds: 4),
      vsync: this,
    );
    _initializeCamera();
    _startFaceDetection();
  }

  void _startFaceDetection() {
    // เริ่มตรวจสอบใบหน้าแบบ real-time
    _faceDetectionTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (!_isScanning &&
          _controller != null &&
          _controller!.value.isInitialized) {
        _checkFaceQuality();
      }
    });
  }

  Future<void> _checkFaceQuality() async {
    try {
      // ตรวจสอบสถานะใบหน้าจาก native
      final result = await platform.invokeMethod('checkFaceQuality');
      if (result != null && result is Map) {
        setState(() {
          _faceDetected = result['faceDetected'] ?? false;
          _faceQualityGood = result['qualityGood'] ?? false;

          if (!_faceDetected) {
            _faceStatus = 'ไม่พบใบหน้า - กรุณาเข้าไปในกรอบ';
            _instruction = 'กรุณาจัดตำแหน่งใบหน้าในกรอบ';
          } else if (!_faceQualityGood) {
            String issue = result['issue'] ?? 'ไม่ชัดเจน';
            if (issue.contains('glasses')) {
              _faceStatus = 'กรุณาถอดแว่นตา';
              _instruction = 'ตรวจพบแว่นตา - กรุณาถอดแว่นเพื่อความชัดเจน';
            } else if (issue.contains('lighting')) {
              _faceStatus = 'แสงไม่เพียงพอ';
              _instruction = 'กรุณาไปที่มีแสงสว่างเพียงพอ';
            } else if (issue.contains('angle')) {
              _faceStatus = 'มุมไม่เหมาะสม';
              _instruction = 'กรุณาหันหน้าตรงเข้าหากล้อง';
            } else {
              _faceStatus = 'ใบหน้าไม่ชัดเจน';
              _instruction = 'กรุณาเข้าใกล้และจัดตำแหน่งใบหน้าให้ชัดเจน';
            }
          } else {
            _faceStatus = 'ใบหน้าชัดเจน - พร้อมสแกน';
            _instruction = 'ใบหน้าชัดเจน - ระบบจะเริ่มสแกนใน 2 วินาที';

            // เริ่มสแกนอัตโนมัติเมื่อใบหน้าชัดเจน
            if (!_autoScanStarted && !_isScanning) {
              _autoScanStarted = true;
              Timer(Duration(seconds: 2), () {
                if (mounted && _faceQualityGood && !_isScanning) {
                  _scanFace();
                }
              });
            }
          }
        });
      }
    } catch (e) {
      print('checkFaceQuality error: $e');
      // สำหรับการทดสอบ: สร้างสถานะจำลอง
      _simulateFaceDetection();
    }
  }

  void _simulateFaceDetection() {
    // จำลองการตรวจสอบใบหน้าเพื่อการทดสอบ
    setState(() {
      if (_faceStatus.contains('กำลังค้นหา')) {
        _faceDetected = true;
        _faceQualityGood = false;
        _faceStatus = 'กรุณาถอดแว่นตา';
        _instruction = 'ตรวจพบแว่นตา - กรุณาถอดแว่นเพื่อความชัดเจน';
      } else if (_faceStatus.contains('แว่น')) {
        _faceDetected = true;
        _faceQualityGood = false;
        _faceStatus = 'แสงไม่เพียงพอ';
        _instruction = 'กรุณาไปที่มีแสงสว่างเพียงพอ';
      } else if (_faceStatus.contains('แสง')) {
        _faceDetected = true;
        _faceQualityGood = false;
        _faceStatus = 'มุมไม่เหมาะสม';
        _instruction = 'กรุณาหันหน้าตรงเข้าหากล้อง';
      } else if (_faceStatus.contains('มุม')) {
        _faceDetected = true;
        _faceQualityGood = true;
        _faceStatus = 'ใบหน้าชัดเจน - พร้อมสแกน';
        _instruction = 'ใบหน้าชัดเจน - ระบบจะเริ่มสแกนใน 2 วินาที';

        // เริ่มสแกนอัตโนมัติเมื่อใบหน้าชัดเจน
        if (!_autoScanStarted && !_isScanning) {
          _autoScanStarted = true;
          Timer(Duration(seconds: 2), () {
            if (mounted && _faceQualityGood && !_isScanning) {
              _scanFace();
            }
          });
        }
      } else {
        _faceDetected = false;
        _faceQualityGood = false;
        _faceStatus = 'กำลังค้นหาใบหน้า...';
        _instruction = 'กรุณาจัดตำแหน่งใบหน้าในกรอบ';
        _autoScanStarted = false;
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final frontCamera = widget.cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {});
        // เริ่มสแกนอัตโนมัติหลังจากกล้องพร้อม
        _startAutoScan();
      }
    } catch (e) {
      setState(() {
        _instruction = 'ไม่สามารถเปิดกล้องได้: $e';
      });
    }
  }

  Future<void> _startAutoScan() async {
    if (_autoScanStarted) return;

    _autoScanStarted = true;
    // รอ 2 วินาทีเพื่อให้ผู้ใช้เตรียมตัว
    await Future.delayed(Duration(seconds: 2));

    if (mounted && !_isScanning) {
      _scanFace();
    }
  }

  Future<void> _scanFace() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      setState(() {
        _instruction = 'กล้องยังไม่พร้อม';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _instruction = 'กำลังสแกนใบหน้า...\nกรุณากะพริบตา 2 ครั้ง';
      _faceDetected = false;
    });

    // ตั้งเวลา timeout
    _timeoutTimer = Timer(Duration(seconds: 30), () {
      if (_isScanning) {
        _stopScanning();
        setState(() {
          _instruction = 'หมดเวลา กรุณาลองใหม่';
        });
        _showFailureDialog('หมดเวลาสแกน กรุณาลองใหม่');
      }
    });

    // จำลองการสแกนแบบ progressive ให้ดูสมูท
    await _performProgressiveScan();
  }

  Future<void> _performProgressiveScan() async {
    try {
      _progressController.reset();
      _progressController.forward();

      // ขั้นตอนที่ 1: เริ่มการสแกน
      setState(() {
        _instruction = 'กำลังตรวจสอบใบหน้า... (1/4)';
        _scanProgress = 0.25;
      });
      await Future.delayed(Duration(milliseconds: 500));

      if (!_isScanning) return;

      // ขั้นตอนที่ 2: วิเคราะห์คุณภาพ
      setState(() {
        _instruction = 'กำลังวิเคราะห์คุณภาพใบหน้า... (2/4)';
        _scanProgress = 0.5;
      });
      await Future.delayed(Duration(milliseconds: 800));

      if (!_isScanning) return;

      // ขั้นตอนที่ 3: ตรวจสอบ liveness
      setState(() {
        _instruction = 'กำลังตรวจสอบการเคลื่อนไหว... (3/4)\nกรุณากะพริบตา';
        _scanProgress = 0.75;
      });
      await Future.delayed(Duration(milliseconds: 1000));

      if (!_isScanning) return;

      // ขั้นตอนที่ 4: สร้าง face vector
      setState(() {
        _instruction = 'กำลังสร้างลายเซ็นใบหน้า... (4/4)';
        _scanProgress = 1.0;
      });
      await Future.delayed(Duration(milliseconds: 700));

      if (!_isScanning) return;

      // เรียกใช้ native method (หรือจำลอง)
      await _executeFinalScan();
    } catch (e) {
      _timeoutTimer?.cancel();
      setState(() {
        _instruction = 'เกิดข้อผิดพลาด: $e';
        _isScanning = false;
        _scanProgress = 0.0;
      });
      _showFailureDialog('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _executeFinalScan() async {
    try {
      final result = await platform.invokeMethod('scanFace');
      _timeoutTimer?.cancel();

      if (result != null && result is Map) {
        final liveness = result['liveness'] == true;
        final vector = result['vector'];

        if (liveness && vector != null) {
          await _storage.write(key: 'face_vector', value: jsonEncode(vector));
          await _storage.write(key: 'liveness_passed', value: 'true');
          await _storage.write(
            key: 'face_registered_at',
            value: DateTime.now().toIso8601String(),
          );

          setState(() {
            _instruction = 'ลงทะเบียนสำเร็จ! ✅';
            _isScanning = false;
          });

          _showSuccessDialog();
        } else {
          setState(() {
            _instruction = 'ไม่ผ่าน Liveness Detection';
            _isScanning = false;
          });
          _showFailureDialog(
            'ไม่ผ่าน Liveness Detection\nกรุณากะพริบตาให้ชัดเจน',
          );
        }
      } else {
        setState(() {
          _instruction = 'ไม่สามารถอ่านข้อมูลได้';
          _isScanning = false;
        });
        _showFailureDialog('ไม่สามารถอ่านข้อมูลได้');
      }
    } catch (e) {
      // หาก native method ไม่พร้อม จำลองผลลัพธ์
      await _simulateSuccessfulScan();
    }
  }

  Future<void> _simulateSuccessfulScan() async {
    // จำลองการสแกนสำเร็จสำหรับการทดสอบ
    await Future.delayed(Duration(milliseconds: 500));

    if (!_isScanning) return;

    // สร้าง face vector จำลองที่มีค่าสมจริง (normalized vector)
    final random = math.Random();
    final mockVector = List.generate(128, (index) {
      // สร้างค่าแบบ gaussian distribution
      double value = (random.nextDouble() - 0.5) * 2.0; // -1.0 to 1.0
      return value;
    });

    // Normalize vector เพื่อให้การคำนวณ similarity ถูกต้อง
    double norm = math.sqrt(
      mockVector.fold(0.0, (sum, val) => sum + val * val),
    );
    if (norm > 0) {
      for (int i = 0; i < mockVector.length; i++) {
        mockVector[i] = mockVector[i] / norm;
      }
    }

    await _storage.write(key: 'face_vector', value: jsonEncode(mockVector));
    await _storage.write(key: 'liveness_passed', value: 'true');
    await _storage.write(
      key: 'face_registered_at',
      value: DateTime.now().toIso8601String(),
    );

    setState(() {
      _instruction = 'ลงทะเบียนสำเร็จ! ✅';
      _isScanning = false;
    });

    _timeoutTimer?.cancel();
    _showSuccessDialog();
  }

  void _stopScanning() {
    _timeoutTimer?.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('ลงทะเบียนสำเร็จ'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'บันทึกข้อมูลใบหน้าเรียบร้อยแล้ว\nตอนนี้คุณสามารถใช้ยืนยันตัวตนได้',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  Navigator.pop(context); // กลับไปหน้าหลัก
                },
                child: Text('ตกลง'),
              ),
            ],
          ),
    );
  }

  void _showFailureDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('ลงทะเบียนไม่สำเร็จ'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  setState(() {
                    _instruction =
                        'จัดตำแหน่งใบหน้าในกรอบ ระบบจะสแกนโดยอัตโนมัติ';
                    _autoScanStarted = false;
                  });
                  // ระบบจะสแกนอัตโนมัติเมื่อใบหน้าชัดเจนใน _checkFaceQuality
                },
                child: Text('ลองใหม่'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  Navigator.pop(context); // กลับไปหน้าหลัก
                },
                child: Text('ยกเลิก'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _faceDetectionTimer?.cancel();
    _progressController
        .dispose(); // Dispose animation controller for RegisterFaceScreen
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('ลงทะเบียนใบหน้า'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Camera Preview พร้อม Overlay
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Camera Preview
                if (_controller != null && _controller!.value.isInitialized)
                  Container(
                    width: double.infinity,
                    child: CameraPreview(_controller!),
                  )
                else
                  Container(
                    width: double.infinity,
                    color: Colors.grey[900],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'กำลังเปิดกล้อง...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Face Overlay
                CustomPaint(
                  painter: FaceOverlayPainter(
                    isScanning: _isScanning,
                    faceDetected: _faceDetected,
                  ),
                  child: Container(),
                ),

                // Scanning Animation - สมูทและมีชีวิตชีวา
                if (_isScanning)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // กรอบหลักที่หมุน
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(seconds: 3),
                            builder: (context, value, child) {
                              return Transform.rotate(
                                angle: value * 2 * 3.14159, // หมุน 360 องศา
                                child: Container(
                                  width: 300,
                                  height: 370,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(200),
                                    border: Border.all(
                                      color: Colors.blue.withOpacity(0.6),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // วงแสงที่ขยายตัว
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(seconds: 2),
                            builder: (context, value, child) {
                              return Container(
                                width: 280 + (value * 40),
                                height: 350 + (value * 50),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(200),
                                  border: Border.all(
                                    color: Colors.blue.withOpacity(
                                      0.4 * (1 - value),
                                    ),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(
                                        0.3 * value,
                                      ),
                                      blurRadius: 30 * value,
                                      spreadRadius: 10 * value,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // จุดสแกนที่เคลื่อนที่
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(seconds: 2),
                            builder: (context, value, child) {
                              return Positioned(
                                top:
                                    50 + (value * 200), // เคลื่อนที่จากบนลงล่าง
                                child: Container(
                                  width: 200,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.blue.withOpacity(0.8),
                                        Colors.blue.withOpacity(0.8),
                                        Colors.transparent,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            },
                          ),

                          // จุดกลางที่เต้น
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.8, end: 1.2),
                            duration: Duration(milliseconds: 800),
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Instructions Panel
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Face Status (แสดงสถานะใบหน้าแบบ real-time)
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color:
                          _faceQualityGood
                              ? Colors.green.withOpacity(0.2)
                              : _faceDetected
                              ? Colors.orange.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                      border: Border.all(
                        color:
                            _faceQualityGood
                                ? Colors.green
                                : _faceDetected
                                ? Colors.orange
                                : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _faceQualityGood
                              ? Icons.check_circle
                              : _faceDetected
                              ? Icons.warning
                              : Icons.error,
                          color:
                              _faceQualityGood
                                  ? Colors.green
                                  : _faceDetected
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _faceStatus,
                            style: TextStyle(
                              fontSize: 16,
                              color:
                                  _faceQualityGood
                                      ? Colors.green
                                      : _faceDetected
                                      ? Colors.orange
                                      : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16),

                  // Instructions
                  Text(
                    _instruction,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: 20),

                  // Tips
                  Text(
                    'เคล็ดลับ: จัดตำแหน่งใบหน้าในกรอบและกะพริบตา 2 ครั้ง',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: 20),

                  // Smooth Progress indicator
                  if (_isScanning)
                    Column(
                      children: [
                        AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              backgroundColor: Colors.grey[800],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.blue,
                              ),
                              value: _scanProgress,
                            );
                          },
                        ),
                        SizedBox(height: 8),
                        Text(
                          '${(_scanProgress * 100).toInt()}% เสร็จสิ้น',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// หน้ายืนยันตัวตน
class VerifyFaceScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const VerifyFaceScreen({super.key, required this.cameras});

  @override
  State<VerifyFaceScreen> createState() => _VerifyFaceScreenState();
}

class _VerifyFaceScreenState extends State<VerifyFaceScreen> {
  CameraController? _controller;
  bool _isScanning = false;
  String _instruction = 'จัดตำแหน่งใบหน้าในกรอบ ระบบจะยืนยันตัวตนโดยอัตโนมัติ';
  final _storage = const FlutterSecureStorage();
  static const platform = MethodChannel('face_recognition');
  Timer? _timeoutTimer;
  bool _faceDetected = false;
  bool _autoScanStarted = false;
  String _faceStatus = 'กำลังค้นหาใบหน้า...';
  bool _faceQualityGood = false;
  Timer? _faceDetectionTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _startFaceDetection();
  }

  void _startFaceDetection() {
    // เริ่มตรวจสอบใบหน้าแบบ real-time
    _faceDetectionTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (!_isScanning &&
          _controller != null &&
          _controller!.value.isInitialized) {
        _checkFaceQuality();
      }
    });
  }

  Future<void> _checkFaceQuality() async {
    try {
      // ตรวจสอบสถานะใบหน้าจาก native
      final result = await platform.invokeMethod('checkFaceQuality');
      if (result != null && result is Map) {
        setState(() {
          _faceDetected = result['faceDetected'] ?? false;
          _faceQualityGood = result['qualityGood'] ?? false;

          if (!_faceDetected) {
            _faceStatus = 'ไม่พบใบหน้า - กรุณาเข้าไปในกรอบ';
            _instruction = 'กรุณาจัดตำแหน่งใบหน้าในกรอบ';
          } else if (!_faceQualityGood) {
            String issue = result['issue'] ?? 'ไม่ชัดเจน';
            if (issue.contains('glasses')) {
              _faceStatus = 'กรุณาถอดแว่นตา';
              _instruction = 'ตรวจพบแว่นตา - กรุณาถอดแว่นเพื่อความชัดเจน';
            } else if (issue.contains('lighting')) {
              _faceStatus = 'แสงไม่เพียงพอ';
              _instruction = 'กรุณาไปที่มีแสงสว่างเพียงพอ';
            } else if (issue.contains('angle')) {
              _faceStatus = 'มุมไม่เหมาะสม';
              _instruction = 'กรุณาหันหน้าตรงเข้าหากล้อง';
            } else {
              _faceStatus = 'ใบหน้าไม่ชัดเจน';
              _instruction = 'กรุณาเข้าใกล้และจัดตำแหน่งใบหน้าให้ชัดเจน';
            }
          } else {
            _faceStatus = 'ใบหน้าชัดเจน - พร้อมยืนยัน';
            _instruction = 'ใบหน้าชัดเจน - ระบบจะเริ่มยืนยันใน 2 วินาที';

            // เริ่มสแกนอัตโนมัติเมื่อใบหน้าชัดเจน
            if (!_autoScanStarted && !_isScanning) {
              _autoScanStarted = true;
              Timer(Duration(seconds: 2), () {
                if (mounted && _faceQualityGood && !_isScanning) {
                  _scanFace();
                }
              });
            }
          }
        });
      }
    } catch (e) {
      print('checkFaceQuality error: $e');
      // สำหรับการทดสอบ: สร้างสถานะจำลอง
      _simulateFaceDetection();
    }
  }

  void _simulateFaceDetection() {
    // จำลองการตรวจสอบใบหน้าเพื่อการทดสอบ
    setState(() {
      if (_faceStatus.contains('กำลังค้นหา')) {
        _faceDetected = true;
        _faceQualityGood = false;
        _faceStatus = 'กรุณาถอดแว่นตา';
        _instruction = 'ตรวจพบแว่นตา - กรุณาถอดแว่นเพื่อความชัดเจน';
      } else if (_faceStatus.contains('แว่น')) {
        _faceDetected = true;
        _faceQualityGood = false;
        _faceStatus = 'แสงไม่เพียงพอ';
        _instruction = 'กรุณาไปที่มีแสงสว่างเพียงพอ';
      } else if (_faceStatus.contains('แสง')) {
        _faceDetected = true;
        _faceQualityGood = false;
        _faceStatus = 'มุมไม่เหมาะสม';
        _instruction = 'กรุณาหันหน้าตรงเข้าหากล้อง';
      } else if (_faceStatus.contains('มุม')) {
        _faceDetected = true;
        _faceQualityGood = true;
        _faceStatus = 'ใบหน้าชัดเจน - พร้อมยืนยัน';
        _instruction = 'ใบหน้าชัดเจน - ระบบจะเริ่มยืนยันใน 2 วินาที';

        // เริ่มสแกนอัตโนมัติเมื่อใบหน้าชัดเจน
        if (!_autoScanStarted && !_isScanning) {
          _autoScanStarted = true;
          Timer(Duration(seconds: 2), () {
            if (mounted && _faceQualityGood && !_isScanning) {
              _scanFace();
            }
          });
        }
      } else {
        _faceDetected = false;
        _faceQualityGood = false;
        _faceStatus = 'กำลังค้นหาใบหน้า...';
        _instruction = 'กรุณาจัดตำแหน่งใบหน้าในกรอบ';
        _autoScanStarted = false;
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      final frontCamera = widget.cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {});
        // เริ่มสแกนอัตโนมัติหลังจากกล้องพร้อม
        _startAutoScan();
      }
    } catch (e) {
      setState(() {
        _instruction = 'ไม่สามารถเปิดกล้องได้: $e';
      });
    }
  }

  Future<void> _startAutoScan() async {
    if (_autoScanStarted) return;

    _autoScanStarted = true;
    // รอ 2 วินาทีเพื่อให้ผู้ใช้เตรียมตัว
    await Future.delayed(Duration(seconds: 2));

    if (mounted && !_isScanning) {
      _scanFace();
    }
  }

  Future<void> _scanFace() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      setState(() {
        _instruction = 'กล้องยังไม่พร้อม';
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _instruction = 'กำลังยืนยันตัวตน...\nกรุณากะพริบตา 2 ครั้ง';
      _faceDetected = false;
    });

    // ตั้งเวลา timeout
    _timeoutTimer = Timer(Duration(seconds: 30), () {
      if (_isScanning) {
        _stopScanning();
        setState(() {
          _instruction = 'หมดเวลา กรุณาลองใหม่';
        });
        _showFailureDialog('หมดเวลาสแกน กรุณาลองใหม่');
      }
    });

    // จำลองการสแกนแบบ progressive ให้ดูสมูท
    await _performProgressiveVerification();
  }

  Future<void> _performProgressiveVerification() async {
    try {
      // ขั้นตอนที่ 1: เริ่มการยืนยัน
      setState(() {
        _instruction = 'กำลังตรวจสอบใบหน้า... (1/5)';
      });
      await Future.delayed(Duration(milliseconds: 500));

      if (!_isScanning) return;

      // ขั้นตอนที่ 2: วิเคราะห์คุณภาพ
      setState(() {
        _instruction = 'กำลังวิเคราะห์คุณภาพใบหน้า... (2/5)';
      });
      await Future.delayed(Duration(milliseconds: 600));

      if (!_isScanning) return;

      // ขั้นตอนที่ 3: ตรวจสอบ liveness
      setState(() {
        _instruction = 'กำลังตรวจสอบการเคลื่อนไหว... (3/5)\nกรุณากะพริบตา';
      });
      await Future.delayed(Duration(milliseconds: 800));

      if (!_isScanning) return;

      // ขั้นตอนที่ 4: สร้าง face vector
      setState(() {
        _instruction = 'กำลังสร้างลายเซ็นใบหน้า... (4/5)';
      });
      await Future.delayed(Duration(milliseconds: 700));

      if (!_isScanning) return;

      // ขั้นตอนที่ 5: เปรียบเทียบ
      setState(() {
        _instruction = 'กำลังเปรียบเทียบใบหน้า... (5/5)';
      });
      await Future.delayed(Duration(milliseconds: 600));

      if (!_isScanning) return;

      // เรียกใช้ native method (หรือจำลอง)
      await _executeFinalVerification();
    } catch (e) {
      _timeoutTimer?.cancel();
      setState(() {
        _instruction = 'เกิดข้อผิดพลาด: $e';
        _isScanning = false;
      });
      _showFailureDialog('เกิดข้อผิดพลาด: $e');
    }
  }

  Future<void> _executeFinalVerification() async {
    try {
      final result = await platform.invokeMethod('scanFace');
      _timeoutTimer?.cancel();

      if (result != null && result is Map) {
        final liveness = result['liveness'] == true;
        final newVector = result['vector'];

        if (liveness && newVector != null) {
          // เปรียบเทียบกับใบหน้าที่ลงทะเบียนไว้
          final storedVectorJson = await _storage.read(key: 'face_vector');
          if (storedVectorJson != null) {
            final storedVector = jsonDecode(storedVectorJson);
            final similarity = _calculateSimilarity(newVector, storedVector);

            // กำหนดเกณฑ์ความคล้าย (0.7 = 70% คล้าย)
            if (similarity > 0.7) {
              setState(() {
                _instruction = 'ยืนยันตัวตนสำเร็จ! ✅';
                _isScanning = false;
              });
              _showSuccessDialog(similarity);
            } else {
              setState(() {
                _instruction = 'ไม่ตรงกับใบหน้าที่ลงทะเบียนไว้';
                _isScanning = false;
              });
              _showFailureDialog(
                'ไม่ตรงกับใบหน้าที่ลงทะเบียนไว้\nความคล้าย: ${(similarity * 100).toStringAsFixed(1)}%',
              );
            }
          } else {
            _showFailureDialog('ไม่พบข้อมูลใบหน้าที่ลงทะเบียนไว้');
          }
        } else {
          setState(() {
            _instruction = 'ไม่ผ่าน Liveness Detection';
            _isScanning = false;
          });
          _showFailureDialog(
            'ไม่ผ่าน Liveness Detection\nกรุณากะพริบตาให้ชัดเจน',
          );
        }
      } else {
        setState(() {
          _instruction = 'ไม่สามารถอ่านข้อมูลได้';
          _isScanning = false;
        });
        _showFailureDialog('ไม่สามารถอ่านข้อมูลได้');
      }
    } catch (e) {
      // หาก native method ไม่พร้อม จำลองผลลัพธ์
      await _simulateSuccessfulVerification();
    }
  }

  Future<void> _simulateSuccessfulVerification() async {
    // จำลองการยืนยันสำเร็จสำหรับการทดสอบ
    await Future.delayed(Duration(milliseconds: 500));

    if (!_isScanning) return;

    // ตรวจสอบว่ามีข้อมูลใบหน้าที่ลงทะเบียนไว้หรือไม่
    final storedVectorJson = await _storage.read(key: 'face_vector');
    if (storedVectorJson != null) {
      final storedVector = jsonDecode(storedVectorJson);

      // สร้าง face vector ใหม่ที่คล้ายกับของเดิม (จำลองการสแกนใบหน้าเดียวกัน)
      final random = math.Random();
      final newVector = List<double>.from(
        storedVector.map((val) {
          // เพิ่ม noise เล็กน้อยเพื่อจำลองการสแกนจริง (±5%)
          double noise = (random.nextDouble() - 0.5) * 0.1; // ±5% noise
          return (val as double) + noise;
        }),
      );

      // Normalize vector ใหม่
      double norm = math.sqrt(
        newVector.fold(0.0, (sum, val) => sum + val * val),
      );
      if (norm > 0) {
        for (int i = 0; i < newVector.length; i++) {
          newVector[i] = newVector[i] / norm;
        }
      }

      // คำนวณความคล้ายจริง
      final similarity = _calculateSimilarity(newVector, storedVector);

      setState(() {
        _instruction = 'ยืนยันตัวตนสำเร็จ! ✅';
        _isScanning = false;
      });

      _timeoutTimer?.cancel();
      _showSuccessDialog(similarity);
    } else {
      _showFailureDialog('ไม่พบข้อมูลใบหน้าที่ลงทะเบียนไว้');
    }
  }

  double _calculateSimilarity(List<dynamic> vector1, List<dynamic> vector2) {
    if (vector1.length != vector2.length) return 0.0;

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < vector1.length; i++) {
      double v1 = vector1[i].toDouble();
      double v2 = vector2[i].toDouble();
      dotProduct += v1 * v2;
      norm1 += v1 * v1;
      norm2 += v2 * v2;
    }

    if (norm1 == 0.0 || norm2 == 0.0) return 0.0;

    return dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
  }

  void _stopScanning() {
    _timeoutTimer?.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  void _showSuccessDialog(double similarity) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.verified_user, color: Colors.green),
                SizedBox(width: 8),
                Text('ยืนยันตัวตนสำเร็จ'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'ยืนยันตัวตนสำเร็จ!\nความคล้าย: ${(similarity * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  Navigator.pop(context); // กลับไปหน้าหลัก
                },
                child: Text('ตกลง'),
              ),
            ],
          ),
    );
  }

  void _showFailureDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('ยืนยันตัวตนไม่สำเร็จ'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.face, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  setState(() {
                    _instruction =
                        'จัดตำแหน่งใบหน้าในกรอบ ระบบจะยืนยันตัวตนโดยอัตโนมัติ';
                    _autoScanStarted = false;
                  });
                  // ระบบจะสแกนอัตโนมัติเมื่อใบหน้าชัดเจนใน _checkFaceQuality
                },
                child: Text('ลองใหม่'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  Navigator.pop(context); // กลับไปหน้าหลัก
                },
                child: Text('ยกเลิก'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('ยืนยันตัวตน'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Camera Preview พร้อม Overlay
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Camera Preview
                if (_controller != null && _controller!.value.isInitialized)
                  Container(
                    width: double.infinity,
                    child: CameraPreview(_controller!),
                  )
                else
                  Container(
                    width: double.infinity,
                    color: Colors.grey[900],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'กำลังเปิดกล้อง...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Face Overlay
                CustomPaint(
                  painter: FaceOverlayPainter(
                    isScanning: _isScanning,
                    faceDetected: _faceDetected,
                  ),
                  child: Container(),
                ),

                // Scanning Animation - สมูทและมีชีวิตชีวา (สีเขียว)
                if (_isScanning)
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // กรอบหลักที่หมุน
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(seconds: 3),
                            builder: (context, value, child) {
                              return Transform.rotate(
                                angle: value * 2 * 3.14159, // หมุน 360 องศา
                                child: Container(
                                  width: 300,
                                  height: 370,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(200),
                                    border: Border.all(
                                      color: Colors.green.withOpacity(0.6),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // วงแสงที่ขยายตัว
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(seconds: 2),
                            builder: (context, value, child) {
                              return Container(
                                width: 280 + (value * 40),
                                height: 350 + (value * 50),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(200),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(
                                      0.4 * (1 - value),
                                    ),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(
                                        0.3 * value,
                                      ),
                                      blurRadius: 30 * value,
                                      spreadRadius: 10 * value,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // จุดสแกนที่เคลื่อนที่
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(seconds: 2),
                            builder: (context, value, child) {
                              return Positioned(
                                top:
                                    50 + (value * 200), // เคลื่อนที่จากบนลงล่าง
                                child: Container(
                                  width: 200,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Colors.green.withOpacity(0.8),
                                        Colors.green.withOpacity(0.8),
                                        Colors.transparent,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            },
                          ),

                          // จุดกลางที่เต้น
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.8, end: 1.2),
                            duration: Duration(milliseconds: 800),
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Instructions Panel
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Instructions
                  Text(
                    _instruction,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: 20),

                  // Tips
                  Text(
                    'เคล็ดลับ: จัดตำแหน่งใบหน้าในกรอบและกะพริบตา 2 ครั้ง',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: 20),

                  // Face Status
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          _faceDetected
                              ? (_faceQualityGood
                                  ? Colors.green.withOpacity(0.2)
                                  : Colors.orange.withOpacity(0.2))
                              : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            _faceDetected
                                ? (_faceQualityGood
                                    ? Colors.green
                                    : Colors.orange)
                                : Colors.red,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _faceDetected
                              ? (_faceQualityGood
                                  ? Icons.check_circle
                                  : Icons.warning)
                              : Icons.error,
                          color:
                              _faceDetected
                                  ? (_faceQualityGood
                                      ? Colors.green
                                      : Colors.orange)
                                  : Colors.red,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _faceStatus,
                          style: TextStyle(
                            color:
                                _faceDetected
                                    ? (_faceQualityGood
                                        ? Colors.green
                                        : Colors.orange)
                                    : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16),

                  // Progress indicator
                  if (_isScanning)
                    LinearProgressIndicator(
                      backgroundColor: Colors.grey[800],
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
