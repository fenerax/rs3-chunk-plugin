# Privacy notice: RS3 Chunk Picker plugin

> **Draft.** The parts in angle brackets are filled in once the hosted picker
> has its server and address. Until then the plugin only talks to a picker on
> your own PC.

This notice covers the RS3 Chunk Picker plugin for RuneScape 3 and the hosted
Chunk Picker server it reports to. It explains what the plugin sends, where it
goes, who can see it and how to have it removed.

The plugin and the hosted picker are run by fenerax, who decides how this data
is used (the "data controller"). Contact: **chunkpickerplugin@gmail.com**.

The plugin is a fan project. It is not made, endorsed or supported by Jagex.

## When anything is sent

Nothing leaves your PC until you do all of these:

1. allow the plugin's web access (`httpAccess`) in the game;
2. create a plugin key in your picker (**More → Game plugin**);
3. paste that key into the plugin's Settings and click **Save**.

Without a key the plugin only shows your chunk number and sends nothing.

You don't have to send anything: no law or contract requires it. Without a key,
or with a report type switched off, the plugin still runs; the picker just
won't see that part of your progress.

## What the plugin sends

Each report goes to one address only: **<picker address>**. The game client
refuses any other address. A report can contain:

| Data | Details | Can you turn it off? |
| --- | --- | --- |
| Position | Map square (x, z) and floor. This is the 64×64-tile chunk you are in, not your exact tile. | No. It goes with every report. |
| World type | Whether you are on a beta world. The world number is never sent. | No. |
| Levels | Level and XP for each skill. | Yes, in Settings. |
| Quests | Names of quests you have finished or started. | Yes. |
| Achievements | Completed achievements, including Achievement Diaries: id, name and category. | Yes. Only sent if the picker says it accepts them. |
| Items | Worn and backpack items and the coin pouch (slot, item id, count and name), tool belt tools, and your bank (item id and count). | Yes, one switch for all items. Only sent if the picker says it accepts each kind. |
| Diagnostics | Up to 80 short lines about what the plugin could read, for example "bank unreadable". They say which settings exist, never their values. | No. |

It also sends your plugin key in a request header, so the picker knows which of
its players the report belongs to.

The plugin never sends your account name, character name, email address or
world number. It does not read chat or other players. The plugin also asks the
picker for your chunk status, task list and any waiting roll, which come from
your picker's save. If your picker partner also uses the plugin, it shows the
chunk their plugin last reported to the same picker. The plugin never reads
other players from the game.

## What stays on your PC

The plugin keeps these in the game client's plugin storage:

- your settings, window positions and shading colours;
- the key for each server;
- the name of the character each key was saved on, so a key saved on one
  character is never used for another (this name is never sent);
- a short list of up to 32 recent changes to what you wear, so a change made
  while the picker was offline still reaches it. Entries are removed once the
  picker confirms it received them.

The game does not say whether this storage is encrypted. **Forget key** in
Settings deletes the selected server's key.

## Why it is used, and on what basis

The data is used for one purpose: running your chunk-locked game in the picker.
That means showing your chunk and its status in game, and suggesting progress
(levels, quests, achievements, item goals) for you to review.

The legal basis is your **consent** (UK GDPR Article 6(1)(a)). You give it by
saving a key and leaving each report type switched on. You can withdraw it at
any time, as easily as you gave it: switch a report type off, click **Forget
key**, or revoke the key in the picker. Withdrawing stops new reports; it
doesn't undo what was sent before, but you can ask for that to be deleted.

## What the picker does with it

The picker uses reports to show your chunk in game and to suggest progress for
you to review. It never unlocks a chunk or ticks a task without you (or the
picker's administrator) approving it, except two kinds of live-world evidence
you can undo: unique achievement matches, and gear goals for items you own.

| Data | Kept where | How long |
| --- | --- | --- |
| Position | Server memory only | 10 minutes, or until the server restarts. Never saved. |
| Diagnostics | Server memory only | Until the next report or a restart. |
| Levels and quests | Server memory, as a suggestion | Until you apply or dismiss it, or the server restarts. Applied progress becomes part of your picker save. |
| Achievements | Your picker save, plus a list of ids already handled | For as long as your picker exists, or until you ask for deletion. |
| Items, coins and bank (live worlds) | A file next to your picker save: items seen, when, the bank's coin total and when it was last seen | For as long as your picker exists, or until you ask for deletion. |
| Items (beta worlds) | Server memory only | Until the server restarts. |
| Plugin key | Only a SHA-256 hash of it | Until you revoke the key. |
| Connection logs | <hosting details> | <log retention> |

Your picker save is backed up with the rest of the server's data. Backups are
kept for <backup retention>.

## Who can see it

- You.
- People you share your picker with. Partners see which chunk you are in while
  your position is fresh (10 minutes), and anyone with access to the picker
  sees the progress you applied.
- The picker's administrator (fenerax), who runs the server.

The server runs on **<hosting provider>**, which stores it for us as a data
processor and may not use it for anything else. Nobody else receives it. The
data is not sold, shared with advertisers or used for anything other than
running your picker.

No decision with legal or similarly significant effects is made about you by
automated means. The automatic ticks above only change your picker's task
list, and you can undo them.

## Where it is stored and how it is protected

- The server is a virtual private server in **Canada**, run by
  **<hosting provider>**. The data is not sent anywhere else. If you are in the
  UK or EU, sending it to Canada is a transfer to a country that the UK and
  EU recognise as giving adequate protection (an "adequacy decision").
- Reports travel over HTTPS.
- Each player has their own plugin key. The key only works for the plugin's
  three routes, can't sign in to the picker, and you can revoke it at any time
  in **More → Game plugin**. The server stores only a hash of it.
- Reports are size- and rate-limited, and anything that doesn't match the
  expected format is rejected.
- Only the administrator has access to the server.

## Your choices and rights

- Turn off levels, quests, achievements or items in the plugin's Settings.
- Stop all sending: click **Forget key**, revoke the key in the picker, or
  remove the plugin's web access.

You have the right to:

- get a copy of your data (access), including in a reusable format
  (portability);
- have it corrected (rectification);
- have it deleted (erasure);
- ask us to stop using it while a concern is checked (restriction);
- withdraw your consent at any time, as described above.

To use any of these, write to **chunkpickerplugin@gmail.com**. You will get a reply within
one month, and it costs nothing.

If you are unhappy with how your data is handled, you can complain to the UK
Information Commissioner's Office: https://ico.org.uk/make-a-complaint/ or
0303 123 1113. If you live in the EU, you can complain to your local data
protection authority instead.

## Changes

Changes to this notice are recorded in this repository's history. The plugin's
listing links to the current version.

Last updated: 27 October 2026.
