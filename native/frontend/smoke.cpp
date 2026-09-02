#include "frontend.h"

#include <filesystem>

namespace retro_atarist {
void platform_open_document(ImportKind) {}
void platform_retro_media_restore() {}
void platform_retro_media_sign_in(const char*, const char*) {}
void platform_retro_media_sign_out() {}
void platform_retro_media_load_artwork(const char*) {}
void platform_retro_media_sync_artwork(const char*, const char*) {}
bool platform_game_downloads_available() { return false; }
void platform_retro_media_browse(const char*) {}
void platform_retro_media_download(const char*) {}
}  // namespace retro_atarist

int main(int argc, char** argv) {
	if (argc != 2) return 2;
	const std::filesystem::path root(argv[1]);
	const std::filesystem::path work = root / "work";
	const std::filesystem::path tos = root / "tos";
	const std::filesystem::path games = root / "games";

	IMGUI_CHECKVERSION();
	ImGui::CreateContext();
	ImGuiIO& io = ImGui::GetIO();
	io.IniFilename = nullptr;
	io.DisplaySize = ImVec2(1280.0f, 720.0f);
	io.DeltaTime = 1.0f / 60.0f;
	unsigned char* font_pixels = nullptr;
	int font_width = 0;
	int font_height = 0;
	io.Fonts->GetTexDataAsRGBA32(&font_pixels, &font_width, &font_height);
	if (!retro_atarist::initialise(work.c_str(), tos.c_str(), games.c_str())) return 1;
	ImGui::NewFrame();
	retro_atarist::tick(1000.0);
	retro_atarist::draw(ImTextureID_Invalid, io.DisplaySize.x, io.DisplaySize.y);
	ImGui::Render();
	retro_atarist::shutdown();
	ImGui::DestroyContext();
	return 0;
}
