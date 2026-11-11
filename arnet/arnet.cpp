// arnet.dll: peer-to-peer multiplayer for STORROR Active Ragdoll, through Steam - SM64Map's sm64net.dll made the
// ragdoll mod's own ("remove the multiplayer and switch it for steam peer to peer", "same as SM64 but obviously don't make
// it connect to sm64", 2026-11-11): its own lobbies (data "armp", never SM64Map's "sm64mp"), its own folder and names.
//
// Steam lobbies find the players (public ones listed in the game's ONLINE tab, friends-only ones joined from a
// friend's invite or Steam's "Join Game"); Steam's peer-to-peer messages (ISteamNetworkingMessages) carry the play
// between them, straight from one PC to the other, through Valve's relays only when a direct link can't be made. No
// server of ours or anyone else's: the user, 2026-11-01, "I wanted this to be peer to peer", "Steam friends", "also
// through the multiplayer menu in game to join public lobbies".
//
// It uses the game's own Steam (steam_api64.dll, already started by STORROR with its app id) through Steam's flat C
// API, found by name. UE4SS's Lua can't open a connection, so the mod's Lua (armp.lua) loads this with package.loadlib and
// calls arnet_start once; from then on the two talk through small files in the mod's net\ folder:
//   cmd.txt         Lua -> here: commands, a line each (host public|friends, list, join <lobby>, leave, invite)
//   me.txt          Lua -> here: this player's state, one line (sent to every other player in the lobby, unreliable)
//   out_events.txt  Lua -> here: events, a line each (sent to every other player, reliable: hits, star gets...)
//   status.txt      here -> Lua: the lobby, its members and the lobby list (replaced whole when it changes)
//   peers.txt       here -> Lua: every other player's latest state, with its age (replaced whole ~30 times a second)
//   in_events.txt   here -> Lua: events from the others (appended; Lua takes the file away to read it)
// Every Steam call is made on this DLL's own thread; Steam's callbacks (a join from the overlay) come on the game's
// thread and are only queued there.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <Xinput.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace {

// ------------------------------------------------------------------------------------------ Steam, by name

typedef uint64_t SteamAPICall_t;
typedef void* Iface;

#pragma pack(push, 8)
struct SteamNetworkingIdentity {  // ESteamNetworkingIdentityType, its size, then a union (a SteamID's 64 bits first)
  int32_t type;
  int32_t size;
  union {
    uint64_t steamID64;
    char reserved[128];
  };
};
struct SteamNetworkingMessage_t {
  void* data;
  int32_t size;
  uint32_t conn;
  SteamNetworkingIdentity peer;
  // (more follows; only these are read, and the message is given back with Release)
};
struct LobbyCreated_t { int32_t result; uint64_t lobby; };                                      // 513
struct LobbyEnter_t { uint64_t lobby; uint32_t perms; bool locked; uint32_t response; };          // 504
struct LobbyMatchList_t { uint32_t count; };                                                     // 510
struct GameLobbyJoinRequested_t { uint64_t lobby; uint64_t friendId; };                          // 333
struct GameRichPresenceJoinRequested_t { uint64_t friendId; char connect[256]; };                 // 337
#pragma pack(pop)

// Steam's callback base, declared as the SDK declares it so MSVC lays out its table the same way.
class CCallbackBase {
 public:
  CCallbackBase() : m_nCallbackFlags(0), m_iCallback(0) {}
  virtual void Run(void* pvParam) = 0;
  virtual void Run(void* pvParam, bool bIOFailure, SteamAPICall_t hSteamAPICall) = 0;
  int GetICallback() { return m_iCallback; }
  virtual int GetCallbackSizeBytes() = 0;

 protected:
  uint8_t m_nCallbackFlags;
  int m_iCallback;
};

