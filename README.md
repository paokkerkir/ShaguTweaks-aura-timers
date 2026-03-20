# ShaguTweaks [Aura Timers]

Companion addon for [ShaguTweaks](https://github.com/shagu/ShaguTweaks) that shows buff/debuff icons with duration timers on target, party, pet, and raid frames. Vanilla WoW 1.12 client.

## Requirements

- [ShaguTweaks](https://github.com/shagu/ShaguTweaks) - core framework
- [SuperWoW](https://github.com/balakethelock/SuperWoW) - aura data and cast event APIs
- [ShaguTweaks-extras](https://github.com/shagu/ShaguTweaks-extras) (optional) - enables raid frame support
- [Nampower](https://github.com/pepopo978/namern) (optional) - provides exact duration data from server

## Installation

Copy `ShaguTweaks-aura-timers/` into `Interface/AddOns/` and `/reload`.

Registers as a ShaguTweaks module - toggle on/off in ShaguTweaks settings.

## How It Works

- Uses `UnitBuff`/`UnitDebuff` to display only visible auras
- Debuffs shown first, then buffs in a single row
- Target: left to right. Party/Pet: right to left. Raid: buffs above, debuffs below
- Timers only appear when duration is known from cast events (no guesswork)
- Duration sources: SuperWoW `UNIT_CASTEVENT` + built-in buff/debuff tables, or Nampower `AURA_CAST` events for exact server durations
- Cooldown spirals + color-coded countdown text (red <5s, yellow <10s, white >=10s)
- Hides default Blizzard target buffs/debuffs to prevent duplicates

## Configuration

Edit constants at the top of `raid-aura-timers.lua`:

```lua
local TARGET_ICON_SIZE = 17
local PARTY_ICON_SIZE = 14
local RAID_ICON_SIZE = 14
local ICON_SPACING = 1
local MAX_BUFFS = 16
local MAX_DEBUFFS = 16
local RAID_MAX_BUFFS = 4
local RAID_MAX_DEBUFFS = 4
```

To add missing buff durations:

```lua
local buffDurations = {
  ["Your Buff Name"] = 300, -- seconds
}
```

Debuff durations are handled automatically by ShaguTweaks' `libdebuff`.

## Compatibility

Default offsets tuned for DragonflightReloaded UI. Works with any UI that keeps standard frame names (`TargetFrame`, `PartyMemberFrame1-4`, `PetFrame`).

## License

Provided as-is for use with vanilla 1.12 client.
