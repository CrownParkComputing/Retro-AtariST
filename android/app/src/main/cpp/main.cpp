#include <android/input.h>
#include <android/log.h>
#include <android_native_app_glue.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <jni.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "atarist_bridge.h"
#include "frontend.h"
#include "imgui.h"
#include "imgui_impl_android.h"
#include "imgui_impl_opengl3.h"

namespace {

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "RetroAtariST", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "RetroAtariST", __VA_ARGS__)

struct PendingImport {
	retro_atarist::ImportKind kind = retro_atarist::ImportKind::Software;
	std::string path;
};

struct AndroidHost {
	android_app* app = nullptr;
	EGLDisplay display = EGL_NO_DISPLAY;
	EGLSurface surface = EGL_NO_SURFACE;
	EGLContext context = EGL_NO_CONTEXT;
	int width = 0;
	int height = 0;
	GLuint frame_texture = 0;
	GLuint brand_texture = 0;
	int brand_width = 0;
	int brand_height = 0;
	int texture_width = 0;
	int texture_height = 0;
	uint64_t uploaded_generation = 0;
	bool first_frame_logged = false;
	bool imgui_ready = false;
	bool frontend_ready = false;
	bool resumed = true;
	std::mutex pending_mutex;
	std::vector<PendingImport> imports;
	std::unordered_map<std::string, GLuint> artwork_textures;
	std::string artwork_type = "box2d";
	int joystick_mask = 0;
	int joystick_axis_mask = 0;
};

AndroidHost* g_host = nullptr;

JNIEnv* activity_env(AndroidHost& host, bool& detach) {
	JNIEnv* env = nullptr;
	detach = false;
	if (host.app->activity->vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
		if (host.app->activity->vm->AttachCurrentThread(&env, nullptr) != JNI_OK) return nullptr;
		detach = true;
	}
	return env;
}

void clear_exception(JNIEnv* env) {
	if (!env->ExceptionCheck()) return;
	env->ExceptionDescribe();
	env->ExceptionClear();
}

void call_void(const char* method_name) {
	if (g_host == nullptr) return;
	bool detach = false;
	JNIEnv* env = activity_env(*g_host, detach);
	if (env == nullptr) return;
	jobject activity = g_host->app->activity->clazz;
	jclass cls = env->GetObjectClass(activity);
	jmethodID method = env->GetMethodID(cls, method_name, "()V");
	if (method != nullptr) env->CallVoidMethod(activity, method);
	clear_exception(env);
	env->DeleteLocalRef(cls);
	if (detach) g_host->app->activity->vm->DetachCurrentThread();
}

void call_void_int(const char* method_name, const int value) {
	if (g_host == nullptr) return;
	bool detach = false;
	JNIEnv* env = activity_env(*g_host, detach);
	if (env == nullptr) return;
	jobject activity = g_host->app->activity->clazz;
	jclass cls = env->GetObjectClass(activity);
	jmethodID method = env->GetMethodID(cls, method_name, "(I)V");
	if (method != nullptr) env->CallVoidMethod(activity, method, value);
	clear_exception(env);
	env->DeleteLocalRef(cls);
	if (detach) g_host->app->activity->vm->DetachCurrentThread();
}

void call_void_string(const char* method_name, const char* value) {
	if (g_host == nullptr) return;
	bool detach = false;
	JNIEnv* env = activity_env(*g_host, detach);
	if (env == nullptr) return;
	jobject activity = g_host->app->activity->clazz;
	jclass cls = env->GetObjectClass(activity);
	jmethodID method = env->GetMethodID(cls, method_name, "(Ljava/lang/String;)V");
	jstring argument = env->NewStringUTF(value != nullptr ? value : "");
	if (method != nullptr) env->CallVoidMethod(activity, method, argument);
	clear_exception(env);
	env->DeleteLocalRef(argument);
	env->DeleteLocalRef(cls);
	if (detach) g_host->app->activity->vm->DetachCurrentThread();
}

void call_void_two_strings(const char* method_name, const char* first, const char* second) {
	if (g_host == nullptr) return;
	bool detach = false;
	JNIEnv* env = activity_env(*g_host, detach);
	if (env == nullptr) return;
	jobject activity = g_host->app->activity->clazz;
	jclass cls = env->GetObjectClass(activity);
	jmethodID method = env->GetMethodID(
	    cls, method_name, "(Ljava/lang/String;Ljava/lang/String;)V");
	jstring a = env->NewStringUTF(first != nullptr ? first : "");
	jstring b = env->NewStringUTF(second != nullptr ? second : "");
	if (method != nullptr) env->CallVoidMethod(activity, method, a, b);
	clear_exception(env);
	env->DeleteLocalRef(a);
	env->DeleteLocalRef(b);
	env->DeleteLocalRef(cls);
	if (detach) g_host->app->activity->vm->DetachCurrentThread();
}

