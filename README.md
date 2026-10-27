# RS3 Chunk Picker plugin

A RuneScape 3 plugin, written for the official [RuneScape plugin API](https://developer.runescape.com/rs/),
that connects the game to a running [Chunk Picker for RS3](https://github.com/fenerax/chunk-picker-rs3).
It shows which chunk you are standing in, shades locked chunks on the ground,
lists your chunk tasks in game, and reports your levels, quests, completed
achievements and items (worn, backpack, coin pouch, tool belt and bank) to the picker.

**Status: beta.** Unreviewed plugins only run on the RuneScape beta world. This
plugin has not been submitted to the Plugin Hub. It automates no gameplay and
never runs game commands.

This is a fan project. It is not made, endorsed or supported by Jagex.
RuneScape is a trademark of Jagex Ltd.

## What it does

- **Panel:** your chunk ID and name, and whether the picker has it **Unlocked**,
  **Locked** or **Can be picked next**. It also shows your partner's chunk and a
  waiting roll when the picker has them. Drag the title bar; **- / +** collapses it.
  **Sync now** sends a fresh reading straight away instead of waiting for you to
  move or for the minute timer.
- **Chunk shading:** a red line where a locked chunk meets one you can walk in
  (amber for chunks you can pick next), fainter lines on the rest of the chunk
  grid nearby, and a dark haze over locked chunks. Colours, fills and optional
  glow walls are in Settings, and a look can be shared as a short code.
- **Locked-chunk warning:** a notice when you walk into a locked chunk, and when
  a roll is waiting.
- **Chunk tasks window:** **Here** lists the active tasks in your current chunk;
  **All active** lists the whole list, 12 rows a page.
- **Progress reports:** skill levels and XP, finished or started quests, and
  completed achievements (Achievement Diaries included), sent to the picker. The
  picker decides what to do with them; the plugin never unlocks a chunk or ticks
  a task itself. Achievements go only to a picker that says it accepts them.
- **Item evidence:** what you wear and carry in your backpack (item id, count,
  slot and name), your coin pouch, the tools on your tool belt and your bank.
  On a live world the picker ticks best-in-slot gear goals for items you own
  and counts your coins; other item tasks wait for your review there. Beta
  worlds never tick. Items go only to a picker that says it accepts them, and
  the coin pouch, tool belt and bank each only to a picker that lists them too.
- **Bank:** the game only shows the plugin your bank after you open it once
  each login, and only sees changes while it is open, so a deposit box or porter
  can change it unseen. The picker shows how long ago the bank was last seen.
- **Tool belt:** there is no tool belt container, so the plugin reads the
  game's per-tool variables (`TOOLBELT_*`).

## Install (beta world)

1. Install **PrettyUI** from the Plugin Hub (plugin ID `6398181`). See the
   [PrettyUI documentation](https://prettyui.j3.gg).
2. Join the beta world and open the console with Alt + the key under Esc.
3. Run `plugins_setpath <path to this repo>\plugins`.
4. Run `prf`, then `pon chunk-picker`.
5. Allow web access. The beta currently has a known issue with permission
   changes, so use the console and run these one at a time:

   ```text
   prl chunk-picker
   ppr chunk-picker
   ppe chunk-picker httpAccess
   prl chunk-picker
   ```

   `ppr` may show nothing; run it anyway. Grants may need repeating after the
   client restarts. **Diagnostics** shows `http=true` once it worked.
6. In the picker, open **More → Game plugin** and create a plugin key. In the
   game, open **Chunk Picker** in the Plugin Hub's Settings, choose the server
   (**home** is a picker on `127.0.0.1:8789`), paste the key and click **Save**,
   then **Test connection**. Each server keeps its own key, so choosing another
   server brings back the key saved for it, or asks for one.

Reload with `prl chunk-picker`; turn it off with `poff chunk-picker`. Without a
key, the panel still shows your chunk (Lumbridge is **12850**, Nardah **13613**).

The plugin can only reach the servers listed under `urls` in
`plugins/chunk-picker/plugin.json`, and those are loopback addresses. To use a
picker on another port, add it there.

## Privacy

- The plugin sends only your position, levels, XP, quest names, your
  completed achievements (id, name and category), your worn, backpack and coin
  pouch items (id, count, slot and name), your tool belt tools and your bank
  (id and count), plus a few diagnostic lines about what the plugin could read.
  Levels, quests, achievements and items each have their own switch in
  Settings; the items switch covers the pouch, tool belt and bank. Position goes
  with every report. It sends no account name, character name or world number.
- The key is kept in the plugin's local storage, which the game does not document
  as encrypted. **Forget key** removes the selected server's key; revoke it in
  the picker as well.
- That storage is shared by every character on the PC, so each server's key
  remembers the character it was saved on. On any other character the plugin stops sending
  and says so, until you click **Use key on this character** in Settings. The
  character name stays on your PC.
- Diagnostics show which settings are present, never their values.
  **Do not share screenshots of Settings.**

## Development

### Tests

The tests run the Lua code in [Fengari](https://github.com/fengari-lua/fengari)
(Lua 5.3; the game uses 5.4) against a mock of the game API. The repo has no
dependencies of its own: install Fengari somewhere else and point `FENGARI_HOME`
at that folder.

```bash
npm install --prefix ../lua-harness fengari
FENGARI_HOME=../lua-harness node tests/run.cjs
```

`tests/run.cjs` syntax-checks every Lua file, then runs the core, progress,
shading, tasks, achievements, items and event-lifecycle tests. Given a file path, it also writes the
HTTP requests `net.lua` would send. `tests/scratch-http.mjs` replays those
requests against a throwaway picker started from a local picker checkout
(`PICKER_SOURCE`); it never attaches to a running picker.

### Picker API

The plugin talks to the picker's plugin API v1 with a bearer key:

- `POST /api/plugin/v1/report` sends position, skills and quests, and, when
  the status lists `achievements`, `items`, `pouch`, `toolbelt` or `bank` under
  `accepts`, completed achievements, items, the coin pouch, the tool belt and
  bank parts.
- `GET /api/plugin/v1/status` returns the current chunk's state, nearby chunk
  states, partners and any waiting roll.
- `GET /api/plugin/v1/tasks` returns the saved task list.

The picker's `docs/plugin-api.md` is the reference. All JSON and HTTP handling
lives in `plugins/chunk-picker/net.lua`. Requests run one at a time, back off up
to five minutes after failures, respect `Retry-After`, and stop on a 401 until
the settings change. Quest lists are sent whole, never split. Completed
achievements are read at login, a few seconds after a completion, and every ten
minutes. They go in numbered parts of at most 12 KB, one part per report and
nothing else in it. The picker's status says how many parts it holds, so the
plugin starts over after a picker restart (at most once a minute) and backs off
for half an hour if the picker refuses them.

Worn and backpack items are read at login, two seconds after an inventory
change and every minute. They go after any achievement part, alone in a report,
when the reading or the worn journal changed. A container the plugin can't read
is sent as `null`, never as empty. Items worn while the picker wasn't listening
wait in a journal of at most 32 events in local storage, kept for the character
the key was saved on, until the picker's status acknowledges them. A refused
items report waits half an hour.

The coin pouch (container 623) and tool belt ride in the items report when the
picker's status lists `pouch` and `toolbelt` under `accepts`. Tool belt rows are
`[name, value]` for each nonzero `TOOLBELT_<TOOL>` varbit; the list of varbits
is found once per login. The bank (container 95) is read once it holds items,
two seconds after an inventory change and every minute. It goes, for a picker
that lists `bank`, as `[id, count]` rows in up to eight parts of at most 700
rows and 12 KB, one part per report and nothing else in it, with `age`: seconds
since the plugin last saw the bank open or changed. Once the status names the
set under `bank`, it isn't sent again unless it changes, the picker forgets it,
or the bank is seen again ten minutes after the time the picker holds.

### Beta dev tools, replay and the release zip

`dev/` holds testing tools that never ship: a separate beta-only plugin whose
buttons run Jagex's dev cheat commands (teleport to a chunk, step one chunk
over, give an item, open the bank), a replay tool that posts recorded reports to
a picker without the game, and `tools/build-release.mjs`, which builds the
Plugin Hub zip and refuses probe, test and dev files, cheat commands and
loopback server URLs. See [dev/README.md](dev/README.md), including the warning
that Jagex logs cheat commands. `node --test tests/build-release.test.mjs
tests/replay.test.mjs` tests the two Node tools.

### Notes

`docs/api-notes.md` collects what we learned about the plugin API on the beta
world: events, permissions, PrettyUI internals and Plugin Hub rules.

`plugins/chunk-picker-test` is the first, minimal experiment: a read-only box
with your chunk and coordinates. It sends nothing.

## Credits

- [PrettyUI](https://github.com/J3sven/prettyui) by J3sven provides the windows
  and controls.
- Chunk IDs follow the RuneScape map-square grid (64 × 64 tiles).

## License

MIT. See [LICENSE](LICENSE).
