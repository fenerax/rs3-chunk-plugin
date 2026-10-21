# RS3 Chunk Picker plugin

A RuneScape 3 plugin, written for the official [RuneScape plugin API](https://developer.runescape.com/rs/),
that connects the game to a running [Chunk Picker for RS3](https://github.com/fenerax/chunk-picker-rs3).
It shows which chunk you are standing in, shades locked chunks on the ground,
lists your chunk tasks in game, and reports your levels, quests and completed
achievements to the picker.

**Status: beta.** Unreviewed plugins only run on the RuneScape beta world. This
plugin has not been submitted to the Plugin Hub. It automates no gameplay and
never runs game commands.

This is a fan project. It is not made, endorsed or supported by Jagex.
RuneScape is a trademark of Jagex Ltd.

## What it does

- **Panel:** your chunk ID and name, and whether the picker has it **Unlocked**,
  **Locked** or **Can be picked next**. It also shows your partner's chunk and a
  waiting roll when the picker has them. Drag the title bar; **- / +** collapses it.
- **Chunk shading:** a red line and a low translucent wall where a locked chunk
  meets one you can walk in (amber for chunks you can pick next), and fainter
  lines on the rest of the chunk grid nearby. Colours and styles are in Settings,
  and a look can be shared as a short code.
- **Locked-chunk warning:** a notice when you walk into a locked chunk, and when
  a roll is waiting.
- **Chunk tasks window:** **Here** lists the active tasks in your current chunk;
  **All active** lists the whole list, 12 rows a page.
- **Progress reports:** skill levels and XP, finished or started quests, and
  completed achievements (Achievement Diaries included), sent to the picker. The
  picker decides what to do with them; the plugin never unlocks a chunk or ticks
  a task itself. Achievements go only to a picker that says it accepts them.

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
   client restarts. **Diagnostics** shows `http=true` once it worked. For chatbox
   notices, do the same with `chatAccess`.
6. In the picker, open **More → Game plugin** and create a plugin key. In the
   game, open **Chunk Picker** in the Plugin Hub's Settings, paste the key, choose
   the server (**home** is a picker on `127.0.0.1:8789`) and click **Save**, then
   **Test connection**.

Reload with `prl chunk-picker`; turn it off with `poff chunk-picker`. Without a
key, the panel still shows your chunk (Lumbridge is **12850**, Nardah **13613**).

The plugin can only reach the servers listed under `urls` in
`plugins/chunk-picker/plugin.json`, and those are loopback addresses. To use a
picker on another port, add it there.

## Privacy

- The plugin sends only your position, levels, XP, quest names and your
  completed achievements (id, name and category), plus a few diagnostic lines
  about what the plugin could read. Levels, quests and achievements each have
  their own switch in Settings; position goes with every report. It sends no
  account name, character name or world number.
- The key is kept in the plugin's local storage, which the game does not document
  as encrypted. **Forget key** removes it; revoke it in the picker as well.
- That storage is shared by every character on the PC, so the key remembers the
  character it was saved on. On any other character the plugin stops sending
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
shading, tasks, achievements and event-lifecycle tests. Given a file path, it also writes the
HTTP requests `net.lua` would send. `tests/scratch-http.mjs` replays those
requests against a throwaway picker started from a local picker checkout
(`PICKER_SOURCE`); it never attaches to a running picker.

### Picker API

The plugin talks to the picker's plugin API v1 with a bearer key:

- `POST /api/plugin/v1/report` sends position, skills and quests, and, when
  the status lists `achievements` under `accepts`, completed achievements.
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