std::string call_string(const char* method_name) {
	if (g_host == nullptr) return {};
	bool detach = false;
	JNIEnv* env = activity_env(*g_host, detach);
	if (env == nullptr) return {};
	jobject activity = g_host->app->activity->clazz;
	jclass cls = env->GetObjectClass(activity);
	jmethodID method = env->GetMethodID(cls, method_name, "()Ljava/lang/String;");
	auto value = method != nullptr ? static_cast<jstring>(env->CallObjectMethod(activity, method)) : nullptr;
	std::string result;
	if (value != nullptr) {
		const char* text = env->GetStringUTFChars(value, nullptr);
		if (text != nullptr) result = text;
		if (text != nullptr) env->ReleaseStringUTFChars(value, text);
		env->DeleteLocalRef(value);
	}
	clear_exception(env);
	env->DeleteLocalRef(cls);
	if (detach) g_host->app->activity->vm->DetachCurrentThread();
	return result;
}

std::string call_string_arg(const char* method_name, const char* argument) {
	if (g_host == nullptr) return {};
	bool detach = false;
	JNIEnv* env = activity_env(*g_host, detach);
	if (env == nullptr) return {};
	jobject activity = g_host->app->activity->clazz;
	jclass cls = env->GetObjectClass(activity);
	jmethodID method = env->GetMethodID(cls, method_name, "(Ljava/lang/String;)Ljava/lang/String;");
	jstring value = env->NewStringUTF(argument != nullptr ? argument : "");
	auto returned = method != nullptr ? static_cast<jstring>(env->CallObjectMethod(activity, method, value)) : nullptr;
	std::string result;
	if (returned != nullptr) {
		const char* text = env->GetStringUTFChars(returned, nullptr);
		if (text != nullptr) result = text;
		if (text != nullptr) env->ReleaseStringUTFChars(returned, text);
		env->DeleteLocalRef(returned);
	}
	clear_exception(env);
	env->DeleteLocalRef(value);
	env->DeleteLocalRef(cls);
	if (detach) g_host->app->activity->vm->DetachCurrentThread();
	return result;
}

std::vector<std::string> split(const std::string& text, const char delimiter) {
	std::vector<std::string> fields;
	std::size_t start = 0;
	while (true) {
		const std::size_t at = text.find(delimiter, start);
		fields.push_back(text.substr(start, at == std::string::npos ? at : at - start));
		if (at == std::string::npos) break;
		start = at + 1;
	}
	return fields;
}

uint32_t read_be32(const unsigned char* bytes) {
	return static_cast<uint32_t>(bytes[0]) << 24 | static_cast<uint32_t>(bytes[1]) << 16 |
	       static_cast<uint32_t>(bytes[2]) << 8 | bytes[3];
}

GLuint load_raw_texture(const std::string& path, int& width, int& height) {
	std::ifstream input(path, std::ios::binary);
	unsigned char header[12]{};
	if (!input.read(reinterpret_cast<char*>(header), sizeof(header)) ||
	    std::memcmp(header, "R3AR", 4) != 0) return 0;
	width = static_cast<int>(read_be32(header + 4));
	height = static_cast<int>(read_be32(header + 8));
	if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return 0;
	std::vector<unsigned char> pixels(static_cast<std::size_t>(width) * height * 4);
	if (!input.read(reinterpret_cast<char*>(pixels.data()), pixels.size())) return 0;
	GLuint texture = 0;
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA,
	             GL_UNSIGNED_BYTE, pixels.data());
	return texture;
}

void load_brand(AndroidHost& host) {
	if (host.brand_texture != 0) glDeleteTextures(1, &host.brand_texture);
	host.brand_texture = load_raw_texture(call_string("getBrandLogoPath"),
	                                      host.brand_width, host.brand_height);
	retro_atarist::brand_logo(static_cast<ImTextureID>(host.brand_texture),
	                         host.brand_width, host.brand_height);
}

