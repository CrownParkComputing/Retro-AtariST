#include "frontend.h"

#include "atarist_bridge.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cctype>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <cstdio>
#include <fstream>
#include <string>
#include <system_error>
#include <unordered_map>
#include <utility>
#include <vector>

namespace retro_atarist {
namespace {

namespace fs = std::filesystem;

enum class Screen {
	Library,
	Artwork,
	Downloads,
	Machine,
	Demo,
	About,
};

struct MediaFile {
	std::string name;
	std::string path;
};

struct GameEntry {
	std::string name;
	std::string media_path;
	std::string tos_path;
	int model = ATARIST_MACHINE_ST;
	int memory_kb = 1024;
	int monitor = ATARIST_MONITOR_RGB;
	bool configured = false;
};

struct Artwork {
	ImTextureID texture = ImTextureID_Invalid;
	int width = 0;
	int height = 0;
};

struct CatalogueItem {
	std::string slug;
	std::string title;
	int file_count = 0;
	uint64_t total_bytes = 0;
};

struct AppState {
	bool initialised = false;
	bool lifecycle_paused = false;
	bool paused_before_lifecycle = false;
	bool show_emulator = false;
	bool show_pad = true;
	bool show_keyboard = false;
	bool accurate_floppy = false;
	bool stereo = true;
	int model = ATARIST_MACHINE_ST;
	int memory_kb = 1024;
	int monitor = ATARIST_MONITOR_RGB;
	int display_aspect_mode = 0;
	int rom_choice = -1;
	int software_choice = -1;
	int physical_joystick_mask = 0;
	int onscreen_joystick_mask = 0;
	int active_disk_index = 0;
	Screen screen = Screen::Library;
	std::string work_dir;
	std::string tos_dir;
	std::string games_dir;
	std::vector<MediaFile> roms;
	std::vector<MediaFile> software;
	std::vector<GameEntry> games;
	std::vector<MediaFile> active_disks;
	std::unordered_map<std::string, Artwork> artwork;
	Artwork brand_logo;

