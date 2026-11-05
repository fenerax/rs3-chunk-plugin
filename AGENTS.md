# RS3 Chunk Picker plugin

Read `README.md`, `PRIVACY.md` and the relevant `dev/README.md` instructions before changing the plugin.

## Public publication

- Treat this repository and its history as public; verify the remote before publishing. Keep private backup bundles, credentials and personal fixtures out of it.
- Use the repository's configured GitHub noreply address for author and committer. Omit AI coauthor email trailers; write "Written by Codex." or similar instead.
- The secret scan in `scripts/secret-scan/` runs as the pre-push hook (enable once per clone with `git config core.hooksPath .githooks`). It needs the maintainer's private-value corpus in `.local/export-gate/`, which is never committed. CI runs the same scan without the corpus. Plain text searches can miss Unicode identifiers on Windows.
- Public hosts and reviewed lines live in `scripts/secret-scan/reviewed.json`, each with a reason. A reviewed line is matched by its hash, so editing that line makes the scan flag it again: re-review it and update the hash. The scanner files are copied from the picker core repository; copy updates from there instead of editing them here.
- Merge locally with the approved noreply identity before an ordinary push; the hosted merge path can use a personal account email. Leave existing public history intact unless a rewrite is explicitly approved.
- Keep fixture identities synthetic and host exceptions limited to the reviewed public endpoints.