struct Steam {
  HMODULE dll = nullptr;
  Iface mm = nullptr, msgs = nullptr, friends = nullptr, user = nullptr, utils = nullptr;
  uint64_t (*GetSteamID)(Iface) = nullptr;
  const char* (*GetPersonaName)(Iface) = nullptr;
  const char* (*GetFriendPersonaName)(Iface, uint64_t) = nullptr;
  void (*InviteDialog)(Iface, uint64_t) = nullptr;
  int (*GetFriendCount)(Iface, int) = nullptr;
  uint64_t (*GetFriendByIndex)(Iface, int, int) = nullptr;
  int (*GetFriendPersonaState)(Iface, uint64_t) = nullptr;
  bool (*GetFriendGamePlayed)(Iface, uint64_t, void*) = nullptr;
  bool (*InviteUserToLobby)(Iface, uint64_t, uint64_t) = nullptr;
  bool (*SetRichPresence)(Iface, const char*, const char*) = nullptr;
  void (*ClearRichPresence)(Iface) = nullptr;
  SteamAPICall_t (*CreateLobby)(Iface, int, int) = nullptr;
  SteamAPICall_t (*JoinLobby)(Iface, uint64_t) = nullptr;
  void (*LeaveLobby)(Iface, uint64_t) = nullptr;
  SteamAPICall_t (*RequestLobbyList)(Iface) = nullptr;
  void (*ListStringFilter)(Iface, const char*, const char*, int) = nullptr;
  void (*ListDistanceFilter)(Iface, int) = nullptr;
  void (*ListCountFilter)(Iface, int) = nullptr;
  uint64_t (*GetLobbyByIndex)(Iface, int) = nullptr;
  int (*GetNumLobbyMembers)(Iface, uint64_t) = nullptr;
  uint64_t (*GetLobbyMemberByIndex)(Iface, uint64_t, int) = nullptr;
  const char* (*GetLobbyData)(Iface, uint64_t, const char*) = nullptr;
  bool (*SetLobbyData)(Iface, uint64_t, const char*, const char*) = nullptr;
  uint64_t (*GetLobbyOwner)(Iface, uint64_t) = nullptr;
  int (*GetLobbyMemberLimit)(Iface, uint64_t) = nullptr;
  bool (*SetLobbyJoinable)(Iface, uint64_t, bool) = nullptr;
  bool (*IsAPICallCompleted)(Iface, SteamAPICall_t, bool*) = nullptr;
  bool (*GetAPICallResult)(Iface, SteamAPICall_t, void*, int, int, bool*) = nullptr;
  int (*SendMessageToUser)(Iface, const SteamNetworkingIdentity*, const void*, uint32_t, int, int) = nullptr;
  int (*ReceiveMessagesOnChannel)(Iface, int, SteamNetworkingMessage_t**, int) = nullptr;
  bool (*AcceptSessionWithUser)(Iface, const SteamNetworkingIdentity*) = nullptr;
  bool (*CloseSessionWithUser)(Iface, const SteamNetworkingIdentity*) = nullptr;
  void (*Release)(SteamNetworkingMessage_t*) = nullptr;
  void (*RegisterCallback)(CCallbackBase*, int) = nullptr;
  void (*UnregisterCallback)(CCallbackBase*) = nullptr;
  std::string missing;

  template <class F>
  void get(F& f, const char* name) {
    f = reinterpret_cast<F>(GetProcAddress(dll, name));
    if (!f) missing += std::string(missing.empty() ? "" : ", ") + name;
  }

