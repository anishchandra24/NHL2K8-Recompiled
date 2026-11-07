#pragma once
// Franchise sim crash fix.
//
// In franchise mode (seen in the second season), the routine at 0x82234310 walks
// every team's roster and, for players with one particular roster status, looks the
// player up in the game's 2700-entry player table (0x8217F3D0). Roster entries can
// hold player numbers up to 3369, so some lookups come back empty, and the very next
// call, a one-line getter (0x821F9188: the halfword at player+10, shifted right by 4),
// read through the empty pointer and crashed the game.
//
// Every one of those calls is followed by "if the value is above 3171, skip this
// player". So when one of those four call sites passes an empty pointer, the getter
// answers with a value above that limit and the game skips the missing player.
// Calls from anywhere else are left exactly as they were.
#include <cstdint>

extern "C" REX_FUNC(sub_821F9188) {
  if (ctx.r3.u32 < 0x10000) {
    const uint32_t from = static_cast<uint32_t>(ctx.lr);
    if (from == 0x822348D0 || from == 0x8223493C || from == 0x822349C0 || from == 0x82234A18) {
      ctx.r3.u64 = 0xFFF;
      return;
    }
  }
  __imp__sub_821F9188(ctx, base);
}