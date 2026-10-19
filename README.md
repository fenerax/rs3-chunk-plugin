# RS3 chunk picker plugin

Experiments with the official RuneScape plugin API
(https://developer.runescape.com/rs/) for syncing the chunk picker with the game.

## chunk-picker-test

This plugin is read-only. It shows the chunk you are standing in and sends nothing anywhere. Unreviewed plugins only run on the RuneScape beta world, not on live worlds.

1. Join the beta world. Use the beta config link in the official "Accessing the API" tutorial, and import your live character from the lobby.
2. Open the console with Alt + the key under Esc.
3. Run `plugins_setpath C:\Users\User\Projects\rs3-chunk-plugin\plugins`
4. Run `prf`, then `plist`. The list should show `chunk-picker-test`.
5. Run `pon chunk-picker-test`.

A box shows `Chunk 12850 (50, 50)  floor 0` in Lumbridge, and it updates as you walk. Each change is also written to the console.

To reload after an edit, run `prl chunk-picker-test`. To turn it off, run `poff chunk-picker-test`.