	// The display area the system does not cover. Zero unless a platform sets
	// it, so every non-Apple target is unaffected.
	float safe_left = 0.0f;
	float safe_top = 0.0f;
	float safe_right = 0.0f;
	float safe_bottom = 0.0f;
	std::vector<CatalogueItem> catalogue;
	bool retro_media_busy = false;
	bool retro_media_signed_in = false;
	bool retro_media_admin = false;
	int retro_media_credits = 0;
	int retro_media_free = 0;
	std::string retro_media_email;
	std::string retro_media_message = "Checking account...";
	std::string retro_media_type = "box2d";
	std::string retro_media_download_slug;
	uint64_t retro_media_download_bytes = 0;
	uint64_t retro_media_download_total = 0;
	std::array<char, 192> email_buffer{};
	std::array<char, 192> password_buffer{};
	std::array<char, 192> search_buffer{};
	std::array<char, 192> library_search_buffer{};
	std::array<char, 128> config_name_buffer{};
	int library_filter = 1;
	bool creating_config = false;
	int catalogue_filter = 1;
	std::vector<uint32_t> frame_pixels;
	Frame current_frame;
	int64_t observed_frame = -1;
	double pending_key_release_ms = 0.0;
	double now_ms = 0.0;
	double menu_visible_until_ms = 0.0;
	int pending_key = -1;
	std::string error;
};

AppState g;

bool game_downloads_visible() {
	return platform_game_downloads_available()
	    && g.retro_media_signed_in
	    && g.retro_media_admin;
}

constexpr ImU32 rgba(const int r, const int green, const int b, const int a = 255) {
	return IM_COL32(r, green, b, a);
}

float ui_scale() {
	const ImGuiIO& io = ImGui::GetIO();
	return std::clamp(std::min(io.DisplaySize.x / 1100.0f, io.DisplaySize.y / 650.0f),
	                  0.72f, 1.55f);
}

std::string lower_extension(const fs::path& path) {
	std::string extension = path.extension().string();
	std::transform(extension.begin(), extension.end(), extension.begin(),
	               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return extension;
}

bool is_software(const fs::path& path) {
	const std::string extension = lower_extension(path);
	return extension == ".st" || extension == ".msa" || extension == ".dim" ||
	       extension == ".stx" || extension == ".ipf" || extension == ".zip" ||
	       extension == ".img";
}

bool looks_like_rom(const fs::path& path) {
	std::error_code error;
	const uintmax_t size = fs::file_size(path, error);
	if (error || (size != 192 * 1024 && size != 256 * 1024 &&
	              size != 512 * 1024 && size != 1024 * 1024)) {
		return false;
	}
	FILE* file = std::fopen(path.string().c_str(), "rb");
	if (file == nullptr) return false;
	unsigned char header[2]{};
	const bool valid = std::fread(header, 1, sizeof(header), file) == sizeof(header) &&
	                   header[0] == 0x60 && header[1] == 0x2e;
	std::fclose(file);
	return valid;
}

int tos_version(const std::string& path) {
	FILE* file = std::fopen(path.c_str(), "rb");
	if (file == nullptr) return 0;
	unsigned char header[4]{};
	const bool valid = std::fread(header, 1, sizeof(header), file) == sizeof(header) &&
	                   header[0] == 0x60 && header[1] == 0x2e;
	std::fclose(file);
	return valid ? (static_cast<int>(header[2]) << 8 | header[3]) : 0;
}

bool is_emutos(const MediaFile& rom) {
	std::string text = rom.name + " " + rom.path;
	std::transform(text.begin(), text.end(), text.begin(),
	               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return text.find("emutos") != std::string::npos || text.find("etos") != std::string::npos;
}

int tos_compatibility_score(const int machine, const int version) {
	switch (machine) {
		case ATARIST_MACHINE_ST:
		case ATARIST_MACHINE_MEGA_ST:
			if (version == 0x0102) return 100;
			if (version == 0x0104) return 90;
			break;
		case ATARIST_MACHINE_STE:
			if (version == 0x0162) return 100;
			if (version == 0x0206) return 90;
			break;
		case ATARIST_MACHINE_MEGA_STE:
			if (version == 0x0206) return 100;
			break;
		case ATARIST_MACHINE_TT:
			if (version == 0x0306) return 100;
			break;
		case ATARIST_MACHINE_FALCON:
			if (version == 0x0404) return 100;
			if (version == 0x0492) return 90;
			break;
		default: break;
	}
	return 0;
}

int recommended_rom_index(const int machine, const bool emutos_only = false) {
	int best = -1;
	int best_score = -1;
	for (std::size_t index = 0; index < g.roms.size(); ++index) {
		const bool emutos = is_emutos(g.roms[index]);
		if (emutos_only) {
			if (emutos) return static_cast<int>(index);
			continue;
		}
		const int score = emutos ? 1 : tos_compatibility_score(machine, tos_version(g.roms[index].path));
		if (score <= 0) continue;
		if (score > best_score) {
			best = static_cast<int>(index);
			best_score = score;
		}
	}
	return best;
}

void scan_directory(const std::string& root, std::vector<MediaFile>& output,
	                const bool roms) {
	output.clear();
	std::error_code error;
	if (root.empty() || !fs::exists(root, error)) return;
	for (fs::recursive_directory_iterator it(root, fs::directory_options::skip_permission_denied,
	                                         error), end;
	     it != end && !error; it.increment(error)) {
		if (!it->is_regular_file(error)) continue;
		const fs::path path = it->path();
		if ((roms && looks_like_rom(path)) || (!roms && is_software(path))) {
			output.push_back({path.stem().string(), path.string()});
		}
	}
	std::sort(output.begin(), output.end(), [](const MediaFile& a, const MediaFile& b) {
		return a.name < b.name;
	});
}

std::vector<MediaFile> disk_set_for(const std::string& media_path) {
	std::vector<MediaFile> disks;
	if (media_path.empty()) return disks;
	const fs::path selected(media_path);
	const fs::path parent = selected.parent_path().lexically_normal();
	const fs::path library_root = fs::path(g.games_dir).lexically_normal();
	std::error_code error;
	if (!parent.empty() && parent != library_root && fs::is_directory(parent, error)) {
		for (fs::directory_iterator it(parent, fs::directory_options::skip_permission_denied, error), end;
		     it != end && !error; it.increment(error)) {
			if (!it->is_regular_file(error) || !is_software(it->path())) continue;
			disks.push_back({it->path().stem().string(), it->path().string()});
		}
	}
	if (disks.empty()) disks.push_back({selected.stem().string(), selected.string()});
	std::sort(disks.begin(), disks.end(), [](const MediaFile& left, const MediaFile& right) {
		std::string a = left.name;
		std::string b = right.name;
		std::transform(a.begin(), a.end(), a.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		std::transform(b.begin(), b.end(), b.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		return a < b;
	});
	return disks;
}

void rebuild_games() {
	g.games.clear();
	std::unordered_map<std::string, std::vector<const MediaFile*>> downloaded_sets;
	const fs::path library_root = fs::path(g.games_dir).lexically_normal();
	for (const MediaFile& media : g.software) {
		const fs::path parent = fs::path(media.path).parent_path().lexically_normal();
		if (!parent.empty() && parent != library_root) {
			downloaded_sets[parent.string()].push_back(&media);
		} else {
			g.games.push_back({media.name, media.path, {}, ATARIST_MACHINE_ST, 1024,
			                   ATARIST_MONITOR_RGB, false});
		}
	}
	for (auto& [directory, media] : downloaded_sets) {
		std::sort(media.begin(), media.end(), [](const MediaFile* left, const MediaFile* right) {
			return left->name < right->name;
		});
		if (media.empty()) continue;
		const std::string title = fs::path(directory).filename().string();
		g.games.push_back({title.empty() ? media.front()->name : title,
		                   media.front()->path, {}, ATARIST_MACHINE_ST, 1024,
		                   ATARIST_MONITOR_RGB, false});
	}
	std::error_code error;
	if (!g.games_dir.empty() && fs::exists(g.games_dir, error)) {
		for (fs::recursive_directory_iterator it(g.games_dir,
		         fs::directory_options::skip_permission_denied, error), end;
		     it != end && !error; it.increment(error)) {
			if (!it->is_regular_file(error) || lower_extension(it->path()) != ".rast") continue;
			GameEntry entry;
			entry.configured = true;
			std::ifstream input(it->path());
			std::string line;
			while (std::getline(input, line)) {
				const std::size_t equals = line.find('=');
				if (equals == std::string::npos) continue;
				const std::string key = line.substr(0, equals);
				const std::string value = line.substr(equals + 1);
				if (key == "name") entry.name = value;
				else if (key == "media") entry.media_path = value;
				else if (key == "tos") entry.tos_path = value;
				else if (key == "model") entry.model = std::atoi(value.c_str());
				else if (key == "memory_kb") entry.memory_kb = std::atoi(value.c_str());
				else if (key == "monitor") entry.monitor = std::atoi(value.c_str());
			}
			if (!entry.name.empty() && fs::is_regular_file(entry.media_path, error)) {
				g.games.push_back(std::move(entry));
			}
		}
	}
	std::sort(g.games.begin(), g.games.end(), [](const GameEntry& left, const GameEntry& right) {
		std::string a = left.name;
		std::string b = right.name;
		std::transform(a.begin(), a.end(), a.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		std::transform(b.begin(), b.end(), b.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		return a < b;
	});
}

void rescan() {
	const std::string old_rom = g.rom_choice >= 0 && g.rom_choice < static_cast<int>(g.roms.size())
	                                ? g.roms[g.rom_choice].path
	                                : std::string();
	const std::string old_software =
	    g.software_choice >= 0 && g.software_choice < static_cast<int>(g.software.size())
	        ? g.software[g.software_choice].path
	        : std::string();
	scan_directory(g.tos_dir, g.roms, true);
	scan_directory(g.games_dir, g.software, false);
	rebuild_games();
	g.rom_choice = g.roms.empty() ? -1 : 0;
	g.software_choice = g.software.empty() ? -1 : 0;
	for (std::size_t i = 0; i < g.roms.size(); ++i) {
		if (g.roms[i].path == old_rom) g.rom_choice = static_cast<int>(i);
	}
	for (std::size_t i = 0; i < g.software.size(); ++i) {
		if (g.software[i].path == old_software) g.software_choice = static_cast<int>(i);
	}
}

void apply_style() {
	ImGuiStyle& style = ImGui::GetStyle();
	ImGui::StyleColorsDark(&style);
	style.WindowRounding = 0.0f;
	style.ChildRounding = 12.0f;
	style.FrameRounding = 9.0f;
	style.PopupRounding = 10.0f;
	style.GrabRounding = 8.0f;
	style.ScrollbarRounding = 8.0f;
	style.FramePadding = ImVec2(14.0f, 11.0f);
	style.ItemSpacing = ImVec2(10.0f, 10.0f);
	style.TouchExtraPadding = ImVec2(4.0f, 4.0f);
	style.Colors[ImGuiCol_WindowBg] = ImVec4(0.018f, 0.020f, 0.026f, 0.98f);
	style.Colors[ImGuiCol_ChildBg] = ImVec4(0.055f, 0.060f, 0.072f, 0.96f);
	style.Colors[ImGuiCol_FrameBg] = ImVec4(0.10f, 0.11f, 0.13f, 1.0f);
	style.Colors[ImGuiCol_Button] = ImVec4(0.25f, 0.28f, 0.32f, 1.0f);
	style.Colors[ImGuiCol_ButtonHovered] = ImVec4(0.72f, 0.10f, 0.12f, 1.0f);
	style.Colors[ImGuiCol_ButtonActive] = ImVec4(0.90f, 0.12f, 0.13f, 1.0f);
	style.Colors[ImGuiCol_Header] = ImVec4(0.45f, 0.08f, 0.10f, 1.0f);
	style.Colors[ImGuiCol_HeaderHovered] = ImVec4(0.76f, 0.11f, 0.13f, 1.0f);
	style.Colors[ImGuiCol_CheckMark] = ImVec4(0.96f, 0.18f, 0.18f, 1.0f);
}

void heading(const char* title, const char* subtitle) {
	(void)title;
	(void)subtitle;
}

void begin_card(const char* id) {
	ImGui::BeginChild(id, ImVec2(0, 0),
	                  ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding);
}

bool nav_button(const char* label, const Screen screen, const float width) {
	const bool selected = g.screen == screen;
	if (selected) ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.78f, 0.07f, 0.09f, 1.0f));
	const bool clicked = ImGui::Button(label, ImVec2(width, 48.0f * ui_scale()));
	if (selected) ImGui::PopStyleColor();
	if (clicked) g.screen = screen;
	return clicked;
}

void media_combo(const char* id, const std::vector<MediaFile>& files, int& choice,
	             const char* empty) {
	const char* preview = choice >= 0 && choice < static_cast<int>(files.size())
	                          ? files[choice].name.c_str()
	                          : empty;
	ImGui::SetNextItemWidth(-1);
	if (!ImGui::BeginCombo(id, preview)) return;
	for (std::size_t i = 0; i < files.size(); ++i) {
		const bool selected = static_cast<int>(i) == choice;
		if (ImGui::Selectable(files[i].name.c_str(), selected)) choice = static_cast<int>(i);
		if (selected) ImGui::SetItemDefaultFocus();
	}
	if (files.empty()) ImGui::TextDisabled("No matching files found");
	ImGui::EndCombo();
}

std::string bundled_demo_path() {
	return (fs::path(g.work_dir) / "retro-atarist-core-demo.st").string();
}

void start_selected(const bool bundled_demo = false, const GameEntry* game = nullptr) {
	int rom_index = g.rom_choice;
	if (bundled_demo) {
		rom_index = recommended_rom_index(ATARIST_MACHINE_ST, true);
	} else if (game != nullptr) {
		rom_index = -1;
		if (!game->tos_path.empty() && fs::is_regular_file(game->tos_path)) {
			for (std::size_t index = 0; index < g.roms.size(); ++index) {
				if (g.roms[index].path == game->tos_path) rom_index = static_cast<int>(index);
			}
		}
		if (rom_index < 0) rom_index = recommended_rom_index(game->model);
	}
	if (rom_index < 0 || rom_index >= static_cast<int>(g.roms.size())) {
		g.error = "Choose an EmuTOS or TOS ROM first.";
		return;
	}
	AtariStConfig config{};
	config.machine = game != nullptr ? game->model : g.model;
	config.memory_kb = game != nullptr ? game->memory_kb : g.memory_kb;
	config.tos_path = g.roms[rom_index].path.c_str();
	config.blitter = config.machine != ATARIST_MACHINE_ST;
	config.accurate_floppy = g.accurate_floppy;
	config.sample_rate = 44100;
	config.stereo = g.stereo;
	config.monitor = game != nullptr ? game->monitor : g.monitor;
	config.joystick_port1 = 1;
	config.work_dir = g.work_dir.c_str();
	const std::string demo = bundled_demo ? bundled_demo_path() : std::string();
	std::string initial_media;
	if (bundled_demo) {
		if (!fs::is_regular_file(demo)) {
			g.error = "The bundled core demo could not be found.";
			return;
		}
		initial_media = demo;
	} else if (game != nullptr) {
		initial_media = game->media_path;
	} else if (g.software_choice >= 0 && g.software_choice < static_cast<int>(g.software.size())) {
		initial_media = g.software[g.software_choice].path;
	}
	config.floppy_a = initial_media.empty() ? nullptr : initial_media.c_str();
	const int result = atarist_core_start(&config);
	if (result != ATARIST_OK) {
		const char* detail = atarist_core_last_error();
		g.error = detail != nullptr ? detail : "Hatari could not start the selected machine.";
		return;
	}
	g.error.clear();
	g.observed_frame = -1;
	g.active_disks = bundled_demo ? std::vector<MediaFile>{{"Demo", demo}}
	                              : disk_set_for(initial_media);
	g.active_disk_index = 0;
	for (std::size_t index = 0; index < g.active_disks.size(); ++index) {
		if (g.active_disks[index].path == initial_media) {
			g.active_disk_index = static_cast<int>(index);
			break;
		}
	}
	g.onscreen_joystick_mask = 0;
	atarist_core_joystick(1, g.physical_joystick_mask);
	g.menu_visible_until_ms = g.now_ms + 3000.0;
	g.show_emulator = true;
}

bool library_game_matches(const GameEntry& game) {
	const auto first = std::find_if(game.name.begin(), game.name.end(),
	                                [](const unsigned char c) { return std::isalnum(c) != 0; });
	if (g.library_filter == 1 &&
	    (first == game.name.end() || !std::isdigit(static_cast<unsigned char>(*first)))) return false;
	if (g.library_filter >= 2 &&
	    (first == game.name.end() || std::toupper(static_cast<unsigned char>(*first)) !=
	                                 'A' + g.library_filter - 2)) return false;
	std::string query(g.library_search_buffer.data());
	std::string title = game.name;
	std::transform(query.begin(), query.end(), query.begin(),
	               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
	std::transform(title.begin(), title.end(), title.begin(),
	               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
	return query.empty() || title.find(query) != std::string::npos;
}

std::string safe_config_name(const char* text) {
	std::string result = text != nullptr ? text : "";
	for (char& c : result) {
		if (!std::isalnum(static_cast<unsigned char>(c)) && c != '-' && c != '_') c = '_';
	}
	return result.empty() ? "My_Atari_ST" : result;
}

void draw_config_editor() {
	heading("New configuration", "Select detected media and create an Atari ST setup.");
	begin_card("config-card");
	if (ImGui::Button("Back to library", ImVec2(-1, 48.0f * ui_scale()))) {
		g.creating_config = false;
	}
	ImGui::InputTextWithHint("##config-name", "Configuration name",
	                         g.config_name_buffer.data(), g.config_name_buffer.size());
	media_combo("##config-media", g.software, g.software_choice, "No local games detected");
	constexpr const char* models[] = {"Atari ST", "Mega ST", "Atari STE", "Mega STE", "TT", "Falcon 030"};
	ImGui::SetNextItemWidth(-1);
	if (ImGui::Combo("##config-model", &g.model, models, IM_ARRAYSIZE(models))) {
		g.rom_choice = recommended_rom_index(g.model);
	}
	media_combo("##config-rom", g.roms, g.rom_choice, "No compatible TOS/EmuTOS installed");
	constexpr int memories[] = {512, 1024, 2048, 4096, 8192, 14336};
	constexpr const char* memory_names[] = {"512 KB", "1 MB", "2 MB", "4 MB", "8 MB", "14 MB"};
	int memory_choice = 1;
	for (int i = 0; i < IM_ARRAYSIZE(memories); ++i) if (g.memory_kb == memories[i]) memory_choice = i;
	ImGui::SetNextItemWidth(-1);
	if (ImGui::Combo("##config-memory", &memory_choice, memory_names, IM_ARRAYSIZE(memory_names))) {
		g.memory_kb = memories[memory_choice];
	}
	constexpr const char* monitors[] = {"High-resolution mono", "Colour RGB", "VGA", "Television"};
	ImGui::SetNextItemWidth(-1);
	ImGui::Combo("##config-monitor", &g.monitor, monitors, IM_ARRAYSIZE(monitors));
	ImGui::BeginDisabled(g.software_choice < 0 || g.rom_choice < 0 || g.roms.empty());
	if (ImGui::Button("Save configuration and boot", ImVec2(-1, 60.0f * ui_scale()))) {
		const MediaFile& media = g.software[static_cast<std::size_t>(g.software_choice)];
		const std::string title = g.config_name_buffer[0] != '\0'
		    ? g.config_name_buffer.data() : media.name;
		const fs::path directory = fs::path(g.games_dir) / "Configurations";
		std::error_code error;
		fs::create_directories(directory, error);
		const fs::path path = directory / (safe_config_name(title.c_str()) + ".rast");
		std::ofstream output(path);
		output << "name=" << title << '\n' << "media=" << media.path << '\n'
		       << "tos=" << g.roms[static_cast<std::size_t>(g.rom_choice)].path << '\n'
		       << "model=" << g.model << '\n' << "memory_kb=" << g.memory_kb << '\n'
		       << "monitor=" << g.monitor << '\n';
		if (!output.good()) {
			g.error = "The configuration could not be saved.";
		} else {
			output.close();
			GameEntry entry{title, media.path,
			                g.roms[static_cast<std::size_t>(g.rom_choice)].path,
			                g.model, g.memory_kb, g.monitor, true};
			rescan();
			g.creating_config = false;
			start_selected(false, &entry);
		}
	}
	ImGui::EndDisabled();
	if (!g.error.empty()) {
		ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.30f, 1.0f), "%s", g.error.c_str());
	}
	ImGui::EndChild();
}

void draw_game_browser() {
	const float scale = ui_scale();
	const float plus_width = 76.0f * scale;
	ImGui::SetCursorPosX(ImGui::GetWindowWidth() - plus_width - ImGui::GetStyle().WindowPadding.x);
	if (ImGui::Button("+", ImVec2(plus_width, 46.0f * scale))) {
		g.creating_config = true;
		g.rom_choice = recommended_rom_index(g.model);
		g.error.clear();
	}
	ImGui::InputTextWithHint("##library-search", "Search local games...",
	                         g.library_search_buffer.data(), g.library_search_buffer.size());
	constexpr const char* filters[] = {
	    "0-9", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
	    "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"};
	std::array<bool, IM_ARRAYSIZE(filters)> available_filters{};
	for (const auto& game : g.games) {
		const auto first = std::find_if(game.name.begin(), game.name.end(),
		                                [](const unsigned char c) { return std::isalnum(c); });
		if (first == game.name.end()) continue;
		const unsigned char initial = static_cast<unsigned char>(*first);
		if (std::isdigit(initial)) {
			available_filters[0] = true;
		} else {
			const int normalized = std::tolower(initial);
			if (normalized >= 'a' && normalized <= 'z') {
				available_filters[1 + normalized - 'a'] = true;
			}
		}
	}
	if (g.library_filter < 1 || g.library_filter > IM_ARRAYSIZE(filters)
	    || !available_filters[g.library_filter - 1]) {
		const auto first_available = std::find(available_filters.begin(), available_filters.end(), true);
		if (first_available != available_filters.end()) {
			g.library_filter = static_cast<int>(std::distance(available_filters.begin(), first_available)) + 1;
		}
	}
	ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4.0f, 8.0f));
	ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(1.0f, 8.0f));
	ImGui::SetWindowFontScale(0.68f);
	const int filter_count = static_cast<int>(std::count(available_filters.begin(), available_filters.end(), true));
	const float filter_width = std::max(38.0f,
	    (ImGui::GetContentRegionAvail().x
	     - ImGui::GetStyle().ItemSpacing.x * std::max(0, filter_count - 1))
	        / std::max(1, filter_count));
	int drawn_filters = 0;
	for (int index = 0; index < IM_ARRAYSIZE(filters); ++index) {
		if (!available_filters[index]) continue;
		if (drawn_filters++ != 0) ImGui::SameLine();
		const int filter = index + 1;
		const bool selected = g.library_filter == filter;
		if (selected) ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.78f, 0.07f, 0.09f, 1.0f));
		if (ImGui::Button(filters[index], ImVec2(filter_width, 44.0f * scale))) g.library_filter = filter;
		if (selected) ImGui::PopStyleColor();
	}
	ImGui::SetWindowFontScale(1.0f);
	ImGui::PopStyleVar(2);
	ImGui::NewLine();
	ImGui::BeginChild("##game-list", ImVec2(0, 0), ImGuiChildFlags_Borders,
	                  ImGuiWindowFlags_AlwaysVerticalScrollbar);
	const float available = ImGui::GetContentRegionAvail().x;
	const int columns = available > 1280.0f ? 4 : available > 820.0f ? 3 : 2;
	std::size_t shown = 0;
	if (ImGui::BeginTable("##game-cards", columns,
	                      ImGuiTableFlags_SizingStretchSame | ImGuiTableFlags_PadOuterX)) {
		for (const GameEntry& game : g.games) {
			if (!library_game_matches(game)) continue;
			ImGui::TableNextColumn();
			ImGui::PushID(&game);
			ImGui::BeginChild("##card", ImVec2(0, 350.0f * scale),
			                  ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding);
			const float button_height = 44.0f * scale;
			const float gap = 8.0f * scale;
			const float inner_width = ImGui::GetContentRegionAvail().x;
			ImGui::SetWindowFontScale(0.82f);
			const float title_height = ImGui::CalcTextSize(
			    game.name.c_str(), nullptr, false, inner_width).y;
			ImGui::SetWindowFontScale(1.0f);
			const auto art = g.artwork.find(fs::path(game.media_path).stem().string());
			float artwork_width = 0.0f;
			float artwork_draw_height = 0.0f;
			if (art != g.artwork.end() && art->second.texture != ImTextureID_Invalid) {
				const float aspect = art->second.height > 0
				    ? static_cast<float>(art->second.width) / static_cast<float>(art->second.height)
				    : 0.75f;
				const float max_artwork_height = 230.0f * scale;
				artwork_width = std::min(inner_width, max_artwork_height * aspect);
				artwork_draw_height = artwork_width / std::max(0.01f, aspect);
				if (artwork_draw_height > max_artwork_height) {
					artwork_draw_height = max_artwork_height;
					artwork_width = artwork_draw_height * aspect;
				}
			}
			const bool has_artwork = artwork_draw_height > 0.0f;
			const float content_height = artwork_draw_height + (has_artwork ? gap : 0.0f)
			    + title_height + gap + button_height;
			float cursor_y = std::max(ImGui::GetCursorPosY(),
			                          (ImGui::GetWindowHeight() - content_height) * 0.5f);
			if (has_artwork) {
				ImGui::SetCursorPosX((ImGui::GetWindowWidth() - artwork_width) * 0.5f);
				ImGui::SetCursorPosY(cursor_y);
				ImGui::Image(art->second.texture, ImVec2(artwork_width, artwork_draw_height));
				cursor_y += artwork_draw_height + gap;
			}
			ImGui::SetCursorPosY(cursor_y);
			ImGui::SetWindowFontScale(0.82f);
			ImGui::TextWrapped("%s", game.name.c_str());
			ImGui::SetWindowFontScale(1.0f);
			ImGui::SetCursorPosY(cursor_y + title_height + gap);
			if (ImGui::Button("PLAY", ImVec2(-1, button_height))) start_selected(false, &game);
			ImGui::EndChild();
			ImGui::PopID();
			++shown;
		}
		ImGui::EndTable();
	}
	if (shown == 0) ImGui::TextDisabled("No games match this filter.");
	ImGui::EndChild();
}

void draw_library() {
	if (g.creating_config) draw_config_editor();
	else draw_game_browser();
}

void draw_artwork() {
	heading("Artwork", "RetroMedia account and library artwork.");
	begin_card("artwork-card");
	if (!g.retro_media_signed_in) {
		ImGui::InputTextWithHint("##rm-email", "Email", g.email_buffer.data(), g.email_buffer.size());
		ImGui::InputTextWithHint("##rm-password", "Password", g.password_buffer.data(),
		                         g.password_buffer.size(), ImGuiInputTextFlags_Password);
		ImGui::BeginDisabled(g.retro_media_busy);
		if (ImGui::Button("Sign in to RetroMedia", ImVec2(-1, 52.0f * ui_scale()))) {
			g.retro_media_busy = true;
			g.retro_media_message = "Signing in...";
			platform_retro_media_sign_in(g.email_buffer.data(), g.password_buffer.data());
			std::fill(g.password_buffer.begin(), g.password_buffer.end(), '\0');
		}
		ImGui::EndDisabled();
	} else {
		ImGui::Text("Signed in as %s", g.retro_media_email.c_str());
		ImGui::TextColored(g.retro_media_admin ? ImVec4(1.0f, 0.68f, 0.20f, 1.0f)
		                                      : ImVec4(0.68f, 0.72f, 0.78f, 1.0f),
		                   "%s", g.retro_media_admin ? "Administrator account" : "Artwork account");
		ImGui::Text("Credits: %d    Free today: %d", g.retro_media_credits, g.retro_media_free);
		ImGui::BeginDisabled(g.retro_media_busy);
		if (ImGui::Button("Sign out")) {
			g.retro_media_busy = true;
			platform_retro_media_sign_out();
		}
		ImGui::EndDisabled();
	}
	ImGui::SeparatorText("Game card artwork");
	constexpr const char* type_ids[] = {"box2d", "images", "thumbnails", "titles"};
	constexpr const char* type_names[] = {"2D cover", "Screenshot", "Thumbnail", "Title screen"};
	int selected = 0;
	for (int index = 0; index < IM_ARRAYSIZE(type_ids); ++index) {
		if (g.retro_media_type == type_ids[index]) selected = index;
	}
	if (ImGui::Combo("##art-type", &selected, type_names, IM_ARRAYSIZE(type_names))) {
		g.retro_media_type = type_ids[selected];
		platform_retro_media_load_artwork(g.retro_media_type.c_str());
	}
	ImGui::TextWrapped("Match local disk names to the Atari ST catalogue and cache artwork on this device.");
	ImGui::BeginDisabled(g.retro_media_busy || !g.retro_media_signed_in || g.software.empty());
	if (ImGui::Button("Sync / download missing artwork", ImVec2(-1, 52.0f * ui_scale()))) {
		std::string names;
		for (const MediaFile& file : g.software) {
			names += file.name;
			names.push_back('\n');
		}
		g.retro_media_busy = true;
		g.retro_media_message = "Matching library and downloading artwork...";
		platform_retro_media_sync_artwork(g.retro_media_type.c_str(), names.c_str());
	}
	ImGui::EndDisabled();
	ImGui::TextWrapped("%s", g.retro_media_message.c_str());
	ImGui::EndChild();
}

std::string byte_size(const uint64_t bytes) {
	char text[64]{};
	if (bytes >= 1024ULL * 1024ULL * 1024ULL) {
		std::snprintf(text, sizeof(text), "%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0));
	} else if (bytes >= 1024ULL * 1024ULL) {
		std::snprintf(text, sizeof(text), "%.1f MB", bytes / (1024.0 * 1024.0));
	} else {
		std::snprintf(text, sizeof(text), "%.1f KB", bytes / 1024.0);
	}
	return text;
}

void draw_downloads() {
	heading("Game downloads", "Android administrator RetroMedia catalogue.");
	begin_card("downloads-card");
	if (!game_downloads_visible()) {
		ImGui::TextColored(ImVec4(1.0f, 0.68f, 0.20f, 1.0f),
		                   "This page requires an Android RetroMedia administrator account.");
		ImGui::EndChild();
		return;
	}
	const float browse_button_width = ImGui::CalcTextSize("Browse / refresh").x
	    + ImGui::GetStyle().FramePadding.x * 2.0f + 8.0f * ui_scale();
	const float search_width = std::max(120.0f * ui_scale(),
	    ImGui::GetContentRegionAvail().x - browse_button_width - ImGui::GetStyle().ItemSpacing.x);
	ImGui::SetNextItemWidth(search_width);
	ImGui::InputTextWithHint("##catalogue-search", "Search downloadable games...",
	                         g.search_buffer.data(), g.search_buffer.size());
	ImGui::SameLine();
	ImGui::BeginDisabled(g.retro_media_busy);
	if (ImGui::Button("Browse / refresh", ImVec2(browse_button_width, 0))) {
		g.retro_media_busy = true;
		g.retro_media_message = "Loading administrator catalogue...";
		platform_retro_media_browse("");
	}
	ImGui::EndDisabled();
	constexpr const char* filter_labels[] = {
	    "0-9", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L",
	    "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"};
	std::array<bool, IM_ARRAYSIZE(filter_labels)> available_filters{};
	for (const auto& entry : g.catalogue) {
		const auto first = std::find_if(entry.title.begin(), entry.title.end(),
		                                [](const unsigned char c) { return std::isalnum(c); });
		if (first == entry.title.end()) continue;
		const unsigned char initial = static_cast<unsigned char>(*first);
		if (std::isdigit(initial)) {
			available_filters[0] = true;
		} else {
			const int normalized = std::tolower(initial);
			if (normalized >= 'a' && normalized <= 'z') {
				available_filters[1 + normalized - 'a'] = true;
			}
		}
	}
	if (g.catalogue_filter < 1 || g.catalogue_filter > IM_ARRAYSIZE(filter_labels)
	    || !available_filters[g.catalogue_filter - 1]) {
		const auto first_available = std::find(available_filters.begin(), available_filters.end(), true);
		if (first_available != available_filters.end()) {
			g.catalogue_filter = static_cast<int>(std::distance(available_filters.begin(), first_available)) + 1;
		}
	}
	ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(4.0f, 8.0f));
	ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(1.0f, 8.0f));
	ImGui::SetWindowFontScale(0.68f);
	const float scale = ui_scale();
	const int filter_count = static_cast<int>(std::count(available_filters.begin(), available_filters.end(), true));
	const float filter_width = std::max(38.0f,
	    (ImGui::GetContentRegionAvail().x
	     - ImGui::GetStyle().ItemSpacing.x * std::max(0, filter_count - 1))
	        / std::max(1, filter_count));
	int drawn_filters = 0;
	for (int index = 0; index < IM_ARRAYSIZE(filter_labels); ++index) {
		if (!available_filters[index]) continue;
		if (drawn_filters++ != 0) ImGui::SameLine();
		const int filter = index + 1;
		const bool selected = g.catalogue_filter == filter;
		if (selected) {
			ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.78f, 0.07f, 0.09f, 1.0f));
		}
		if (ImGui::Button(filter_labels[index], ImVec2(filter_width, 44.0f * scale))) {
			g.catalogue_filter = filter;
		}
		if (selected) ImGui::PopStyleColor();
	}
	ImGui::SetWindowFontScale(1.0f);
	ImGui::PopStyleVar(2);
	ImGui::NewLine();

	std::string query(g.search_buffer.data());
	std::transform(query.begin(), query.end(), query.begin(),
	               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
	std::vector<std::size_t> visible;
	visible.reserve(g.catalogue.size());
	for (std::size_t index = 0; index < g.catalogue.size(); ++index) {
		std::string title = g.catalogue[index].title;
		std::transform(title.begin(), title.end(), title.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		const auto first = std::find_if(title.begin(), title.end(),
		                                [](const unsigned char c) { return std::isalnum(c); });
		const bool query_match = query.empty() || title.find(query) != std::string::npos;
		bool letter_match = false;
		if (first != title.end() && g.catalogue_filter == 1) {
			letter_match = std::isdigit(static_cast<unsigned char>(*first)) != 0;
		} else if (first != title.end() && g.catalogue_filter >= 2) {
			letter_match = *first == static_cast<char>('a' + g.catalogue_filter - 2);
		}
		if (query_match && letter_match) visible.push_back(index);
	}
	std::sort(visible.begin(), visible.end(), [](const std::size_t left, const std::size_t right) {
		std::string a = g.catalogue[left].title;
		std::string b = g.catalogue[right].title;
		std::transform(a.begin(), a.end(), a.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		std::transform(b.begin(), b.end(), b.begin(),
		               [](const unsigned char c) { return static_cast<char>(std::tolower(c)); });
		return a < b;
	});
	if (!g.retro_media_message.empty()) ImGui::TextWrapped("%s", g.retro_media_message.c_str());
	ImGui::BeginChild("##catalogue-scroll", ImVec2(0, 0), ImGuiChildFlags_Borders,
	                  ImGuiWindowFlags_AlwaysVerticalScrollbar);
	const float available = ImGui::GetContentRegionAvail().x;
	const int columns = available > 1280.0f ? 4 : available > 820.0f ? 3 : 2;
	if (ImGui::BeginTable("##catalogue-cards", columns,
	                      ImGuiTableFlags_SizingStretchSame | ImGuiTableFlags_PadOuterX)) {
		for (const std::size_t index : visible) {
			const CatalogueItem& item = g.catalogue[index];
			ImGui::TableNextColumn();
			ImGui::PushID(item.slug.c_str());
			ImGui::BeginChild("##download-card", ImVec2(0, 174.0f * scale),
			                  ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding);
			ImGui::SetWindowFontScale(1.12f);
			ImGui::TextWrapped("%s", item.title.c_str());
			ImGui::SetWindowFontScale(1.0f);
			ImGui::TextDisabled("%d file%s  %s", item.file_count,
			                    item.file_count == 1 ? "" : "s",
			                    byte_size(item.total_bytes).c_str());
			ImGui::SetCursorPosY(ImGui::GetWindowHeight() - 52.0f * scale);
			if (g.retro_media_busy && g.retro_media_download_slug == item.slug) {
				const float fraction = g.retro_media_download_total > 0
				    ? static_cast<float>(std::min(1.0,
				          static_cast<double>(g.retro_media_download_bytes)
				              / static_cast<double>(g.retro_media_download_total)))
				    : 0.0f;
				std::string progress = byte_size(g.retro_media_download_bytes);
				if (g.retro_media_download_total > 0) {
					progress += " / " + byte_size(g.retro_media_download_total);
				}
				ImGui::ProgressBar(fraction, ImVec2(-1, 42.0f * scale), progress.c_str());
			} else {
				ImGui::BeginDisabled(g.retro_media_busy);
				if (ImGui::Button("DOWNLOAD", ImVec2(-1, 42.0f * scale))) {
					g.retro_media_busy = true;
					g.retro_media_download_slug = item.slug;
					g.retro_media_download_bytes = 0;
					g.retro_media_download_total = item.total_bytes;
					g.retro_media_message = "Downloading " + item.title + "...";
					platform_retro_media_download(item.slug.c_str());
				}
				ImGui::EndDisabled();
			}
			ImGui::EndChild();
			ImGui::PopID();
		}
		ImGui::EndTable();
	}
	if (visible.empty()) ImGui::TextDisabled("No downloads match this filter.");
	ImGui::EndChild();
	ImGui::EndChild();
}

void draw_machine() {
	heading("Machine", "Choose the Atari model, memory and boot ROM.");
	begin_card("machine-card");
	ImGui::SeparatorText("Machine");
	constexpr const char* models[] = {"Atari ST", "Mega ST", "Atari STE", "Mega STE", "TT", "Falcon 030"};
	ImGui::SetNextItemWidth(-1);
	ImGui::Combo("##machine", &g.model, models, IM_ARRAYSIZE(models));
	constexpr int memories[] = {512, 1024, 2048, 4096, 8192, 14336};
	constexpr const char* memory_names[] = {"512 KB", "1 MB", "2 MB", "4 MB", "8 MB", "14 MB"};
	int memory_choice = 1;
	for (int i = 0; i < IM_ARRAYSIZE(memories); ++i) if (g.memory_kb == memories[i]) memory_choice = i;
	ImGui::SetNextItemWidth(-1);
	if (ImGui::Combo("##memory", &memory_choice, memory_names, IM_ARRAYSIZE(memory_names))) {
		g.memory_kb = memories[memory_choice];
	}
	constexpr const char* monitors[] = {"High-resolution mono", "Colour RGB", "VGA", "Television"};
	ImGui::SetNextItemWidth(-1);
	ImGui::Combo("##monitor", &g.monitor, monitors, IM_ARRAYSIZE(monitors));
	ImGui::SeparatorText("Boot ROM");
	media_combo("##rom", g.roms, g.rom_choice, "No EmuTOS/TOS image installed");
	ImGui::TextWrapped("EmuTOS is the recommended legal default. Original Atari TOS is not supplied by this app.");
	ImGui::SeparatorText("Media");
	media_combo("##media", g.software, g.software_choice, "No disk in drive A");
	ImGui::Checkbox("Cycle-accurate floppy timing", &g.accurate_floppy);
	ImGui::TextWrapped("Enable accurate timing for protected STX/IPF originals. Ordinary ST/MSA images boot faster with it off.");
	if (ImGui::Button("Rescan app folders", ImVec2(-1, 48.0f * ui_scale()))) rescan();
	ImGui::SeparatorText("Input");
	ImGui::Checkbox("Show on-screen joystick", &g.show_pad);
	ImGui::Checkbox("Show Atari keyboard", &g.show_keyboard);
	ImGui::TextWrapped("Touching the emulated display drives the ST mouse. External keyboards use physical Atari key positions.");
	ImGui::SeparatorText("Audio / Video");
	constexpr const char* aspect_modes[] = {"4:3", "16:9"};
	ImGui::SetNextItemWidth(-1);
	ImGui::Combo("##display-aspect", &g.display_aspect_mode,
	             aspect_modes, IM_ARRAYSIZE(aspect_modes));
	ImGui::Checkbox("Stereo output", &g.stereo);
	ImGui::EndChild();
}

void draw_about() {
	heading("About Retro-AtariST", "A native mobile front end for Hatari.");
	begin_card("about-card");
	ImGui::TextWrapped(platform_game_downloads_available()
	                       ? "Atari ST, Mega ST, STE, Mega STE, TT and Falcon emulation through Hatari, presented by NativeActivity, OpenGL ES and Dear ImGui."
	                       : "Atari ST, Mega ST, STE, Mega STE, TT and Falcon emulation through Hatari, presented by UIKit, Metal and Dear ImGui.");
	ImGui::Spacing();
	ImGui::TextUnformatted("Source: github.com/CrownParkComputing/Retro-AtariST");
	ImGui::TextUnformatted("Not affiliated with or endorsed by Atari.");
	ImGui::SeparatorText("Core");
	ImGui::Text("Hatari: %s", atarist_core_hatari_version());
	ImGui::Text("Audio: %s", atarist_core_audio_backend());
	ImGui::TextUnformatted("CPU: interpreted 68000/68030 core (no JIT)");
	ImGui::EndChild();
}

void draw_demo() {
	heading("Demo", "Test Hatari with EmuTOS and open project-authored software.");
	begin_card("demo-card");
	ImGui::TextWrapped("This demonstration boots the bundled GPLv2 EmuTOS replacement ROM and Retro-AtariST core-test floppy. It contains no Atari TOS ROM or commercial game content.");
	ImGui::Spacing();
	ImGui::BeginDisabled(g.roms.empty());
	if (ImGui::Button("Start EmuTOS core demo", ImVec2(-1, 62.0f * ui_scale()))) {
		start_selected(true);
	}
	ImGui::EndDisabled();
	if (!g.error.empty()) {
		ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.30f, 1.0f), "%s", g.error.c_str());
	}
	ImGui::EndChild();
}