  bool load() {
    dll = GetModuleHandleW(L"steam_api64.dll");
    if (!dll) {
      missing = "steam_api64.dll (the game has no Steam)";
      return false;
    }
    missing.clear();
    Iface (*fMM)() = nullptr, (*fMsgs)() = nullptr, (*fFriends)() = nullptr, (*fUser)() = nullptr, (*fUtils)() = nullptr;
    get(fMM, "SteamAPI_SteamMatchmaking_v009");
    get(fMsgs, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002");
    get(fFriends, "SteamAPI_SteamFriends_v017");
    get(fUser, "SteamAPI_SteamUser_v023");
    get(fUtils, "SteamAPI_SteamUtils_v010");
    get(GetSteamID, "SteamAPI_ISteamUser_GetSteamID");
    get(GetPersonaName, "SteamAPI_ISteamFriends_GetPersonaName");
    get(GetFriendPersonaName, "SteamAPI_ISteamFriends_GetFriendPersonaName");
    get(InviteDialog, "SteamAPI_ISteamFriends_ActivateGameOverlayInviteDialog");
    get(GetFriendCount, "SteamAPI_ISteamFriends_GetFriendCount");
    get(GetFriendByIndex, "SteamAPI_ISteamFriends_GetFriendByIndex");
    get(GetFriendPersonaState, "SteamAPI_ISteamFriends_GetFriendPersonaState");
    get(GetFriendGamePlayed, "SteamAPI_ISteamFriends_GetFriendGamePlayed");
    get(InviteUserToLobby, "SteamAPI_ISteamMatchmaking_InviteUserToLobby");
    get(SetRichPresence, "SteamAPI_ISteamFriends_SetRichPresence");
    get(ClearRichPresence, "SteamAPI_ISteamFriends_ClearRichPresence");
    get(CreateLobby, "SteamAPI_ISteamMatchmaking_CreateLobby");
    get(JoinLobby, "SteamAPI_ISteamMatchmaking_JoinLobby");
    get(LeaveLobby, "SteamAPI_ISteamMatchmaking_LeaveLobby");
    get(RequestLobbyList, "SteamAPI_ISteamMatchmaking_RequestLobbyList");
    get(ListStringFilter, "SteamAPI_ISteamMatchmaking_AddRequestLobbyListStringFilter");
    get(ListDistanceFilter, "SteamAPI_ISteamMatchmaking_AddRequestLobbyListDistanceFilter");
    get(ListCountFilter, "SteamAPI_ISteamMatchmaking_AddRequestLobbyListResultCountFilter");
    get(GetLobbyByIndex, "SteamAPI_ISteamMatchmaking_GetLobbyByIndex");
    get(GetNumLobbyMembers, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers");
    get(GetLobbyMemberByIndex, "SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex");
    get(GetLobbyData, "SteamAPI_ISteamMatchmaking_GetLobbyData");
    get(SetLobbyData, "SteamAPI_ISteamMatchmaking_SetLobbyData");
    get(GetLobbyOwner, "SteamAPI_ISteamMatchmaking_GetLobbyOwner");
    get(GetLobbyMemberLimit, "SteamAPI_ISteamMatchmaking_GetLobbyMemberLimit");
    get(SetLobbyJoinable, "SteamAPI_ISteamMatchmaking_SetLobbyJoinable");
    get(IsAPICallCompleted, "SteamAPI_ISteamUtils_IsAPICallCompleted");
    get(GetAPICallResult, "SteamAPI_ISteamUtils_GetAPICallResult");
    get(SendMessageToUser, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser");
    get(ReceiveMessagesOnChannel, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel");
    get(AcceptSessionWithUser, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser");
    get(CloseSessionWithUser, "SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser");
    get(Release, "SteamAPI_SteamNetworkingMessage_t_Release");
    get(RegisterCallback, "SteamAPI_RegisterCallback");
    get(UnregisterCallback, "SteamAPI_UnregisterCallback");
    if (!missing.empty()) return false;
    mm = fMM();
    msgs = fMsgs();
    friends = fFriends();
    user = fUser();
    utils = fUtils();
    if (!mm || !msgs || !friends || !user || !utils) {
      missing = "Steam isn't started in this game (no interfaces)";
      return false;
    }
    return GetSteamID(user) != 0;
  }
};

Steam S;

// --------------------------------------------------------------------------------------------- files

std::wstring Wide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n > 0 ? n : 0, L'\0');
  if (n > 0) MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), &w[0], n);
  return w;
}

std::wstring g_dir;  // ...\Mods\StorrorActiveRagdoll\net\ (with its backslash)

bool ReadAll(const std::wstring& path, std::string& out) {
  HANDLE h = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  out.clear();
  char buf[8192];
  DWORD got = 0;
  while (out.size() < (1u << 20) && ReadFile(h, buf, sizeof buf, &got, nullptr) && got > 0) out.append(buf, got);
  CloseHandle(h);
  return true;
}

// Replaced whole: written beside, then moved over the old one (a reader sees the old file or the new, never half).
bool WriteWhole(const std::wstring& name, const std::string& text) {
  const std::wstring tmp = g_dir + name + L".tmp", dst = g_dir + name;
  HANDLE h = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  DWORD put = 0;
  WriteFile(h, text.data(), (DWORD)text.size(), &put, nullptr);
  CloseHandle(h);
  return MoveFileExW(tmp.c_str(), dst.c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
}

bool Append(const std::wstring& name, const std::string& text) {
  HANDLE h = CreateFileW((g_dir + name).c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr, OPEN_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  DWORD put = 0;
  WriteFile(h, text.data(), (DWORD)text.size(), &put, nullptr);
  CloseHandle(h);
  return put == text.size();
}

// A file Lua appends to, taken away whole to be read (renamed first, so Lua's next lines start a new one).
bool Take(const std::wstring& name, std::string& out) {
  const std::wstring from = g_dir + name, to = g_dir + name + L".taking";
  if (!MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_REPLACE_EXISTING)) return false;
  bool ok = ReadAll(to, out);
  DeleteFileW(to.c_str());
  return ok;
}

std::vector<std::string> Lines(const std::string& text) {
  std::vector<std::string> out;
  size_t a = 0;
  while (a < text.size()) {
    size_t b = text.find('\n', a);
    if (b == std::string::npos) b = text.size();
    std::string line = text.substr(a, b - a);
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
    if (!line.empty()) out.push_back(line);
    a = b + 1;
  }
  return out;
}

// A name or other text for a line of ours: no | or line breaks in it, 48 bytes at most.
std::string Clean(const char* s, size_t max = 48) {
  std::string out;
  for (const char* p = s ? s : ""; *p && out.size() < max; p++) {
    char c = *p;
    out += (c == '|' || c == '\n' || c == '\r' || c == '\t') ? ' ' : c;
  }
  return out;
}

void Log(const std::string& line) {
  SYSTEMTIME t;
  GetLocalTime(&t);
  char stamp[32];
  std::snprintf(stamp, sizeof stamp, "%02d:%02d:%02d ", t.wHour, t.wMinute, t.wSecond);
  Append(L"arnet.log", stamp + line + "\n");
}

double NowMs() {
  static LARGE_INTEGER f = [] {
    LARGE_INTEGER q;
    QueryPerformanceFrequency(&q);
    return q;
  }();
  LARGE_INTEGER c;
  QueryPerformanceCounter(&c);
  return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
}

std::string U64(uint64_t v) { return std::to_string((unsigned long long)v); }

SteamNetworkingIdentity Identity(uint64_t id) {
  SteamNetworkingIdentity i;
  std::memset(&i, 0, sizeof i);
  i.type = 16;  // k_ESteamNetworkingIdentityType_SteamID
  i.size = 8;
  i.steamID64 = id;
  return i;
}

// ----------------------------------------------------------------------- what the game's thread queues

std::mutex g_qm;
std::deque<uint64_t> g_joinRequests;  // lobbies to join (Steam's overlay: a friend's "Join Game", an accepted invite)

class JoinLobbyCallback : public CCallbackBase {  // GameLobbyJoinRequested_t
 public:
  JoinLobbyCallback() { m_iCallback = 333; }
  void Run(void* p) override {
    const GameLobbyJoinRequested_t* r = static_cast<const GameLobbyJoinRequested_t*>(p);
    std::lock_guard<std::mutex> lock(g_qm);
    g_joinRequests.push_back(r->lobby);
  }
  void Run(void* p, bool, SteamAPICall_t) override { Run(p); }
  int GetCallbackSizeBytes() override { return sizeof(GameLobbyJoinRequested_t); }
};

class RichJoinCallback : public CCallbackBase {  // GameRichPresenceJoinRequested_t: "+connect_lobby <id>"
 public:
  RichJoinCallback() { m_iCallback = 337; }
  void Run(void* p) override {
    const GameRichPresenceJoinRequested_t* r = static_cast<const GameRichPresenceJoinRequested_t*>(p);
    char connect[257];
    std::memcpy(connect, r->connect, 256);
    connect[256] = 0;
    const char* at = std::strstr(connect, "+connect_lobby");
    if (!at) return;
    unsigned long long id = std::strtoull(at + 14, nullptr, 10);
    if (!id) return;
    std::lock_guard<std::mutex> lock(g_qm);
    g_joinRequests.push_back(id);
  }
  void Run(void* p, bool, SteamAPICall_t) override { Run(p); }
  int GetCallbackSizeBytes() override { return sizeof(GameRichPresenceJoinRequested_t); }
};

JoinLobbyCallback* g_joinCb = nullptr;
RichJoinCallback* g_richCb = nullptr;

// ---------------------------------------------------------------------------------------------- the net

const int kMaxMembers = 100;  // ("increase the player limit to 100", 2026-11-01; Steam's lobbies take up to 250)
const char* kVersion = "1";  // lobbies of other versions aren't listed (the state line's meaning changes with it)

// a state line's scene: S|1|<scene>|...
std::string SceneOf(const std::string& line) {
  if (line.compare(0, 4, "S|1|") != 0) return std::string();
  size_t bar = line.find('|', 4);
  return bar == std::string::npos ? std::string() : line.substr(4, bar - 4);
}

struct Peer {
  std::string scene;      // the scene its last state line said
  std::string state;      // the last state line
  double at = 0;          // when it came
  std::string name;
};

struct Net {
  enum State { OFF, IDLE, CREATING, JOINING, IN_LOBBY, FAILED } state = OFF;
  uint64_t me = 0, lobby = 0;
  std::string myName, error;
  bool wantPublic = true;
  std::string lockNext;  // the lock the next lobby made gets ("lock <hash>" before "host"; none: "lock -")
  SteamAPICall_t createCall = 0, joinCall = 0, listCall = 0;
  std::vector<uint64_t> members;
  std::map<uint64_t, Peer> peers;
  std::map<uint64_t, double> beatAt;
  std::vector<std::string> friendLines;  // "friend=<id>|<name>|<1 playing STORROR>" for each friend online
  double friendsAt = -1e9;
  std::atomic<uint64_t> lobbyNow{0};     // (the lobby, read by the game's thread for the overlay's invite)  // when each player in another scene was last sent its once-a-second line
  std::vector<std::string> listLines;
  int listDone = 0;
  std::string lastStatus;
  double membersAt = -1e9, sentAt = 0, peersAt = 0, acceptAt = -1e9, statusAt = -1e9;
  std::string meLine;
  double meReadAt = 0;
  bool peersDirty = false;

  void fail(const std::string& why) {
    error = why;
    Log("error: " + why);
  }

  bool callDone(SteamAPICall_t call, void* out, int size, int id, bool& failed) {
    failed = false;
    if (!S.IsAPICallCompleted(S.utils, call, &failed)) return false;
    if (failed) return true;
    bool f2 = false;
    if (!S.GetAPICallResult(S.utils, call, out, size, id, &f2) || f2) failed = true;
    return true;
  }

  void leave() {
    if (lobby) {
      for (uint64_t m : members) {
        if (m == me) continue;
        SteamNetworkingIdentity id = Identity(m);
        S.CloseSessionWithUser(S.msgs, &id);
      }
      S.LeaveLobby(S.mm, lobby);
      Log("left lobby " + U64(lobby));
    }
    S.ClearRichPresence(S.friends);
    lobby = 0;
    members.clear();
    peers.clear();
    peersDirty = true;
    state = IDLE;
  }

  void host(bool pub) {
    if (state == CREATING || state == JOINING) return;
    leave();
    wantPublic = pub;
    createCall = S.CreateLobby(S.mm, pub ? 2 : 1, kMaxMembers);  // k_ELobbyTypePublic, k_ELobbyTypeFriendsOnly
    state = CREATING;
    error.clear();
    Log(std::string("creating a ") + (pub ? "public" : "friends-only") + " lobby");
  }

  void join(uint64_t id) {
    if (!id || id == lobby) return;
    leave();
    joinCall = S.JoinLobby(S.mm, id);
    state = JOINING;
    error.clear();
    Log("joining lobby " + U64(id));
  }

  void list() {
    if (listCall) return;
    S.ListStringFilter(S.mm, "armp", kVersion, 0);    // k_ELobbyComparisonEqual (the ragdoll mod's lobbies only)
    S.ListDistanceFilter(S.mm, 3);                     // k_ELobbyDistanceFilterWorldwide
    S.ListCountFilter(S.mm, 50);
    listCall = S.RequestLobbyList(S.mm);
  }

  void entered(uint64_t id) {
    lobby = id;
    state = IN_LOBBY;
    membersAt = -1e9;
    std::string connect = "+connect_lobby " + U64(id);
    S.SetRichPresence(S.friends, "connect", connect.c_str());
    S.SetRichPresence(S.friends, "status", "Playing STORROR together");
    Log("in lobby " + U64(id) + " (owner " + U64(S.GetLobbyOwner(S.mm, id)) + ")");
  }

  void command(const std::string& line) {
    if (line.compare(0, 5, "lock ") == 0) lockNext = line.size() > 5 && line[5] != '-' ? Clean(line.c_str() + 5, 32) : std::string();
    else if (line == "host public") host(true);
    else if (line == "host friends") host(false);
    else if (line == "list") list();
    else if (line == "leave") leave();
    else if (line == "invite") {
      if (lobby) S.InviteDialog(S.friends, lobby);
    } else if (line.compare(0, 7, "invite ") == 0) {  // one friend, by Steam's own invite (no overlay needed)
      uint64_t who = std::strtoull(line.c_str() + 7, nullptr, 10);
      if (lobby && who) {
        bool ok = S.InviteUserToLobby(S.mm, lobby, who);
        Log(std::string("invited ") + U64(who) + (ok ? "" : " (Steam refused)"));
      }
    } else if (line.compare(0, 5, "join ") == 0) {
      join(std::strtoull(line.c_str() + 5, nullptr, 10));
    } else if (line.compare(0, 6, "scene ") == 0) {  // the host's scene, shown in the lobby list
      if (lobby && S.GetLobbyOwner(S.mm, lobby) == me) S.SetLobbyData(S.mm, lobby, "scene", Clean(line.c_str() + 6, 32).c_str());
    }
  }

  void tick() {
    const double now = NowMs();
    // queued joins (the overlay) and commands
    {
      std::deque<uint64_t> q;
      {
        std::lock_guard<std::mutex> lock(g_qm);
        q.swap(g_joinRequests);
      }
      for (uint64_t id : q) join(id);
    }
    std::string text;
    if (Take(L"cmd.txt", text))
      for (const std::string& line : Lines(text)) command(line);

    bool failed = false;
    if (createCall) {
      LobbyCreated_t r{};
      if (callDone(createCall, &r, sizeof r, 513, failed)) {
        createCall = 0;
        if (failed || r.result != 1 || !r.lobby) {
          state = IDLE;
          fail("couldn't make a lobby (Steam said " + std::to_string(r.result) + ")");
        } else {
          S.SetLobbyData(S.mm, r.lobby, "armp", kVersion);
          S.SetLobbyData(S.mm, r.lobby, "name", myName.c_str());
          S.SetLobbyData(S.mm, r.lobby, "public", wantPublic ? "1" : "0");
          S.SetLobbyData(S.mm, r.lobby, "lock", lockNext.c_str());
          S.SetLobbyJoinable(S.mm, r.lobby, true);
          entered(r.lobby);
        }
      }
    }
    if (joinCall) {
      LobbyEnter_t r{};
      if (callDone(joinCall, &r, sizeof r, 504, failed)) {
        joinCall = 0;
        if (failed || r.response != 1 || !r.lobby) {  // k_EChatRoomEnterResponseSuccess
          state = IDLE;
          fail("couldn't join that lobby (it's full or gone: " + std::to_string(r.response) + ")");
        } else {
          entered(r.lobby);
        }
      }
    }
    if (listCall) {
      LobbyMatchList_t r{};
      if (callDone(listCall, &r, sizeof r, 510, failed)) {
        listCall = 0;
        listLines.clear();
        for (int i = 0; !failed && i < (int)r.count && i < 50; i++) {
          uint64_t id = S.GetLobbyByIndex(S.mm, i);
          if (!id) continue;
          listLines.push_back("list=" + U64(id) + "|" + Clean(S.GetLobbyData(S.mm, id, "name")) + "|" +
                              std::to_string(S.GetNumLobbyMembers(S.mm, id)) + "|" + std::to_string(S.GetLobbyMemberLimit(S.mm, id)) +
                              "|" + Clean(S.GetLobbyData(S.mm, id, "scene"), 32) + "|" + Clean(S.GetLobbyData(S.mm, id, "lock"), 32));
        }
        listDone++;
      }
    }

    lobbyNow.store(state == IN_LOBBY ? lobby : 0);
    // the friends online (those playing STORROR first), every 5 s while in a lobby: to invite from the ONLINE tab
    if (state == IN_LOBBY && now - friendsAt > 5000) {
      friendsAt = now;
      std::vector<std::string> playing, other;
      const int n = S.GetFriendCount(S.friends, 4);  // k_EFriendFlagImmediate
      for (int i = 0; i < n && i < 2000; i++) {
        uint64_t f = S.GetFriendByIndex(S.friends, i, 4);
        if (!f || S.GetFriendPersonaState(S.friends, f) == 0) continue;  // (offline)
        unsigned char info[64];
        std::memset(info, 0, sizeof info);
        bool here = false;
        if (S.GetFriendGamePlayed(S.friends, f, info)) {
          uint64_t game = 0;
          std::memcpy(&game, info, 8);
          here = (game & 0xFFFFFF) == 3125250;
        }
        std::string l = "friend=" + U64(f) + "|" + Clean(S.GetFriendPersonaName(S.friends, f)) + "|" + (here ? "1" : "0");
        (here ? playing : other).push_back(l);
      }
      friendLines = playing;
      for (const std::string& l : other)
        if (friendLines.size() < 40) friendLines.push_back(l);
    }
    if (state != IN_LOBBY) friendLines.clear();
    if (state == IN_LOBBY) {
      if (now - membersAt > 500) {
        membersAt = now;
        std::vector<uint64_t> m;
        int n = S.GetNumLobbyMembers(S.mm, lobby);
        for (int i = 0; i < n && i < 64; i++) m.push_back(S.GetLobbyMemberByIndex(S.mm, lobby, i));
        if (m != members) {
          for (uint64_t old : members)
            if (old != me && std::find(m.begin(), m.end(), old) == m.end()) {
              peers.erase(old);
              peersDirty = true;
              SteamNetworkingIdentity id = Identity(old);
              S.CloseSessionWithUser(S.msgs, &id);
              Log("left: " + U64(old));
            }
          for (uint64_t now_m : m)
            if (std::find(members.begin(), members.end(), now_m) == members.end() && now_m != me)
              Log("joined: " + U64(now_m) + " " + Clean(S.GetFriendPersonaName(S.friends, now_m)));
          members = m;
        }
        if (n == 0) {  // (the lobby went: Steam says we're in none)
          fail("the lobby closed");
          leave();
        }
      }
      if (now - acceptAt > 1000) {
        acceptAt = now;
        for (uint64_t m : members)
          if (m != me) {
            SteamNetworkingIdentity id = Identity(m);
            S.AcceptSessionWithUser(S.msgs, &id);
          }
      }
      // this player's state, as often as Lua writes it (at most 30 times a second)
      if (now - meReadAt > 30) {
        meReadAt = now;
        std::string line;
        if (ReadAll(g_dir + L"me.txt", line) && line.size() > 2 && line.size() < 1200 && line.back() == '\n' && line[0] == 'S') {
          line.pop_back();
          if (line != meLine || now - sentAt > 250) {
            meLine = line;
            sentAt = now;
            // (the whole pose only to the players in the same scene - the ones who draw it; to the rest a line of the
            // scene alone once a second: with up to 100 in a lobby, spread over the courses, a pose to every one of
            // them was more than a home connection sends)
            const std::string mine = SceneOf(line);
            const std::string beat = "S|1|" + mine + "|0|-";
            for (uint64_t m : members)
              if (m != me) {
                auto it = peers.find(m);
                const bool same = it == peers.end() || it->second.scene.empty() || it->second.scene == mine;
                SteamNetworkingIdentity id = Identity(m);
                if (same) {
                  S.SendMessageToUser(S.msgs, &id, line.data(), (uint32_t)line.size(), 0 | 32, 0);  // unreliable, restart broken
                } else if (now - beatAt[m] > 1000) {
                  beatAt[m] = now;
                  S.SendMessageToUser(S.msgs, &id, beat.data(), (uint32_t)beat.size(), 0 | 32, 0);
                }
              }
          }
        }
      }
      // events: reliable, to everyone (or "to=<id>|..." to one)
      if (Take(L"out_events.txt", text))
        for (const std::string& line : Lines(text)) {
          uint64_t only = 0;
          std::string body = line;
          if (line.compare(0, 3, "to=") == 0) {
            size_t bar = line.find('|');
            if (bar == std::string::npos) continue;
            only = std::strtoull(line.c_str() + 3, nullptr, 10);
            body = line.substr(bar + 1);
          }
          if (body.empty() || body.size() > 1100) continue;
          for (uint64_t m : members)
            if (m != me && (!only || m == only)) {
              SteamNetworkingIdentity id = Identity(m);
              S.SendMessageToUser(S.msgs, &id, body.data(), (uint32_t)body.size(), 8 | 32, 1);  // reliable
            }
        }
    }
    // what came: states (channel 0), events (channel 1); from lobby members only
    for (int ch = 0; ch < 2; ch++) {
      SteamNetworkingMessage_t* got[32];
      int n;
      while ((n = S.ReceiveMessagesOnChannel(S.msgs, ch, got, 32)) > 0) {
        std::string events;
        for (int i = 0; i < n; i++) {
          SteamNetworkingMessage_t* m = got[i];
          const uint64_t from = m->peer.type == 16 ? m->peer.steamID64 : 0;
          const bool member = state == IN_LOBBY && from && std::find(members.begin(), members.end(), from) != members.end();
          if (member && m->size > 0 && m->size < 1200) {
            std::string body(static_cast<const char*>(m->data), (size_t)m->size);
            for (char& c : body)
              if (c == '\n' || c == '\r') c = ' ';
            if (ch == 0) {
              Peer& p = peers[from];
              p.scene = SceneOf(body);
              p.state = body;
              p.at = now;
              peersDirty = true;
            } else {
              events += U64(from) + "|" + body + "\n";
            }
          }
          S.Release(m);
        }
        if (!events.empty()) Append(L"in_events.txt", events);
        if (n < 32) break;
      }
    }
    // the others' states for Lua, ~30 times a second while there are any
    if ((peersDirty || !peers.empty()) && now - peersAt > 33) {
      peersAt = now;
      peersDirty = false;
      std::string out;
      for (auto& kv : peers) {
        if (kv.second.name.empty()) kv.second.name = Clean(S.GetFriendPersonaName(S.friends, kv.first));
        out += U64(kv.first) + "|" + std::to_string((long long)(now - kv.second.at)) + "|" + kv.second.name + "|" + kv.second.state + "\n";
      }
      WriteWhole(L"peers.txt", out);
    }
    // the status, when it changes (and once a second)
    if (now - statusAt > 100) {
      statusAt = now;
      static const char* names[] = {"off", "idle", "creating", "joining", "in_lobby", "failed"};
      std::string st = std::string("state=") + names[state] + "\nme=" + U64(me) + "\nmyname=" + myName + "\nlobby=" + U64(lobby) +
                       "\nowner=" + U64(lobby ? S.GetLobbyOwner(S.mm, lobby) : 0) + "\npublic=" +
                       (lobby ? Clean(S.GetLobbyData(S.mm, lobby, "public"), 2) : std::string()) + "\nlock=" +
                       (lobby ? Clean(S.GetLobbyData(S.mm, lobby, "lock"), 32) : std::string()) + "\nerror=" + error + "\n";
      for (uint64_t m : members) st += "member=" + U64(m) + "|" + Clean(m == me ? myName.c_str() : S.GetFriendPersonaName(S.friends, m)) + "\n";
      for (const std::string& l : listLines) st += l + "\n";
      for (const std::string& l : friendLines) st += l + "\n";
      st += "listdone=" + std::to_string(listDone) + "\nmax=" + std::to_string(lobby ? S.GetLobbyMemberLimit(S.mm, lobby) : kMaxMembers) + "\n";
      if (st != lastStatus) {
        if (WriteWhole(L"status.txt", st)) lastStatus = st;
      }
    }
  }
};

Net* g_net = nullptr;
std::atomic<bool> g_started{false};

// The pad's A (and the keyboard's Enter) for the ONLINE tab's screen: STORROR's menu keeps A to itself - nothing of the
// mod's Lua ever saw it ("theres no way to select ... with A?", 2026-11-01) - so it is read here, straight from the
// controller (XInput), while Lua says its screen is up (net\pad_on.txt there), and each press is a line in pad.txt.
DWORD WINAPI PadWorker(LPVOID) {
  HMODULE x = LoadLibraryW(L"xinput1_4.dll");
  if (!x) x = LoadLibraryW(L"xinput1_3.dll");
  if (!x) x = LoadLibraryW(L"xinput9_1_0.dll");
  typedef DWORD(WINAPI * GetState_t)(DWORD, XINPUT_STATE*);
  GetState_t get = x ? reinterpret_cast<GetState_t>(GetProcAddress(x, "XInputGetState")) : nullptr;
  Log(std::string("pad reader: ") + (get ? "XInput found" : "no XInput (Enter only)"));
  WORD last[4] = {0, 0, 0, 0};
  bool lastEnter = false, on = false, fresh = true;
  double checkAt = -1e9;
  for (;;) {
    const double now = NowMs();
    if (now - checkAt > 100) {
      checkAt = now;
      const bool was = on;
      on = GetFileAttributesW((g_dir + L"pad_on.txt").c_str()) != INVALID_FILE_ATTRIBUTES;
      if (on && !was) fresh = true;  // (a button already down as the screen comes up isn't a press)
    }
    if (!on) {
      Sleep(50);
      continue;
    }
    int presses = 0;
    for (DWORD i = 0; i < 4; i++) {
      XINPUT_STATE st;
      std::memset(&st, 0, sizeof st);
      WORD b = 0;
      if (get && get(i, &st) == ERROR_SUCCESS) b = st.Gamepad.wButtons;
      if (!fresh && (b & XINPUT_GAMEPAD_A) && !(last[i] & XINPUT_GAMEPAD_A)) presses++;
      last[i] = b;
    }
    DWORD pid = 0;
    HWND fg = GetForegroundWindow();
    if (fg) GetWindowThreadProcessId(fg, &pid);
    const bool enter = pid == GetCurrentProcessId() && (GetAsyncKeyState(VK_RETURN) & 0x8000) != 0;
    if (!fresh && enter && !lastEnter) presses++;
    lastEnter = enter;
    fresh = false;
    if (presses > 0) Append(L"pad.txt", std::string((size_t)presses, 'A') + "\n");
    Sleep(8);
  }
  return 0;
}

DWORD WINAPI Worker(LPVOID) {
  Net& n = *g_net;
  double triedAt = -1e9;
  for (;;) {
    const double now = NowMs();
    if (n.state == Net::OFF) {
      if (now - triedAt > 2000) {
        triedAt = now;
        if (S.load()) {
          n.me = S.GetSteamID(S.user);
          n.myName = Clean(S.GetPersonaName(S.friends));
          n.state = Net::IDLE;
          Log("Steam ready: " + U64(n.me) + " " + n.myName);
          // a launch from a friend's "Join Game" when the game wasn't running: +connect_lobby <id> on the command line
          const wchar_t* cl = GetCommandLineW();
          const wchar_t* at = cl ? std::wcsstr(cl, L"+connect_lobby") : nullptr;
          if (at) {
            unsigned long long id = std::wcstoull(at + 14, nullptr, 10);
            if (id) {
              std::lock_guard<std::mutex> lock(g_qm);
              g_joinRequests.push_back(id);
            }
          }
        } else {
          static std::string said;
          if (said != S.missing) {
            said = S.missing;
            Log("waiting for Steam: " + S.missing);
            WriteWhole(L"status.txt", "state=off\nerror=" + S.missing + "\n");
          }
        }
      }
    } else {
      n.tick();
    }
    Sleep(n.state == Net::IN_LOBBY ? 8 : 30);
  }
  return 0;
}

}  // namespace

// Lua: package.loadlib(<this dll>, "arnet_start")() once. Lua's state is never touched: it returns nothing.
extern "C" __declspec(dllexport) int arnet_start(void* /*lua_State*/) {
  bool expected = false;
  if (!g_started.compare_exchange_strong(expected, true)) return 0;
  // Kept loaded for good: Lua's package library would free it when its state closes, under the running thread.
  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, reinterpret_cast<LPCWSTR>(&arnet_start), &self);
  wchar_t path[MAX_PATH];
  DWORD n = GetModuleFileNameW(self, path, MAX_PATH);
  std::wstring p(path, n);
  p = p.substr(0, p.find_last_of(L"\\/"));    // ...\StorrorActiveRagdoll\bin
  p = p.substr(0, p.find_last_of(L"\\/"));    // ...\StorrorActiveRagdoll
  g_dir = p + L"\\net\\";
  CreateDirectoryW(g_dir.c_str(), nullptr);
  for (const wchar_t* f : {L"peers.txt", L"status.txt", L"in_events.txt", L"cmd.txt", L"out_events.txt", L"me.txt", L"pad.txt", L"pad_on.txt"})
    DeleteFileW((g_dir + f).c_str());
  Log("started");
  g_net = new Net();
  CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
  CreateThread(nullptr, 0, PadWorker, nullptr, 0, nullptr);
  return 0;
}

// Lua, on the game's thread: Steam overlay's invite dialog for the lobby ("nothing shows when you press invite steam
// friends", 2026-11-01: asked from the DLL's own thread, the overlay showed nothing)
extern "C" __declspec(dllexport) int arnet_invite(void* /*lua_State*/) {
  if (!g_net || !S.InviteDialog || !S.friends) return 0;
  const uint64_t lobby = g_net->lobbyNow.load();
  if (lobby) {
    S.InviteDialog(S.friends, lobby);
    Log("invite dialog asked for (game thread)");
  }
  return 0;
}

// Lua, on the game's thread, once Steam is up: Steam's join callbacks registered (they run on this thread).
extern "C" __declspec(dllexport) int arnet_callbacks(void* /*lua_State*/) {
  static bool done = false;
  if (done || !S.RegisterCallback) return 0;
  done = true;
  g_joinCb = new JoinLobbyCallback();
  g_richCb = new RichJoinCallback();
  S.RegisterCallback(g_joinCb, 333);
  S.RegisterCallback(g_richCb, 337);
  Log("join callbacks registered");
  return 0;
}
