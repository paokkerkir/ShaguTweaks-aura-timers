local _G = ShaguTweaks.GetGlobalEnv()
local T = ShaguTweaks.T

-- Require SuperWoW
if not SUPERWOW_VERSION then return end

local module = ShaguTweaks:register({
  title = T["Aura Timers"],
  description = T["Show buff and debuff icons with duration timers on target, party, and pet frames. Requires SuperWoW."],
  expansions = { ["vanilla"] = true, ["tbc"] = false },
  category = T["Unit Frames"],
  enabled = true,
})

-- ============================================================================
-- CORE: Utilities, icon creation, duration tracking
-- ============================================================================

local libdebuff = ShaguTweaks.libdebuff

-- Icon sizes and layout
local TARGET_ICON_SIZE = 17
local PARTY_ICON_SIZE = 14
local ICON_SPACING = 2
local TARGET_TIMER_FONT = 8
local PARTY_TIMER_FONT = 7
local MAX_BUFFS = 16
local MAX_DEBUFFS = 16
local PARTY_MAX_PER_ROW = 5

-- Gold timer color (WoW standard gold)
local GOLD_R, GOLD_G, GOLD_B = 1.0, 0.82, 0

-- Duration tracking: [targetGuid] = { [spellId] = { start, duration } }
-- ONLY populated by actual events (UNIT_CASTEVENT / AURA_CAST), never from snapshots
local auraDurations = {}

-- Spell icon cache
local iconCache = {}
local function GetSpellIcon(spellId)
  if not spellId or spellId <= 0 then return nil end
  if iconCache[spellId] then return iconCache[spellId] end
  if GetSpellRecField and GetSpellIconTexture then
    local iconId = GetSpellRecField(spellId, "spellIconID")
    if iconId and type(iconId) == "number" and iconId > 0 then
      local tex = GetSpellIconTexture(iconId)
      if tex then
        if not string.find(tex, "\\") then
          tex = "Interface\\Icons\\" .. tex
        end
        iconCache[spellId] = tex
        return tex
      end
    end
  end
  return nil
end

-- Spell name cache
local nameCache = {}
local function GetSpellName(spellId)
  if not spellId or spellId <= 0 then return nil end
  if nameCache[spellId] then return nameCache[spellId] end
  if SpellInfo then
    local name = SpellInfo(spellId)
    if name then nameCache[spellId] = name end
    return name
  end
  return nil
end

-- Common buff durations (libdebuff only covers debuffs)
local buffDurations = {
  -- Priest
  ["Power Word: Fortitude"] = 1800,
  ["Prayer of Fortitude"] = 3600,
  ["Power Word: Shield"] = 30,
  ["Divine Spirit"] = 1800,
  ["Prayer of Spirit"] = 3600,
  ["Shadow Protection"] = 600,
  ["Prayer of Shadow Protection"] = 1200,
  ["Inner Fire"] = 600,
  ["Renew"] = 15,
  ["Fear Ward"] = 600,
  -- Druid
  ["Mark of the Wild"] = 1800,
  ["Gift of the Wild"] = 3600,
  ["Thorns"] = 600,
  ["Rejuvenation"] = 12,
  ["Regrowth"] = 21,
  -- Mage
  ["Arcane Intellect"] = 1800,
  ["Arcane Brilliance"] = 3600,
  ["Ice Armor"] = 1800,
  ["Frost Armor"] = 1800,
  ["Mage Armor"] = 1800,
  ["Ice Barrier"] = 60,
  ["Dampen Magic"] = 600,
  ["Amplify Magic"] = 600,
  -- Paladin
  ["Blessing of Might"] = 300,
  ["Blessing of Wisdom"] = 300,
  ["Blessing of Kings"] = 300,
  ["Blessing of Salvation"] = 300,
  ["Blessing of Light"] = 300,
  ["Blessing of Sanctuary"] = 300,
  ["Greater Blessing of Might"] = 900,
  ["Greater Blessing of Wisdom"] = 900,
  ["Greater Blessing of Kings"] = 900,
  ["Greater Blessing of Salvation"] = 900,
  ["Greater Blessing of Light"] = 900,
  ["Greater Blessing of Sanctuary"] = 900,
  -- Warlock
  ["Demon Armor"] = 1800,
  ["Demon Skin"] = 1800,
  ["Unending Breath"] = 600,
  -- Warrior
  ["Battle Shout"] = 120,
  -- Shaman
  ["Lightning Shield"] = 600,
  ["Water Shield"] = 600,
  -- Consumables
  ["Flask of the Titans"] = 7200,
  ["Flask of Supreme Power"] = 7200,
  ["Flask of Distilled Wisdom"] = 7200,
  ["Flask of Chromatic Resistance"] = 7200,
  ["Spirit of Zanza"] = 7200,
  ["Rallying Cry of the Dragonslayer"] = 7200,
  ["Songflower Serenade"] = 3600,
  ["Fengus' Ferocity"] = 7200,
  ["Mol'dar's Moxie"] = 7200,
  ["Slip'kik's Savvy"] = 7200,
  ["Warchief's Blessing"] = 3600,
}