void draw_workbench(const float width, const float height) {
	ImGui::SetNextWindowPos(ImVec2(g.safe_left, g.safe_top));
	ImGui::SetNextWindowSize(ImVec2(width - g.safe_left - g.safe_right,
	                                height - g.safe_top - g.safe_bottom));
	ImGui::Begin("##workbench", nullptr,
	             ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
	                 ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus);
	const ImVec2 min = ImGui::GetWindowPos();
	const ImVec2 max(min.x + ImGui::GetWindowWidth(), min.y + ImGui::GetWindowHeight());
	ImGui::GetWindowDrawList()->AddRectFilled(min, max, rgba(5, 6, 8));

	const float scale = ui_scale();
	const float rail = 180.0f * scale;
	ImGui::SetCursorPos(ImVec2(10.0f * scale, 10.0f * scale));
	ImGui::BeginChild("rail", ImVec2(rail, height - 20.0f * scale), ImGuiChildFlags_Borders,
	                  ImGuiWindowFlags_NoScrollbar);
	if (g.brand_logo.texture != ImTextureID_Invalid && g.brand_logo.width > 0 &&
	    g.brand_logo.height > 0) {
		const float logo_width = ImGui::GetContentRegionAvail().x;
		const float logo_height = logo_width * static_cast<float>(g.brand_logo.height) /
		                          static_cast<float>(g.brand_logo.width);
		ImGui::Image(g.brand_logo.texture, ImVec2(logo_width, logo_height));
	}
	ImGui::Separator();
	const float button_width = ImGui::GetContentRegionAvail().x;
	nav_button("Library", Screen::Library, button_width);
	nav_button("Artwork", Screen::Artwork, button_width);
	if (game_downloads_visible()) {
		nav_button("Downloads", Screen::Downloads, button_width);
	}
	nav_button("Machine", Screen::Machine, button_width);
	ImGui::Spacing();
	ImGui::Separator();
	nav_button("Demo", Screen::Demo, button_width);
	nav_button("About", Screen::About, button_width);
	ImGui::EndChild();

	ImGui::SetCursorPos(ImVec2(rail + 22.0f * scale, 10.0f * scale));
	ImGui::BeginChild("content", ImVec2(width - rail - 32.0f * scale, height - 20.0f * scale),
	                  ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding);
	switch (g.screen) {
		case Screen::Library: draw_library(); break;
		case Screen::Artwork: draw_artwork(); break;
		case Screen::Downloads: draw_downloads(); break;
		case Screen::Machine: draw_machine(); break;
		case Screen::Demo: draw_demo(); break;
		case Screen::About: draw_about(); break;
	}
	ImGui::EndChild();
	ImGui::End();
}

