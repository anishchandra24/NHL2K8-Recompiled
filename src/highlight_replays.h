// highlight_replays.h - makes the intermission and postgame highlight replays work.
//
// NHL 2K8 saves each highlight clip (goals, saves, hits) to the Xbox 360's
// cache partition (the "utility drive") during the period, and the
// intermission and postgame shows play them back from there. Two things
// stopped that in the recompile:
//  1. The game formats the cache with 32 KB clusters and rejects the drive if
//     the drive reports anything else. The SDK's placeholder cache partition
//     reports 64 KB, so the mount failed and no highlights were ever recorded.
//  2. The placeholder partition cannot hold files, so saved clips were lost.
// The fix: let the cluster check pass, and point the game's cache: drive at a
// real folder (nhl2k8_cache, next to the exe) before the game links it to the
// placeholder. The SDK never replaces an existing drive link, so the game's
// own link is ignored.
#pragma once

#include <filesystem>
#include <memory>
#include <string>
#include <system_error>

#include <rex/filesystem/devices/host_path_device.h>
#include <rex/system/kernel_state.h>
#include <rex/filesystem/vfs.h>

namespace highlight_replays {

inline void MountCacheFolder() {
  static bool done = false;
  if (done) return;
  done = true;
  auto* ks = rex::system::kernel_state();
  if (!ks || !ks->file_system()) {
    REXLOG_WARN("highlight replays: no file system yet, cache: not mounted");
    return;
  }
  std::filesystem::path dir;
#ifdef _WIN32
  wchar_t exe[MAX_PATH] = {0};
  DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (n > 0) dir = std::filesystem::path(std::wstring(exe, n)).parent_path() / L"nhl2k8_cache";
#endif
  if (dir.empty()) dir = std::filesystem::current_path() / "nhl2k8_cache";
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  auto device = std::make_unique<rex::filesystem::HostPathDevice>("\\CACHE", dir, false, true);
  if (!device->Initialize()) {
    REXLOG_WARN("highlight replays: cannot use {}", dir.string());
    return;
  }
  ks->file_system()->RegisterDevice(std::move(device));
  ks->file_system()->RegisterSymbolicLink("cache:", "\\CACHE");
  ks->file_system()->RegisterSymbolicLink("cache0:", "\\CACHE");
  REXLOG_INFO("highlight replays: cache: is {}", dir.string());
}

}  // namespace highlight_replays

// The game's own XMountUtilityDrive (from the Xbox SDK, compiled into the
// game): mount the real folder first.
extern "C" REX_FUNC(sub_82125108) {
  highlight_replays::MountCacheFolder();
  __imp__sub_82125108(ctx, base);
}

// The volume check after the game formats the cache: the game asks for its
// 32 KB clusters; ask for the 64 KB the placeholder partition reports instead.
extern "C" REX_FUNC(sub_82124998) {
  ctx.r4.u32 = 0x10000;
  __imp__sub_82124998(ctx, base);
}