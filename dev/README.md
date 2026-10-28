# Dev tools (beta world only)

Nothing in `dev/` ever ships. `tools/build-release.mjs` zips only
`plugins/chunk-picker`, and refuses to build if that folder contains a probe
file, a test file, anything named `dev`, or a cheat command.

## Cheat commands: read this first

- These tools type Jagex's **dev cheat commands** (`!tele`, `!give`, `!bank`,
  `!getcoord`). They only work on the development (beta) servers.
- **Jagex logs every cheat command on the server**, and says accounts found
  abusing them, for any reason, may be banned. Use them only to test this
  plugin, on beta, and never on a live world.
- A command runs only when you press its button, at most one every 2 seconds.
  Each send is numbered (Sent #3) and printed in the console; a second press
  inside the 2 seconds is dropped and says so.
  Nothing here runs on a timer or in a loop.

## Chunk Picker dev tools plugin

`dev/chunk-picker-dev` is a separate plugin with one window:

- **Position:** chunk id, map square, local tile and floor, read the same way
  as the real plugin (an instance is mapped back to its source).
- **Teleport:** type a chunk id (`12850`), a map square (`50,50`) or
  floor and square (`1,50,50`), then **Teleport** to the middle of it
  (`!tele floor,x,z,32,32`). Without a floor it keeps yours.
- **N / E / S / W:** one chunk over, keeping your floor and spot in the
  chunk, for chunk-crossing tests.
- **Find an item:** type part of its name (`rune arrow`) and press **Search**.
  The first search each login reads the game's item list, a slice per frame,
  then shows 5 results at a time (**More** for the next). Press a result's
  number to put its id under Give. Searching never sends a command.
- **Give:** an item configName (`logs`) or its numeric id (`1511`, looked up
  through `config.Obj`), and a count (default 1; `5000`, `20k`, `1.5m`, `2b`
  also work, up to 2147483647): `!give logs 1`.
- **Give noted:** the same, but gives the noted copy so a big count fits
  (`!give logs_noted 5000`, whatever its configName is). The API has no note
  link, so it takes the item next to it (id + 1, then id - 1) that has the
  same name and always stacks. Items that already stack say so instead.
- **Open bank** (`!bank`) and **Where am I** (`!getcoord`, printed in the
  console).

If a command can't run from the plugin, the window shows the exact command to
type into the console yourself.

## Loading it next to the real plugin

The dev path is a single folder, so link both plugins into one folder. In
PowerShell, from the repo:

```text
powershell -File dev\link-dev-plugins.ps1
```

It makes `%LOCALAPPDATA%\chunk-picker-dev-plugins` with junctions to
`plugins\chunk-picker` and `dev\chunk-picker-dev`, and prints the console
block. In the beta client's console (Alt + the key under Esc):

```text
plugins_setpath C:\Users\<you>\AppData\Local\chunk-picker-dev-plugins
prf
pon chunk-picker
pon chunk-picker-dev
```

The folder names stay `chunk-picker` and `chunk-picker-dev`, so the real
plugin keeps its saved settings and the usual `prl chunk-picker` still works.
Closing the dev window hides it until `prl chunk-picker-dev`.

## Other test tools

- `node tools/replay.mjs <picker origin> <key file> tests/fixtures/replay-basic.jsonl`
  posts a recorded sequence of plugin reports to a picker, so picker-side
  checks run without logging in. It fills in `v`, `seq` and `sentAt`, never
  prints the key or the picker's address, refuses non-loopback pickers unless
  `--allow-remote`, and refuses live-world reports unless `--allow-live-world`.
  The fixture is synthetic and claims a beta world, so a picker ticks nothing.
- `node tools/build-release.mjs <output dir outside the repo> --version 1.0.0`
  builds the Plugin Hub zip (`chunk-picker-100.zip`), leaving loopback server
  URLs out of its manifest. `--allow-local` keeps them, for a beta zip, with a
  warning.

Tests: `node tests/run.cjs` (Lua, including the dev tools' command strings) and
`node --test tests/build-release.test.mjs tests/replay.test.mjs`.