void tap_key(const int scancode) {
	if (g.pending_key >= 0) atarist_core_key_event(g.pending_key, 0);
	atarist_core_key_event(scancode, 1);
	g.pending_key = scancode;
	g.pending_key_release_ms = 0.0;
}

void draw_keyboard(const float width, const float height) {
	if (!g.show_keyboard) return;
	const float scale = ui_scale();
	const float key_height = 36.0f * scale;
	const float keyboard_height = key_height * 6.0f + ImGui::GetStyle().WindowPadding.y * 2.0f +
	                              ImGui::GetStyle().ItemSpacing.y * 5.0f;
	ImGui::SetNextWindowBgAlpha(0.68f);
	ImGui::SetNextWindowPos(ImVec2(0.0f, height - keyboard_height));
	ImGui::SetNextWindowSize(ImVec2(width, keyboard_height));
	ImGui::Begin("##atari-st-keyboard", nullptr,
	             ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
	                 ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoScrollbar);
	struct Key { const char* label; int code; float units; };
	constexpr Key functions[] = {
	    {"ESC", 0x01, 1.3f}, {"F1", 0x3b, 1}, {"F2", 0x3c, 1}, {"F3", 0x3d, 1},
	    {"F4", 0x3e, 1}, {"F5", 0x3f, 1}, {"F6", 0x40, 1}, {"F7", 0x41, 1},
	    {"F8", 0x42, 1}, {"F9", 0x43, 1}, {"F10", 0x44, 1}, {"HELP", 0x62, 1.4f},
	    {"UNDO", 0x61, 1.4f}};
	constexpr Key numbers[] = {
	    {"`", 0x29, 1}, {"1", 0x02, 1}, {"2", 0x03, 1}, {"3", 0x04, 1},
	    {"4", 0x05, 1}, {"5", 0x06, 1}, {"6", 0x07, 1}, {"7", 0x08, 1},
	    {"8", 0x09, 1}, {"9", 0x0a, 1}, {"0", 0x0b, 1}, {"-", 0x0c, 1},
	    {"=", 0x0d, 1}, {"BACKSPACE", 0x0e, 2.1f}};
	constexpr Key qwerty[] = {
	    {"TAB", 0x0f, 1.5f}, {"Q", 0x10, 1}, {"W", 0x11, 1}, {"E", 0x12, 1},
	    {"R", 0x13, 1}, {"T", 0x14, 1}, {"Y", 0x15, 1}, {"U", 0x16, 1},
	    {"I", 0x17, 1}, {"O", 0x18, 1}, {"P", 0x19, 1}, {"[", 0x1a, 1},
	    {"]", 0x1b, 1}, {"RETURN", 0x1c, 1.8f}};
	constexpr Key home[] = {
	    {"CTRL", 0x1d, 1.7f}, {"A", 0x1e, 1}, {"S", 0x1f, 1}, {"D", 0x20, 1},
	    {"F", 0x21, 1}, {"G", 0x22, 1}, {"H", 0x23, 1}, {"J", 0x24, 1},
	    {"K", 0x25, 1}, {"L", 0x26, 1}, {";", 0x27, 1}, {"'", 0x28, 1},
	    {"#", 0x2b, 1}, {"ENTER", 0x1c, 1.8f}};
	constexpr Key lower[] = {
	    {"LSHIFT", 0x2a, 2.1f}, {"<", 0x60, 1}, {"Z", 0x2c, 1}, {"X", 0x2d, 1},
	    {"C", 0x2e, 1}, {"V", 0x2f, 1}, {"B", 0x30, 1}, {"N", 0x31, 1},
	    {"M", 0x32, 1}, {",", 0x33, 1}, {".", 0x34, 1}, {"/", 0x35, 1},
	    {"RSHIFT", 0x36, 2.1f}};
	constexpr Key bottom[] = {
	    {"CAPS", 0x3a, 1.5f}, {"ALT", 0x38, 1.5f}, {"SPACE", 0x39, 6.0f},
	    {"INSERT", 0x52, 1.5f}, {"HOME", 0x47, 1.5f}, {"LEFT", 0x4b, 1.2f},
	    {"DOWN", 0x50, 1.2f}, {"UP", 0x48, 1.2f}, {"RIGHT", 0x4d, 1.2f},
	    {"DELETE", 0x53, 1.5f}};
	auto draw_row = [&](const Key* keys, const int count) {
		float total_units = 0.0f;
		for (int index = 0; index < count; ++index) total_units += keys[index].units;
		const float gaps = ImGui::GetStyle().ItemSpacing.x * (count - 1);
		const float unit = (ImGui::GetContentRegionAvail().x - gaps) / total_units;
		for (int index = 0; index < count; ++index) {
			if (index != 0) ImGui::SameLine();
			if (ImGui::Button(keys[index].label, ImVec2(unit * keys[index].units, key_height))) {
				tap_key(keys[index].code);
			}
		}
	};
	draw_row(functions, IM_ARRAYSIZE(functions));
	draw_row(numbers, IM_ARRAYSIZE(numbers));
	draw_row(qwerty, IM_ARRAYSIZE(qwerty));
	draw_row(home, IM_ARRAYSIZE(home));
	draw_row(lower, IM_ARRAYSIZE(lower));
	draw_row(bottom, IM_ARRAYSIZE(bottom));
	ImGui::End();
}