void load_artwork(AndroidHost& host, const char* media_type) {
	host.artwork_type = media_type != nullptr ? media_type : "box2d";
	for (const auto& [name, texture] : host.artwork_textures) {
		(void)name;
		glDeleteTextures(1, &texture);
	}
	host.artwork_textures.clear();
	retro_atarist::retro_media_artwork_begin();
	const std::string listing = call_string_arg("retroMediaArtwork", host.artwork_type.c_str());
	std::istringstream lines(listing);
	std::string line;
	while (std::getline(lines, line)) {
		const std::vector<std::string> fields = split(line, '|');
		if (fields.size() < 4) continue;
		std::ifstream input(fields[1], std::ios::binary);
		unsigned char header[12]{};
		if (!input.read(reinterpret_cast<char*>(header), sizeof(header)) ||
		    std::memcmp(header, "R3AR", 4) != 0) continue;
		const int width = static_cast<int>(read_be32(header + 4));
		const int height = static_cast<int>(read_be32(header + 8));
		if (width <= 0 || height <= 0 || width > 4096 || height > 4096) continue;
		std::vector<unsigned char> pixels(static_cast<std::size_t>(width) * height * 4);
		if (!input.read(reinterpret_cast<char*>(pixels.data()), pixels.size())) continue;
		GLuint texture = 0;
		glGenTextures(1, &texture);
		glBindTexture(GL_TEXTURE_2D, texture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, GL_BLUE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, GL_GREEN);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_B, GL_RED);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_A, GL_ALPHA);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA,
		             GL_UNSIGNED_BYTE, pixels.data());
		host.artwork_textures[fields[0]] = texture;
		retro_atarist::retro_media_artwork_item(
		    fields[0].c_str(), static_cast<ImTextureID>(texture), width, height);
	}
}

void load_catalogue() {
	retro_atarist::retro_media_catalogue_begin();
	std::istringstream lines(call_string("retroMediaCatalogueResult"));
	std::string line;
	while (std::getline(lines, line)) {
		const std::vector<std::string> fields = split(line, '|');
		if (fields.size() < 4) continue;
		retro_atarist::retro_media_catalogue_item(fields[0].c_str(), fields[1].c_str(),
		    std::atoi(fields[2].c_str()), std::strtoull(fields[3].c_str(), nullptr, 10));
	}
}

void poll_retro_media(AndroidHost& host) {
	const std::vector<std::string> progress = split(call_string("retroMediaDownloadProgress"), '|');
	if (progress.size() >= 2) {
		retro_atarist::retro_media_download_progress(
		    std::strtoull(progress[0].c_str(), nullptr, 10),
		    std::strtoull(progress[1].c_str(), nullptr, 10));
	}
	const std::string result = call_string("consumeRetroMediaResult");
	if (result.empty()) return;
	const std::vector<std::string> fields = split(result, '|');
	if (fields.size() < 9) {
		retro_atarist::retro_media_operation_finished(false, "Invalid RetroMedia response");
		return;
	}
	const bool ok = fields[0] == "OK";
	const std::string& operation = fields[1];
	const std::string& message = fields[8];
	if (!ok) {
		retro_atarist::retro_media_operation_finished(false, message.c_str());
		return;
	}
	retro_atarist::retro_media_account(true, !fields[2].empty(), fields[2].c_str(),
	    std::atoi(fields[3].c_str()), std::atoi(fields[4].c_str()), fields[7] == "1",
	    message.c_str());
	if (operation == "SYNC") load_artwork(host, host.artwork_type.c_str());
	else if (operation == "CATALOGUE") load_catalogue();
	else if (operation == "DOWNLOAD") {
		const std::string path = call_string("consumeDownloadedPath");
		retro_atarist::retro_media_downloaded(path.c_str(), message.c_str());
	}
}

