package com.thebitculture.retro_atarist

import android.content.Context
import android.hardware.input.InputManager
import android.os.Handler
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
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
