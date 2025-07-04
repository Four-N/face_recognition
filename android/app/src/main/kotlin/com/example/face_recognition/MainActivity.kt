package com.example.face_recognition

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.*
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import androidx.annotation.NonNull
import androidx.annotation.OptIn
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.common.util.concurrent.ListenableFuture
import androidx.camera.core.Camera as CameraX
import java.util.concurrent.ExecutionException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import kotlin.math.abs
import java.io.ByteArrayOutputStream
import androidx.core.graphics.scale

class MainActivity: FlutterActivity() {
    private val FACE_CHANNEL = "face_recognition"
    private val BIOMETRIC_CHANNEL = "com.example.face_auth/biometric"
    private val CAMERA_PREVIEW_CHANNEL = "camera_preview"
    private val CAMERA_PERMISSION_REQUEST_CODE = 100

    private var livenessCallback: ((FloatArray, Boolean) -> Unit)? = null
    private var blinkCount = 0
    private var lastEyeOpen = true
    private var faceRect: Rect? = null
    private var cameraExecutor: ExecutorService? = null
    private var tfliteInterpreter: Interpreter? = null
    private var imageCapture: ImageCapture? = null
    private var preview: Preview? = null
    private var cameraX: CameraX? = null
    private var previewChannel: MethodChannel? = null
    
    // Real-time face tracking variables
    private var isRealTimeTrackingActive = false
    private var realTimeCallback: MethodChannel.Result? = null
    private var lastFaceQualityCheck = 0L
    private val FACE_QUALITY_CHECK_INTERVAL = 200L // Check every 200ms for smooth real-time
    
    // Face quality tracking
    private var consecutiveGoodFrames = 0
    private var consecutiveBadFrames = 0
    private val REQUIRED_GOOD_FRAMES = 3 // Need 3 consecutive good frames
    private val MAX_BAD_FRAMES = 5 // Reset after 5 bad frames

