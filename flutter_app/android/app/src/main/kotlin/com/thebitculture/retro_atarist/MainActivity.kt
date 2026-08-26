package com.thebitculture.retro_atarist

import android.content.Context
import android.content.Intent
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

/**
 * The gamepads_android plugin casts the host Activity to
 * GamepadsCompatibleActivity when it attaches. A plain FlutterActivity does
 * not implement it, so plugin registration throws
 *
 *     java.lang.ClassCastException: MainActivity cannot be cast to
 *     org.flame_engine.gamepads_android.GamepadsCompatibleActivity
 *
 * on every launch, the plugin is skipped entirely, and no physical controller
 * is ever seen on Android.
 *
 * That failure is easy to miss during development, and was missed here: on
 * Linux desktop the same Dart code uses a different platform implementation
 * and works perfectly, so a controller that is detected and mapped on the
 * development machine is simply invisible on the device -- which, for a
 * handheld like the Retroid, means no input at all.
 *
 * Implementing the interface wires the plugin's listeners into this Activity's
 * own input dispatch, which is what it expects. Same fix as Retro-Dosbox's
 * MainActivity, minus the parts that app needs for its separate emulator
 * process and its SDL JNI setup -- this app's core runs in-process and links
 * no SDL on Android.
 */
class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {

    /* All-files access, the Retro-Amiga way. The library lives wherever the
     * user keeps it -- usually an SD card -- and scoped storage will not let
     * the app read a raw path there without this. The request opens the
     * system's All-files-access page; the parked result is completed from
     * onResume when the user comes back. */
    private var pendingStorageAccess: MethodChannel.Result? = null
    private var waitingForStorageSettings = false

    private fun hasSharedStorageAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasSharedStorageAccess" ->
                    result.success(hasSharedStorageAccess())
                "requestSharedStorageAccess" -> {
                    if (hasSharedStorageAccess()) {
                        result.success(true)
                    } else if (pendingStorageAccess != null) {
                        result.error(
                            "busy",
                            "storage access settings are already open",
                            null,
                        )
                    } else {
                        pendingStorageAccess = result
                        waitingForStorageSettings = true
                        val intent = Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:$packageName"),
                        )
                        try {
                            startActivity(intent)
                        } catch (error: Exception) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (waitingForStorageSettings) {
            waitingForStorageSettings = false
            val pending = pendingStorageAccess
            pendingStorageAccess = null
            pending?.success(hasSharedStorageAccess())
        }
    }

    companion object {
        private const val STORAGE_CHANNEL = "retro_atarist/storage"
    }
    private var keyEventHandler: ((KeyEvent) -> Boolean)? = null
    private var motionEventHandler: ((MotionEvent) -> Boolean)? = null

    override fun registerInputDeviceListener(
        listener: InputManager.InputDeviceListener,
        handler: Handler?
    ) {
        val inputManager = getSystemService(Context.INPUT_SERVICE) as InputManager
        inputManager.registerInputDeviceListener(listener, handler)
    }

    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) {
        keyEventHandler = handler
    }

    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) {
        motionEventHandler = handler
    }

    /**
     * Give the plugin first refusal on every key event.
     *
     * It returns true only for events from a device it recognises as a
     * gamepad, so ordinary keyboard input still falls through to Flutter --
     * which matters here, because the ST keyboard overlay and any attached
     * hardware keyboard both depend on that path.
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (keyEventHandler?.invoke(event) == true) return true
        return super.dispatchKeyEvent(event)
    }

    /** The same for analogue sticks and triggers, which arrive as motion. */
    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (motionEventHandler?.invoke(event) == true) return true
        return super.dispatchGenericMotionEvent(event)
    }
}
