// nhl2k8 - real names for the unnamed players on the classic ("legend") teams.
//
// The game's roster stores the unlicensed legends with a first name like "1" and a last
// name like "Center", so they show up as "1. Center". While the game runs, this looks for
// the classic teams in the game's memory and writes the real names into those players.
// Only players that still carry the placeholder name are changed, so edits made in the
// game are kept. Turn it off with --legend_names=false.

#pragma once

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <functional>
#include <map>
#include <string>
#include <thread>
#include <vector>

namespace legend_names {

struct Entry {
  const char* team;   // team code, e.g. "SJS02"
  uint8_t jersey;     // jersey number in the game's roster
  uint8_t slot;       // the placeholder first name: 1 for "1. Center"
  char pos;           // C, L (left wing), R (right wing), D or G
  const char* first;  // real name (15 letters at most each)
  const char* last;
};

#include "legend_names_data.inc"  // static const Entry kEntries[]

// Layout of the roster data in the game's memory.
constexpr uint32_t kPlayerSize = 0xCC;      // one player record
constexpr uint32_t kPlayerNameOff = 0x30;   // first name [16], then last name [16]
constexpr uint32_t kTeamCodeOff = 4;        // team code [8], e.g. "SJS02"
constexpr uint32_t kTeamNameOff = 28;       // team name [16], e.g. "Sharks '02"
constexpr uint32_t kTeamRosterOff = 0x4C;   // roster entries: [u16 player][u8 jersey]...
constexpr uint32_t kRosterEntrySize = 20;
constexpr uint32_t kRosterMax = 80;

inline const char* PosName(char p) {
  switch (p) {
    case 'C': return "Center";
    case 'L': return "Left Wing";
    case 'R': return "Right Wing";
    case 'D': return "Defenseman";
    case 'G': return "Goalie";
  }
  return "";
}

// Guest memory access; reads and writes fail safely instead of crashing.
struct Memory {
  virtual ~Memory() = default;
  virtual bool Read(uint32_t addr, void* dst, uint32_t len) = 0;
  virtual bool Write(uint32_t addr, const void* src, uint32_t len) = 0;
  // Calls fn(start, length) for each readable range of guest memory worth searching.
  virtual void ForEachRange(const std::function<void(uint32_t, uint32_t)>& fn) = 0;
};

inline void Field16(char out[16], const char* s) {
  std::memset(out, 0, 16);
  std::strncpy(out, s, 15);
}

// A 16-byte name field holding a plain string followed by zero bytes.
inline bool NameField(const uint8_t* p, std::string* out) {
  if (p[0] == 0) return false;
  size_t n = 0;
  while (n < 16 && p[n] != 0) {
    if (p[n] < 32 || p[n] > 126) return false;
    ++n;
  }
  if (n == 16) return false;
  for (size_t i = n; i < 16; ++i) {
    if (p[i] != 0) return false;
  }
  out->assign(reinterpret_cast<const char*>(p), n);
  return true;
}

class Renamer {
 public:
  explicit Renamer(Memory* mem) : mem_(mem) {
    for (const Entry& e : kEntries) by_team_[e.team].push_back(&e);
  }

  // One full pass: find the classic teams, then rename their placeholder players.
  // Returns the number of players renamed in this pass.
  int Pass() {
    renamed_ = 0;
    teams_.clear();
    known_.clear();
    std::vector<uint8_t> buf;
    mem_->ForEachRange([&](uint32_t start, uint32_t len) {
      const uint32_t kChunk = 4u << 20, kOverlap = 64;
      for (uint64_t at = start; at < uint64_t(start) + len; at += kChunk) {
        uint32_t n = uint32_t(std::min<uint64_t>(kChunk + kOverlap, uint64_t(start) + len - at));
        buf.resize(n);
        if (!mem_->Read(uint32_t(at), buf.data(), n)) continue;
        FindTeams(uint32_t(at), buf.data(), n);
      }
    });
    std::sort(teams_.begin(), teams_.end());
    teams_.erase(std::unique(teams_.begin(), teams_.end()), teams_.end());
    for (const auto& t : teams_) DoTeam(t.first, t.second);
    return renamed_;
  }

