package ru.vyatsu.ecotrack.ecotrack_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingActivityPermissionResult: MethodChannel.Result? = null

    private val activityRecognitionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        pendingActivityPermissionResult?.success(granted)
        pendingActivityPermissionResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ru.vyatsu.ecotrack/permissions"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestActivityRecognition" -> handleActivityRecognitionRequest(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleActivityRecognitionRequest(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(true)
            return
        }
        val alreadyGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED
        if (alreadyGranted) {
            result.success(true)
            return
        }
        if (pendingActivityPermissionResult != null) {
            result.error(
                "PERMISSION_IN_PROGRESS",
                "Activity recognition permission request already active",
                null
            )
            return
        }
        pendingActivityPermissionResult = result
        activityRecognitionLauncher.launch(Manifest.permission.ACTIVITY_RECOGNITION)
    }
}
