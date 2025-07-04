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
                    checkFaceQuality(result)
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

            // Preprocess image
            val resizedBitmap = faceImage.scale(inputSize, inputSize)
            val inputBuffer = bitmapToByteBuffer(resizedBitmap, inputSize)

            // Run inference
            val output = Array(1) { FloatArray(128) } // Assuming 128-dimensional embedding
            tfliteInterpreter?.run(inputBuffer, output)

            return output[0]
        } catch (e: Exception) {
            return floatArrayOf()
        }
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

    private fun stopCamera() {
        cameraExecutor?.shutdown()
        cameraX = null
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

    private fun checkFaceQuality(result: MethodChannel.Result) {
        // ตรวจสอบสถานะใบหน้าแบบ real-time
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf(
                "faceDetected" to false,
                "qualityGood" to false,
                "issue" to "camera_permission"
            ))
            return
        }

        cameraExecutor = Executors.newSingleThreadExecutor()
        val cameraProviderFuture: ListenableFuture<ProcessCameraProvider> = ProcessCameraProvider.getInstance(this)

        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                val imageAnalyzer = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also {
                        it.setAnalyzer(cameraExecutor!!) { imageProxy ->
                            checkFaceQualityFromImage(imageProxy, result)
                        }
                    }

                val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
                cameraProvider.bindToLifecycle(
                    this as LifecycleOwner,
                    cameraSelector,
                    imageAnalyzer
                )
            } catch (exc: Exception) {
                result.success(mapOf(
                    "faceDetected" to false,
                    "qualityGood" to false,
                    "issue" to "camera_error"
                ))
            }
        }, ContextCompat.getMainExecutor(this))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun checkFaceQualityFromImage(imageProxy: ImageProxy, result: MethodChannel.Result) {
        val mediaImage = imageProxy.image
        if (mediaImage != null) {
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            
            val options = FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .build()

            val detector = FaceDetection.getClient(options)

            detector.process(image)
                .addOnSuccessListener { faces ->
                    if (faces.isNotEmpty()) {
                        val face = faces[0]
                        val faceWidth = face.boundingBox.width()
                        val faceHeight = face.boundingBox.height()
                        val imageWidth = imageProxy.width
                        val imageHeight = imageProxy.height
                        
                        // ตรวจสอบขนาดใบหน้า (ควรใหญ่พอ)
                        val faceSizeRatio = (faceWidth * faceHeight).toFloat() / (imageWidth * imageHeight)
                        val isGoodSize = faceSizeRatio > 0.05f // อย่างน้อย 5% ของภาพ
                        
                        // ตรวจสอบมุมใบหน้า
                        val headEulerAngleY = face.headEulerAngleY
                        val headEulerAngleZ = face.headEulerAngleZ
                        val isGoodAngle = abs(headEulerAngleY) < 15 && abs(headEulerAngleZ) < 15
                        
                        // ตรวจสอบแว่นตา (ถ้าตาไม่ชัดเจน อาจใส่แว่น)
                        val leftEyeOpen = face.leftEyeOpenProbability ?: 0.5f
                        val rightEyeOpen = face.rightEyeOpenProbability ?: 0.5f
                        val eyesVisible = leftEyeOpen > 0.3f && rightEyeOpen > 0.3f
                        
                        var issue = ""
                        var qualityGood = true
                        
                        when {
                            !isGoodSize -> {
                                issue = "too_small"
                                qualityGood = false
                            }
                            !isGoodAngle -> {
                                issue = "angle"
                                qualityGood = false
                            }
                            !eyesVisible -> {
                                issue = "glasses"
                                qualityGood = false
                            }
                        }
                        
                        result.success(mapOf(
                            "faceDetected" to true,
                            "qualityGood" to qualityGood,
                            "issue" to issue
                        ))
                    } else {
                        result.success(mapOf(
                            "faceDetected" to false,
                            "qualityGood" to false,
                            "issue" to "no_face"
                        ))
                    }
                    imageProxy.close()
                }
                .addOnFailureListener {
                    result.success(mapOf(
                        "faceDetected" to false,
                        "qualityGood" to false,
                        "issue" to "detection_failed"
                    ))
                    imageProxy.close()
                }
        } else {
            result.success(mapOf(
                "faceDetected" to false,
                "qualityGood" to false,
                "issue" to "no_image"
            ))
            imageProxy.close()
        }
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
        tfliteInterpreter?.close()
        cameraExecutor?.shutdown()
    }
}