# Privacy notice: RS3 Chunk Picker plugin

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

Each report goes to one address only: **https://chunkpicker.ca**. The game
client refuses any other address. A report can contain:

| Data | Details | Can you turn it off? |
| --- | --- | --- |
| Position | Map square (x, z) and floor. This is the 64×64-tile chunk you are in, not your exact tile. | No. It goes with every report. |
| World type | Whether you ticked "I'm playing on the beta world" in Settings. The world number is never sent. | No. |
| Levels | Level and XP for each skill. | Yes, in Settings. |
| Quests | Names of quests you have finished or started. | Yes. |
| Achievements | Completed achievements, including Achievement Diaries: id, name and category. | Yes. Only sent if the picker says it accepts them. |
| Items | Worn and backpack items and the coin pouch (slot, item id, count and name), tool belt tools, and your bank (item id and count). | Yes, one switch for all items. Only sent if the picker says it accepts each kind. |
| Diagnostics | Up to 80 short lines about what the plugin could read, for example "bank unreadable". They say which settings exist, never their values. | No. |

It also sends your plugin key in a request header, so the picker knows which of
its players the report belongs to. Like any web request, each one also shows
the server your IP address (see connection logs below).

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
- equipment journals, kept separately for each character and server/key binding,
  so something briefly worn while the picker was offline can still reach it.
  Up to eight journals of 32 events each are retained, within 64 KiB in total.
  Pending entries are removed only after that destination confirms delivery.
  A full store keeps its pending journals; a new destination's journal then stays
  in memory only and can be lost when the plugin closes. Each journal also stops
  adding events at 32 until delivery is acknowledged.

This storage persists on disk between sessions and may be copied by your PC's
backup software. The game does not say whether it is encrypted. **Forget key**
in Settings deletes the selected server's key; it does not delete pending
journals or copies already in your PC's backups. Turning off item reports also
leaves pending journals in storage. The plugin cannot remove your PC's backups.

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
| Current items and bank from beta or unknown worlds | Server memory only | Until the server restarts. |
| Equipment-journal evidence, including beta and unknown worlds | Persistent picker storage, including delivery records and saved review decisions | For as long as your picker exists, or until you ask for deletion. The plugin's current journal format does not record the observation world, so the picker retains it as unknown-world evidence. |
| Plugin key | Only a SHA-256 hash of it | Until you revoke the key. |
| Connection logs | The web server's log: IP address, time, request method, status code and response time. No page addresses, keys or other request details. | 7 days. |

Your picker save and persistent equipment-journal evidence are included in
server backups, including evidence from beta and unknown worlds. Positions,
diagnostics and current beta/unknown-world item readings remain memory-only.

The server keeps 30 daily backups, with encrypted copies on the administrator's
PC in Canada. The hosting provider also keeps a daily whole-server backup.
There is also an encrypted cloud backup stored in the United States. It is
encrypted before leaving the server; the cloud provider cannot read its contents.
The cloud retention policy keeps up to 30 daily, 8 weekly and 12 monthly restore
points. Restore points are kept for up to about a year under the retention
policy, and older ones are removed when retention is applied.

Deleting data from the running picker does not immediately remove it from
existing backups. Those copies remain until the relevant backups expire or are
removed. Cloud retention is applied by the operator, so deletion from older
restore points is not automatic and may take longer than a year. If a backup
is restored, deletion requests must also be applied to the restored data.

## Who can see it

- You.
- People you share your picker with. Partners see which chunk you are in while
  your position is fresh (10 minutes), and anyone with access to the picker
  sees the progress you applied.
- The picker's administrator (fenerax), who runs the server.

The server runs on **OVHcloud**, which stores it for us as a data processor
and may not use it for anything else. The cloud backup provider stores
encrypted backups and cannot read their contents. The
data is not sold, shared with advertisers or used for anything other than
running and recovering your picker.

No decision with legal or similarly significant effects is made about you by
automated means. The automatic ticks above only change your picker's task
list, and you can undo them.

## Where it is stored and how it is protected

- The running server is a virtual private server in OVHcloud's Beauharnois,
  Quebec data centre. It and the administrator's PC backup are in **Canada**.
  An encrypted cloud backup is stored in the **United States**, as described
  above. If you are in the UK or EU, sending reports to Canada is a transfer
  to a country that the UK and EU recognise as giving adequate protection
  (an "adequacy decision").
- Reports travel over HTTPS.
- Each player has their own plugin key. The key only works for the plugin's
  three routes, can't sign in to the picker, and you can revoke it at any time
  in **More → Game plugin**. The server stores only a hash of it.
- Changing your declared RuneScape name in the picker revokes existing keys
  when the normalized name changes. Create a new key and pair the plugin again,
  even if you undo the name change. Case, outer whitespace and equivalent
  spaces/underscores do not revoke keys. Previously saved observations stay
  with the same picker character.
- Reports are size- and rate-limited, and anything that doesn't match the
  expected format is rejected.
- Only the administrator can log in to the server, with key-based login only.
  The picker's admin pages are reachable only over a private network, and the
  connection log is readable only by the administrator.

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

Last updated: 19 November 2026.