bool initialise_egl(AndroidHost& host) {
	constexpr EGLint config_attributes[] = {
	    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
	    EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
	    EGL_DEPTH_SIZE, 0, EGL_NONE};
	constexpr EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
	host.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (host.display == EGL_NO_DISPLAY || !eglInitialize(host.display, nullptr, nullptr)) return false;
	EGLConfig config = nullptr;
	EGLint count = 0;
	if (!eglChooseConfig(host.display, config_attributes, &config, 1, &count) || count == 0) return false;
	EGLint format = 0;
	eglGetConfigAttrib(host.display, config, EGL_NATIVE_VISUAL_ID, &format);
	ANativeWindow_setBuffersGeometry(host.app->window, 0, 0, format);
	host.surface = eglCreateWindowSurface(host.display, config, host.app->window, nullptr);
	host.context = eglCreateContext(host.display, config, EGL_NO_CONTEXT, context_attributes);
	if (host.surface == EGL_NO_SURFACE || host.context == EGL_NO_CONTEXT ||
	    !eglMakeCurrent(host.display, host.surface, host.surface, host.context)) return false;
	eglQuerySurface(host.display, host.surface, EGL_WIDTH, &host.width);
	eglQuerySurface(host.display, host.surface, EGL_HEIGHT, &host.height);
	eglSwapInterval(host.display, 1);

	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO();
	io.IniFilename = nullptr;
	io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;
	ImFontConfig font;
	font.SizePixels = std::clamp(static_cast<float>(host.height) / 30.0f, 26.0f, 40.0f);
	io.Fonts->AddFontDefault(&font);
	ImGui_ImplAndroid_Init(host.app->window);
	ImGui_ImplOpenGL3_Init("#version 300 es");
	glGenTextures(1, &host.frame_texture);
	host.imgui_ready = true;
	g_host = &host;
	const std::string work = call_string("getWorkDirectory");
	const std::string tos = call_string("getTosDirectory");
	const std::string games = call_string("getGamesDirectory");
	host.frontend_ready = retro_atarist::initialise(work.c_str(), tos.c_str(), games.c_str());
	if (host.frontend_ready) {
		load_brand(host);
		load_artwork(host, host.artwork_type.c_str());
	}
	LOGI("native ImGui host ready (%dx%d)", host.width, host.height);
	return host.frontend_ready;
}

