# BuildForge

A build manager for Synastria (WoW 3.3.5a). It saves, shares and applies a whole build: Perks with their
options and chosen abilities, Talents for every class, Glyphs, Recommended Gear, Hunter pet aspects, the spec
name and notes.

## Commands

| Command | Does |
|---|---|
| `/bforge list` | Lists saved builds; builds for other classes are marked |
| `/bforge save <name>` | Saves your active spec as a build |
| `/bforge apply <name>` | Lists what would change in chat, then asks before applying |
| `/bforge export <name>` | Shows the build as a one-line string to copy |
| `/bforge import` | Opens a box to paste a BuildForge or SynastriaPerkManager string |
| `/bforge gear <name>` | Shows each slot: worn, in bags or missing, and attunement |
| `/bforge equip <name>` | Equips the build's gear you're carrying |
| `/bforge note <name> <text>` | Sets the build's notes |
| `/bforge delete <name>` | Deletes a build |

Perk activations need the Perk window open at an innkeeper. Perk options and chosen abilities apply anywhere.
Glyphs are listed for you to socket, since they're used up.

## Development

The addon lives in `BuildForge/`; the game's `AddOns\BuildForge` is a junction to it.

Run the offline tests (needs Python with `lupa`, and the client data next to this one, or
`DATA_PATH` pointing at it):

```bash
py -I -X utf8 test/run.py
```

`docs/DESIGN.md` covers the client APIs, the export format and what's still untested.