-- Look up duration by spell name (debuff table first, then buff table)
local function LookupDuration(name)
  if not name then return nil end
  if libdebuff then
    local dur = libdebuff:GetDuration(name, nil)
    if dur and dur > 0 then return dur end
  end
  local dur = buffDurations[name]
  if dur and dur > 0 then return dur end
  return nil
end

-- Record a duration for a spell on a target (only called from events)
local function TrackDuration(targetGuid, spellId, durationSec)
  if not targetGuid or not spellId or not durationSec or durationSec <= 0 then return end
  if not auraDurations[targetGuid] then auraDurations[targetGuid] = {} end
  auraDurations[targetGuid][spellId] = {
    start = GetTime(),
    duration = durationSec,
  }
end

-- Get tracked duration for a spell
local function GetTrackedDuration(guid, spellId)
  if not guid or not spellId then return nil, nil end
  if auraDurations[guid] and auraDurations[guid][spellId] then
    local data = auraDurations[guid][spellId]
    local remaining = (data.start + data.duration) - GetTime()
    if remaining > 0 then
      return data.duration, remaining
    else
      auraDurations[guid][spellId] = nil
    end
  end
  return nil, nil
end

-- Build texture->spellId map from GetUnitField for a unit's auras
local function BuildTexToSpellMap(guid)
  local map = {}
  if not guid then return map end
  local auras = GetUnitField(guid, "aura")
  if not auras then return map end
  for slot = 1, 48 do
    local spellId = auras[slot]
    if spellId and spellId > 0 then
      local tex = GetSpellIcon(spellId)
      if tex then
        map[string.lower(tex)] = spellId
      end
    end
  end
  return map
end

-- Simple time formatter (no embedded color codes - we use gold FontString color)
local function FormatTime(remaining)
  if remaining >= 86400 then
    return math.floor(remaining / 86400) .. "d"
  elseif remaining >= 3600 then
    return math.floor(remaining / 3600) .. "h"
  elseif remaining >= 60 then
    return math.floor(remaining / 60) .. "m"
  else
    return math.floor(remaining) .. ""
  end
end

-- ============================================================================
-- ICON CREATION
-- ============================================================================