void apply_joystick_state() {
	if (atarist_core_is_running()) {
		atarist_core_joystick(1, g.physical_joystick_mask | g.onscreen_joystick_mask);
	}
}

void draw_joystick(const float width, const float height) {
	if (!g.show_pad) {
		if (g.onscreen_joystick_mask != 0) {
			g.onscreen_joystick_mask = 0;
			apply_joystick_state();
		}
		return;
	}
	const float size = 58.0f * ui_scale();
	ImGui::SetNextWindowBgAlpha(0.45f);
	ImGui::SetNextWindowPos(ImVec2(12.0f, height - size * 3.35f));
	ImGui::SetNextWindowSize(ImVec2(size * 3.4f, size * 3.3f));
	ImGui::Begin("##joystick", nullptr,
	             ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoSavedSettings |
	                 ImGuiWindowFlags_NoBackground);
	int mask = 0;
	ImGui::Dummy(ImVec2(size, size)); ImGui::SameLine();
	ImGui::Button("UP", ImVec2(size, size)); if (ImGui::IsItemActive()) mask |= ATARIST_JOY_UP;
	ImGui::Button("LEFT", ImVec2(size, size)); if (ImGui::IsItemActive()) mask |= ATARIST_JOY_LEFT;
	ImGui::SameLine(); ImGui::Dummy(ImVec2(size, size)); ImGui::SameLine();
	ImGui::Button("RIGHT", ImVec2(size, size)); if (ImGui::IsItemActive()) mask |= ATARIST_JOY_RIGHT;
	ImGui::Dummy(ImVec2(size, size)); ImGui::SameLine();
	ImGui::Button("DOWN", ImVec2(size, size)); if (ImGui::IsItemActive()) mask |= ATARIST_JOY_DOWN;
	ImGui::End();

	ImGui::SetNextWindowBgAlpha(0.45f);
	ImGui::SetNextWindowPos(ImVec2(width - size * 2.1f, height - size * 2.25f));
	ImGui::SetNextWindowSize(ImVec2(size * 2.0f, size * 2.0f));
	ImGui::Begin("##fire", nullptr,
	             ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoSavedSettings |
	                 ImGuiWindowFlags_NoBackground);
	ImGui::Button("FIRE", ImVec2(size * 1.7f, size * 1.7f));
	if (ImGui::IsItemActive()) mask |= ATARIST_JOY_FIRE;
	ImGui::End();
	if (mask != g.onscreen_joystick_mask) {
		g.onscreen_joystick_mask = mask;
		apply_joystick_state();
	}
}

