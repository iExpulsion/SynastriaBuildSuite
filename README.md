# BuildForge

A build manager for Synastria (WoW 3.3.5a). It saves, shares and applies a whole build: Perks with their
options and chosen abilities, Talents for every class, Glyphs, Recommended Gear, Hunter pet aspects, the spec
name and notes.

## The Window

`/bforge`, or the BuildForge button above the Perk window or the talent frame, opens the build window. Drag
its title bar to move it (it remembers where); Esc closes it.

- **Sidebar:** search your builds, grouped by class; click a group to collapse it. Groups for classes you
  don't have start collapsed. The build last applied to this spec says Applied. New Build saves your
  character as a build; Import pastes one in.
- **Build header:** click the name to rename it and set the spec name (press Enter to keep). Apply Build opens
  a Review Changes sheet listing everything that would change; nothing happens until you click Apply Changes.
  Export gives the share string; Delete asks first. The title bar shows whether the Perk window is open at an
  innkeeper, which perk activations need.
- **Tabs:** Perks, Talents, Glyphs, Gear and Notes. A badge on a tab counts what differs from your character.
- **Talents:** a talent calculator for the build's classes, any class, not just yours. Left-click adds a point,
  right-click removes one; tier, prerequisite and point limits work like the talent frame, and the tooltip
  shows your character's rank when it's the class shown in your talent window. Each class gets 71 points for
  its own trees, so a same-class dual (Warrior x2) gets 142. Builds with two different classes get a button
  per class. Use My Talents copies your spec; Reset Class clears the class shown.
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
| `/bforge checktalents` | Checks the talent data against your live talents (for the class in your talent window) |
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

`BuildForge/Data/Talents.lua` is generated from client data; after re-running
the data extractor, regenerate it with:

```bash
py -I -X utf8 tools/gen_talents.py
```

`docs/DESIGN.md` covers the client APIs, the export format and what's still untested.