  // A cheap pass over the teams found by the last full pass: renames players again if
  // their roster was loaded again at the same place (for example a saved roster).
  int Quick() {
    renamed_ = 0;
    for (const Known& k : known_) {
      std::vector<Slot> roster;
      if (!ReadRoster(k.team, &roster)) continue;
      const auto& es = by_team_[k.code];
      if (!Fits(k.base, roster, es)) continue;
      RenameTeam(k.base, roster, es);
    }
    return renamed_;
  }

  size_t TeamsSeen() const { return teams_.size(); }

 private:
  struct Slot {
    uint16_t player;
    uint8_t jersey;
  };

  Memory* mem_;
  std::map<std::string, std::vector<const Entry*>> by_team_;
  std::vector<std::pair<uint32_t, std::string>> teams_;
  struct Known {
    uint32_t team;
    std::string code;
    uint32_t base;
  };
  std::vector<Known> known_;     // teams matched by the last full pass
  std::vector<uint32_t> bases_;  // player table starts found so far
  std::map<uint32_t, int> skip_;  // teams that could not be matched, passes to wait
  int renamed_ = 0;

  void FindTeams(uint32_t ga, const uint8_t* b, uint32_t n) {
    // Every classic team's name has an apostrophe ("Sharks '02", "1960's").
    for (const uint8_t* q = b; (q = static_cast<const uint8_t*>(std::memchr(q, '\'', b + n - q))) != nullptr; ++q) {
      uint32_t qi = uint32_t(q - b);
      for (uint32_t k = 1; k < 15 && k <= qi; ++k) {
        if (qi < kTeamNameOff + k) break;
        uint32_t s = qi - kTeamNameOff - k;
        if (s + kTeamNameOff + 16 > n) continue;
        std::string code, name;
        if (!Code8(b + s + kTeamCodeOff, &code)) continue;
        if (!NameField(b + s + kTeamNameOff, &name) || name[k] != '\'') continue;
        if (by_team_.count(code)) teams_.emplace_back(ga + s, code);
      }
    }
  }

  static bool Code8(const uint8_t* p, std::string* out) {
    size_t n = 0;
    while (n < 8 && ((p[n] >= 'A' && p[n] <= 'Z') || (p[n] >= '0' && p[n] <= '9'))) ++n;
    if (n < 3 || n >= 8) return false;
    for (size_t i = n; i < 8; ++i) if (p[i] != 0) return false;
    out->assign(reinterpret_cast<const char*>(p), n);
    return true;
  }

  bool ReadRoster(uint32_t team, std::vector<Slot>* out) {
    std::vector<uint8_t> t(kTeamRosterOff + kRosterEntrySize * kRosterMax);
    if (!mem_->Read(team, t.data(), uint32_t(t.size()))) return false;
    for (uint32_t i = 0; i < kRosterMax; ++i) {
      const uint8_t* e = t.data() + kTeamRosterOff + i * kRosterEntrySize;
      uint16_t p = uint16_t((e[0] << 8) | e[1]);
      if (p == 0xFFFF) break;
      out->push_back({p, e[2]});
    }
    return !out->empty();
  }

  bool PlayerName(uint32_t base, uint16_t player, std::string* first, std::string* last) {
    uint8_t nm[32];
    if (!mem_->Read(base + uint32_t(player) * kPlayerSize + kPlayerNameOff, nm, 32)) return false;
    return NameField(nm, first) && NameField(nm + 16, last);
  }

  // Which entry, if any, belongs to this roster spot with this current name.
  const Entry* Match(const std::vector<const Entry*>& es, const Slot& s, const std::string& first,
                     const std::string& last, bool* placeholder) {
    const Entry* loose = nullptr;
    int loose_count = 0;
    for (const Entry* e : es) {
      bool ph = first.size() == 1 && first[0] == char('0' + e->slot) && last == PosName(e->pos);
      bool real = first == e->first && last == e->last;
      if (!ph && !real) continue;
      if (e->jersey == s.jersey) {
        *placeholder = ph;
        return e;
      }
      if (ph) {
        loose = e;
        ++loose_count;
      }
    }
    if (loose_count == 1) {
      *placeholder = true;
      return loose;
    }
    return nullptr;
  }

