# BuildForge

A build manager for Synastria (WoW 3.3.5a). It saves, shares and applies a whole build: Perks with their
options and chosen abilities, Talents for every class, Glyphs, Recommended Gear, Hunter pet aspects, the spec
name and notes.

## The Window

`/bforge`, the minimap button, or the BuildForge button above the Perk Manager or the talent frame opens the
build window. Drag its title bar to move it (it remembers where); Esc closes it. At an innkeeper, the Open
BuildForge line under "Manage perks" opens the Perk Manager and BuildForge together, ready to apply perks.

The minimap button's left-click opens or closes the window; right-click opens the build linked to your active
spec. Drag it around the minimap's edge to move it, and `/bforge minimap` hides or shows it. With a
LibDataBroker display (Titan Panel, ChocolateBar and so on) BuildForge also appears there as a launcher.

- **Sidebar:** search your builds, grouped by class; click a group to collapse it. Groups for classes you
  don't have start collapsed. Builds linked to this character's specs sit at the top in Your Specs, one row
  per spec, numbered in spec order, with the active one in green. Everything else is under Saved Builds. Import
  pastes a build in. New Build opens a sheet with one or two classes (yours to start with, but any class works)
  and Perks, Talents, Glyphs and Gear checkboxes for what to copy from your character. Only what applies to the
  chosen classes is copied, so a class you don't have can only take your gear; uncheck everything to start blank.
  For classes you don't have, perk values, ranks and category limits still show your character's.
- **Build header:** click the name to rename it and set the spec name (press Enter to keep). Apply Build opens
  a Review Changes sheet listing everything that would change; nothing happens until you click Apply Changes.
  Talents can only be added, so if your spec has more points in a talent than the build, the review lists them;
  unlearn your talents at a class trainer and BuildForge reopens the review, ready to apply.
  Export gives the share string; Duplicate makes an unlinked copy ("Name Copy") to try changes on; Delete asks
  first. The title bar shows whether the Perk Manager is open at an
  innkeeper, which perk activations need.
