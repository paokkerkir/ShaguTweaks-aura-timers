# ShaguTweaks [Aura Timers]

Companion addon for [ShaguTweaks](https://github.com/paokkerkir/ShaguTweaks) that shows buff/debuff icons with duration timers on target, party, and pet frames. Vanilla WoW 1.12 client.

## Requirements

- [ShaguTweaks](https://github.com/shagu/ShaguTweaks) — core framework
- [SuperWoW](https://github.com/balakethelock/SuperWoW) — aura data and cast event APIs
- [Nampower](https://github.com/pepopo978/namern) (optional) — provides exact duration data from server

## Installation

Copy `ShaguTweaks-aura-timers/` into `Interface/AddOns/` and restart WoW.

Registers as a ShaguTweaks module — toggle on/off in ShaguTweaks settings.

## How It Works

- Uses `UnitBuff`/`UnitDebuff` to display only visible auras
- Debuffs shown first, then buffs; both groups sorted ascending by remaining duration
- **Target**: left to right, timer text centered inside icons (17px icons, 8pt font)
- **Party/Pet**: right to left, timer text centered inside icons (14px icons, 7pt font)
- Party/Pet wraps to a second row after 5 icons; frames below shift down automatically
- Timer color changes with time remaining: white (≥10s), gold (5–10s), red (<5s)
- Debuff timers fall back to ShaguTweaks `libdebuff` when no cast event data is available
- Duration sources: SuperWoW `UNIT_CASTEVENT` + built-in buff/debuff tables, Nampower `AURA_CAST` events for exact server durations, `libdebuff` for debuffs
- Cooldown spirals on all icons
- Hides default Blizzard target buffs/debuffs to prevent duplicates

## Configuration

Edit constants at the top of `aura-timers.lua` and /reload:

```lua
local TARGET_ICON_SIZE = 17
local PARTY_ICON_SIZE = 14
local ICON_SPACING = 2
local TARGET_TIMER_FONT = 8
local PARTY_TIMER_FONT = 7
local MAX_BUFFS = 16
local MAX_DEBUFFS = 16
local PARTY_MAX_PER_ROW = 5
local SORT_ORDER = "Duration ascending"  -- "Default", "Duration ascending", "Duration descending"
```

To add missing buff durations, add entries to the `buffDurations` table:

```lua
["Your Buff Name"] = 300, -- duration in seconds
```

Debuff durations are provided by ShaguTweaks' `libdebuff` (cast-event tracking and fallback lookup).

## Compatibility

Default offsets tuned for BlizzardUI and ShaguTweaks edits. Works with any UI that keeps standard frame names (`TargetFrame`, `PartyMemberFrame1-4`, `PetFrame`).

## License

Provided as-is for use with vanilla 1.12 client.
