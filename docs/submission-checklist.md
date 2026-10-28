# Plugin Hub submission checklist

What still has to happen before this plugin can be submitted to the RuneScape
Plugin Hub on mod.io. Tick items off as they land.

Sources, read 2026-10-26: Jagex's
[Plugins FAQ](https://secure.runescape.com/m=news/runescape-plugins---faq) (2026-10-26),
the [submission process](https://developer.runescape.com/rs/submission/process.html),
[guidelines](https://developer.runescape.com/rs/submission/guidelines.html) and
[example description](https://developer.runescape.com/rs/submission/example.html) pages
(updated 2026-10-23), and staff posts in the RuneScape Plugin Discord up to 2026-10-26.
`api-notes.md` section 9 holds the older rules; where the two differ, this file is newer.

## How review works now

- New plugins ship in batches every two weeks. Jagex picks a batch at the start
  of week 1 and checks the code and listing. Developers fix required feedback in week 2, and the batch
  releases on a Thursday. The next batch is 2026-11-05, so the earliest we could
  join is the one after that.
- Batch picks favour older submissions, popular plugins, and code that is small,
  well commented and easy to read. Jagex says fully AI-written plugins take
  longer because they tend to be bloated. Over 200 plugins are waiting.
- Plugins that duplicate existing ones are allowed but come after new
  functionality (Discord, 2026-10-26). Chunk Borders and Chunk Tasks by
  maplescaper overlap with part of ours.
- Once moderation starts, the mod.io listing and files are frozen until the report
  comes back (Pass, Minor, Major or Fail). Updates to an approved plugin are
  reviewed while the old version stays live.

## 1. Decisions

- [x] **Which servers the plugin can reach.** Decided 2026-10-27: (b), the hosted
      picker on the Canadian VPS, once it exists. Until then the manifest stays
      on loopback for beta testing. `urls` in `plugin.json` is fixed at
      submission and shown to reviewers. Today it lists only loopback addresses,
      which reach a picker on the player's own PC and nothing else. A partner on
      another PC would need the picker's public address in the manifest, which
      makes that address public. Options:
      (a) loopback only: works for anyone who runs their own picker;
      (b) add the hosted picker's address;
      (c) wait for a proper hosted picker with accounts.
      Loopback calls work on beta, but nobody has seen one pass review yet.
      Character Relay, a skills-to-local-listener plugin, is waiting for Jagex's
      answer (Discord, 2026-10-24).
      Done 2026-10-28: `production` is `https://chunkpicker.ca` (OVHcloud, Beauharnois).
- [x] **Data protection case.** Decided 2026-10-27: case 2. Case 1 means data never
      leaves the player's own PC, and reports go to the hosted picker. A host in
      Canada is case 2: list the endpoints and security measures and
      link a privacy notice. If traffic passes through a relay in the USA, it may be case 3,
      which also means sending Jagex private contact details through their form.
- [x] **Public contact email.** Decided 2026-10-27: a dedicated plugin mailbox
      chunkpickerplugin@gmail.com (created 2026-10-27), forwarded from the picker's domain later. Required unless case 1. Jagex recommends an address
      separate from the mod.io and RuneScape logins. mod.io can't sign in with
      addresses that contain `+`.
- [x] **Feedback route and collaboration stance.** Decided 2026-10-27: GitHub issues
      on this repo; open an issue before sending code.
- [x] **Keep `chatAccess`?** Dropped 2026-10-27, along with the chatbox notices.
      The banners show the same messages. Bring it back only if players ask.
- [x] **What goes in version 1.** Decided 2026-10-27: everything, including the
      bank, tool belt and coin pouch reports.
- [ ] **Name.** Check that "Chunk Picker" is free on mod.io, and say in the
      description how it differs from Chunk Borders and Chunk Tasks. Those two are
      maplescaper's Plugin Hub plugins with no licence we can see, so per the AI rules
      only a human reads their listings. maplescaper's older Bolt plugin
      (codeberg.org/maplescaper/bolt-chunkman) is GPL-3.0: it greys the world and map
      using unlocks it reads from the original chunk picker's public data, keeps
      task ticks locally, and sends nothing back. Ours reports progress to the picker and gets its state,
      partner chunk and rolls back. Don't copy its code (GPL).

## 2. Code

- [x] Remove the beta-only pieces. `probe.lua` is gone (2026-10-27). The `scratch`
      and `home` loopback URLs stay in the repo for beta testing;
      `tools/build-release.mjs` leaves them out of a Hub zip, which lists only
      `production`, and the plugin then connects there by default (2026-10-28).
- [ ] Readability pass. Split dense one-line statements, comment `json.lua`,
      `location.lua`, `progress.lua`, `diagnostics.lua` and `sync.lua`, and cut
      anything unused. Reviewers reject code that is "unnecessarily difficult to
      follow" or "unvetted AI generation".
- [x] `settings.lua` wrapped PrettyUI's internal `Resize._Refresh` for wider grips.
      Removed 2026-10-27; windows use PrettyUI's own resize strips. Wider grips would
      need J3sven to support them. `window.root` is still read for position and size.
- [ ] PrettyUI's repo has no licence, and the guidelines forbid giving other
      plugins' code or documentation to an AI model without the author's
      permission. Ask J3sven for that permission, or stop reading PrettyUI's
      source with AI tools.
- [x] Treat a pasted look code (`CP1.…`) as untrusted (2026-10-27). Check its length,
      character set and value ranges, and test malformed codes. A malicious
      Tilemarkers import string crashed clients (hotfix 2026-10-24).
- [x] Show when the bank was last seen, because the game only updates it while
      it is open. The picker already does this. Staff allow cached observations
      of state the game showed you.
- [x] Check the Tasks window against the reported PrettyUI bugs: resize leak with
      many components, leftover edge markers when hiding mid-drag, wheel scrolling.
      No problems in the 2026-10-28 beta test.
- [x] Set `version` to `1.0.0` (2026-10-28; build-release also checks the version
      `main.lua` shows). Every later upload needs a new version that matches the
      manifest, plus a changelog against the last approved version.
- [ ] Update the README "Status" section once approved. Hub install steps added
      2026-10-28, marked "not available yet".

## 3. Final test on beta

- [x] Build the exact zip: `main.lua` and `plugin.json` at the top level, named
      `chunk-picker-100.zip`, with no tests or `chunk-picker-test`. Built 2026-10-28
      from 42b8f4e: 19 files, SHA-256 30F491BF…48334598, `urls` production only.
- [x] Clean install of that zip on the beta world with PrettyUI installed from the
      Hub. Run every feature in the README: panel, shading, warning, Tasks
      window, reports, key per server, character binding. Passed 2026-10-28,
      unzipped as `chunk-picker-hub` against https://chunkpicker.ca. Chunk ids
      matched at Lumbridge, Nardah, Anachronia, Wendlewick, Waiko and Lost Grove;
      nothing posted in chat.
- [x] Confirm the permission grant with `Plugin.HasPermission` and a real request.
      `ppe` reports success even for names that don't exist. On beta the game never
      prompted, and its permission toggle said the permission "could not be
      changed"; `ppe chunk-picker-hub httpAccess` granted it and reports went
      through. The Hub install prompt can only be checked after approval.

## 4. mod.io listing

- [x] Create the listing early, hidden, to reserve the name. Done 2026-10-28:
      https://mod.io/g/runescape/m/chunk-picker, Private, ID 6485729. The cover
      image is a temporary placeholder.
- [ ] Summary of 10 to 250 ASCII characters, a 16:9 logo of at least 512×288, and screenshots.
- [ ] Homepage link to this repo.
- [x] Description sections, following the example page. Written in
      [listing.md](listing.md) and saved on the listing (2026-10-28):
  - [x] Contact email.
  - [x] Feedback and collaboration.
  - [x] The EULA statement, copied word for word from the process page.
  - [x] Permissions: what `httpAccess` sends, to which address and why.
  - [x] Data protection: what is sent (position, levels, XP, quests, achievements,
        item reports), where to, security (HTTPS where used, a bearer key per
        player, revocable in the picker), who can read it, and a link to the
        privacy notice.
  - [x] Note that the partner chunk and roll come from the player's own picker, not
        from the game. "Obtaining any information about other players" gets
        extra review.
- [x] Privacy notice page: [PRIVACY.md](../PRIVACY.md), checked against the ICO's
      list of required privacy information; server details filled in 2026-10-28.
- [x] Tags, including the tag for each permission. Saved 2026-10-28: Interface,
      Utility, Navigation, Stats and Analytics, Planning and Calculators, Content
      helpers, and "httpAccess (optional)" to match `optionalPermissions`.
- [x] Add PrettyUI (6398181) as a mod.io dependency; it must match
      `requiredDependencies`. Saved 2026-10-28.
- [ ] Platforms: tick what the upload form asks for. Staff said Windows, Mac and Linux
      (2026-10-05 and 10-08); the process page still shows an older table.

## 5. Submit and after

- [ ] Optionally register the plugin through the Discord plugin-directory process.
- [ ] Upload, submit, and leave mod.io untouched once moderation starts.
- [ ] Work through the report; resubmit with a new version number.
