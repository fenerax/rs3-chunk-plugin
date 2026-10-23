# RS3 Plugin API notes (chunk picker companion)

Digest of the official docs at https://developer.runescape.com/rs/ as read on 2026-10-19.
Signatures are copied exactly; everything else is paraphrased. **UNDOCUMENTED** marks things the docs don't
say, so test those on the beta world first.

Runtime: Lua 5.4.8 embedded in the client (https://developer.runescape.com/rs/getting-started.html).

---

## 1. Manifest and permissions

Sources: https://developer.runescape.com/rs/structure.html, https://developer.runescape.com/rs/core/plugin.html,
https://developer.runescape.com/rs/core/events.html (for the two icon flags)

Layout: `main.lua` (entry point), `plugin.json` (manifest), `resources/` (PNG/OGG only).

| Field | Type | Notes |
|---|---|---|
| `name` | String | display name |
| `version` | String | digits and dots (mod.io enforces this too) |
| `contactEmailAddress` | String | legally required; the docs suggest it differ from the mod.io login |
| `requiredDependencies` / `optionalDependencies` | `[String]` or `{Var -> Plugin}` | other plugins |
| `requiredPermissions` / `optionalPermissions` | `[String]` | `httpAccess`, `chatAccess`, `trackingAccess` |
| `urls` | `{ VarName -> URL }` | HTTP or HTTPS **base** URLs; the only source of URL handles |
| `hasSettingsIcon` | Bool | only on the events page; enables `Event.SettingsLayerReady` |
| `hasRibbonIcon` | Bool | only on the events page; enables `Event.ContentLayerReady` |

Remote manifests may add extra fields prefixed `remote`.

Lua side:
- Manifest URLs: `Plugin.urls.<VarName>` returns a `PluginURL`.
- Resources: `Plugin.resources.<path>` with `:Load()`, `:Unload()` and props `path`, `loaded`, `inUse`.
  PNG sprites max out at 1024x1024.
- `function Plugin.HasPermission(permission : PluginPermissions) -> Bool`.
- The docs advise making permissions optional and checking them at runtime; `Event.OptionalPermissionChanged
  {permissionName, enabled}` fires when the player toggles one.
- `require("path/without/ext")`: paths are relative to the plugin root, results are cached, cycles raise an error.
- Global hooks you define yourself; they must not be `local`:
  - `PluginShutdown()` runs on disable or client close.
  - `PluginDependencyUpdate(info)` receives `{pluginIdentifier, enabled}`.

Likely manifest:
```json
{ "name": "Chunk Picker", "version": "0.1.0", "contactEmailAddress": "...",
  "optionalPermissions": ["httpAccess"], "urls": { "picker": "https://picker.example.com" },
  "hasSettingsIcon": true }
```

## 2. HTTP

Source: https://developer.runescape.com/rs/core/http.html

Needs the `httpAccess` permission, and the target must be declared in manifest `urls`. Malformed URLs and
shortener or redirect URLs get rejected in moderation.

```
function HTTPRequest.new(baseURL : PluginURL, path : String?) -> HTTPRequest
function HTTPRequest:Get(completionCallback : function? (self), progressCallback : function? (self))
function HTTPRequest:Post(data : String, completionCallback : function? (self), progressCallback : function? (self))
function HTTPRequest:Cancel()
function HTTPRequest:AddHeader(key : String, value : String)
```
- Calling Get, Post or AddHeader on an active request raises an error. Add headers first and use one object per call.
- Properties:
  - Response: `data`, `header`, `responseCode`, `url`.
  - State: `finished`, `successful`, `failed`, `timedOut`, `cancelled`.
  - Errors: `errorCode`, `errorInfo`.
  - Progress: `progress` (Float?), `downloadedBytes`, `downloadTotalBytes`.
- The POST body is a plain String. The default Content-Type is UNDOCUMENTED, so set it with `AddHeader`. The player
  key can go in a header such as `Authorization`.

Decision-relevant:
- **Runtime URL: the host cannot be changed at runtime.**
  - `baseURL` must be a `PluginURL` from `Plugin.urls`, fixed in the manifest at submission. Only `path` is a runtime
    string.
  - So a player can't type in their own server address. Options:
    - (a) one fixed public base URL plus a per-player key/path;
    - (b) several pre-declared base URLs to choose from.
- **localhost / 127.0.0.1: UNDOCUMENTED.** No page mentions either. Plain `http://` appears in the examples, so http
  itself looks allowed. Try a `http://127.0.0.1:<port>` manifest URL on beta; it may work in dev yet fail review,
  since review runs in a closed environment.
- The timeout length, body size limit, rate limit, TLS/cert rules and redirect handling are all UNDOCUMENTED.

## 3. JSON and Lua stdlib

Sources: https://developer.runescape.com/rs/core/string.html, https://developer.runescape.com/rs/core/index.html

- **No JSON encoder or decoder is documented.**
  - Bundle a small hand-written `json.lua` encoder, escaping `"`, `\` and control characters.
  - Keep server replies trivial (status code only), or write a tiny decoder.
- Globals:
  - `formatStr(format, ...) -> String` uses fmtlib `{}` syntax, elementary types only.
  - `print(...)`, `log(...)` (adds the plugin name), `ExecuteConsoleCommand(command : String)`.
- Stdlib availability (`os`, `io`, `utf8`, `string.format`, `load`) is UNDOCUMENTED. There is no sandbox page;
  examples only use `string`, `pairs`, `ipairs`, `tostring`, `#`. Probe on beta with `print(type(os), type(io))`.
- Lua integers are 64-bit, so `mapSquareX*256+mapSquareZ` is safe.

## 4. Player data

Sources: https://developer.runescape.com/rs/game/player.html, https://developer.runescape.com/rs/game/entity/playerentity.html,
https://developer.runescape.com/rs/game/coordgrid.html, https://developer.runescape.com/rs/game/world.html,
https://developer.runescape.com/rs/game/config/questtype.html, https://developer.runescape.com/rs/game/config/vartype.html,
https://developer.runescape.com/rs/game/inventory.html, https://developer.runescape.com/rs/game/config/enumtype.html

**Player**
- `Player.IsAvailable()`; `Player.GetTrackingID() -> Long?` (needs `trackingAccess`, arrives seconds after login;
  a possible stable account id).
- Levels: `GetLevelGameplay(skill)` (boosted), `GetLevelCapped(skill)` (F2P cap), `GetLevelUncapped(skill)`.
  XP: `GetXPCapped(skill)`, `GetXPUncapped(skill)`. Also `GetRunEnergy()`, `GetWeight()`, `GetCombatLevel()`,
  `GetEntity() -> PlayerEntity` (same as `PlayerList.Self()`).
- `SkillType` 0-28: ATTACK, DEFENCE, STRENGTH, HITPOINTS, RANGED, PRAYER, MAGIC, COOKING, WOODCUTTING, FLETCHING,
  FISHING, FIREMAKING, CRAFTING, SMITHING, MINING, HERBLORE, AGILITY, THIEVING, SLAYER, FARMING, RUNECRAFTING,
  HUNTER, CONSTRUCTION, SUMMONING, DUNGEONEERING, DIVINATION, INVENTION, ARCHAEOLOGY, NECROMANCY.
  `SkillType.FromID(id)` exists; one example writes `SkillType.Attack`, so looping `FromID(0..28)` is safest.

**PlayerEntity** props: `isValid`, `uid`, `displayName`, `position`, `coordGrid`, `facing`, `route`, `routeEnd`.

**CoordGrid** (location: `Player.GetEntity().coordGrid`)
- Props: `level` 0-3; `x`, `z` 0-12799; `mapSquareX`, `mapSquareZ` 0-199 (chunk = `mapSquareX*256+mapSquareZ`);
  `localX`, `localZ` 0-63.
- `CoordGrid.new(level, msX, msZ[, lx, lz])`; `:ToPacked()` gives `(level<<28)|(x<<14)|z`; `ToCoordFine`/`FromCoordFine`.
- **Instances:** when `World.IsRegion()` is true, map back with `World.GetRegionSourceForCoordGrid(coord) -> CoordGrid?`;
  otherwise instance coordinates give bogus chunks.
- `World.IsMembers()` is a members **world**, not account membership (not exposed). Also `GetMapSquareBounds() -> Rect?`,
  `GetPing`, `GetRebootTimer`, `GetGroundHeight`.

**Quests** (`config.Quest.COOK_QUEST`, `config.Quest["QUEST_DUCK"]`, `config.Quest.FromID(n)`, ids in `id.Quest.*`)
- Identity: `id`, `configName`, `name`, `sortName`, `deprecated`, `isMembers`.
- Type and rewards: `questPoints`, `type` (NORMAL/SEASONAL/TUTORIAL), `difficulty`.
- Prerequisites: `preReqQuests`, `preReqSkills {skillType, minimumLevel}`, `preReqQuestPoints`, `canStartQuest`.
- **Status: `hasStartedQuest`, `hasFinishedQuest`.**
- Other: `masterQuestVars {varPlayer, startState, endState}`, `startCoordGrids`, `params`.
- **Iterating all quests is UNDOCUMENTED; no list API exists.** Try in order:
  1. `pairs(config.Quest)` or `pairs(id.Quest)`
  2. a `FromID(0..N)` scan that skips nil, `deprecated` and non-NORMAL entries
  3. a game `config.Enum` listing quests; enums expose `.values` as `{ {in,out}, ... }`, but which enum is unknown
  4. a static list of configNames shipped with the plugin.
- Config objects are proxy usertypes. They're fine to keep in Lua but can't go into PersistentDB, so store ids or
  configNames instead.

**Vars:** `var.VarPlayer.NAME`, `var.VarClient.NAME`, `.FromID(n)`; props `value`, `valueType`, `isVarBit`. Only
server-transmitted vars are readable.

**Inventory**
- `Inventory.Find(config.Inv.X | id) -> Inv`
- Methods: `GetSlot(i)` (1-based), `GetSlots()`, `GetTotal(obj|id)`, `GetCategoryTotal`.
- Props: `slotCount`, `usedSlotCount`, `freeSlotCount`, `isValid`. A slot is `{obj : ObjType, count}`.
- `config.Inv["BANK"]` exists. When bank contents are present (probably only while it's open) is UNDOCUMENTED, and so
  are the backpack and equipment inv names.
- `items.lua` tries `config.Inv` INV, BACKPACK, INVENTORY, then id 93 for the backpack, and WORN, EQUIPMENT,
  WORNITEMS, then id 94 for worn items (the classic cache ids). Diagnostics show which one answered ("via").
  Empty slots are assumed to hold id -1 or no object. Check both on beta.

**Guideline limit:** exporting info about OTHER players is prohibited. The player's own data is fine.

## 5. Events

Source: https://developer.runescape.com/rs/core/events.html

`Event.<Name>.Subscribe(refName : String, fn)` / `Event.<Name>.Unsubscribe(refName)`; the handler gets one table.

| Event | Payload / use for us |
|---|---|
| `Logic` | `{logicTick}`, 50/s; too hot for HTTP |
| `ServerLogic` | no payload, ~600 ms game tick; poll location here |
| `WorldUpdated` / `WorldCreated` | movement (no payload) / map-square min/max bounds |
| `RegionCreated` / `RegionUpdated` | instances |
| `SkillTransmit` | `{skill, oldXP, newXP, oldGameplayLevel, newGameplayLevel}` |
| `VarTransmit` | `{var, oldValue, newValue}`; pair with a quest's `masterQuestVars.varPlayer` |
| `InventoryAdded` / `InventoryUpdated` / `InventoryRemoved` | `{inv}` / `{inv, slotsUpdated}` / `{inv}` |
| `GameStateChanged` | `{oldState, newState}`: LOGINSCREEN 10, LOBBY 20, GAME 30, SWITCH_WORLD 37, LOADING 40; snapshot on GAME |
| `WindowSizeChanged` | `{oldWidth, oldHeight, newWidth, newHeight}`; re-clamp the panel |
| `KeyDown` / `KeyUp` / `KeyTyped` | keyboard |
| `SettingsLayerReady` | `{component}`; needs `hasSettingsIcon`; the plugin's layer in the Plugin Hub Manage tab, cleared before each call |
| `ContentLayerReady` | `{component}`; needs `hasRibbonIcon`; the plugin's layer in the "Plugins" floating window ribbon |

**Missing:** there is no location-changed event and no quest event. Diff `coordGrid` on `ServerLogic`/`WorldUpdated`
and use `VarTransmit` for quests.

## 6. UI

Sources: https://developer.runescape.com/rs/ui/component.html, https://developer.runescape.com/rs/ui/component_configs.html,
https://developer.runescape.com/rs/ui/common_types.html, https://developer.runescape.com/rs/ui/stylesheets.html,
https://developer.runescape.com/rs/ui/interactive_components/input_field.html,
https://developer.runescape.com/rs/ui/layout_components/group_box.html, https://developer.runescape.com/rs/ui/layout_components/panel.html,
https://developer.runescape.com/rs/core/mouse.html, https://developer.runescape.com/rs/tutorial/2simpleui.html

**Root and constructors**
- Free-floating root, from tutorial 2: `ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)`.
  Plugins cannot create new interfaces.
- Every constructor has the form `X.new(parent, categoryID : Int?, dynamicID : Int?)` and fails on an id clash.
  Category ids run 0-235; dynamic ids run 0-4096 when cat = 0, otherwise 0-235.
- Containers:
  - `ui.Layer` places children freely.
  - `ui.Panel` auto-stacks children (`isVertical`, `spacing`).
  - `ui.GroupBox` adds a background and optional header, which suits our panel.
    `SetHeaderLayout(width, height, offsetX, offsetY, ui.GroupBoxHeaderAlignMode.LEFT|CENTRE|RIGHT)`; props
    `headerText`, `contentBackgroundSprite`, `headerBackgroundSprite`, `contentMargin`.
- Leaves:
  - `ui.Text`: `content` (with `<br>`), `font`, `AlignTo`, `maxLines`, `isShadowed`.
  - `ui.Rectangle`: `fill`, `outlineThickness`.
  - `ui.Sprite`: `sprite`.
  - `ui.Button`: `label`, `canToggle`, `isToggled`, `mode`. Custom sprites need 8 vertical states.

**Layout and look**
- `SetPos(x, y, parentPcX?, parentPcY?, selfPcX?, selfPcY?)`, `SetSize(w, h, parentPcX?, parentPcY?)`, `SetX/SetY`,
  `MoveToFront()`, `Destroy()`.
- Read-only: `x`, `y`, `width`, `height`, `xyGlobal`.
- Look: `hidden`, `alpha`, `colour` (Vector4), `rgba`, `stylesheetID`, `clickthrough`, `enabled`.

**Hooks:** `comp:Subscribe(ui.Hook.X, [id,] fn)`. Returning false stops later handlers.
- `ONCLICK` / `ONRELEASE` / `ONHOLD (self, x, y)`
- `ONDRAG (self, dragStartX, dragStartY)`, `ONDRAGCOMPLETE (self, dragDestination, dragEndX, dragEndY)`
- `ONBUTTONPRESSED (self, cur, prev)`, `ONCONTENTCHANGED (self, reason, newContents)`
- `ONMOUSEOVER`, `ONMOUSELEAVE`, `ONTIMER` (per logic tick), `ONRESIZE`

**Dragging (movable panel):** there is no built-in movable window.
- `dragConfig : ui.ComponentDragConfig {draggedComponent, renderBehaviour, dragDelayTicks, deadZone}`, with
  `ui.DragRenderBehaviour` TRANSPARENT_OVERLAY / OPAQUE / OPAQUE_OVERLAY / INVISIBLE. Combine it with
  `ONDRAGCOMPLETE` and then call `SetPos`.
- Fallback: on header `ONCLICK`, store `Mouse.GetPosition()` minus the panel position. While held, `SetPos` on each
  `Logic` tick; stop on `ONRELEASE`.
- `Mouse.GetPosition() -> Vector2?` is relative to the game window. `Mouse.IsAvailable()` is false on mobile.
- Whether dragging moves the real component or only a ghost is UNDOCUMENTED. Prototype both approaches.
- Saving position: write x/y to PersistentDB on drag end, restore at startup, and clamp on `WindowSizeChanged`.

**Collapse:** not built in. Use a header `ui.Button` with `canToggle = true` that sets the body to `hidden` and calls
`SetSize` on the GroupBox. Persist the flag.

**Input fields**
```
function ui.InputField.new(parent : ui.ComponentCollection, categoryID : Int?, dynamicID : Int?) -> InputField
function ui.InputField:Setup(visibility : ui.TextContentVisibilityMode, filter : ui.InputFieldFilterMode, maxLength : Int)
```
- Props:
  - `content` (the real text; `text.content` is not it), `emptyText` (placeholder)
  - `contentQuantity` (numeric modes), `filterMode`, `maxLength`
  - Caret and selection colours, `containerSprite` (2 states: default, disabled)
- Filter values: NONE, ALPHANUMERIC, NUMERIC, QUANTITY, NUMBERS_AS_TEXT.
- `ONCONTENTCHANGED` reasons: NONE, ERROR, CONTENT_CHANGE, SUBMIT (Enter), SUBMIT_ON_ESCAPE, SUBMIT_ON_FOCUS_LOSS.
- **Masking caveat:** visibility SHOW_LAST or HIDDEN auto-flags the field as restricted, and a restricted field's
  `content` reads `""`. The plugin can't read a masked key field.
  - Use a VISIBLE field instead, or test whether `newContents` in `ONCONTENTCHANGED` still carries the text.
- Natural home for the server/key inputs: the Plugin Hub settings layer (`hasSettingsIcon` and `SettingsLayerReady`).
  It is rebuilt on each open, so recreate the widgets in the handler.

**Styling and fonts**
- `comp.stylesheetID = id.StyleSheet.<NAME>`. Recommended names:
  - DEFAULT, GROUPBOX_DEFAULT, INPUT_DEFAULT
  - BUTTON_DEFAULT, BUTTON_CORNERED_BOLD_NEUTRAL / POSITIVE / NEGATIVE
  - CHECKBOX_DEFAULT, DROPDOWN_DEFAULT, SLIDER_DEFAULT
- Custom sheets: `ui.StyleSheets[10000]` with `.parent` and integer-only `ui.StyleValue.*` entries. Re-assign after
  edits.
- Fonts: `id.Font.MUSEO_SANS_15PT_REGULAR` (also `config.Font.*`). Custom fonts are not possible because resources
  are PNG/OGG only.

## 7. PersistentDB

Sources: https://developer.runescape.com/rs/core/persistentdb.html, https://developer.runescape.com/rs/tutorial/5database.html

```
PersistentDB:Get(key) / GetBool / GetInt / GetFloat / GetString / GetStructuredData (key)
PersistentDB:Set(key, value) -> Bool ; SetBool / SetInt / SetFloat / SetString / SetStructuredData
PersistentDB:CheckExists(key) ; CheckExistsTyped(key, PersistentDBType)
function PersistentDB:IterateEntries(callback : function (key : String, value : Bool/Int/Float/String/Table) -> Bool) -> Int
PersistentDB:Delete(key) ; PersistentDB:Clear()
```
- Types: `PersistentDBType` is BOOL 0, INT 1, FLOAT 2, STRING 3, STRUCTURED_DATA 4.
  - Use the typed pairs, because untyped `Set` can confuse Int and Float.
  - STRUCTURED_DATA holds Lua tables. Unsupported field types (functions, usertypes) are silently dropped.
- **Scope:**
  - Isolated per plugin and stored in a local file.
  - **Per character, per account or per machine is UNDOCUMENTED.** It is most likely per plugin per install.
  - Namespace keys by `displayName` or the tracking id if per-character settings are needed, and check by switching
    characters on beta.
- **Durability:** the tutorial saves in `PluginShutdown()`. That covers logout and normal or forced closes, but not
  a client crash. Write settings and position as soon as they change.
- **Secrets:** encryption at rest is UNDOCUMENTED. Assume the API key sits in plain text on disk.

## 8. Console and beta-world testing

Sources: https://developer.runescape.com/rs/managing.html, https://developer.runescape.com/rs/tutorial/1helloworld.html,
https://developer.runescape.com/rs/cheats.html, https://developer.runescape.com/rs/tutorial/6cheats.html

- **Beta:** join via the launcher link in the docs. "Import save" in the lobby copies the live character (once per
  hour); beta progress never returns to live.
- **Dev folder:** `C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\<folder>`; the folder name is the plugin name.
  The manifest is optional for testing.
- **Console:** ALT+` opens it, `help` lists commands; no console on mobile. The in-game plugin manager UI is still
  in development.

| Command / alias | Purpose |
|---|---|
| `plugins_setpath <path>` | set the dev path |
| `plugins_refresh` / `prf`, `plugins_list` / `plist` | rescan, list |
| `plugins_enable` / `pon`, `plugins_disable` / `poff`, `plugins_setenabled <name> <bool>` | toggle |
| `plugins_reload` / `prl` | reload after editing |
| `plugins_permissions_request` / `ppr <name>` | prompt for the manifest permissions |
| `plugins_permissions_enable` / `ppe <name> <perm>`, `..._disable` / `ppd` | grant or revoke |

**Dev-only cheats** (logged server-side; abuse can mean a ban):
- `!resetsave` / `!unresetsave`, `!allinone`, `!godmode`, `!give <objConfigName>`, `!setvar <varp> <n>`, `!setvarc`.
- `!tele 0,50,52,12,53` (level,msX,msZ,lx,lz); CTRL+SHIFT+click also teleports. `pan VarPlayer` / `pan Obj` list names.
- `ExecuteConsoleCommand("!tele ...")` works from Lua in dev. Useful for scripted chunk-crossing tests; never ship it.

## 9. Guidelines and submission

Sources: https://developer.runescape.com/rs/submission/guidelines.html, https://developer.runescape.com/rs/submission/process.html,
https://developer.runescape.com/rs/submission/adequacy.html, https://developer.runescape.com/rs/submission/example.html,
https://developer.runescape.com/rs/requests/index.html

- **Allowed:** clarity, tracking, planning, logging/history, XP calculators, overlays, summaries of known info.
  **Forbidden:** automation, revealing hidden info, deception, exporting other players' data. Own location, stats
  and quests sent to our server fits "tracking/planning".
- **Permissions:** any requested permission triggers review. The listing must explain each one (or say "none");
  expect `httpAccess` to be scrutinised.
- **Third-party server:** OK if declared in the manifest and explained in the listing. No shorteners or redirectors,
  and no supported player-entered host (section 2).
- **Data protection** (mod.io description) has three cases:
  1. Local only.
  2. UK or adequate country: endpoints, security measures and a privacy notice (ICO generator suggested).
  3. Non-adequate country (e.g. USA): case 2 plus private contact details to Jagex via a form.
- **Adequacy (Sept 2026):** full for Andorra, Argentina, Faroe Islands, Gibraltar, Guernsey, Isle of Man, Israel,
  Jersey, New Zealand, South Korea, Switzerland, Uruguay; partial for Canada and Japan; the USA is excluded. A Canada
  host is case 2; check where a Tailscale Funnel relay terminates.
- **mod.io listing:** name 1-50 ASCII; summary 10-250 ASCII; 16:9 image at least 512x288; description up to 50k
  characters with sections Email, EULA statement, Permissions, Data Protection. Tags must include the permission tags.
- **Upload:** zip with `main.lua` and `plugin.json` at the top level (max 20GB). Tick Windows, Linux, Android, iOS and
  Source. Version is digits and dots.
- **Review:** manual code review in a closed environment under a code freeze; outcomes Pass, Minor, Major, Fail.
  **No turnaround time is stated.** New versions are re-reviewed while the old one stays live. The example page lists
  "Screenshot"/"File I/O" permissions that don't exist in the API.
- **AI policy:** code must be readable and commented; unvetted AI or obfuscated code is rejected. Claude Code or Codex
  is fine if the author reviews and understands it. Never give Jagex-private material to an AI; the public docs are fine.
- **Feature requests:** through the API council on Discord (https://dsc.gg/rspp).

## 10. Open questions / not documented

1. Does a localhost/127.0.0.1 `urls` entry work on beta, and does it pass review?
2. HTTP limits: timeout, body size, rate, redirects, default headers.
3. Are any JSON helpers hidden in globals? Which stdlib modules exist (`os`, `io`, `utf8`, `load`)?
4. How do you enumerate all quests: `pairs(config.Quest)`, a FromID scan, or a quest enum?
5. Is PersistentDB per character, per account or per machine? Is it encrypted?
6. Can a masked InputField's text be caught in `ONCONTENTCHANGED` before restriction blanks it?
7. Does `dragConfig` move the real component or a ghost? Which coordinate space do the ONDRAG args use?
8. Is the bank readable only while it's open? What are the backpack and equipment `config.Inv` names?
9. Is `SkillType` upper or mixed case (the docs disagree)?
10. Does `TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP` survive world hops and interface-mode changes, or must the UI be
    rebuilt on `GameStateChanged`?
11. Account membership isn't exposed; only `World.IsMembers()` exists.
12. Mobile: all platforms must be ticked, but `Mouse` is unavailable there. Dragging needs a touch fallback
    (ONSWIPE*) or a fixed position.
13. What is the review turnaround, and are single-developer HTTP backends accepted in practice?
