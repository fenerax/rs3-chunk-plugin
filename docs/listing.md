# mod.io listing text (draft)

The description to paste into the Plugin Hub listing, following Jagex's example
description page. Fill in the angle-bracket parts once the hosted picker and the
plugin mailbox exist. The EULA paragraph is copied word for word from Jagex's
submission process page; don't edit it.

Summary (10 to 250 ASCII characters):

> Connects RuneScape to Chunk Picker for RS3: shows your chunk and its status,
> shades locked chunks, lists your chunk tasks and reports progress to your picker.

---

## Chunk Picker

Play a chunk-locked account with [Chunk Picker for RS3](https://github.com/fenerax/chunk-picker-rs3).
The plugin shows which chunk you are in and whether your picker has it unlocked,
shades locked chunks on the ground, and lists your chunk tasks in game. It sends
your levels, quests, completed achievements and items to your picker, which
suggests progress for you to review. The plugin never unlocks a chunk or ticks a
task by itself, and it automates no gameplay.

Requires [PrettyUI](https://prettyui.j3.gg) and a picker account with a plugin key.

How this differs from Chunk Borders and Chunk Tasks: this plugin works with
Chunk Picker for RS3, a separate website that rolls your chunks and tracks your
tasks. Your unlocks, rolls and partner come from that picker.

## Email

The contact email address for this plugin is <contact email>.

## Feedback and collaboration

Bug reports and ideas are welcome as GitHub issues at
https://github.com/fenerax/rs3-chunk-plugin/issues. If you'd like to contribute
code, please open an issue first.

## EULA

This Plugin uses software licensed by Jagex to the developer under the terms of
the Jagex End User Licence Agreement (EULA) found at
https://legal.jagex.com/docs/terms/eula. The development and any use of the
Plugin is at all times subject to the Jagex EULA.

## Permissions

**HttpAccess.** This plugin requests the HttpAccess permission for
<picker address>. It sends your current chunk (map square and floor), and, if
you turn them on, your skill levels and XP, quest names, completed achievements
and items (worn, backpack, coin pouch, tool belt and bank) to your Chunk Picker,
so the picker can show your chunk and suggest progress. It reads back your
chunk's status, your task list, your picker partner's chunk and any waiting
roll. Nothing is sent until you paste a plugin key from your picker into
Settings.

## Data protection

This plugin sends data to a server in Canada, which has a UK adequacy decision.
The privacy notice is at
https://github.com/fenerax/rs3-chunk-plugin/blob/main/PRIVACY.md.

The data is protected by:

- HTTPS for every request;
- a separate plugin key for each player, which only works for the plugin's
  routes and can be revoked in the picker at any time (the server stores only a
  hash of it);
- size and rate limits, and rejection of any report that doesn't match the
  expected format;
- server access limited to the plugin's developer.

Your data can be seen by you, the people you share your picker with, and the
developer, who runs the server. The plugin never sends your account name,
character name or world number, and it does not read chat or other players.
Your partner's chunk is shown only when your partner uses the plugin with the
same picker; it is what their own plugin reported, not something read from the
game.

Sending is based on your consent: nothing goes out until you save a key, each
report type can be switched off, and you can withdraw at any time with Forget
key or by revoking the key in the picker.

To ask for a copy of your data, a correction or deletion, email the address
above.

Your position and diagnostics are not stored between sessions; the server keeps
them in memory only. Progress you apply becomes part of your picker save, and
live-world item evidence is kept beside it. The plugin stores its settings,
your keys, the character each key belongs to and a short list of recent
equipment changes on your PC.
