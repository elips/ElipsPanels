# ElipsPanels

The suite's small panels in one addon, for any class in WoW: Forever. Each panel can be shown or hidden by itself (`/ep`, General). More panels will move in here over time.

## Information bar

A thin bar, centered at the top of the screen to start with, with the things worth a glance:

- the time (the game's 12 or 24 hour setting), latency and frames per second
- experience per hour and gold per hour, this session
- what the addons take of each frame, and of memory
- your most worn piece of gear, and free bag slots
- any currencies you tick

Right-click the bar and a list opens under it: tick what it shows. Shift-click it to start the per-hour counts again. Point at it for the details (realm time, both latencies, the addons using the most memory, what the session has earned). The text size is in the settings.

**Gold per hour, with Auctionator**: with Auctionator installed, gold per hour is the coin you've gained plus what the things you looted are worth at the prices from its latest scan. Without it, it's the coin alone.

- Each item you loot counts at the price Auctionator last saw it listed for. What can't be auctioned (bind on pickup, quest items), greys, and anything with no auction price, or one below what a vendor pays, counts at the vendor's price.
- Only loot counts: not a quest's reward, nor what you buy or make.
- Coin that comes in while a vendor's window or the mailbox is open isn't added on top: those things were counted when you looted them. What you spend there (repairs, postage) still counts against you.
- The figure is an estimate. A price is the lowest listing at your last scan, so it's as fresh as that scan, and one silly listing on a rarely traded item inflates it.
- The bar's tooltip shows the loot's worth, the coin set aside, and the session's earnings. Shift-click the bar starts all of it again.

## Chase list

A list of things to go after, each with a short note on how to get it, so there's always something to do. Each character has its own list.

- **What goes on it**: an item (by link, or its ID; done when you own it, or that many of it), a reputation (by name; done at Exalted), a quest (`quest 1234`; done when the game has it flagged complete), or a goal of your own (ticked off by hand).
- **The list window** (`/ep chase`): add things, write how to get them, move them up and down, tick them off. Where one of the dungeon journal addons is installed, an item's note is filled in from its loot tables.
- **The panel on screen**: the first few things still to get and how far along each is. It hides itself when there's nothing left. Click its header to fold it, right-click the header for the list window.
- **Speaking up**: a line in chat and a notice on screen when an item on your list comes up for a roll or lies in a loot window, and "Chase complete" when one is done; items on the list are marked in their tooltips. Each can be switched off.

## Group mana and raid cooldowns

Two panels for a party or raid; each can be set to parties and raids, or raids only.

- **Group mana**: a line for each healer and each Mage in your group: their name and their mana as a percent, colored from full (blue) through half (yellow) to nearly empty (red), with a small icon beside anyone getting mana back (drinking, Innervate, Evocation, Mana Tide). Healers are those with the Healer role; where nobody has a role, the healing classes stand in. This panel stays up in a fight (it's for the fight).
- **Raid cooldowns**: a line for each watched cooldown someone in your group can have (Rebirth, Reincarnation, Lay on Hands, Divine Intervention, Soulstone, Innervate, and more you can tick): who has it ready, and how long until the others' are back. A use is seen when the game says who cast what; a cooldown nobody was seen using counts as ready. Shift-click a line to tell your group.
- Both: click the header to fold, drag it to move, mouse wheel to scroll. `/ep group test` shows both with a made-up raid for a minute, to see and place them.

The game hides other players' mana and buffs from addons in a fight; the panels hand the hidden values straight to the game's own widgets, so the percents and colors still show.

## All panels

- **Fade away in a fight**: in combat the panels fade out, and come back while the mouse is over where they sit. It can be switched off.
- **Moving**: `/ep move` (or Move the panels in the settings) puts a blue box where each panel sits. Drag one and its panel goes there; right-click a box to put its panel back where it started. While you drag, a box lines up with the middle of the screen and with the suite's other frames (a green line shows what it lined up with); hold Shift to place it freely. The boxes are put away in a fight.
- **Look**: dark, rounded panels with a thin edge of weathered bronze. The accent (the line along a panel's foot, ticks) is antique gold. With ElipsUI installed and a class HUD running, the accent takes the HUD's theme color and the panels get ElipsUI's gloss along the top; ElipsUI's "Gloss on panels" switches the gloss off for the whole suite.

## Commands

| Command | What it does |
| --- | --- |
| `/ep` (or `/elipspanels`) | Opens the settings |
| `/ep move` | Shows or puts away the boxes for moving the panels |
| `/ep info` | Shows or hides the information bar |
| `/ep chase` | Opens the chase list window. `/ep chase add [item link]`, an item ID, a reputation's name, `quest 1234` or any goal adds to it (a note after " - "); `/ep chase show` and `/ep chase hide` for the panel on screen |
| `/ep group test` | Both group panels with a made-up raid for a minute (`/ep group reset`: forget the cooldowns seen) |
| `/ep status` | How each panel stands |

## Coming from ArchDruid

These panels were part of ArchDruid. The first time each runs here, the settings it had in ArchDruid come along (and a line in chat says so).

## Files

| File | What's in it |
| --- | --- |
| `Kit.lua` | The small toolkit shared by the suite's addons |
| `Core.lua` | Settings, the panels' look, fading in a fight, moving, the slash command |
| `FromArchDruid.lua` | Brings settings over from ArchDruid, once. The only file that knows of ArchDruid |
| `Worth.lua` | What looted items are worth (Auctionator's prices), for gold per hour |
| `Info.lua` | The information bar |
| `Chase.lua` | The chase list |
| `Group.lua` | Group mana and raid cooldowns |
| `Options.lua` | The settings window |