void draw_emulator(const ImTextureID texture, const float width, const float height) {
	const ImGuiIO& io = ImGui::GetIO();
	if (ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
		g.menu_visible_until_ms = g.now_ms + 3000.0;
	}
	const bool menu_visible = g.now_ms <= g.menu_visible_until_ms;
	ImGui::SetNextWindowPos(ImVec2(0, 0));
	ImGui::SetNextWindowSize(ImVec2(width, height));
	// Deliberately NOT inset: the emulated picture should reach the edges of
	// the screen. Only the overlay controls drawn into it are kept clear of
	// the cutout, via the padding applied where each is positioned.
	ImGui::Begin("##emulator", nullptr,
	             ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
	                 ImGuiWindowFlags_NoSavedSettings);
	if (menu_visible) {
		if (ImGui::Button("Library")) {
			g.physical_joystick_mask = 0;
			g.onscreen_joystick_mask = 0;
			atarist_core_stop();
			g.show_emulator = false;
		}
		ImGui::SameLine();
		if (ImGui::Button(atarist_core_is_paused() ? "Resume" : "Pause")) {
			atarist_core_set_paused(!atarist_core_is_paused());
		}
		ImGui::SameLine();
		if (ImGui::Button("Cold reset")) atarist_core_reset(1);
		ImGui::SameLine();
		if (ImGui::Button("Keyboard")) g.show_keyboard = !g.show_keyboard;
		ImGui::SameLine();
		if (ImGui::Button(g.display_aspect_mode == 0 ? "Aspect 4:3" : "Aspect 16:9")) {
			g.display_aspect_mode = g.display_aspect_mode == 0 ? 1 : 0;
		}
		if (g.active_disks.size() > 1) {
			ImGui::SameLine();
			char disk_label[48]{};
			std::snprintf(disk_label, sizeof(disk_label), "Next disk (%d/%zu)",
			              g.active_disk_index + 1, g.active_disks.size());
			if (ImGui::Button(disk_label)) {
				const int next = (g.active_disk_index + 1) % static_cast<int>(g.active_disks.size());
				if (atarist_core_set_floppy(ATARIST_DRIVE_A,
				                            g.active_disks[static_cast<std::size_t>(next)].path.c_str())
				    == ATARIST_OK) {
					g.active_disk_index = next;
				}
			}
		}
		ImGui::SameLine();
		const char* status = atarist_core_status_line();
		ImGui::TextDisabled("%s", status != nullptr ? status : "Booting...");
	}

	const ImVec2 available = ImGui::GetContentRegionAvail();
	ImVec2 image_size = available;
	const float target_aspect = g.display_aspect_mode == 0 ? 4.0f / 3.0f : 16.0f / 9.0f;
	if (image_size.x / image_size.y > target_aspect) image_size.x = image_size.y * target_aspect;
	else image_size.y = image_size.x / target_aspect;
	ImGui::SetCursorPosX(ImGui::GetCursorPosX() + (available.x - image_size.x) * 0.5f);
	ImGui::SetCursorPosY(ImGui::GetCursorPosY() + (available.y - image_size.y) * 0.5f);
	if (texture != ImTextureID_Invalid) {
		ImGui::Image(texture, image_size);
		if (ImGui::IsItemHovered()) {
			if (ImGui::IsMouseClicked(ImGuiMouseButton_Left)) atarist_core_mouse_button(0, 1);
			if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) atarist_core_mouse_button(0, 0);
			if (ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
				atarist_core_mouse_motion(static_cast<int>(std::lround(io.MouseDelta.x)),
				                         static_cast<int>(std::lround(io.MouseDelta.y)));
			}
		}
	} else {
		ImGui::TextDisabled("Waiting for the Atari ST to draw its first frame...");
	}
	ImGui::End();
	draw_joystick(width, height);
	draw_keyboard(width, height);
}

}  // namespace