-- timerBelow: true = timer text below icon (target frames)
--             false = timer text inside icon center (party/pet frames)
local function CreateAuraIcon(parent, iconSize, isDebuff, timerFontSize, timerBelow)
  timerFontSize = timerFontSize or PARTY_TIMER_FONT

  local icon = CreateFrame("Button", nil, parent)
  icon:SetWidth(iconSize)
  icon:SetHeight(iconSize)
  icon:SetFrameLevel(parent:GetFrameLevel() + 10)

  icon.texture = icon:CreateTexture(nil, "ARTWORK")
  icon.texture:SetAllPoints()
  icon.texture:SetTexCoord(.08, .92, .08, .92)

  icon.stacks = icon:CreateFontString(nil, "OVERLAY")
  icon.stacks:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
  icon.stacks:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
  icon.stacks:Hide()

  if isDebuff then
    icon.border = icon:CreateTexture(nil, "OVERLAY")
    icon.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
    icon.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
  end

  -- Cooldown spiral overlay
  icon.cd = CreateFrame("Model", nil, icon, "CooldownFrameTemplate")
  icon.cd.noCooldownCount = true
  icon.cd:SetAllPoints()
  icon.cd:SetScale(0.7)
  icon.cd:SetAlpha(0.4)

  -- Timer text
  icon.timer = icon:CreateFontString(nil, "OVERLAY")
  icon.timer:SetFont(STANDARD_TEXT_FONT, timerFontSize, "OUTLINE")
  icon.timer:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
  if timerBelow then
    icon.timer:SetPoint("TOP", icon, "BOTTOM", 0, -1)
  else
    icon.timer:SetPoint("BOTTOM", icon, "BOTTOM", 0, 1)
  end
  icon.timer:SetJustifyH("CENTER")
  icon.timer:Hide()

  -- Tooltip on hover
  icon:EnableMouse(true)
  icon:SetScript("OnEnter", function()
    if this.tooltipUnit and this.tooltipIndex then
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      if this.tooltipIsDebuff then
        GameTooltip:SetUnitDebuff(this.tooltipUnit, this.tooltipIndex)
      else
        GameTooltip:SetUnitBuff(this.tooltipUnit, this.tooltipIndex)
      end
    end
  end)
  icon:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  icon:Hide()
  return icon
end

-- ============================================================================
-- AURA DISPLAY UPDATE
-- ============================================================================

local function UpdateBuffIcons(icons, maxCount, unitstr, guid, texToSpell, isDebuff)
  local idx = 0

  for i = 1, 32 do
    if idx >= maxCount then break end

    local texture, debuffStacks, debuffType
    if isDebuff then
      texture, debuffStacks, debuffType = UnitDebuff(unitstr, i)
    else
      texture = UnitBuff(unitstr, i)
    end

    if not texture then break end

    idx = idx + 1
    local icon = icons[idx]
    icon.texture:SetTexture(texture)

    -- Store tooltip data
    icon.tooltipUnit = unitstr
    icon.tooltipIndex = i
    icon.tooltipIsDebuff = isDebuff

    -- Stacks
    if isDebuff and debuffStacks and debuffStacks > 1 then
      icon.stacks:SetText(debuffStacks)
      icon.stacks:Show()
    else
      icon.stacks:Hide()
    end

    -- Debuff border color
    if isDebuff and icon.border then
      local color = debuffType and DebuffTypeColor[debuffType] or DebuffTypeColor["none"]
      if color then
        icon.border:SetVertexColor(color.r, color.g, color.b)
      end
    end

    -- Duration timer: only from event-tracked data
    local spellId = texToSpell and texToSpell[string.lower(texture)] or nil
    local duration, timeleft = GetTrackedDuration(guid, spellId)
    if duration and timeleft and duration > 0 then
      local start = GetTime() + timeleft - duration
      CooldownFrame_SetTimer(icon.cd, start, duration, 1)
      icon.cd:Show()
      icon.timerStart = start
      icon.timerDuration = duration
      icon.timer:Show()
    else
      CooldownFrame_SetTimer(icon.cd, 0, 0, 0)
      icon.timerStart = nil
      icon.timerDuration = nil
      icon.timer:SetText("")
      icon.timer:Hide()
    end

    icon:Show()
  end

  -- Hide unused
  for i = idx + 1, maxCount do
    icons[i]:Hide()
  end

  return idx
end

-- ============================================================================
-- AURA DISPLAY CREATION
-- ============================================================================