  // A player table start is right for a team when every roster spot points at a real
  // player record and most of our legends for that team are found on the spots with
  // their jersey number (under the placeholder or the real name).
  bool Fits(uint32_t base, const std::vector<Slot>& roster, const std::vector<const Entry*>& es) {
    size_t strict = 0;
    for (const Slot& s : roster) {
      std::string f, l;
      if (!PlayerName(base, s.player, &f, &l)) return false;
      for (const Entry* e : es) {
        if (e->jersey != s.jersey) continue;
        bool ph = f.size() == 1 && f[0] == char('0' + e->slot) && l == PosName(e->pos);
        if (ph || (f == e->first && l == e->last)) {
          ++strict;
          break;
        }
      }
    }
    return strict >= std::min<size_t>(3, es.size()) && strict * 2 >= es.size();
  }

  bool FindBase(const std::vector<Slot>& roster, const std::vector<const Entry*>& es, uint32_t* base) {
    for (uint32_t b : bases_) {
      if (Fits(b, roster, es)) {
        *base = b;
        return true;
      }
    }
    // Not a known table: search memory for one of this team's legends by name
    // (only the first one, so a team that cannot be matched costs little).
    for (const Slot& s : roster) {
      for (const Entry* e : es) {
        if (e->jersey != s.jersey) continue;
        bool any = false;
        for (int form = 0; form < 2; ++form) {
          char pat[32];
          if (form == 0) {
            char d[2] = {char('0' + e->slot), 0};
            Field16(pat, d);
            Field16(pat + 16, PosName(e->pos));
          } else {
            Field16(pat, e->first);
            Field16(pat + 16, e->last);
          }
          bool found = false;
          SearchAll(pat, 32, [&](uint32_t hit) {
            uint64_t b = uint64_t(hit) - kPlayerNameOff - uint64_t(s.player) * kPlayerSize;
            if (b > hit || found) return;
            if (Fits(uint32_t(b), roster, es)) {
              *base = uint32_t(b);
              found = true;
            }
          });
          if (found) {
            bases_.push_back(*base);
            return true;
          }
          any = true;
        }
        if (any) return false;
      }
    }
    return false;
  }

  void SearchAll(const char* pat, uint32_t plen, const std::function<void(uint32_t)>& fn) {
    std::vector<uint8_t> buf;
    mem_->ForEachRange([&](uint32_t start, uint32_t len) {
      const uint32_t kChunk = 4u << 20;
      for (uint64_t at = start; at < uint64_t(start) + len; at += kChunk) {
        uint32_t n = uint32_t(std::min<uint64_t>(kChunk + plen, uint64_t(start) + len - at));
        buf.resize(n);
        if (!mem_->Read(uint32_t(at), buf.data(), n)) continue;
        const uint8_t* b = buf.data();
        const uint8_t* end = b + n;
        for (const uint8_t* p = b; p + plen <= end;) {
          p = std::search(p, end, pat, pat + plen,
                          [](uint8_t x, char y) { return x == uint8_t(y); });
          if (p + plen > end) break;
          fn(uint32_t(at + (p - b)));
          ++p;
        }
      }
    });
  }

  void RenameTeam(uint32_t base, const std::vector<Slot>& roster, const std::vector<const Entry*>& es) {
    for (const Slot& s : roster) {
      std::string f, l;
      if (!PlayerName(base, s.player, &f, &l)) continue;
      bool ph = false;
      const Entry* e = Match(es, s, f, l, &ph);
      if (!e || !ph) continue;
      char nm[32];
      Field16(nm, e->first);
      Field16(nm + 16, e->last);
#ifdef LEGEND_DEBUG
      printf("   %X #%d %s %s -> %s %s\n", s.player, s.jersey, f.c_str(), l.c_str(), e->first, e->last);
#endif
      if (mem_->Write(base + uint32_t(s.player) * kPlayerSize + kPlayerNameOff, nm, 32)) ++renamed_;
    }
  }

  void DoTeam(uint32_t team, const std::string& code) {
    const auto& es = by_team_[code];
    std::vector<Slot> roster;
    if (!ReadRoster(team, &roster)) return;
    auto skip = skip_.find(team);
    if (skip != skip_.end() && skip->second > 0) {
      --skip->second;
      return;
    }
    uint32_t base;
    if (!FindBase(roster, es, &base)) {
      skip_[team] = 30;  // try this one again only after a while
      return;
    }
#ifdef LEGEND_DEBUG
    printf("team %08X %s base %08X\n", team, code.c_str(), base);
#endif
    known_.push_back({team, code, base});
    RenameTeam(base, roster, es);
  }
};

}  // namespace legend_names
