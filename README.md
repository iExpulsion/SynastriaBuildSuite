# BuildForge

A build manager for Synastria (WoW 3.3.5a). Save, share and apply a whole build in one place: perks with
their options and chosen abilities, talents for every class, glyphs, recommended gear, Hunter pet aspects, the
spec name and notes.

## Features

- **Save Every Spec at Once:** one click saves each of your specs as its own build, linked to that spec.
- **Plan Any Class:** start a build for any class or class pair, blank or copied from your character.
- **Review Before Applying:** Apply Build lists every change first, and nothing happens until you confirm.
- **Talent Calculator:** for any class, with Synastria's 71 points per class and dual-class builds.
- **Perk Editor:** every perk your build's classes can use, with options, chosen abilities, set bonuses and
  category limits.
- **Glyphs and Gear:** see what's socketed, worn, in your bags or missing, and equip a build's gear in one click.
- **Share Builds:** export the sections you choose as a single line, and import BuildForge,
  SynastriaBuildManager (SBM) and SynastriaPerkManager (SPM) strings.
- **Shared Perks:** your Misc perks live in one list that every build applies, and they're never exported or
  overwritten by an import.

## Installation

1. Download the latest release.
2. Extract the `BuildForge` folder into `World of Warcraft\Interface\AddOns`.
3. Restart the game, or log out to the character screen and back in.

## Getting Started

Open BuildForge with `/bforge`, the minimap button, or the **Open BuildForge** line in an innkeeper's chat
options. The innkeeper line also opens the Perk Manager, which perk activations need.

On first use, click **Add Current Specs** to save all of your specs as builds. Specs you're not in can't show
their perks yet, so those builds fill theirs in the first time you switch to them.

To make a single build, click **New Build**. Pick one or two classes, check what to copy from your character
(Perks, Talents, Glyphs, Gear), name it and click **Create Build**. Leave everything unchecked to start blank.

## The Window

- **Sidebar:** builds linked to this character's specs are at the top under Your Specs, with the active spec
  in green. Everything else is under Saved Builds, grouped by class. Search filters by name or spec name.
- **Build Header:** click the name to rename it or set the spec name. Assign To links a build to one of your
  specs. **Apply Build** opens a review of everything that would change; for a spec you're not in, it becomes
  **Switch to Spec N**. **Export**, **Duplicate** and **Delete** sit beside it.
- **Tabs:** Perks, Talents, Glyphs, Gear and Notes. A badge on a tab counts what differs from your character.
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
build doesn't, the review lists them; unlearn at a class trainer and BuildForge reopens the review.

### Glyphs

Each socket shows green when that glyph is socketed, yellow when it's in your bags and red when you don't have
it. Click a socket to pick a glyph; right-click to clear it. Dual-class builds have glyphs per class. Glyphs are
used up when socketed, so BuildForge leaves socketing to you; **Open Glyph Frame** opens the game's window.

### Gear

A paper doll of the build's Best item per slot, plus Alts in order of preference. Drop an item anywhere on the
tab to add it to its slot. Items the build's classes can't use are refused. **Equip from Bags** puts on the
highest-ranked item you're carrying in each slot.

## Sharing Builds

**Export** shows the build as a single line, with checkboxes for the sections to include. Click **Select All**,
then press Ctrl+C to copy.

**Import** takes a pasted string, shows which sections it has and lets you pick which to bring in. **Import as
New** makes a new build; **Into** replaces just those sections of the selected build.

Import reads:

- **BuildForge** strings.
- **SynastriaBuildManager** (SBM3 and SBM2): perks, talents for each class, chosen abilities and pet aspects.
- **SynastriaPerkManager** (SPM): perks and their options. SPM strings only carry perks, so importing one
  **Into** an existing build is the handy way to use it.

Misc perks are left out of every import and export, so your Shared Perks only change when you change them.

## Commands

| Command | Does |
|---|---|
| `/bforge` | Opens or closes the window |
| `/bforge help` | Lists the commands |
| `/bforge list` | Lists saved builds |
| `/bforge save <name>` | Saves your active spec as a build |
| `/bforge specs` | Saves every spec as a build linked to it |
| `/bforge apply <name>` | Lists what would change in chat, then asks before applying |
| `/bforge export <name>` | Opens the export box for a build |
| `/bforge import` | Opens the import box |
| `/bforge gear <name>` | Shows each slot: worn, in bags or missing |
| `/bforge equip <name>` | Equips the build's gear you're carrying |
| `/bforge note <name> <text>` | Sets the build's notes |
| `/bforge delete <name>` | Deletes a build |
| `/bforge minimap` | Hides or shows the minimap button |
| `/bforge reset` | Moves the window back to the center of the screen |

The minimap button opens the window on left-click and your active spec's build on right-click. Drag it around
the minimap to move it. With a LibDataBroker display such as Titan Panel, BuildForge appears there too.