bool initialise(const char* work_dir, const char* tos_dir, const char* games_dir) {
	if (g.initialised) {
		apply_style();
		return true;
	}
	g.work_dir = work_dir != nullptr ? work_dir : "";
	g.tos_dir = tos_dir != nullptr ? tos_dir : "";
	g.games_dir = games_dir != nullptr ? games_dir : "";
	std::error_code error;
	fs::create_directories(g.work_dir, error);
	fs::create_directories(g.tos_dir, error);
	fs::create_directories(g.games_dir, error);
	atarist_core_init(g.work_dir.c_str(), g.tos_dir.c_str());
	if (atarist_core_abi_version() != ATARIST_BRIDGE_ABI) {
		g.error = "The Hatari bridge ABI does not match this frontend.";
		return false;
	}
	apply_style();
	rescan();
	g.initialised = true;
	platform_retro_media_restore();
	return true;
}

void shutdown() {
	if (!g.initialised) return;
	if (g.pending_key >= 0) atarist_core_key_event(g.pending_key, 0);
	atarist_core_shutdown();
	g = AppState{};
}

void tick(const double now_ms) {
	if (!g.initialised) return;
	g.now_ms = now_ms;
	if (g.pending_key >= 0) {
		if (g.pending_key_release_ms == 0.0) g.pending_key_release_ms = now_ms + 85.0;
		else if (now_ms >= g.pending_key_release_ms) {
			atarist_core_key_event(g.pending_key, 0);
			g.pending_key = -1;
			g.pending_key_release_ms = 0.0;
		}
	}
	if (!atarist_core_is_running()) return;
	const int64_t generation = atarist_core_frame_counter();
	if (generation == g.observed_frame) return;
	int width = 0;
	int height = 0;
	int pitch = 0;
	const uint32_t* pixels = atarist_core_get_framebuffer(&width, &height, &pitch);
	if (pixels == nullptr || width <= 0 || height <= 0 || pitch < width * 4) return;
	g.frame_pixels.resize(static_cast<std::size_t>(width) * height);
	for (int y = 0; y < height; ++y) {
		std::memcpy(g.frame_pixels.data() + static_cast<std::size_t>(y) * width,
		            reinterpret_cast<const unsigned char*>(pixels) + static_cast<std::size_t>(y) * pitch,
		            static_cast<std::size_t>(width) * sizeof(uint32_t));
	}
	g.observed_frame = generation;
	g.current_frame = {g.frame_pixels.data(), width, height, width * 4,
	                   atarist_core_pixel_aspect() > 0.0 ? atarist_core_pixel_aspect() : 4.0 / 3.0,
	                   static_cast<uint64_t>(generation)};
}

