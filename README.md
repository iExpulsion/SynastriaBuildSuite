# Synastria Build Suite

A build manager for Synastria (WoW 3.3.5a). Save, share and apply a whole build in one place: perks with
their options and chosen abilities, talents for every class, glyphs, recommended gear, item affix priority,
Hunter pet aspects, the spec name and notes.

![The Synastria Build Suite window on the Perks tab: your specs and saved builds in the sidebar, the build's perks by category, and a perk's details](docs/images/perks.png)

## Features

- **Save Every Spec at Once:** one click saves each of your specs as its own build, linked to that spec.
- **Plan Any Class:** start a build for any class or class pair, blank or copied from your character.
- **Review Before Applying:** Apply Build lists every change first, and nothing happens until you confirm.
- **Talent Calculator:** for any class, with Synastria's 71 points per class and dual-class builds.
- **Perk Editor:** every perk your build's classes can use, with options, chosen abilities, set bonuses and
  category limits.
- **Glyphs and Gear:** see what's socketed, worn, in your bags or missing, and equip a build's gear in one click.
- **Affix Priority:** a suggested order for the Item Affix Manager, set along with the rest of the build.
- **Share Builds:** export the sections you choose as a single line, and import Synastria Build Suite,
  SynastriaBuildManager (SBM), SynastriaPerkManager (SPM) and Item Affix Manager strings.
- **Shared Perks:** your Misc perks live in one list that every build applies, and they're never exported or
  overwritten by an import.

## Installation

1. Download the latest release.
2. Extract the `SynastriaBuildSuite` folder into `World of Warcraft\Interface\AddOns`.
3. Restart the game, or log out to the character screen and back in.

## Getting Started

Open Synastria Build Suite with `/sbs`, the minimap button, or the **Open Synastria Build Suite** line in an innkeeper's chat
options. The innkeeper line also opens the Perk Manager, which perk activations need.

![An innkeeper's chat options with Open Synastria Build Suite under Manage perks](docs/images/innkeeper.png)

On first use, click **Add Current Specs** to save all of your specs as builds. Specs you're not in can't show
their perks or affix order yet, so those builds fill them in the first time you switch to them.

To make a single build, click **New Build**. Pick one or two classes, check what to copy from your character
(Perks, Talents, Glyphs, Gear, Affixes), name it and click **Create Build**. Leave everything unchecked to start
blank.

## The Window

- **Sidebar:** builds linked to this character's specs are at the top under Your Specs, with the active spec
  in green. Everything else is under Saved Builds, grouped by class. Search filters by name or spec name.
- **Build Header:** click the name to rename it or set the spec name. Assign To links a build to one of your
  specs. **Apply Build** opens a review of everything that would change; for a spec you're not in, it becomes
  **Switch to Spec N**. **Export**, **Duplicate** and **Delete** sit beside it.
- **Tabs:** Perks, Talents, Glyphs, Gear, Affixes and Notes. A badge on a tab counts what differs from your character.
- **Use Current:** each tab's Use Current button copies that part of your character into the build, only for
  the build's classes you have.

### Perks

In Build lists the build's perks; All Perks lists every perk its classes can use. Check a perk to add it, then
click it to set its options or chosen ability. Category headers count the build's perks against your limits,
and perks in a set show the set's bonuses. Misc perks are kept in **Shared Perks**, at the top of the sidebar.

Perk activations need the Perk Manager open at an innkeeper; the title bar shows whether it is. Perk options
and chosen abilities apply anywhere.

### Talents

Left-click adds a point, right-click removes one, with the same tier and prerequisite rules as the talent
window. Dual-class builds get a button per class. Talents can only be added, so if your spec has points the
build doesn't, the review lists them; unlearn at a class trainer and Synastria Build Suite reopens the review.

![The Talents tab: a Death Knight's three trees with 71 of 71 points spent](docs/images/talents.png)

### Glyphs

Each socket shows green when that glyph is socketed, yellow when it's in your bags and red when you don't have
it. Click a socket to pick a glyph; right-click to clear it. Dual-class builds have glyphs per class. Glyphs are
used up when socketed, so Synastria Build Suite leaves socketing to you; **Open Glyph Frame** opens the game's window.

![The Glyphs tab: socketed major glyphs, empty minor sockets and the glyph picker for a socket](docs/images/glyphs.png)

### Gear

A paper doll of the build's Best item per slot, plus Alts in order of preference. Drop an item anywhere on the
tab to add it to its slot. Items the build's classes can't use are refused. **Equip from Bags** puts on the
highest-ranked item you're carrying in each slot.

![The Gear tab: the paper doll with every slot worn, and the Head slot's items beside it](docs/images/gear.png)

### Affixes

An item can have several of its affixes attuned, but only one is active at a time. The server picks the first
one in your spec's affix order, the same 16 slots as the game's Item Affix Manager. The left side is the build's
order, most wanted first: select an affix to move it up or down or remove it, or right-click it to remove it.
**Load Preset** starts from one of the game's orders (Strength DPS, Agility DPS, Tank, Caster). The right side
lists every affix with its stats on hover; click one to add it to the end.

The affix order belongs to the spec and only changes near an innkeeper; the Perk Manager doesn't need to be open.
Apply Build sets it along with the rest of the build. A build with no affix order leaves yours alone.

## Sharing Builds

**Export** shows the build as a single line, with checkboxes for the sections to include. Click **Select All**,
then press Ctrl+C to copy.

**Import** takes a pasted string, shows which sections it has and lets you pick which to bring in. **Import as
New** makes a new build; **Into** replaces just those sections of the selected build.

Import reads:

- **Synastria Build Suite** strings.
- **SynastriaBuildManager** (SBM3 and SBM2): perks, talents for each class, chosen abilities and pet aspects.
- **SynastriaPerkManager** (SPM): perks and their options. SPM strings only carry perks, so importing one
  **Into** an existing build is the handy way to use it.
- **Item Affix Manager** exports: the game's own affix order strings. Like SPM strings, they're best imported
  **Into** a build.

Misc perks are left out of every import and export, so your Shared Perks only change when you change them.

## Commands

| Command | Does |
|---|---|
| `/sbs` | Opens or closes the window |
| `/sbs help` | Lists the commands |
| `/sbs list` | Lists saved builds |
| `/sbs save <name>` | Saves your active spec as a build |
| `/sbs specs` | Saves every spec as a build linked to it |
| `/sbs apply <name>` | Lists what would change in chat, then asks before applying |
| `/sbs export <name>` | Opens the export box for a build |
| `/sbs import` | Opens the import box |
| `/sbs gear <name>` | Shows each slot: worn, in bags or missing |
| `/sbs equip <name>` | Equips the build's gear you're carrying |
| `/sbs note <name> <text>` | Sets the build's notes |
| `/sbs delete <name>` | Deletes a build |
| `/sbs minimap` | Hides or shows the minimap button |
| `/sbs reset` | Moves the window back to the center of the screen |

The minimap button opens the window on left-click and your active spec's build on right-click. Drag it around
the minimap to move it. With a LibDataBroker display such as Titan Panel, Synastria Build Suite appears there too.

## License

Synastria Build Suite is released under the [MIT License](LICENSE). The game data in `SynastriaBuildSuite/Data` comes from the
Synastria client and isn't covered by it.