void shutdown_egl(AndroidHost& host) {
	if (host.imgui_ready) {
		for (const auto& [name, texture] : host.artwork_textures) {
			(void)name;
			glDeleteTextures(1, &texture);
		}
		host.artwork_textures.clear();
		retro_atarist::retro_media_artwork_begin();
		if (host.frame_texture != 0) glDeleteTextures(1, &host.frame_texture);
		if (host.brand_texture != 0) glDeleteTextures(1, &host.brand_texture);
		host.frame_texture = 0;
		host.brand_texture = 0;
		host.brand_width = 0;
		host.brand_height = 0;
		retro_atarist::brand_logo(ImTextureID_Invalid, 0, 0);
		host.uploaded_generation = 0;
		host.first_frame_logged = false;
		ImGui_ImplOpenGL3_Shutdown();
		ImGui_ImplAndroid_Shutdown();
		ImGui::DestroyContext();
		host.imgui_ready = false;
	}
	if (host.display != EGL_NO_DISPLAY) {
		eglMakeCurrent(host.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
		if (host.context != EGL_NO_CONTEXT) eglDestroyContext(host.display, host.context);
		if (host.surface != EGL_NO_SURFACE) eglDestroySurface(host.display, host.surface);
		eglTerminate(host.display);
	}
	host.display = EGL_NO_DISPLAY;
	host.surface = EGL_NO_SURFACE;
	host.context = EGL_NO_CONTEXT;
}

int android_key_to_atari(const int32_t key) {
	static constexpr int letters[26] = {
	    0x1e, 0x30, 0x2e, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26,
	    0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1f, 0x14, 0x16, 0x2f, 0x11, 0x2d,
	    0x15, 0x2c};
	if (key >= AKEYCODE_A && key <= AKEYCODE_Z) return letters[key - AKEYCODE_A];
	static constexpr int digits[10] = {0x0b, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a};
	if (key >= AKEYCODE_0 && key <= AKEYCODE_9) return digits[key - AKEYCODE_0];
	switch (key) {
		case AKEYCODE_ENTER: return 0x1c;
		case AKEYCODE_ESCAPE: case AKEYCODE_BACK: return 0x01;
		case AKEYCODE_DEL: return 0x0e;
		case AKEYCODE_TAB: return 0x0f;
		case AKEYCODE_SPACE: return 0x39;
		case AKEYCODE_DPAD_UP: return 0x48;
		case AKEYCODE_DPAD_DOWN: return 0x50;
		case AKEYCODE_DPAD_LEFT: return 0x4b;
		case AKEYCODE_DPAD_RIGHT: return 0x4d;
		default: return -1;
	}
}

int32_t handle_input(android_app* app, AInputEvent* event) {
	const int32_t imgui_handled = ImGui::GetCurrentContext() != nullptr
	    ? ImGui_ImplAndroid_HandleInputEvent(event) : 0;
	AndroidHost& host = *static_cast<AndroidHost*>(app->userData);
	const int32_t source = AInputEvent_getSource(event);
	const bool controller = (source & AINPUT_SOURCE_GAMEPAD) == AINPUT_SOURCE_GAMEPAD ||
	                        (source & AINPUT_SOURCE_JOYSTICK) == AINPUT_SOURCE_JOYSTICK ||
	                        (source & AINPUT_SOURCE_DPAD) == AINPUT_SOURCE_DPAD;
	if (controller && AInputEvent_getType(event) == AINPUT_EVENT_TYPE_MOTION) {
		constexpr float dead = 0.35f;
		float x = AMotionEvent_getAxisValue(event, AMOTION_EVENT_AXIS_X, 0);
		float y = AMotionEvent_getAxisValue(event, AMOTION_EVENT_AXIS_Y, 0);
		const float hat_x = AMotionEvent_getAxisValue(event, AMOTION_EVENT_AXIS_HAT_X, 0);
		const float hat_y = AMotionEvent_getAxisValue(event, AMOTION_EVENT_AXIS_HAT_Y, 0);
		if (std::fabs(hat_x) > std::fabs(x)) x = hat_x;
		if (std::fabs(hat_y) > std::fabs(y)) y = hat_y;
		host.joystick_axis_mask = 0;
		if (x < -dead) host.joystick_axis_mask |= ATARIST_JOY_LEFT;
		if (x > dead) host.joystick_axis_mask |= ATARIST_JOY_RIGHT;
		if (y < -dead) host.joystick_axis_mask |= ATARIST_JOY_UP;
		if (y > dead) host.joystick_axis_mask |= ATARIST_JOY_DOWN;
		retro_atarist::joystick_event(host.joystick_mask | host.joystick_axis_mask);
		return 1;
	}
	if (AInputEvent_getType(event) == AINPUT_EVENT_TYPE_KEY) {
		const int32_t key = AKeyEvent_getKeyCode(event);
		const int32_t action = AKeyEvent_getAction(event);
		const bool pressed = action == AKEY_EVENT_ACTION_DOWN;
		int joystick_bit = 0;
		if (controller) {
			switch (key) {
				case AKEYCODE_DPAD_UP: joystick_bit = ATARIST_JOY_UP; break;
				case AKEYCODE_DPAD_DOWN: joystick_bit = ATARIST_JOY_DOWN; break;
				case AKEYCODE_DPAD_LEFT: joystick_bit = ATARIST_JOY_LEFT; break;
				case AKEYCODE_DPAD_RIGHT: joystick_bit = ATARIST_JOY_RIGHT; break;
				case AKEYCODE_BUTTON_A: case AKEYCODE_BUTTON_B:
				case AKEYCODE_BUTTON_X: case AKEYCODE_BUTTON_Y:
					joystick_bit = ATARIST_JOY_FIRE;
					break;
				default: break;
			}
		}
		if (joystick_bit != 0) {
			if (pressed) host.joystick_mask |= joystick_bit;
			else host.joystick_mask &= ~joystick_bit;
			retro_atarist::joystick_event(host.joystick_mask | host.joystick_axis_mask);
			return 1;
		}
		const int scancode = android_key_to_atari(key);
		if (scancode >= 0 && (action == AKEY_EVENT_ACTION_DOWN || action == AKEY_EVENT_ACTION_UP)) {
			retro_atarist::key_event(scancode, pressed);
			return 1;
		}
	}
	return imgui_handled;
}

void handle_command(android_app* app, const int32_t command) {
	AndroidHost& host = *static_cast<AndroidHost*>(app->userData);
	switch (command) {
		case APP_CMD_INIT_WINDOW:
			if (app->window != nullptr && !host.imgui_ready && !initialise_egl(host)) {
				LOGE("failed to initialise EGL/ImGui");
			}
			break;
		case APP_CMD_TERM_WINDOW: shutdown_egl(host); break;
		case APP_CMD_RESUME: case APP_CMD_GAINED_FOCUS:
			host.resumed = true;
			retro_atarist::pause_for_lifecycle(false);
			break;
		case APP_CMD_PAUSE: case APP_CMD_LOST_FOCUS:
			host.resumed = false;
			retro_atarist::pause_for_lifecycle(true);
			break;
		default: break;
	}
}

void render(AndroidHost& host) {
	{
		std::scoped_lock lock(host.pending_mutex);
		for (const PendingImport& imported : host.imports) {
			retro_atarist::imported_file(imported.kind, imported.path.c_str());
		}
		host.imports.clear();
	}
	poll_retro_media(host);
	using clock = std::chrono::steady_clock;
	const double now_ms = std::chrono::duration<double, std::milli>(
	    clock::now().time_since_epoch()).count();
	retro_atarist::tick(now_ms);
	const retro_atarist::Frame frame = retro_atarist::frame();
	if (frame.pixels != nullptr && frame.width > 0 && frame.height > 0 &&
	    frame.generation != host.uploaded_generation) {
		if (!host.first_frame_logged) {
			LOGI("Hatari first frame ready (%dx%d, generation %llu)", frame.width, frame.height,
			     static_cast<unsigned long long>(frame.generation));
			host.first_frame_logged = true;
		}
		glBindTexture(GL_TEXTURE_2D, host.frame_texture);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, frame.width, frame.height, 0,
		             GL_RGBA, GL_UNSIGNED_BYTE, frame.pixels);
		host.texture_width = frame.width;
		host.texture_height = frame.height;
		host.uploaded_generation = frame.generation;
	}
	ImGui_ImplOpenGL3_NewFrame();
	ImGui_ImplAndroid_NewFrame();
	ImGui::NewFrame();
	retro_atarist::draw(static_cast<ImTextureID>(host.frame_texture),
	                    static_cast<float>(host.width), static_cast<float>(host.height));
	ImGui::Render();
	glViewport(0, 0, host.width, host.height);
	glClearColor(0.018f, 0.020f, 0.026f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
	eglSwapBuffers(host.display, host.surface);
}

}  // namespace