-- growDir: "RIGHT" = left-to-right (target), "LEFT" = right-to-left (party/pet)
-- timerBelow: true for target (text below icon), false for party/pet (text inside)
-- maxPerRow: icons per row before wrapping (nil = no wrapping)
local function CreateAuraDisplay(parent, maxBuffs, maxDebuffs, iconSize, xOffset, yOffset, timerFontSize, growDir, timerBelow, maxPerRow)
  timerFontSize = timerFontSize or PARTY_TIMER_FONT
  xOffset = xOffset or 5
  yOffset = yOffset or 2
  growDir = growDir or "RIGHT"

  local step = iconSize + ICON_SPACING

  local display = {}
  display.buffs = {}
  display.debuffs = {}
  display.iconSize = iconSize
  display.growDir = growDir
  display.parent = parent
  display.xOffset = xOffset
  display.yOffset = yOffset
  display.maxPerRow = maxPerRow
  display.hasSecondRow = false

  -- Create all icons (positioned initially, will be repositioned in UpdateDisplay)
  for i = 1, maxDebuffs do
    local icon = CreateAuraIcon(parent, iconSize, true, timerFontSize, timerBelow)
    icon:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 0) -- placeholder
    display.debuffs[i] = icon
  end
  for i = 1, maxBuffs do
    local icon = CreateAuraIcon(parent, iconSize, false, timerFontSize, timerBelow)
    icon:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, 0) -- placeholder
    display.buffs[i] = icon
  end

  return display
end

-- Position a single icon based on its combined position index
local function PositionIcon(icon, display, pos)
  local step = display.iconSize + ICON_SPACING
  local maxPerRow = display.maxPerRow or 999
  local row = 0
  local col = pos
  if maxPerRow and pos > maxPerRow then
    row = 1
    col = pos - maxPerRow
  end
  local rowHeight = display.iconSize + 2

  icon:ClearAllPoints()
  if display.growDir == "RIGHT" then
    icon:SetPoint("TOPLEFT", display.parent, "BOTTOMLEFT",
      display.xOffset + (col - 1) * step,
      display.yOffset - row * rowHeight)
  else
    icon:SetPoint("TOPRIGHT", display.parent, "BOTTOMRIGHT",
      -(display.xOffset + (col - 1) * step),
      display.yOffset - row * rowHeight)
  end
end

-- Full update for a display
local function UpdateDisplay(display, maxBuffs, maxDebuffs, unitstr)
  if not UnitExists(unitstr) then
    for i = 1, maxBuffs do display.buffs[i]:Hide() end
    for i = 1, maxDebuffs do display.debuffs[i]:Hide() end
    display.hasSecondRow = false
    return
  end

  local guid = GetUnitGUID and GetUnitGUID(unitstr) or nil
  local texToSpell = BuildTexToSpellMap(guid)

  -- Update debuffs first, count visible
  local visibleDebuffs = UpdateBuffIcons(display.debuffs, maxDebuffs, unitstr, guid, texToSpell, true)

  -- Position visible debuffs
  for i = 1, visibleDebuffs do
    PositionIcon(display.debuffs[i], display, i)
  end

  -- Position buff icons after visible debuffs
  for i = 1, maxBuffs do
    PositionIcon(display.buffs[i], display, visibleDebuffs + i)
  end

  -- Update buffs
  local visibleBuffs = UpdateBuffIcons(display.buffs, maxBuffs, unitstr, guid, texToSpell, false)

  -- Track whether second row is used
  local totalVisible = visibleDebuffs + visibleBuffs
  local maxPerRow = display.maxPerRow or 999
  display.hasSecondRow = (totalVisible > maxPerRow)
end

-- ============================================================================
-- MAIN ENABLE
-- ============================================================================

