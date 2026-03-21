# ShaguTweaks [Aura Timers]

Companion addon for [ShaguTweaks](https://github.com/shagu/ShaguTweaks) that shows buff/debuff icons with duration timers on target, party, and pet frames. Vanilla WoW 1.12 client.

## Requirements

- [ShaguTweaks](https://github.com/shagu/ShaguTweaks) — core framework
- [SuperWoW](https://github.com/balakethelock/SuperWoW) — aura data and cast event APIs
- [Nampower](https://github.com/pepopo978/namern) (optional) — provides exact duration data from server

## Installation

Copy `ShaguTweaks-aura-timers/` into `Interface/AddOns/` and `/reload`.

Registers as a ShaguTweaks module — toggle on/off in ShaguTweaks settings.

## How It Works

- Uses `UnitBuff`/`UnitDebuff` to display only visible auras
- Debuffs shown first, then buffs in a single row
- **Target**: left to right, timer text below icons (17px icons, 8pt font)
- **Party/Pet**: right to left, timer text inside icons (14px icons, 7pt font)
- Party/Pet wraps to a second row after 5 icons; frames below shift down automatically
- Timer text in gold WoW color for all frames
- Timers only appear when duration is known from cast events (no guesswork)
- Duration sources: SuperWoW `UNIT_CASTEVENT` + built-in buff/debuff tables, or Nampower `AURA_CAST` events for exact server durations
- Cooldown spirals on all icons
- Hides default Blizzard target buffs/debuffs to prevent duplicates

## Configuration

Edit constants at the top of `aura-timers.lua`:

```lua
local TARGET_ICON_SIZE = 17
local PARTY_ICON_SIZE = 14
local ICON_SPACING = 2
local TARGET_TIMER_FONT = 8
local PARTY_TIMER_FONT = 7
local MAX_BUFFS = 16
local MAX_DEBUFFS = 16
local PARTY_MAX_PER_ROW = 5
```

To add missing buff durations, add entries to the `buffDurations` table:

```lua
["Your Buff Name"] = 300, -- duration in seconds
```

Debuff durations are handled automatically by ShaguTweaks' `libdebuff`.

## Compatibility

Default offsets tuned for DragonflightReloaded UI. Works with any UI that keeps standard frame names (`TargetFrame`, `PartyMemberFrame1-4`, `PetFrame`).

## License

Provided as-is for use with vanilla 1.12 client.
