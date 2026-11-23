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

## Rebuff List

Who in your group needs the buffs you can cast, with a click (or one key) to cast them. So far it knows a Druid's two, Mark of the Wild and Thorns; other classes' buffs can be added, and until then the list is there for Druids only. Inside a battleground it follows "Hide in battlegrounds" like the other panels (the buff key still works).

- **Rebuff List (Thorns and Mark of the Wild)**: out of combat, in a group, a small list of who needs your buffs: missing, a lower rank than you can cast (yours or another druid's), or yours running out soon (a countdown, under 60 seconds by default). One row per player, with an icon for each buff they need: click to cast your highest rank of Mark, then Thorns once it lands; right-click casts Thorns straight away. The icons say which buffs, so the row's right side stays empty for a missing buff and only shows what the icons can't: the time left on one about to run out ("0:42") or a lower rank ("r4"). Hovering a row spells it out. It hides when nobody needs anything. Thorns is checked on tanks (group role or main tank), you, anyone wearing your Thorns or that you've buffed in this group, and anyone you pin with `/ep rebuff watch` (your target, or `/ep rebuff watch Name`; again to take them off); in a party with no tank, the whole party. Mark of the Wild is checked on everyone, you too; when 3 or more in your party or raid need it, one Gift of the Wild row takes their place, while you have Wild Thornroot. On WoW Forever a Gift lands on everyone in the raid, not one group of it, so there is one row for the whole raid and it's cast on you. The Gift row reads "5 need it"; when all of them already wear a Mark or Gift and it is only a lower rank than yours (another druid's Gift rank 1 under your rank 2, say), it reads "5 lower rank" in the lower-rank orange instead, and hovering it says how many have none, how many have a lower rank, which rank and whose. Tanks needing Thorns first, then Gift rows, then everyone else; up to 10 rows ("+N more" past that), dimmed when out of range. It hides in combat (the game doesn't let addon buttons change then) and comes back after. Drag it to move it; `/ep rebuff` turns it on or off (`/ep rebuff show`, `/ep rebuff hide`), `/ep rebuff test` shows a made-up party and `/ep rebuff test raid` a made-up 40-player raid, to place it and see how it looks. Settings on the Rebuff tab; the switch is on General. A Mark or Gift of the Wild is known by its name, so another Druid's counts whatever version it is; one with a spell ID the list has no rank for is taken as a full one (and listed in `/ep status`). In a battleground the game hides everyone's buffs the whole time, yours included, and other players' casts too. So there the list is about the buffs you gave: who they're on (your own casts; a Gift counts for everyone alive in the raid) and when they run out, plus what people had when buffs were last readable. Anyone nothing is known about is left off it, and dying puts a player back to not known: it won't say "40 need it" about a raid another Druid may have buffed. A Gift of the Wild on someone is measured against your own Gift, not against your Mark: it shows as a lower rank only when your Gift is a higher rank than theirs (the row then says "Gift r1"), so a raid under another Druid's Gift of the same rank needs nothing.
- **Buff key**: one key for all your buffing (set it on the Rebuff tab, under Key Bindings > ElipsPanels, or with `/ep rebuff bind F`, any key, e.g. `SHIFT-B`; `/ep rebuff unbind` clears it). Each press, out of combat, casts the first buff of the list's marked row (the first one in range, marked with a soft wash and an edge on the left), and when the cast lands it moves on to the next one at once: Mark, then Thorns, then the next player. The key shows on the list's header. It works with the list turned off, does nothing in combat, and says so in chat when there's nothing to buff.
- **Thorns warnings**: for the people who've worn your Thorns, a line in chat when it falls off ("Your Thorns fell off Morvessa."), when another druid's replaces it ("Leafy overwrote your Thorns on Morvessa."), and when someone wears a lower rank than you can cast ("Morvessa has Thorns rank 4. You can cast rank 6."). Once per change; the game hides buffs in combat, so what happens in a fight is told when it ends. In a group; a new zone starts watching afresh. Switch: "Thorns warnings in chat" on the Rebuff tab.

## All panels

- **Fade away in a fight**: in combat the panels fade out, and come back while the mouse is over where they sit. It can be switched off.
- **Hide in battlegrounds**: inside a battleground none of the panels show; they come back when you leave. It can be switched off (General).
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
| `/ep rebuff` | Shows or hides the Rebuff List (`test`, `test raid`: a made-up group; `watch`: pin your target for Thorns; `bind KEY`, `unbind`: the buff key) |
| `/ep status` | How each panel stands |

## Coming from ArchDruid

These panels were part of ArchDruid. The first time each runs here, the settings it had in ArchDruid come along (and a line in chat says so). The Rebuff List's buff key comes along too: the key you'd bound is bound to ElipsPanels' button the first time, with nothing to set again.

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
| `Rebuff.lua` | The Rebuff List and its buff key |
| `Bindings.xml` | The buff key's place under Key Bindings |
| `Options.lua` | The settings window |