Frame frame() {
	return g.current_frame;
}

void draw(const ImTextureID frame_texture, const float display_width, const float display_height) {
	if (g.show_emulator && atarist_core_is_running()) draw_emulator(frame_texture, display_width, display_height);
	else draw_workbench(display_width, display_height);
}

void brand_logo(const ImTextureID texture, const int width, const int height) {
	g.brand_logo = {texture, width, height};
}

void safe_area_insets(const float left, const float top,
                      const float right, const float bottom) {
	g.safe_left = left;
	g.safe_top = top;
	g.safe_right = right;
	g.safe_bottom = bottom;
}

void imported_file(const ImportKind kind, const char* path) {
	if (path == nullptr || path[0] == '\0') return;
	rescan();
	const std::string imported(path);
	if (kind == ImportKind::Rom) {
		for (std::size_t i = 0; i < g.roms.size(); ++i) {
			if (g.roms[i].path == imported) g.rom_choice = static_cast<int>(i);
		}
	} else {
		for (std::size_t i = 0; i < g.software.size(); ++i) {
			if (g.software[i].path == imported) g.software_choice = static_cast<int>(i);
		}
	}
}

void key_event(const int st_scancode, const bool pressed) {
	if (atarist_core_is_running()) atarist_core_key_event(st_scancode, pressed ? 1 : 0);
}

void joystick_event(const int mask) {
	g.physical_joystick_mask = mask;
	apply_joystick_state();
}

void pause_for_lifecycle(const bool paused) {
	g.lifecycle_paused = paused;
	if (!atarist_core_is_running() || !g.show_emulator) return;
	if (paused) {
		g.paused_before_lifecycle = atarist_core_is_paused() != 0;
		atarist_core_set_paused(1);
	} else {
		atarist_core_set_paused(g.paused_before_lifecycle ? 1 : 0);
	}
}

void retro_media_account(const bool ok, const bool signed_in, const char* email,
	                     const int credits, const int free_remaining, const bool is_admin,
	                     const char* message) {
	g.retro_media_busy = false;
	g.retro_media_signed_in = signed_in;
	g.retro_media_admin = signed_in && is_admin;
	g.retro_media_credits = credits;
	g.retro_media_free = free_remaining;
	g.retro_media_email = email != nullptr ? email : "";
	if (!g.retro_media_email.empty()) {
		std::snprintf(g.email_buffer.data(), g.email_buffer.size(), "%s", g.retro_media_email.c_str());
	}
	g.retro_media_message = message != nullptr ? message : (ok ? "Connected" : "Request failed");
	if (!game_downloads_visible() && g.screen == Screen::Downloads) {
		g.screen = Screen::Artwork;
	}
}

void retro_media_artwork_begin() { g.artwork.clear(); }

void retro_media_artwork_item(const char* local_name, const ImTextureID texture,
	                          const int width, const int height) {
	if (local_name == nullptr || local_name[0] == '\0') return;
	g.artwork[local_name] = {texture, width, height};
}

void retro_media_catalogue_begin() { g.catalogue.clear(); }

void retro_media_catalogue_item(const char* slug, const char* title, const int file_count,
	                            const uint64_t total_bytes) {
	if (slug == nullptr || slug[0] == '\0') return;
	g.catalogue.push_back({slug, title != nullptr ? title : slug, file_count, total_bytes});
}

void retro_media_download_progress(const uint64_t transferred_bytes, const uint64_t total_bytes) {
	if (g.retro_media_download_slug.empty()) return;
	g.retro_media_download_bytes = transferred_bytes;
	if (total_bytes > 0) g.retro_media_download_total = total_bytes;
}

void retro_media_operation_finished(const bool ok, const char* message) {
	g.retro_media_busy = false;
	g.retro_media_download_slug.clear();
	g.retro_media_download_bytes = 0;
	g.retro_media_download_total = 0;
	g.retro_media_message = message != nullptr ? message : (ok ? "Complete" : "Request failed");
}

void retro_media_downloaded(const char* path, const char* message) {
	g.retro_media_busy = false;
	g.retro_media_download_slug.clear();
	g.retro_media_download_bytes = 0;
	g.retro_media_download_total = 0;
	g.retro_media_message = message != nullptr ? message : "Game downloaded";
	rescan();
	if (path == nullptr) return;
	for (std::size_t index = 0; index < g.software.size(); ++index) {
		if (g.software[index].path == path) g.software_choice = static_cast<int>(index);
	}
}

}  // namespace retro_atarist
