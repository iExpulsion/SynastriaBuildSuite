# BuildForge

A build manager for Synastria (WoW 3.3.5a). It saves, shares and applies a whole build: Perks with their
options and chosen abilities, Talents for every class, Glyphs, Recommended Gear, Hunter pet aspects, the spec
name and notes.

## The Window

`/bforge`, or the BuildForge button above the Perk window or the talent frame, opens the build window. It's
laid out like the Quest Log and opens and closes like other Blizzard panels (Esc closes it):

- **Build list (left):** builds grouped under class headers; groups for classes you don't have start
  collapsed. The build last applied to this spec says Applied. New saves your character as a new build,
  Import pastes one in, Export gives the share string, Delete asks first.
- **Details (right):** click the build's name to rename it and set its spec name (press Enter to keep).
  Apply lists the changes in chat and asks first. The top corner says whether the Perk window is open at an
  innkeeper, which perk activations need.
- **Tabs (under the frame):** Perks, Talents, Glyphs, Gear and Notes.
- **Perks, Talents, Glyphs:** what the build has, compared with your character right now (Active, To Activate,
  To Deactivate, points still to spend, glyphs to socket). Each tab can take your current setup for that part.
- **Gear:** each slot has a Best item to aim for and Alts (Alt 1, Alt 2, ...) as stand-ins in order of
  preference, each shown as worn, in bags or missing, plus attunement. Drop an item on a slot to add an Alt,
  right-click to remove, Ctrl-click to make it Best. Equip from Bags puts on the highest-ranked item you're
  carrying in each slot.
- **Notes:** free text saved with the build and included in exports.

## Commands

| Command | Does |
|---|---|
| `/bforge` | Opens or closes the window |
| `/bforge help` | Lists the commands |
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
