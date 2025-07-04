import UIKit
import Flutter
import AVFoundation
import MLKitFaceDetection
import MLKitVision
import TensorFlowLite
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
  var livenessCallback: (([Double], Bool) -> Void)?
  var blinkCount = 0
  var lastEyeOpen = true
  var session: AVCaptureSession?
  var faceRect: CGRect?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // Channel for face recognition
    let faceChannel = FlutterMethodChannel(name: "face_recognition", binaryMessenger: controller.binaryMessenger)
    faceChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "scanFace" {
        self?.startCameraForLiveness { vector, liveness in
          let response: [String: Any] = [
            "vector": vector,
            "liveness": liveness
          ]
          result(response)
        }
      } else if call.method == "checkFaceQuality" {
        self?.checkFaceQuality(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Channel for biometric authentication
    let biometricChannel = FlutterMethodChannel(name: "com.example.face_auth/biometric", binaryMessenger: controller.binaryMessenger)
    biometricChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "authenticate" {
        self?.authenticateBiometric(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func startCameraForLiveness(callback: @escaping ([Double], Bool) -> Void) {
    livenessCallback = callback
    blinkCount = 0
    lastEyeOpen = true
    faceRect = nil

    let session = AVCaptureSession()
    session.sessionPreset = .medium
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device) else {
      callback([], false)
      return
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
    session.addOutput(output)
    self.session = session
    session.startRunning()
  }

  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let image = VisionImage(buffer: sampleBuffer)
    image.orientation = .leftMirrored

    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.classificationMode = .all
    let detector = FaceDetector.faceDetector(options: options)

    detector.process(image) { [weak self] faces, error in
      guard let self = self, let faces = faces, error == nil else { return }
      if let face = faces.first {
        let leftEyeOpen = face.leftEyeOpenProbability
        let rightEyeOpen = face.rightEyeOpenProbability
        self.faceRect = face.frame

        if leftEyeOpen > 0.7 && rightEyeOpen > 0.7 {
          if !self.lastEyeOpen {
            self.blinkCount += 1
            self.lastEyeOpen = true
          }
        } else if leftEyeOpen < 0.3 && rightEyeOpen < 0.3 {
          self.lastEyeOpen = false
        }

        if self.blinkCount >= 2 {
          // ผ่าน liveness!
          if let faceImage = self.cropFaceFromBuffer(pixelBuffer, faceRect: face.frame) {
            let vector = self.getFaceEmbedding(faceImage: faceImage).map { Double($0) }
            self.livenessCallback?(vector, true)
          } else {
            self.livenessCallback?([], false)
          }
          self.session?.stopRunning()
          self.session = nil
        }
      }
    }
  }

  // --- Crop face from pixelBuffer using bounding box ---
  func cropFaceFromBuffer(_ pixelBuffer: CVPixelBuffer, faceRect: CGRect) -> UIImage? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    let scale = UIScreen.main.scale
    let cropRect = CGRect(x: faceRect.origin.x * scale,
                          y: faceRect.origin.y * scale,
                          width: faceRect.size.width * scale,
                          height: faceRect.size.height * scale)
    guard let cgImage = context.createCGImage(ciImage, from: cropRect) else { return nil }
    return UIImage(cgImage: cgImage)
  }

  // --- TFLite: Load model and run inference ---
  func getFaceEmbedding(faceImage: UIImage) -> [Float] {
    let inputSize = 112 // หรือ 160 ขึ้นกับโมเดล
    guard let inputData = faceImage.normalizedData(size: CGSize(width: inputSize, height: inputSize)) else { return [] }
    guard let modelPath = Bundle.main.path(forResource: "face", ofType: "tflite") else { return [] }
    guard let interpreter = try? Interpreter(modelPath: modelPath) else { return [] }
    try? interpreter.allocateTensors()
//    try? interpreter.copy(inputData, toInputAt: 0)
    try? interpreter.invoke()
    guard let outputTensor = try? interpreter.output(at: 0) else { return [] }
    let output = outputTensor.data.toArray(type: Float32.self, count: 128)
    return output
  }
  
  // --- Biometric Authentication ---
  func authenticateBiometric(result: @escaping FlutterResult) {
    let context = LAContext()
    var error: NSError?
    
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      let reason = "ยืนยันตัวตนด้วยลายนิ้วมือหรือ Face ID"
      
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authenticationError in
        DispatchQueue.main.async {
          if success {
            result(true)
          } else {
            result(false)
          }
        }
      }
    } else {
      result(false)
    }
  }
  
  // --- Face Quality Check ---
  func checkFaceQuality(result: @escaping FlutterResult) {
    let session = AVCaptureSession()
    session.sessionPreset = .medium
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
          let input = try? AVCaptureDeviceInput(device: device) else {
      result(["faceDetected": false, "qualityGood": false, "issue": "camera_error"])
      return
    }
    session.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "faceQualityQueue"))
    session.addOutput(output)
    session.startRunning()
    
    // ตรวจสอบเฉพาะครั้งเดียว
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      session.stopRunning()
    }
  }

  func checkFaceQualityFromImage(_ sampleBuffer: CMSampleBuffer, result: @escaping FlutterResult) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      result(["faceDetected": false, "qualityGood": false, "issue": "no_image"])
      return
    }
    
    let image = VisionImage(buffer: sampleBuffer)
    image.orientation = .leftMirrored

    let options = FaceDetectorOptions()
    options.performanceMode = .fast
    options.classificationMode = .all
    options.landmarkMode = .all
    let detector = FaceDetector.faceDetector(options: options)

    detector.process(image) { faces, error in
      guard let faces = faces, error == nil else {
        result(["faceDetected": false, "qualityGood": false, "issue": "detection_failed"])
        return
      }
      
      if let face = faces.first {
        let faceFrame = face.frame
        let imageSize = CVImageBufferGetDisplaySize(pixelBuffer)
        
        // ตรวจสอบขนาดใบหน้า
        let faceSizeRatio = (faceFrame.width * faceFrame.height) / (imageSize.width * imageSize.height)
        let isGoodSize = faceSizeRatio > 0.05 // อย่างน้อย 5% ของภาพ
        
        // ตรวจสอบมุมใบหน้า
        let headEulerAngleY = face.headEulerAngleY
        let headEulerAngleZ = face.headEulerAngleZ
        let isGoodAngle = abs(headEulerAngleY) < 15 && abs(headEulerAngleZ) < 15
        
        // ตรวจสอบแว่นตา
        let leftEyeOpen = face.leftEyeOpenProbability
        let rightEyeOpen = face.rightEyeOpenProbability
        let eyesVisible = leftEyeOpen > 0.3 && rightEyeOpen > 0.3
        
        var issue = ""
        var qualityGood = true
        
        switch true {
        case !isGoodSize:
          issue = "too_small"
          qualityGood = false
        case !isGoodAngle:
          issue = "angle"
          qualityGood = false
        case !eyesVisible:
          issue = "glasses"
          qualityGood = false
        default:
          break
        }
        
        result([
          "faceDetected": true,
          "qualityGood": qualityGood,
          "issue": issue
        ])
      } else {
        result([
          "faceDetected": false,
          "qualityGood": false,
          "issue": "no_face"
        ])
      }
    }
  }
}

