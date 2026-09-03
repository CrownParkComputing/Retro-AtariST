#pragma once

#include <cstdint>
#include <string>

#include "imgui.h"

namespace retro_atarist {

enum class ImportKind {
	Rom,
	Software,
};

struct Frame {
	const uint32_t* pixels = nullptr;
	int width = 0;
	int height = 0;
	int pitch_bytes = 0;
	double display_aspect = 4.0 / 3.0;
	uint64_t generation = 0;
};

// Implemented by the iOS shell. The picker copies the selected file into the
// app's Documents/AtariST tree, then calls imported_file().
void platform_open_document(ImportKind kind);
void platform_retro_media_restore();
void platform_retro_media_sign_in(const char* email, const char* password);
void platform_retro_media_sign_out();
void platform_retro_media_load_artwork(const char* media_type);
void platform_retro_media_sync_artwork(const char* media_type, const char* game_names);
bool platform_game_downloads_available();
void platform_retro_media_browse(const char* search);
void platform_retro_media_download(const char* slug);

bool initialise(const char* work_dir, const char* tos_dir, const char* games_dir);
void shutdown();
void tick(double now_ms);
Frame frame();
void draw(ImTextureID frame_texture, float display_width, float display_height);
void brand_logo(ImTextureID texture, int width, int height);

// The area of the display the system does not cover. On a phone with a
// cutout or a home indicator this is smaller than the display, and drawing
// from (0,0) puts the top of the UI underneath the cutout. Defaults to zero,
// so a platform that does not set it behaves exactly as before.
void safe_area_insets(float left, float top, float right, float bottom);

void imported_file(ImportKind kind, const char* path);
void key_event(int st_scancode, bool pressed);
void joystick_event(int mask);
void pause_for_lifecycle(bool paused);

// Platform callbacks are delivered on the UI thread. ImTextureID values remain
// owned by the platform renderer and are only borrowed by the frontend.
void retro_media_account(bool ok, bool signed_in, const char* email, int credits,
	                     int free_remaining, bool is_admin, const char* message);
void retro_media_artwork_begin();
void retro_media_artwork_item(const char* local_name, ImTextureID texture,
	                          int width, int height);
void retro_media_catalogue_begin();
void retro_media_catalogue_item(const char* slug, const char* title,
	                            int file_count, uint64_t total_bytes);
void retro_media_download_progress(uint64_t transferred_bytes, uint64_t total_bytes);
void retro_media_operation_finished(bool ok, const char* message);
void retro_media_downloaded(const char* path, const char* message);

}  // namespace retro_atarist
