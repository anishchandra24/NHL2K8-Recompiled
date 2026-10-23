// nhl2k8 - ReXGlue Recompiled Project
//
// Customize your app by overriding virtual hooks from rex::ReXApp.

#pragma once

#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include <rex/logging.h>
#include <rex/rex_app.h>
#include <rex/system/kernel_state.h>
#include <rex/system/util/xdbf_utils.h>
#include <rex/ui/window.h>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <timeapi.h>
#pragma comment(lib, "winmm.lib")
#pragma comment(lib, "user32.lib")
#endif

class Nhl2k8App : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<Nhl2k8App>(new Nhl2k8App(ctx, "nhl2k8",
        PPCImageConfig));
  }

#ifdef _WIN32
  // Frame pacing: the SDK's GPU vsync thread sleeps in 1 ms steps, but
  // Windows wakes threads only every ~15.6 ms unless a finer timer
  // resolution is requested. Ask for 1 ms for this process.
  void OnPreSetup(rex::RuntimeConfig& config) override {
    timeBeginPeriod(1);
  }
#endif

  // The window and the game's data may not both be ready at the first hook,
  // so each hook tries again until the work is done.
  void OnPostLoadXexImage() override { ApplyWindowExtras(); }
  void OnPostSetup() override { ApplyWindowExtras(); }
  void OnPreLaunchModule() override { ApplyWindowExtras(); }

 private:
  bool cursor_done_ = false;
  bool icon_done_ = false;

  void ApplyWindowExtras() {
    rex::ui::Window* w = window();
    if (!w) {
      return;
    }
    if (!cursor_done_) {
      // Hide the mouse pointer after a short idle time; moving the mouse shows it again.
      w->SetCursorVisibility(rex::ui::Window::CursorVisibility::kAutoHidden);
      cursor_done_ = true;
    }
#ifdef _WIN32
    if (!icon_done_) {
      ApplyTitleIcon(w);
    }
#endif
  }

#ifdef _WIN32
  // Takes the game's own title icon (a PNG stored inside default.xex), wraps it
  // as nhl2k8.ico next to the exe, and sets it as the window icon.
  void ApplyTitleIcon(rex::ui::Window* w) {
    HWND hwnd = static_cast<HWND>(w->GetNativeWindowHandle());
    if (!hwnd) {
      return;  // window not open yet; the next hook tries again
    }
    icon_done_ = true;  // only one real attempt
    if (!runtime() || !runtime()->kernel_state()) {
      REXLOG_WARN("icon: no kernel state yet");
      return;
    }
    auto db = runtime()->kernel_state()->title_xdbf();
    if (!db.is_valid()) {
      REXLOG_WARN("icon: no XDBF data in the game");
      return;
    }
    auto icon = db.icon();
    if (!icon || icon.size < 33) {
      REXLOG_WARN("icon: the game has no title icon");
      return;
    }
    const uint8_t* p = icon.buffer;
    static const uint8_t kPngSig[8] = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    if (std::memcmp(p, kPngSig, 8) != 0) {
      REXLOG_WARN("icon: the title icon is not a PNG");
      return;
    }
    uint32_t width = (uint32_t(p[16]) << 24) | (uint32_t(p[17]) << 16) | (uint32_t(p[18]) << 8) | p[19];
    uint32_t height = (uint32_t(p[20]) << 24) | (uint32_t(p[21]) << 16) | (uint32_t(p[22]) << 8) | p[23];

    std::vector<uint8_t> ico;
    auto put16 = [&](uint16_t v) { ico.push_back(uint8_t(v & 0xFF)); ico.push_back(uint8_t(v >> 8)); };
    auto put32 = [&](uint32_t v) { put16(uint16_t(v & 0xFFFF)); put16(uint16_t(v >> 16)); };
    put16(0);  // reserved
    put16(1);  // type: icon
    put16(1);  // one image
    ico.push_back(width >= 256 ? 0 : uint8_t(width));
    ico.push_back(height >= 256 ? 0 : uint8_t(height));
    ico.push_back(0);  // palette colors
    ico.push_back(0);  // reserved
    put16(1);          // planes
    put16(32);         // bits per pixel
    put32(uint32_t(icon.size));
    put32(22);  // offset of the image data
    ico.insert(ico.end(), p, p + icon.size);

    wchar_t exe[MAX_PATH] = {0};
    DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
    if (n == 0) {
      REXLOG_WARN("icon: cannot find the exe folder");
      return;
    }
    std::filesystem::path ico_path = std::filesystem::path(std::wstring(exe, n)).parent_path() / L"nhl2k8.ico";
    {
      std::ofstream f(ico_path, std::ios::binary);
      if (f) {
        f.write(reinterpret_cast<const char*>(ico.data()), static_cast<std::streamsize>(ico.size()));
      }
      if (!f || !f.good()) {
        REXLOG_WARN("icon: cannot write {}", ico_path.string());
      }
    }
    HICON big = static_cast<HICON>(LoadImageW(nullptr, ico_path.c_str(), IMAGE_ICON,
                                              GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON),
                                              LR_LOADFROMFILE));
    HICON small_icon = static_cast<HICON>(LoadImageW(nullptr, ico_path.c_str(), IMAGE_ICON,
                                                     GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
                                                     LR_LOADFROMFILE));
    if (big) {
      SendMessageW(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(big));
    }
    if (small_icon) {
      SendMessageW(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(small_icon));
    }
    REXLOG_INFO("icon: {}x{} title icon applied (big={}, small={}), saved to {}", width, height,
                big != nullptr, small_icon != nullptr, ico_path.string());
  }
#endif
};
