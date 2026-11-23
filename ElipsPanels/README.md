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
| `/ep status` | How each panel stands |

## Coming from ArchDruid

These panels were part of ArchDruid. The first time each runs here, the settings it had in ArchDruid come along (and a line in chat says so).

## Files

| File | What's in it |
| --- | --- |
| `Kit.lua` | The small toolkit shared by the suite's addons |
| `Core.lua` | Settings, the panels' look, fading in a fight, moving, the slash command |
| `FromArchDruid.lua` | Brings settings over from ArchDruid, once. The only file that knows of ArchDruid |
| `Info.lua` | The information bar |
| `Options.lua` | The settings window |
