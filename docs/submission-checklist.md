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

- [ ] **Which servers the plugin can reach.** `urls` in `plugin.json` is fixed at
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
- [ ] **Data protection case.** Loopback-only may count as case 1 (data never
      leaves the PC) or case 2; ask in `guidelines-questions` on the Discord.
      A host in Canada is case 2: list the endpoints and security measures and
      link a privacy notice. If traffic passes through a relay in the USA, it may be case 3,
      which also means sending Jagex private contact details through their form.
- [ ] **Public contact email.** Required unless case 1. Jagex recommends an address
      separate from the mod.io and RuneScape logins. mod.io can't sign in with
      addresses that contain `+`.
- [ ] **Feedback route and collaboration stance.** For example GitHub issues on
      this repo, plus a sentence on whether contributions are welcome.
- [ ] **Keep `chatAccess`?** Every permission adds review. It only copies the
      locked-chunk and roll notices to the chatbox, and the grant is ignored on beta.
- [ ] **What goes in version 1.** Smaller plugins review faster. Consider leaving
      the bank, tool belt and coin pouch reports for a later update.
- [ ] **Name.** Check that "Chunk Picker" is free on mod.io, and say in the
      description how it differs from Chunk Borders and Chunk Tasks.

## 2. Code

- [ ] Remove the beta-only pieces: `probe.lua`, its diagnostics lines, and the
      `scratch` URL in `plugin.json`.
- [ ] Readability pass. Split dense one-line statements, comment `json.lua`,
      `location.lua`, `progress.lua`, `diagnostics.lua` and `sync.lua`, and cut
      anything unused. Reviewers reject code that is "unnecessarily difficult to
      follow" or "unvetted AI generation".
- [ ] `settings.lua` wraps PrettyUI's internal `Resize._Refresh`. Replace it with
      PrettyUI's public API, or ask J3sven to support wider grips. Patching another
      plugin's internals is fragile and hard to justify in review.
- [ ] PrettyUI's repo has no licence, and the guidelines forbid giving other
      plugins' code or documentation to an AI model without the author's
      permission. Ask J3sven for that permission, or stop reading PrettyUI's
      source with AI tools.
- [ ] Treat a pasted look code (`CP1.…`) as untrusted. Check its length,
      character set and value ranges, and test malformed codes. A malicious
      Tilemarkers import string crashed clients (hotfix 2026-10-24).
- [x] Show when the bank was last seen, because the game only updates it while
      it is open. The picker already does this. Staff allow cached observations
      of state the game showed you.
- [ ] Check the Tasks window against the reported PrettyUI bugs: resize leak with
      many components, leftover edge markers when hiding mid-drag, wheel scrolling.
- [ ] Set `version` to `1.0.0`. Every upload needs a new version that matches
      the manifest, plus a changelog against the last approved version.
- [ ] Update the README "Status" section and the install steps for Hub users.

## 3. Final test on beta

- [ ] Build the exact zip: `main.lua` and `plugin.json` at the top level, named
      `chunk-picker-100.zip`, with no tests or `chunk-picker-test`.
- [ ] Clean install of that zip on the beta world with PrettyUI installed from the
      Hub. Run every feature in the README: panel, shading, warning, Tasks
      window, reports, key per server, character binding.
- [ ] Confirm the permission grant with `Plugin.HasPermission` and a real request.
      `ppe` reports success even for names that don't exist.

## 4. mod.io listing

- [ ] Create the listing early, hidden, to reserve the name.
- [ ] Summary of 10 to 250 ASCII characters, a 16:9 logo of at least 512×288, and screenshots.
- [ ] Homepage link to this repo.
- [ ] Description sections, following the example page:
  - [ ] Contact email.
  - [ ] Feedback and collaboration.
  - [ ] The EULA statement, copied word for word from the process page.
  - [ ] Permissions: what `httpAccess` sends, to which address and why; `chatAccess`
        if kept; and how they work together.
  - [ ] Data protection: what is sent (position, levels, XP, quests, achievements,
        item reports), where to, security (HTTPS where used, a bearer key per
        player, revocable in the picker), who can read it, and a link to the
        privacy notice.
  - [ ] Note that the partner chunk and roll come from the player's own picker, not
        from the game. "Obtaining any information about other players" gets
        extra review.
- [ ] Privacy notice page (Jagex points to the ICO generator), for example
      `PRIVACY.md` in this repo.
- [ ] Tags, including the tag for each permission.
- [ ] Add PrettyUI (6398181) as a mod.io dependency; it must match
      `requiredDependencies`.
- [ ] Platforms: tick what the upload form asks for. Staff said Windows, Mac and Linux
      (2026-10-05 and 10-08); the process page still shows an older table.

## 5. Submit and after

- [ ] Optionally register the plugin through the Discord plugin-directory process.
- [ ] Upload, submit, and leave mod.io untouched once moderation starts.
- [ ] Work through the report; resubmit with a new version number.
