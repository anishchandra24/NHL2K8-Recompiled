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

#include <rex/cvar.h>
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

#include "legend_names.h"

REXCVAR_DEFINE_BOOL(legend_names, true, "Game",
                    "Give the unnamed players on the classic teams (shown as \"1. Center\") their "
                    "real names");

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
  void OnPostSetup() override {
    ApplyWindowExtras();
#ifdef _WIN32
    StartLegendNames();
#endif
  }
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
  // Guest memory for the legend-names helper. Reads and writes go through
  // Read/WriteProcessMemory so a page the game frees at the same moment fails
  // the call instead of crashing the game.
  class GuestMemory : public legend_names::Memory {
   public:
    explicit GuestMemory(uint8_t* base) : base_(base) {}
    bool Read(uint32_t addr, void* dst, uint32_t len) override {
      SIZE_T got = 0;
      return ReadProcessMemory(GetCurrentProcess(), base_ + addr, dst, len, &got) && got == len;
    }
    bool Write(uint32_t addr, const void* src, uint32_t len) override {
      SIZE_T put = 0;
      return WriteProcessMemory(GetCurrentProcess(), base_ + addr, src, len, &put) && put == len;
    }
    void ForEachRange(const std::function<void(uint32_t, uint32_t)>& fn) override {
      // The game keeps its rosters in its physical-memory heap, 0xA0000000-0xBFFFFFFF.
      const uint64_t ranges[1][2] = {{0xA0000000ull, 0xC0000000ull}};
      for (const auto& r : ranges) {
        uint64_t run_start = 0, run_end = 0;
        for (uint64_t g = r[0]; g < r[1];) {
          MEMORY_BASIC_INFORMATION mbi;
          if (!VirtualQuery(base_ + g, &mbi, sizeof(mbi))) break;
          uint64_t start = uint64_t(static_cast<uint8_t*>(mbi.BaseAddress) - base_);
          uint64_t end = std::min<uint64_t>(start + mbi.RegionSize, r[1]);
          if (end <= g) end = g + 0x1000;
          bool readable = mbi.State == MEM_COMMIT &&
                          (mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY |
                                          PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE)) &&
                          !(mbi.Protect & PAGE_GUARD);
          uint64_t from = std::max<uint64_t>(start, g);
          if (readable) {
            if (run_end == from) {
              run_end = end;
            } else {
              if (run_end > run_start) fn(uint32_t(run_start), uint32_t(run_end - run_start));
              run_start = from;
              run_end = end;
            }
          }
          g = end;
        }
        if (run_end > run_start) fn(uint32_t(run_start), uint32_t(run_end - run_start));
      }
    }

   private:
    uint8_t* base_;
  };

  // Keeps the classic teams' players named while the game runs (rosters can be
  // loaded again at any time, for example from a saved roster).
  void StartLegendNames() {
    static bool started = false;
    if (started || !REXCVAR_GET(legend_names)) return;
    started = true;
    std::thread([] {
      std::this_thread::sleep_for(std::chrono::seconds(1));
      auto* ks = rex::system::kernel_state();
      if (!ks || !ks->memory()) return;
      GuestMemory mem(ks->memory()->virtual_membase());
      legend_names::Renamer renamer(&mem);
      // A full search every 2 seconds finds rosters wherever the game puts them; in
      // between, the teams already found are checked 4 times a second, so a roster that
      // is loaded again gets its names back before it shows on screen.
      for (int tick = 0;; ++tick) {
        int n = (tick % 8 == 0) ? renamer.Pass() : renamer.Quick();
        if (n > 0) {
          REXLOG_INFO("legend names: {} players named ({} classic teams found)", n, renamer.TeamsSeen());
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(250));
      }
    }).detach();
  }

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
