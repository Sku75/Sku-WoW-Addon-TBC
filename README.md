# Sku — WoW Screen Reader Addon (TBC)

**Sku** makes World of Warcraft playable for blind and visually impaired
players, providing a complete screen-reader interface (NVDA / JAWS). This
build targets the Burning Crusade Classic Anniversary client
(Interface `20506, 11508` — TBC 2.5.6 + Era 1.15.8).

This repository is the **single home** for Sku TBC:

- **Source code** — the full addon source lives under [`Sku/`](Sku/): all Lua,
  XML and TOC code, data tables (creatures, items, spells, quests, routes,
  wiki), locales and UI definitions.
- **Ready-to-play downloads** — the packaged, playable ZIPs are published on
  the [Releases page](../../releases).
- **Download / install page** — served via GitHub Pages from [`docs/`](docs/)
  at <https://sku75.github.io/Sku-WoW-Addon-TBC/>.

> Previously the source lived in a separate repository
> (`Sku-WoW-Addon-TBC-Source`). It has been consolidated here; that repo is now
> archived and read-only.

## Building / running from source

The tracked source under `Sku/` deliberately **excludes bulky binary assets**
(voice audio `*.mp3`/`*.ogg`, fonts, images, and the large generated game-data
tables). These ship inside the release ZIPs. So:

- To **play**, download the latest ZIP from [Releases](../../releases) and
  follow the install guide in [`docs/`](docs/).
- To **develop**, clone this repo and overlay the asset files from a release
  ZIP (or your existing install) into `Sku/`. See `Sku/.gitignore` for the
  exact excluded patterns.

## Companion addons

Sku relies on separately-distributed companion packages (voice audio packs,
navigation data, beacon soundsets, health assets). These are not tracked here;
grab them from the download page.

## Contributing

Fork, branch, and open a pull request against this repository. Patches are
code-only by design (assets are not tracked).

## License

See [`Sku/LICENSE.txt`](Sku/LICENSE.txt).