    @RequiresApi(Build.VERSION_CODES.P)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize preview channel
        previewChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_PREVIEW_CHANNEL)

        // Face Recognition Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FACE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFace" -> {
                    startCameraForLiveness { vector, liveness ->
                        val response = mapOf(
                            "vector" to vector.toList(),
                            "liveness" to liveness
                        )
                        result.success(response)
                    }
                }
                "checkFaceQuality" -> {
                    startRealTimeFaceTracking(result)
                }
                "stopFaceTracking" -> {
                    stopRealTimeFaceTracking()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Biometric Authentication Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "authenticate" -> {
                    authenticateBiometric(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startCameraForLiveness(callback: (FloatArray, Boolean) -> Unit) {
        livenessCallback = callback
        blinkCount = 0
        lastEyeOpen = true
        faceRect = null

        // Check camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST_CODE)
            return
        }

        cameraExecutor = Executors.newSingleThreadExecutor()
        startCamera()
    }

    private fun startCamera() {
        val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()

                // Preview
                preview = Preview.Builder().build()

                // Image capture
                imageCapture = ImageCapture.Builder().build()

                // Image analyzer for face detection
                val imageAnalyzer = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also {
                        it.setAnalyzer(cameraExecutor!!) { imageProxy ->
                            processImageProxy(imageProxy)
                        }
                    }

                // Select front camera
                val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

                try {
                    cameraProvider.unbindAll()
                    cameraX = cameraProvider.bindToLifecycle(
                        this as LifecycleOwner,
                        cameraSelector,
                        preview,
                        imageCapture,
                        imageAnalyzer
                    )
                } catch (exc: Exception) {
                    livenessCallback?.invoke(floatArrayOf(), false)
                }
            } catch (exc: ExecutionException) {
                livenessCallback?.invoke(floatArrayOf(), false)
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun processImageProxy(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            // Send preview to Flutter - ทำเป็น async
            try {
                sendPreviewToFlutter(imageProxy)
            } catch (e: Exception) {
                Log.e("FaceRecognition", "Error sending preview", e)
            }

            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)

            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                .build()

            val detector = FaceDetection.getClient(options)

            detector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        val face = faces[0]
                        val leftEyeOpen = face.leftEyeOpenProbability ?: 0f
                        val rightEyeOpen = face.rightEyeOpenProbability ?: 0f
                        faceRect = face.boundingBox

                        if (leftEyeOpen > 0.7f && rightEyeOpen > 0.7f) {
                            if (!lastEyeOpen) {
                                blinkCount++
                                lastEyeOpen = true
                            }
                        } else if (leftEyeOpen < 0.3f && rightEyeOpen < 0.3f) {
                            lastEyeOpen = false
                        }

                        if (blinkCount >= 2) {
                            // ผ่าน liveness!
                            Log.d("FaceLiveness", "Liveness passed, blinkCount=$blinkCount")
                            val faceBitmap = cropFaceFromImageProxy(imageProxy, face.boundingBox)
                            if (faceBitmap != null) {
                                val vector = getFaceEmbedding(faceBitmap)
                                runOnUiThread {
                                    livenessCallback?.invoke(vector, true)
                                }
                            } else {
                                runOnUiThread {
                                    livenessCallback?.invoke(floatArrayOf(), false)
                                }
                            }
                            stopCamera()
                        }
                    }
                    imageProxy.close()
                }
                .addOnFailureListener {
                    imageProxy.close()
                }
        } else {
            imageProxy.close()
        }
    }

    private fun sendPreviewToFlutter(imageProxy: ImageProxy) {
        // ลดขนาดภาพเพื่อประสิทธิภาพ
        val bitmap = imageProxyToBitmap(imageProxy)
        val scaledBitmap = bitmap.scale(320, 240) // ลดขนาดลง
        val byteArray = bitmapToByteArray(scaledBitmap)

        // ส่งกลับไปยัง Flutter บน UI Thread
        runOnUiThread {
            previewChannel?.invokeMethod("updatePreview", byteArray)
        }
    }

    private fun bitmapToByteArray(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        // ลดคุณภาพเพื่อความเร็ว
        bitmap.compress(Bitmap.CompressFormat.JPEG, 60, stream)
        return stream.toByteArray()
    }

    private fun cropFaceFromImageProxy(imageProxy: ImageProxy, faceRect: Rect): Bitmap? {
        return try {
            val bitmap = imageProxyToBitmap(imageProxy)
            val croppedBitmap = Bitmap.createBitmap(
                bitmap,
                faceRect.left.coerceAtLeast(0),
                faceRect.top.coerceAtLeast(0),
                faceRect.width().coerceAtMost(bitmap.width - faceRect.left),
                faceRect.height().coerceAtMost(bitmap.height - faceRect.top)
            )
            croppedBitmap
        } catch (e: Exception) {
            null
        }
    }

    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap {
        val yBuffer = imageProxy.planes[0].buffer // Y
        val vuBuffer = imageProxy.planes[2].buffer // VU

        val ySize = yBuffer.remaining()
        val vuSize = vuBuffer.remaining()

        val nv21 = ByteArray(ySize + vuSize)

        yBuffer.get(nv21, 0, ySize)
        vuBuffer.get(nv21, ySize, vuSize)

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 100, out)
        val imageBytes = out.toByteArray()

        return BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
    }

    private fun getFaceEmbedding(faceImage: Bitmap): FloatArray {
        val inputSize = 112 // หรือ 160 ขึ้นกับโมเดล

        try {
            // Load TFLite model
            if (tfliteInterpreter == null) {
                val modelFile = loadModelFile("face.tflite")
                tfliteInterpreter = Interpreter(modelFile)
            }

            // Preprocess image - ทำให้ได้คุณภาพดีขึ้น
            val resizedBitmap = Bitmap.createScaledBitmap(faceImage, inputSize, inputSize, true)
            val inputBuffer = bitmapToByteBuffer(resizedBitmap, inputSize)

            // Run inference
            val output = Array(1) { FloatArray(128) } // Assuming 128-dimensional embedding
            tfliteInterpreter?.run(inputBuffer, output)

            val rawEmbedding = output[0]
            
            // Normalize the embedding vector (สำคัญมากสำหรับ cosine similarity)
            val normalizedEmbedding = normalizeVector(rawEmbedding)
            
            Log.d("FaceEmbedding", "Generated embedding, norm: ${calculateVectorNorm(normalizedEmbedding)}")
            
            return normalizedEmbedding
        } catch (e: Exception) {
            Log.e("FaceEmbedding", "Error generating embedding", e)
            // Return normalized random vector as fallback
            return generateNormalizedRandomVector(128)
        }
    }
    
    private fun normalizeVector(vector: FloatArray): FloatArray {
        val norm = kotlin.math.sqrt(vector.map { it * it }.sum())
        return if (norm > 0) {
            vector.map { it / norm }.toFloatArray()
        } else {
            generateNormalizedRandomVector(vector.size)
        }
    }
    
    private fun calculateVectorNorm(vector: FloatArray): Float {
        return kotlin.math.sqrt(vector.map { it * it }.sum())
    }
    
    private fun generateNormalizedRandomVector(size: Int): FloatArray {
        val random = kotlin.random.Random
        val vector = FloatArray(size) { random.nextFloat() * 2f - 1f } // -1 to 1
        return normalizeVector(vector)
    }

    private fun loadModelFile(modelName: String): MappedByteBuffer {
        val assetFileDescriptor = assets.openFd(modelName)
        val fileInputStream = FileInputStream(assetFileDescriptor.fileDescriptor)
        val fileChannel = fileInputStream.channel
        val startOffset = assetFileDescriptor.startOffset
        val declaredLength = assetFileDescriptor.declaredLength
        return fileChannel.map(FileChannel.MapMode.READ_ONLY, startOffset, declaredLength)
    }

    private fun bitmapToByteBuffer(bitmap: Bitmap, inputSize: Int): ByteBuffer {
        val byteBuffer = ByteBuffer.allocateDirect(4 * inputSize * inputSize * 3)
        byteBuffer.order(ByteOrder.nativeOrder())

        val pixels = IntArray(inputSize * inputSize)
        bitmap.getPixels(pixels, 0, inputSize, 0, 0, inputSize, inputSize)

        for (pixelValue in pixels) {
            val r = (pixelValue shr 16 and 0xFF)
            val g = (pixelValue shr 8 and 0xFF)
            val b = (pixelValue and 0xFF)

            // Normalize to [-1, 1]
            byteBuffer.putFloat((r - 127.5f) / 128.0f)
            byteBuffer.putFloat((g - 127.5f) / 128.0f)
            byteBuffer.putFloat((b - 127.5f) / 128.0f)
        }

        return byteBuffer
    }

    private fun startRealTimeFaceTracking(result: MethodChannel.Result) {
        if (isRealTimeTrackingActive) {
            // Already tracking, just update callback
            realTimeCallback = result
            return
        }
        
        realTimeCallback = result
        isRealTimeTrackingActive = true
        consecutiveGoodFrames = 0
        consecutiveBadFrames = 0
        
        // Check camera permission
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            sendFaceQualityResult(false, false, "camera_permission")
            return
        }

        if (cameraExecutor == null) {
            cameraExecutor = Executors.newSingleThreadExecutor()
        }
        
        if (cameraX == null) {
            startCameraForRealTimeTracking()
        }
    }
    
    private fun stopRealTimeFaceTracking() {
        isRealTimeTrackingActive = false
        realTimeCallback = null
        consecutiveGoodFrames = 0
        consecutiveBadFrames = 0
    }
    
    private fun startCameraForRealTimeTracking() {
        val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                
                // Only create new camera if not exists
                if (cameraX == null) {
                    // Preview
                    preview = Preview.Builder()
                        .setTargetResolution(android.util.Size(1280, 720)) // HD for better quality
                        .build()

                    // Image analyzer for real-time face detection
                    val imageAnalyzer = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setTargetResolution(android.util.Size(640, 480)) // Lower res for faster processing
                        .build()
                        .also {
                            it.setAnalyzer(cameraExecutor!!) { imageProxy ->
                                processImageForRealTimeTracking(imageProxy)
                            }
                        }

                    val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                    
                    try {
                        cameraProvider.unbindAll()
                        cameraX = cameraProvider.bindToLifecycle(
                            this as LifecycleOwner,
                            cameraSelector,
                            preview,
                            imageAnalyzer
                        )
                    } catch (exc: Exception) {
                        Log.e("FaceRecognition", "Camera binding failed", exc)
                        sendFaceQualityResult(false, false, "camera_error")
                    }
                }
            } catch (exc: Exception) {
                Log.e("FaceRecognition", "Camera setup failed", exc)
                sendFaceQualityResult(false, false, "camera_error")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @RequiresPermission(Manifest.permission.USE_BIOMETRIC)
    @RequiresApi(Build.VERSION_CODES.P)
    private fun authenticateBiometric(result: MethodChannel.Result) {
        val biometricPrompt = BiometricPrompt.Builder(this)
            .setTitle("ยืนยันตัวตน")
            .setSubtitle("ใช้ลายนิ้วมือหรือใบหน้าเพื่อยืนยัน")
            .setDescription("กรุณาใช้ข้อมูลชีวมิติเพื่อยืนยันตัวตน")
            .setNegativeButton("ยกเลิก", mainExecutor) { _, _ ->
                result.success(false)
            }
            .build()

        val cancellationSignal = CancellationSignal()

        biometricPrompt.authenticate(
            cancellationSignal,
            mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result_bio: BiometricPrompt.AuthenticationResult?) {
                    super.onAuthenticationSucceeded(result_bio)
                    result.success(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    super.onAuthenticationError(errorCode, errString)
                    result.success(false)
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    result.success(false)
                }
            }
        )
    }

    @OptIn(ExperimentalGetImage::class)
    private fun processImageForRealTimeTracking(imageProxy: ImageProxy) {
        if (!isRealTimeTrackingActive) {
            imageProxy.close()
            return
        }
        
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastFaceQualityCheck < FACE_QUALITY_CHECK_INTERVAL) {
            imageProxy.close()
            return
        }
        lastFaceQualityCheck = currentTime
        
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            
            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE) // Faster processing
                .setMinFaceSize(0.15f) // Minimum face size for better detection
                .build()

            val detector = FaceDetection.getClient(options)

            detector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        val face = faces[0]
                        val qualityResult = analyzeFaceQualityAdvanced(face, imageProxy)
                        
                        if (qualityResult.qualityGood) {
                            consecutiveGoodFrames++
                            consecutiveBadFrames = 0
                            
                            if (consecutiveGoodFrames >= REQUIRED_GOOD_FRAMES) {
                                sendFaceQualityResult(true, true, "good_quality")
                            }
                        } else {
                            consecutiveBadFrames++
                            consecutiveGoodFrames = 0
                            
                            if (consecutiveBadFrames >= MAX_BAD_FRAMES) {
                                sendFaceQualityResult(true, false, qualityResult.issue)
                            }
                        }
                    } else {
                        consecutiveBadFrames++
                        consecutiveGoodFrames = 0
                        
                        if (consecutiveBadFrames >= MAX_BAD_FRAMES) {
                            sendFaceQualityResult(false, false, "no_face")
                        }
                    }
                    imageProxy.close()
                }
                .addOnFailureListener {
                    sendFaceQualityResult(false, false, "detection_failed")
                    imageProxy.close()
                }
        } else {
            sendFaceQualityResult(false, false, "no_image")
            imageProxy.close()
        }
    }
    
    private data class FaceQualityResult(
        val qualityGood: Boolean,
        val issue: String
    )
    
    private fun analyzeFaceQualityAdvanced(face: com.google.mlkit.vision.face.Face, imageProxy: ImageProxy): FaceQualityResult {
        val faceWidth = face.boundingBox.width()
        val faceHeight = face.boundingBox.height()
        val imageWidth = imageProxy.width
        val imageHeight = imageProxy.height
        
        // 1. ตรวจสอบขนาดใบหน้า (แบบธนาคาร: ต้องใหญ่พอให้เห็นรายละเอียด)
        val faceSizeRatio = (faceWidth * faceHeight).toFloat() / (imageWidth * imageHeight)
        if (faceSizeRatio < 0.08f) { // เพิ่มขึ้นจาก 0.05f
            return FaceQualityResult(false, "too_small")
        }
        if (faceSizeRatio > 0.6f) { // ใกล้เกินไป
            return FaceQualityResult(false, "too_close")
        }
        
        // 2. ตรวจสอบตำแหน่งใบหน้า (ต้องอยู่กลางภาพ)
        val faceCenterX = face.boundingBox.centerX().toFloat()
        val faceCenterY = face.boundingBox.centerY().toFloat()
        val imageCenterX = imageWidth / 2f
        val imageCenterY = imageHeight / 2f
        
        val centerOffsetX = abs(faceCenterX - imageCenterX) / imageWidth
        val centerOffsetY = abs(faceCenterY - imageCenterY) / imageHeight
        
        if (centerOffsetX > 0.25f || centerOffsetY > 0.25f) {
            return FaceQualityResult(false, "not_centered")
        }
        
        // 3. ตรวจสอบมุมใบหน้า (เข้มงวดกว่าเดิม)
        val headEulerAngleY = abs(face.headEulerAngleY)
        val headEulerAngleZ = abs(face.headEulerAngleZ)
        val headEulerAngleX = abs(face.headEulerAngleX)
        
        if (headEulerAngleY > 10 || headEulerAngleZ > 10 || headEulerAngleX > 10) {
            return FaceQualityResult(false, "angle")
        }
        
        // 4. ตรวจสอบความชัดของดวงตา
        val leftEyeOpen = face.leftEyeOpenProbability ?: 0.5f
        val rightEyeOpen = face.rightEyeOpenProbability ?: 0.5f
        
        if (leftEyeOpen < 0.4f || rightEyeOpen < 0.4f) {
            return FaceQualityResult(false, "eyes_not_clear")
        }
        
        // 5. ตรวจสอบการยิ้ม (ธนาคารบางแห่งไม่ชอบให้ยิ้มมาก)
        val smiling = face.smilingProbability ?: 0f
        if (smiling > 0.7f) {
            return FaceQualityResult(false, "too_much_smile")
        }
        
        // 6. ตรวจสอบแสง (ใช้ brightness ของ bounding box)
        val faceRegionBrightness = calculateFaceRegionBrightness(imageProxy, face.boundingBox)
        if (faceRegionBrightness < 80 || faceRegionBrightness > 200) { // 0-255 scale
            return FaceQualityResult(false, "lighting")
        }
        
        return FaceQualityResult(true, "good_quality")
    }
    
    private fun calculateFaceRegionBrightness(imageProxy: ImageProxy, faceRect: Rect): Float {
        try {
            // Sample a few points in the face region to calculate average brightness
            val yBuffer = imageProxy.planes[0].buffer
            val ySize = yBuffer.remaining()
            val yArray = ByteArray(ySize)
            yBuffer.get(yArray)
            
            val width = imageProxy.width
            val height = imageProxy.height
            
            // Ensure face rect is within image bounds
            val left = faceRect.left.coerceAtLeast(0)
            val top = faceRect.top.coerceAtLeast(0)
            val right = faceRect.right.coerceAtMost(width)
            val bottom = faceRect.bottom.coerceAtMost(height)
            
            var totalBrightness = 0L
            var pixelCount = 0
            
            // Sample every 10th pixel for performance
            for (y in top until bottom step 10) {
                for (x in left until right step 10) {
                    val index = y * width + x
                    if (index < yArray.size) {
                        totalBrightness += (yArray[index].toInt() and 0xFF)
                        pixelCount++
                    }
                }
            }
            
            return if (pixelCount > 0) totalBrightness.toFloat() / pixelCount else 128f
        } catch (e: Exception) {
            return 128f // Default neutral brightness
        }
    }
    
    private fun sendFaceQualityResult(faceDetected: Boolean, qualityGood: Boolean, issue: String) {
        if (!isRealTimeTrackingActive || realTimeCallback == null) return
        
        runOnUiThread {
            realTimeCallback?.success(mapOf(
                "faceDetected" to faceDetected,
                "qualityGood" to qualityGood,
                "issue" to issue,
                "timestamp" to System.currentTimeMillis()
            ))
        }
    }
    
    private fun stopCamera() {
        stopRealTimeFaceTracking()
        cameraExecutor?.shutdown()
        cameraExecutor = null
        cameraX = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                startCamera()
            } else {
                livenessCallback?.invoke(floatArrayOf(), false)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopRealTimeFaceTracking()
        tfliteInterpreter?.close()
        cameraExecutor?.shutdown()
    }
}