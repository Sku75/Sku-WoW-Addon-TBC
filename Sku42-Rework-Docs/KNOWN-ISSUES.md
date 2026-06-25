# Sku 42 — Known Issues

Running log of known issues, regressions, and gotchas for the Sku 42 rework.
Keep entries short and actionable. Move resolved items to a "Resolved" section
(with the commit/date that fixed them) rather than deleting, so we keep the
history.

## Format (per entry)

- **Title** — one line.
  - Symptom: what is observed (what is spoken / what breaks).
  - Repro: deterministic steps if known.
  - Suspected cause / area: file or workstream.
  - Status: open / investigating / workaround / blocked.

## Setup / environment gotchas (carried from the rework setup)

- **v42 worktree is missing the gitignored runtime assets.** A fresh worktree
  contains only version-controlled source. The bulky assets that the addon needs
  to actually RUN are gitignored and therefore absent here: `*.mp3/*.ogg/*.wav`,
  fonts/images (`*.ttf/*.otf/*.png/*.jpg/*.tga/*.blp`), `routedata_global_wotlk.lua`,
  and everything under `SkuDB/assets/`. Before symlinking this worktree into WoW,
  these must be copied (or junctioned) in from the v41 tree's `Sku/` folder.
  - Status: open — pending the asset-copy step.
- **Shared SavedVariables with v41.** Same addon name + same account = same
  `Sku.lua` (`SkuOptionsDB`). v42's settings-schema rework (W1) can rewrite the
  saved settings v41 expects. Test v42 against the WTF backup / a copied account,
  or accept that v42 testing migrates the live settings. Never run both clients
  at once.
- **Symlink swap to test v42.** WoW loads the addon via the `AddOns\Sku` symlink.
  It currently points at the v41 tree (`...\Sku-TBC\Sku`). To test v42, repoint
  it (admin, `mklink /D`) at `...\Sku-TBC-42\Sku`, and point it back to test v41.

## Open issues

- (none logged yet)

## Resolved

- (none yet)