// --- UIImage extension สำหรับ normalize/resize ---
extension UIImage {
    func normalizedData(size: CGSize) -> Data? {
      guard let resized = self.resized(to: size),
            let cgImage = resized.cgImage else { return nil }
      let width = Int(size.width)
      let height = Int(size.height)
      let bytesPerRow = width * 4
      var pixelData = [UInt8](repeating: 0, count: width * height * 4)
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let context = CGContext(data: &pixelData,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

      var floatData = [Float32](repeating: 0, count: width * height * 3)
      for i in 0..<(width * height) {
        let offset = i * 4
        floatData[i * 3 + 0] = (Float32(pixelData[offset]) - 127.5) / 128.0
        floatData[i * 3 + 1] = (Float32(pixelData[offset + 1]) - 127.5) / 128.0
        floatData[i * 3 + 2] = (Float32(pixelData[offset + 2]) - 127.5) / 128.0
      }

      // ✅ สร้าง Data อย่างปลอดภัย
      return floatData.withUnsafeBytes { Data($0) }
    }

  func resized(to size: CGSize) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    self.draw(in: CGRect(origin: .zero, size: size))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return newImage
  }
}

// --- Data extension สำหรับแปลง output tensor ---
extension Data {
  func toArray<T>(type: T.Type, count: Int) -> [T] {
    return withUnsafeBytes {
      Array(UnsafeBufferPointer<T>(start: $0.baseAddress!.assumingMemoryBound(to: T.self), count: count))
    }
  }
}