- **Export and Import by section:** both boxes have Perks, Talents, Glyphs, Gear and Notes checkboxes. Export
  rebuilds the string as you check and uncheck them, and remembers the choice; Select All selects the string so
  Ctrl+C copies it (WoW gives addons no clipboard access, so the key press is yours). Import shows which sections the
  pasted string has; Import as New makes a build from the checked ones, named in the Name field (filled with the
  string's build name, numbered if you already have one by that name), and Into (the selected build) replaces
  just those sections of it, leaving the rest. Hunter pet aspects go with Perks; the name, classes and spec name
  always go. Import also reads SynastriaBuildManager strings (SBM3 and SBM2): their perks, talents for each
  class, chosen abilities and pet aspects. Their Misc perks and SBM's options (all Misc perk options) are left
  out, so your Shared Perks never change.
- **Specs:** Synastria keeps perks, talents and glyphs per talent spec (up to 8). With more than one spec, the
  header's Assign to menu ties a saved build to one of this character's specs (it then reads Linked to, with
  Active Spec when that spec is active), and applying a build links it to the active spec; Review Changes says
  so, and which build it replaces. A build for a spec that isn't active isn't compared with your character:
  the Perks, Talents and Glyphs tabs drop their badges and statuses and the footer says to switch, and Apply
  Build becomes Switch to Spec N. Gear is the same in every spec, so it's always compared.
- **Tabs:** Perks, Talents, Glyphs, Gear and Notes. A badge on a tab counts what differs from your character.
- **Talents:** a talent calculator for the build's classes, any class, not just yours. Left-click adds a point,
  right-click removes one; tier, prerequisite and point limits work like the talent frame, and the tooltip
  shows your character's rank when it's the class shown in your talent window. Each class gets 71 points for
  its own trees, so a same-class dual (Warrior x2) gets 142. Builds with two different classes get a button
  per class. Use Current Talents copies your spec; Reset Class clears the class shown. The Use Current buttons
  only replace the parts for the build's classes you have, so a dual build keeps its other class's talents,
  glyphs and class perks. On a build with none of your classes, Use Current Perks, Talents and Glyphs are
  disabled; Use Current Gear still works.
- **Perks:** a perk editor for the build's classes, any class, not just yours. In Build lists the build's perks
  (and any it would turn off); All Perks lists every perk the classes can use, with a search box. Check a perk
  to add it to the build. Click a perk to see its effect, notes, options and, for perks that grant one, the
  ability to choose; options and abilities are set on the build's copy of the perk. Category headers count the
  build's perks against how many your character can have on. Each row shows what applying the build would do
  (Active, To Activate, To Deactivate, Options Differ). Perks in a set (Blood Death Knight, Overhealed, ...)
  sit together under the set's name, which counts how many of its perks the build has; a set perk's details
  list the set bonuses, green once the build has enough of them. Nothing changes on your character until Apply
  Build.
- **Shared Perks:** Misc perks aren't part of builds. They're in one Shared Perks list, at the top of the
  sidebar, that every build applies along with its own perks, so each spec gets them. Select it to edit the list:
  it shows every Misc perk you can use, checked if it's in the list. Its Apply Perks sets your active spec's Misc
  perks and leaves the rest alone, and
  its Use Current Perks takes your active Misc perks. Misc perks are yours alone: exports never include them,
  and imports drop any a string has, so only you change Shared Perks.
- **Glyphs:** the six sockets, Major and Minor, each with a green border when the glyph is socketed in your
  active spec, yellow when the glyph item is in your bags and red when you don't have it. Click a socket to
  list that class's glyphs of that kind (with a search box) and click one to choose it; right-click a
  socket or use Clear Socket to empty it. A glyph can only be in one socket. Each class of a dual-class
  character has its own glyphs, so those builds get a button per class, like the Talents tab; sockets are only
  compared for the class shown in the talent window. Glyphs are used up when socketed, so BuildForge leaves
  that to you: Open Glyph Frame opens the game's glyph window. Use Current Glyphs copies yours, for each of the build's classes you have.
- **Gear:** a paper doll of the build's Best item per slot, with a green border when you're wearing it, yellow
  when it's in your bags and red when you don't have it; a badge counts the slot's Alts (stand-ins, in order of
  preference). Click a slot to list its Best and Alts beside the doll, where Make Best and Remove (or Ctrl-click
  and right-click) reorder them. Drop an item anywhere on the tab and it goes to its slot; rings, trinkets and
  one-hand weapons fill an empty slot of the pair first. Items the build's classes can't use are refused: armor
  and weapon types (a Priest can't take plate), off-hand weapons without a dual-wielding class or the Dual
  Wielding perk, and items made for other classes. A dual-class build can use what either class can. Equip from
  Bags puts on the highest-ranked item you're carrying in each slot.
- **Notes:** free text saved with the build and included in exports.

## Commands

| Command | Does |
|---|---|
| `/bforge` | Opens or closes the window |
| `/bforge help` | Lists the commands |
| `/bforge list` | Lists saved builds; builds for other classes are marked |
| `/bforge save <name>` | Saves your active spec as a build |
| `/bforge apply <name>` | Lists what would change in chat, then asks before applying |
| `/bforge export <name>` | Shows the build as a one-line string to copy, with section checkboxes |
| `/bforge import` | Opens a box to paste a BuildForge string and pick its sections |
| `/bforge gear <name>` | Shows each slot: worn, in bags or missing |
| `/bforge equip <name>` | Equips the build's gear you're carrying |
| `/bforge note <name> <text>` | Sets the build's notes |
| `/bforge minimap` | Hides or shows the minimap button |
| `/bforge reset` | Moves the window back to the center of the screen |
| `/bforge checktalents` | Checks the talent data against your live talents (for the class in your talent window) |
| `/bforge delete <name>` | Deletes a build |

Perk activations need the Perk Manager open at an innkeeper. Perk options and chosen abilities apply anywhere.
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

`BuildForge/Data/Glyphs.lua` (every class's glyphs and their items) comes from client data
the client data:

```bash
py -I -X utf8 tools/gen_glyphs.py
```

`BuildForge/Data/Abilities.lua` (the abilities perks like Master of Precision can grant) comes from client data
the client data:

```bash
py -I -X utf8 tools/gen_abilities.py
```

`docs/DESIGN.md` covers the client APIs, the export format and what's still untested.