module.enable = function(self)

  -- ===========================================================================
  -- Duration tracking via SuperWoW UNIT_CASTEVENT
  -- ===========================================================================
  local tracker = CreateFrame("Frame")
  tracker:RegisterEvent("UNIT_CASTEVENT")
  tracker:SetScript("OnEvent", function()
    local casterGuid = arg1
    local targetGuid = arg2
    local eventType = arg3
    local spellId = arg4

    if eventType == "CAST" and targetGuid and targetGuid ~= "" and spellId then
      local name = GetSpellName(spellId)
      local dur = LookupDuration(name)
      if dur then
        TrackDuration(targetGuid, spellId, dur)
      end
    end
  end)

  -- Nampower AURA_CAST events
  pcall(function()
    local nampowerTracker = CreateFrame("Frame")
    nampowerTracker:RegisterEvent("AURA_CAST_ON_SELF")
    nampowerTracker:RegisterEvent("AURA_CAST_ON_OTHER")
    nampowerTracker:SetScript("OnEvent", function()
      local spellId = arg1
      local casterGuid = arg2
      local targetGuid = arg3
      local durationMs = arg8

      if not targetGuid or targetGuid == "" then
        targetGuid = casterGuid
      end

      if targetGuid and spellId and durationMs and type(durationMs) == "number" and durationMs > 0 then
        TrackDuration(targetGuid, spellId, durationMs / 1000)
      end
    end)
  end)

  -- Timer text update loop (every 0.1s)
  local timerUpdate = CreateFrame("Frame")
  local allDisplays = {}
  timerUpdate:SetScript("OnUpdate", function()
    if not this.next then this.next = GetTime() + 0.1 end
    if this.next > GetTime() then return end
    this.next = GetTime() + 0.1

    for _, display in ipairs(allDisplays) do
      if display.buffs then
        for _, icon in ipairs(display.buffs) do
          if icon:IsShown() and icon.timerDuration and icon.timerStart then
            local remaining = icon.timerDuration - (GetTime() - icon.timerStart)
            if remaining > 0 then
              icon.timer:SetText(FormatTime(remaining))
              icon.timer:Show()
            else
              icon.timer:SetText("")
              icon.timer:Hide()
            end
          end
        end
      end
      if display.debuffs then
        for _, icon in ipairs(display.debuffs) do
          if icon:IsShown() and icon.timerDuration and icon.timerStart then
            local remaining = icon.timerDuration - (GetTime() - icon.timerStart)
            if remaining > 0 then
              icon.timer:SetText(FormatTime(remaining))
              icon.timer:Show()
            else
              icon.timer:SetText("")
              icon.timer:Hide()
            end
          end
        end
      end
    end
  end)

  -- Periodic cleanup (every 60s)
  local cleanupTick = 0
  tracker:SetScript("OnUpdate", function()
    if cleanupTick > GetTime() then return end
    cleanupTick = GetTime() + 60
    local now = GetTime()
    for guid, spells in pairs(auraDurations) do
      local empty = true
      for spellId, data in pairs(spells) do
        if data.start + data.duration < now then
          spells[spellId] = nil
        else
          empty = false
        end
      end
      if empty then auraDurations[guid] = nil end
    end
  end)

  -- ===========================================================================
  -- HIDE DEFAULT BUFF TOOLTIPS
  -- ===========================================================================
  if PartyMemberBuffTooltip then
    PartyMemberBuffTooltip:Hide()
    PartyMemberBuffTooltip.Show = function(self) self:Hide() end
  end

  if RefreshBuffs then
    RefreshBuffs = function() end
  end

  -- ===========================================================================
  -- HIDE DEFAULT BLIZZARD TARGET BUFFS/DEBUFFS
  -- ===========================================================================
  local function HideDefaultTargetAuras()
    for i = 1, 16 do
      local buff = _G["TargetFrameBuff" .. i]
      if buff then buff:Hide() end
      local debuff = _G["TargetFrameDebuff" .. i]
      if debuff then debuff:Hide() end
    end
  end

  if TargetFrame_UpdateAuras then
    local origUpdateAuras = TargetFrame_UpdateAuras
    TargetFrame_UpdateAuras = function()
      origUpdateAuras()
      HideDefaultTargetAuras()
    end
  end

  if TargetDebuffButton_Update then
    local origDebuffUpdate = TargetDebuffButton_Update
    TargetDebuffButton_Update = function()
      origDebuffUpdate()
      HideDefaultTargetAuras()
    end
  end

  HideDefaultTargetAuras()

  -- ===========================================================================
  -- TARGET FRAME: timer inside-bottom, no row wrapping
  -- ===========================================================================
  do
    local targetDisplay = CreateAuraDisplay(TargetFrame, MAX_BUFFS, MAX_DEBUFFS,
      TARGET_ICON_SIZE, 5, 30, TARGET_TIMER_FONT, "RIGHT", false, nil)
    table.insert(allDisplays, targetDisplay)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("UNIT_AURA")
    ev:SetScript("OnEvent", function()
      if event == "UNIT_AURA" and arg1 ~= "target" then return end
      HideDefaultTargetAuras()
      UpdateDisplay(targetDisplay, MAX_BUFFS, MAX_DEBUFFS, "target")
    end)
  end

  -- ===========================================================================
  -- PARTY FRAMES: timer inside icons, wraps at 5 per row
  -- ===========================================================================
  do
    local partyDisplays = {}

    -- Capture original positions (lazy, on first update)
    local partyOrigY = {}
    local petOrigY = {}
    local positionsCaptured = false

    local function CapturePositions()
      if positionsCaptured then return end
      for i = 1, 4 do
        local frame = _G["PartyMemberFrame" .. i]
        if frame and frame:GetPoint(1) then
          local point, relativeTo, relPoint, x, y = frame:GetPoint(1)
          partyOrigY[i] = { point = point, relativeTo = relativeTo, relPoint = relPoint, x = x, y = y }
        end
        local petFrame = _G["PartyMemberFrame" .. i .. "PetFrame"]
        if petFrame and petFrame:GetPoint(1) then
          local point, relativeTo, relPoint, x, y = petFrame:GetPoint(1)
          petOrigY[i] = { point = point, relativeTo = relativeTo, relPoint = relPoint, x = x, y = y }
        end
      end
      positionsCaptured = true
    end

    -- Reposition party frames 2-4 and party pet frames based on second row usage
    local function RepositionPartyFrames()
      local extraRow = PARTY_ICON_SIZE + 4
      for i = 2, 4 do
        local frame = _G["PartyMemberFrame" .. i]
        local orig = partyOrigY[i]
        if frame and orig then
          local extra = 0
          if partyDisplays[i - 1] and partyDisplays[i - 1].hasSecondRow then
            extra = -extraRow
          end
          frame:ClearAllPoints()
          frame:SetPoint(orig.point, orig.relativeTo, orig.relPoint, orig.x, orig.y + extra)
        end
      end
      -- Shift party pet frames down when their party member has a second row
      for i = 1, 4 do
        local petFrame = _G["PartyMemberFrame" .. i .. "PetFrame"]
        local orig = petOrigY[i]
        if petFrame and orig then
          local extra = 0
          if partyDisplays[i] and partyDisplays[i].hasSecondRow then
            extra = -extraRow
          end
          petFrame:ClearAllPoints()
          petFrame:SetPoint(orig.point, orig.relativeTo, orig.relPoint, orig.x, orig.y + extra)
        end
      end
    end

    for i = 1, 4 do
      local frame = _G["PartyMemberFrame" .. i]
      if frame then
        partyDisplays[i] = CreateAuraDisplay(frame, MAX_BUFFS, MAX_DEBUFFS,
          PARTY_ICON_SIZE, 12, 20, PARTY_TIMER_FONT, "LEFT", false, PARTY_MAX_PER_ROW)
        table.insert(allDisplays, partyDisplays[i])
      end
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_AURA")
    ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function()
      CapturePositions()
      if event == "UNIT_AURA" then
        for i = 1, 4 do
          if arg1 == "party" .. i and partyDisplays[i] then
            UpdateDisplay(partyDisplays[i], MAX_BUFFS, MAX_DEBUFFS, "party" .. i)
            RepositionPartyFrames()
            return
          end
        end
      else
        for i = 1, 4 do
          if partyDisplays[i] then
            UpdateDisplay(partyDisplays[i], MAX_BUFFS, MAX_DEBUFFS, "party" .. i)
          end
        end
        RepositionPartyFrames()
      end
    end)
  end

  -- ===========================================================================
  -- PET FRAME: timer inside icons, wraps at 5 per row
  -- ===========================================================================
  if PetFrame then
    local petDisplay = CreateAuraDisplay(PetFrame, MAX_BUFFS, MAX_DEBUFFS,
      PARTY_ICON_SIZE, 14, 11, PARTY_TIMER_FONT, "LEFT", false, PARTY_MAX_PER_ROW)
    table.insert(allDisplays, petDisplay)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("UNIT_AURA")
    ev:RegisterEvent("UNIT_PET")
    ev:RegisterEvent("PLAYER_PET_CHANGED")
    ev:SetScript("OnEvent", function()
      if event == "UNIT_AURA" and arg1 ~= "pet" then return end
      UpdateDisplay(petDisplay, MAX_BUFFS, MAX_DEBUFFS, "pet")
    end)
  end
end
