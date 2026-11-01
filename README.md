# BuildForge

A build manager for Synastria (WoW 3.3.5a). It saves, shares and applies a whole build: Perks with their
options and chosen abilities, Talents for every class, Glyphs, Recommended Gear, Hunter pet aspects, the spec
name and notes.

## The Window

`/bforge`, or the BuildForge button above the Perk window or the talent frame, opens the build window:

- **Build list:** builds for your classes, with the one last applied to this spec marked. Tick Show Other
  Classes to see the rest. Save Current saves your character as a new build; Import pastes one in.
- **Header:** rename the build or set its spec name (type, then Enter). Apply lists the changes in chat and asks
  first; Export gives the share string; Delete asks first.
- **Perks, Talents, Glyphs:** what the build has, compared with your character right now (Active, To Activate,
  To Deactivate, points still to spend, glyphs to socket). Each tab can take your current setup for that part.
- **Gear:** the recommended item per slot, with alternatives, shown as worn, in bags or missing, plus
  attunement. Drop an item on a slot to add it, right-click to remove, Ctrl-click to make it the top choice.
  Equip from Bags puts on the best items you're carrying.
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
