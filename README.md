# RS3 chunk picker plugin

Experiments with the official RuneScape plugin API
(https://developer.runescape.com/rs/) for syncing the chunk picker with the game.

## Chunk Picker 0.1.0 (beta)

This is the real companion in `plugins/chunk-picker/`. The original
`chunk-picker-test` below is unchanged and remains the local-only fallback.

1. Install **PrettyUI** from the Plugin Hub (Jagex-recommended, plugin ID
   `6398181`). [PrettyUI documentation](https://prettyui.j3.gg).
2. On the **beta world**, open the console with Alt + the key under Esc.
3. Run `plugins_setpath C:\Users\User\Projects\rs3-chunk-plugin\plugins`.
4. Run `prf`, then `pon chunk-picker`. If the old box is enabled, run
   `poff chunk-picker-test` to remove the overlap.
5. With no key, check the local chunk first: Nardah should show **13613**;
   Lumbridge **12850**. The panel starts near the top centre. Drag its title
   bar, then use **- / +** at the right of the title to collapse/expand it.
6. Run `ppe chunk-picker httpAccess` to allow web access (on beta, `ppr` showed
   no prompt). Open **Chunk Picker** in
   the Plugin Hub's Settings layer.
7. Choose **home** for your own picker on port **8789**, once its plugin routes
   are installed and running. **scratch** is only for an intentionally started
   test picker on port **8950**; the offline test server is stopped after tests.
   The server list comes from `Plugin.urls`; add future servers in the manifest.
8. Create a personal key in the picker's **Game plugin** page. Paste it in the
   visible field, click **Save**, then **Test connection**. Keep **Beta world**
   on while using the imported beta character. Levels and quests default on;
   either can be turned off. **Forget key** removes the saved key.
9. Look for a chunk name and **Unlocked** in green, **Locked** in red with a
   warning, or **Can be picked next** only when the picker reports availability.
   Walk normally over an allowed chunk boundary; sync follows about one second
   after the new chunk is stable. Floors above zero appear separately.
10. Drag/collapse, reload with `prl chunk-picker`, and check the saved position
    and collapsed state. Try a world hop, resize, and an interface-mode change.
    In an instance, expect a mapped source chunk or **Instance**, never an
    unverified instance-local chunk.
11. Open the plugin's ribbon tab, **Diagnostics**. Use **Copy to console** to
    print the same lines; this button logs text, it does not access the clipboard.
    Send screenshots of the panel and Diagnostics, plus any console lines
    starting **Chunk Picker**. **Do not screenshot Settings or share your key.**
12. Open your tasks in the picker once, then click **Tasks** on the panel. Check
    **Here** in Nardah, walk into the next chunk and watch it change within a few
    seconds, switch to **All active** and page with **More** / **Back**. Drag the
    window, close it, reload, and check it stays closed and reopens where it was.

### Chunk shading

With **Shade locked chunks** on (the default), the plugin draws the picker's
states on the ground around you once it has a status from the picker:

- Where a locked chunk meets an unlocked or available one, a bright red line
  follows the ground along the border, with a translucent red wall about half
  a tile high that fades upward. Available next to unlocked is the same in amber.
- Other edges of locked or available chunks in the 5×5 block get a fainter line,
  so the chunk grid stays visible when everything around you is locked.
- Unlocked and unknown chunks draw nothing. Shading is hidden in instances.

It is one persistent shape (`ShapeList.CreateInstance`), rebuilt only when the
states, your floor or the toggle change, or when terrain that was not loaded
yet arrives. Diagnostics shows a `Shading:` line with its state and the number
of edges and walls drawn.

### Tasks window

**Tasks** on the panel's title bar opens a separate **Chunk tasks** window with
your own active tasks, in the picker's Active Tasks order:

- **Here** lists the active tasks in the chunk you are standing in.
- **All active** lists your whole active list (the first 100; the header shows
  the true total). **Back** / **More** page through 12 rows at a time.

The list is the one the picker last saved for you; the plugin never asks the
picker to calculate tasks. If the header says **No saved task list yet**, open
your tasks in the picker once. After you tick a task or unlock a chunk, the
header adds **saved before your last change** until the picker shows your
tasks again: ticked tasks already drop out, new chunks' tasks are not there yet.
The window refreshes every 15 seconds while open, and sooner (at most every 3
seconds) when you walk into another chunk. Closing it stops the requests. Its
position and view are remembered. A picker without this route shows **this
picker has no in-game task list** and checks again after five minutes; location
sync is unaffected.

To reload: `prl chunk-picker`. To disable: `poff chunk-picker`. **Show panel**
in Settings hides the overlay while syncing continues. No gameplay is automated.
The picker only proposes observed progress for review; it never unlocks a chunk
from plugin traffic. Stopping or forgetting a key does not revoke it on the picker;
use the picker's key controls to revoke it.

### Beta diagnostics and limits

The game cannot be run by the offline test harness. Beta screenshots
will establish whether manifest loopback URLs work in the client, which quest
enumeration works (`config.Quest`, `id.Quest`, or bounded `FromID(0..4095)`),
whether all 29 skill readings are available, whether instance mapping exists,
which standard libraries exist, and whether PrettyUI's drag position persists.
The panel uses PrettyUI's source-verified `root` field to observe movement on
each client tick; that field is not part of its documented public interface.
Window rebuilds and the title toggle also need the beta visual check.
Diagnostics logs only database key presence, never saved values. It records
the last five HTTP codes/flags and redacted transport errors, and whether any
loopback URL returned an HTTP response (including an auth error).

PersistentDB's character/account scope and encryption are undocumented. Assume
the personal key is stored unencrypted locally and shared by this plugin's local
settings. Check Settings when changing characters; use **Forget key** if needed.
This beta package deliberately omits `contactEmailAddress`, as requested. It is
not ready for Plugin Hub submission or moderation review.

The public game API has no documented current world number. Reports use the fixed
companion channel `world.id = 1` and the actual **Beta world** toggle. This is a
channel identifier, not a claim that the player is on RuneScape World 1. Distinct
beta/live copies remain separate in picker proposals; real world-number changes
are not tracked. If the client omits `os.time`, the plugin bootstraps UTC from
the authenticated status response's HTTP `Date` header and advances it with the
documented Draw elapsed time. If both clocks are unavailable, location remains
local and Diagnostics explains why reports cannot be dated.

### Wire contract

Aligned to `C:/Users/User/Projects/chunk-picker-rs3-core-wt/plugsync/docs/plugin-api.md`
on 2026-10-19. All JSON and HTTP shape decisions are in
`plugins/chunk-picker/net.lua`. Both requests use:

```text
Authorization: Bearer <personal plugin key>
Content-Type: application/json
```

`GET /api/plugin/v1/status` has no body or query. **Test connection** uses this
route; it does not send a progress snapshot itself. Reports use
`POST /api/plugin/v1/report` with this exact shape (skills, quests and world are
optional in the API; this plugin always supplies world):

```json
{
  "v": 1,
  "seq": 1792411200000,
  "sentAt": "2026-10-19T12:00:00Z",
  "world": { "id": 1, "beta": true },
  "position": { "x": 53, "z": 45, "floor": 0 },
  "skills": { "ATTACK": { "level": 12, "xp": 1584 } },
  "quests": { "finished": ["Cook's Assistant"], "started": ["The Blood Pact"] }
}
```

Sequence numbers persist immediately and increase from Unix milliseconds when
UTC is available. XP is sent as actual XP from the API, without a guessed scaling
conversion. Skills cover all 29 IDs on login and only changed names thereafter,
debounced ten seconds. Quest snapshots contain display names; relevant quest-var
changes debounce thirty seconds, with a three-minute poll when mappings are
incomplete. The stable location diff waits one second and heartbeats every sixty
seconds. Instance mapping failures suppress reports because position is required.
One HTTP request can be active; failures back off 2, 4, 8… up to 300 seconds.
429 respects numeric `Retry-After`; 401 stops sends until connection settings
change. Requests have a local thirty-second cancellation guard.

Both routes return:

```json
{
  "v": 1,
  "player": { "id": "player1", "name": "Explorer 1" },
  "chunkId": "13613",
  "chunkName": "Nardah",
  "state": "unlocked",
  "activeTaskCount": null,
  "unlockedChunkCount": 1,
  "pendingProgress": true,
  "seenAt": "2026-10-19T12:00:00.000Z"
}
```

`state` may be `unlocked`, `locked`, `available`, or `unknown`; `chunkId`,
`chunkName`, and `seenAt` may be null. Newer pickers add `nearby`: up to 25
`{ "chunkId", "state" }` rows for the 5×5 block of map squares around the
reported chunk, or null. `net.lua` turns it into a map from chunk ID to state
and drops malformed rows; shading falls back to the current chunk without it.
Other fields are currently informational.
Errors are `{ "message": "…" }`; the plugin does not log response bodies.

The Tasks window uses `GET /api/plugin/v1/tasks` (no body or query, same key).
It returns `{ v, ready, stale, stateRevision, chunkId, hereKnown, here, all,
hereCount, allCount }`, where rows are `{ id, label, category, level? }`; see
the picker's `docs/plugin-api.md`. Task reads never block or slow reports: they
keep their own retry timer, and a 401/404 only disables the window.

Differences from the provisional brief: ISO UTC `sentAt` replaces Unix seconds/ms;
`world` is `{id,beta}` rather than `"beta"`; response keys are `chunkId`,
`activeTaskCount`, `unlockedChunkCount`, and `pendingProgress`. Quest objects
**replace**, rather than append to, the prior lists. Therefore the plugin sends
quests separately from skills if that keeps the complete lists below 16,384
bytes. If quests alone exceed that limit or 500 names per list, it holds them
locally, shows a diagnostic, and continues location/skills. Splitting quest lists
across reports would overwrite earlier parts, so that requires a future API
extension. No partial quest list is silently sent.

### Offline verification

No dependencies are installed in this repo. Install `fengari` in
`C:/Users/User/Projects/chunk-picker-rs3/.local/claude-tools/lua-harness`, or set
`FENGARI_HOME` to another external harness directory with that package. Run:

```powershell
node C:/Users/User/Projects/rs3-chunk-plugin/tests/run.cjs C:/Users/User/Projects/chunk-picker-rs3/.local/claude-tools/lua-harness/plugin-requests.json
node C:/Users/User/Projects/rs3-chunk-plugin/tests/scratch-http.mjs C:/Users/User/Projects/chunk-picker-rs3/.local/claude-tools/lua-harness/plugin-requests.json
```

The first command syntax-checks **every Lua file**, runs JSON/location/instance,
payload/backoff, progress and mocked UI/event lifecycle tests, then exports real
`net.lua` requests. Fengari is Lua 5.3; the game uses 5.4.8. The second command
needs a picker checkout with the plugin routes: `PICKER_SOURCE` (default: the
`plugin-port` worktree under `.local/claude-tools`); `SCRATCH_HTTP_PORT` picks
another free port. It checks the port is free, starts one picker
with bundled/synthetic inputs and a fresh isolated save/master/key, tests those
exported requests, and stops the child. It never attaches to a running picker.
Scratch data stays outside every repo. No live endpoints or game client are used.

## chunk-picker-test

This plugin is read-only. It shows the chunk you are standing in and sends nothing anywhere. Unreviewed plugins only run on the RuneScape beta world, not on live worlds.

1. Join the beta world. Use the beta config link in the official "Accessing the API" tutorial, and import your live character from the lobby.
2. Open the console with Alt + the key under Esc.
3. Run `plugins_setpath C:\Users\User\Projects\rs3-chunk-plugin\plugins`
4. Run `prf`, then `plist`. The list should show `chunk-picker-test`.
5. Run `pon chunk-picker-test`.

A box shows `Chunk 12850 (50, 50)  floor 0` in Lumbridge, and it updates as you walk. Each change is also written to the console.

To reload after an edit, run `prl chunk-picker-test`. To turn it off, run `poff chunk-picker-test`.