namespace retro_atarist {

void platform_open_document(const ImportKind kind) { call_void_int("openDocumentPicker", static_cast<int>(kind)); }
void platform_retro_media_restore() { call_void("retroMediaStatus"); }
void platform_retro_media_sign_in(const char* email, const char* password) {
	call_void_two_strings("retroMediaLogin", email, password);
}
void platform_retro_media_sign_out() { call_void("retroMediaLogout"); }
void platform_retro_media_load_artwork(const char* media_type) {
	if (g_host != nullptr) load_artwork(*g_host, media_type);
}
void platform_retro_media_sync_artwork(const char* media_type, const char* game_names) {
	call_void_two_strings("retroMediaSync", game_names, media_type);
}
bool platform_game_downloads_available() { return true; }
void platform_retro_media_browse(const char* search) { call_void_string("retroMediaBrowse", search); }
void platform_retro_media_download(const char* slug) { call_void_string("retroMediaDownload", slug); }

}  // namespace retro_atarist

extern "C" JNIEXPORT void JNICALL
Java_com_crownparkcomputing_retroatarist_RetroAtariSTActivity_nativeDocumentImported(
    JNIEnv* env, jclass, jint kind, jstring path) {
	if (g_host == nullptr || path == nullptr) return;
	const char* text = env->GetStringUTFChars(path, nullptr);
	PendingImport imported;
	imported.kind = kind == static_cast<int>(retro_atarist::ImportKind::Rom)
	    ? retro_atarist::ImportKind::Rom : retro_atarist::ImportKind::Software;
	if (text != nullptr) imported.path = text;
	if (text != nullptr) env->ReleaseStringUTFChars(path, text);
	std::scoped_lock lock(g_host->pending_mutex);
	g_host->imports.push_back(std::move(imported));
}

extern "C" void android_main(android_app* app) {
	auto storage = std::make_unique<AndroidHost>();
	AndroidHost& host = *storage;
	host.app = app;
	g_host = &host;
	app->userData = &host;
	app->onAppCmd = handle_command;
	app->onInputEvent = handle_input;
	while (app->destroyRequested == 0) {
		android_poll_source* source = nullptr;
		int events = 0;
		const int timeout = host.imgui_ready && host.resumed ? 0 : -1;
		if (ALooper_pollOnce(timeout, nullptr, &events, reinterpret_cast<void**>(&source)) >= 0 &&
		    source != nullptr) source->process(app, source);
		while (app->destroyRequested == 0) {
			source = nullptr;
			if (ALooper_pollOnce(0, nullptr, &events, reinterpret_cast<void**>(&source)) < 0) break;
			if (source != nullptr) source->process(app, source);
		}
		if (host.imgui_ready && host.resumed) render(host);
	}
	retro_atarist::shutdown();
	shutdown_egl(host);
	g_host = nullptr;
}
