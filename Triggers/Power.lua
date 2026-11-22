---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local TriggerTypes = CDM.TriggerTypes
local L = NRSKNUI.Libs.AL

local GetPowerRegenForPowerType = GetPowerRegenForPowerType
local GetUnitChargedPowerPoints = GetUnitChargedPowerPoints
local UnitPowerDisplayMod = UnitPowerDisplayMod
local GetSpecialization = GetSpecialization
local UnitPartialPower = UnitPartialPower
local UnitPowerMissing = UnitPowerMissing
local UnitPowerPercent = UnitPowerPercent
local GetRuneCooldown = GetRuneCooldown
local issecretvalue = issecretvalue
local UnitHealthMax = UnitHealthMax
local UnitPowerType = UnitPowerType
local UnitPowerMax = UnitPowerMax
local CreateFrame = CreateFrame
local tContains = tContains
local UnitPower = UnitPower
local huge = math.huge
local GetTime = GetTime
local ipairs = ipairs
local select = select
local pairs = pairs

-- Plain for the player under every restriction (probed), the stub has no player exemption
local UnitStagger = UnitStagger --[[@as fun(unit: 'player'): number]]

local GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
local IsSpellKnown = C_SpellBook.IsSpellKnown
local NewTimer = C_Timer.NewTimer

local PowerType = Enum.PowerType

local powerLayers = {} ---@type table<CDMLayer, CDMTrigger>

-- Power types --

-- Enhancement's Maelstrom Weapon is a buff's stacks that reads plain in combat
local MAELSTROM_WEAPON = 'maelstromWeapon'
local MAELSTROM_WEAPON_AURA = 344179
local RAGING_MAELSTROM = 384143

-- Brewmaster Stagger against max health, as Blizzard's bar draws it
local STAGGER = 'stagger'
local STAGGER_MODERATE, STAGGER_HEAVY = 0.3, 0.6 -- STAGGER_STATES in MonkStaggerBar.lua, live

-- These change with UNIT_AURA, never UNIT_POWER_*
local AURA_POWER = {
    [MAELSTROM_WEAPON] = true,
    [STAGGER] = true,
}

-- What a power trigger can follow, 'primary' is whatever the current form or spec uses
CDM.POWER_TYPES = {
    { value = 'primary',               text = L['Primary Power'] },
    { value = PowerType.Mana,          text = L['Mana'] },
    { value = PowerType.Rage,          text = L['Rage'] },
    { value = PowerType.Focus,         text = L['Focus'] },
    { value = PowerType.Energy,        text = L['Energy'] },
    { value = PowerType.RunicPower,    text = L['Runic Power'] },
    { value = PowerType.LunarPower,    text = L['Astral Power'] },
    { value = PowerType.Maelstrom,     text = L['Maelstrom'] },
    { value = MAELSTROM_WEAPON,        text = L['Maelstrom Weapon'] },
    { value = PowerType.Insanity,      text = L['Insanity'] },
    { value = PowerType.Fury,          text = L['Fury'] },
    { value = PowerType.ComboPoints,   text = L['Combo Points'] },
    { value = PowerType.HolyPower,     text = L['Holy Power'] },
    { value = PowerType.SoulShards,    text = L['Soul Shards'] },
    { value = PowerType.Chi,           text = L['Chi'] },
    { value = PowerType.ArcaneCharges, text = L['Arcane Charges'] },
    { value = PowerType.Essence,       text = L['Essence'] },
    { value = PowerType.Runes,         text = L['Runes'] },
    { value = STAGGER,                 text = L['Stagger'] },
}

-- Counted in whole points, split by Automatic ticks, a pip each in Static or Progress
CDM.SEGMENTED_POWER = {
    [PowerType.ComboPoints] = true,
    [PowerType.HolyPower] = true,
    [PowerType.SoulShards] = true,
    [PowerType.Chi] = true,
    [PowerType.ArcaneCharges] = true,
    [PowerType.Essence] = true,
    [PowerType.Runes] = true,
    [MAELSTROM_WEAPON] = true,
}
local SEGMENTED_POWER = CDM.SEGMENTED_POWER

-- What a Resource Bar follows, every spec of these classes shares one, the rest go by spec
local CLASS_RESOURCES = {
    DEATHKNIGHT = PowerType.Runes,
    PALADIN = PowerType.HolyPower,
    ROGUE = PowerType.ComboPoints,
    WARLOCK = PowerType.SoulShards,
    EVOKER = PowerType.Essence,
}
local SPEC_RESOURCES = {
    [62] = PowerType.ArcaneCharges, -- Arcane
    [103] = PowerType.ComboPoints, -- Feral
    [263] = MAELSTROM_WEAPON, -- Enhancement
    [268] = STAGGER, -- Brewmaster
    [269] = PowerType.Chi, -- Windwalker
}

---@return number|string resource a power type or a named one, 'primary' when there's nothing else
function CDM:GetSpecResource()
    return SPEC_RESOURCES[NRSKNUI.MySpec.id] or CLASS_RESOURCES[NRSKNUI.MyClass] or 'primary'
end

-- Points that can be supercharged, as Blizzard's combo point and Essence bars draw them
CDM.CHARGED_POWER = {
    [PowerType.ComboPoints] = true,
    [PowerType.Essence] = true,
}

-- One of each, for Each Rune and the like
CDM.PIP_NAMES = {
    [PowerType.ComboPoints] = L['Combo Point'],
    [PowerType.HolyPower] = L['Holy Power'],
    [PowerType.SoulShards] = L['Soul Shard'],
    [PowerType.Chi] = L['Chi'],
    [PowerType.ArcaneCharges] = L['Arcane Charge'],
    [PowerType.Essence] = L['Essence'],
    [PowerType.Runes] = L['Rune'],
    [MAELSTROM_WEAPON] = L['Stack'],
}

local POWER_NAMES = {}
for _, entry in ipairs(CDM.POWER_TYPES) do
    POWER_NAMES[entry.value] = entry.text
end

---@return number stacks, number max 10 with Raging Maelstrom, else 5
local function MaelstromWeapon()
    local aura = GetPlayerAuraBySpellID(MAELSTROM_WEAPON_AURA)
    return aura and aura.applications or 0, IsSpellKnown(RAGING_MAELSTROM) and 10 or 5
end

-- Split bars --

local runeOrder, runeRemaining = {}, {}
local RUNE_START_SLACK = 0.1 -- So a rune spent this frame never reads as queued

-- Runes ready first, then by time left (RuneFrame.lua), rune timings are never secret
---@return number[]
local function SortedRunes()
    local now = GetTime()
    for i = 1, 6 do
        local start, duration, ready = GetRuneCooldown(i)
        runeOrder[i] = i
        -- A rune waiting its turn has no start yet, so it sorts after every running one
        local remaining = start and duration and duration > 0 and start + duration - now or huge
        -- One that ran out isn't ready until RUNE_POWER_UPDATE, so it can't sort ahead of ready ones
        runeRemaining[i] = ready and -1 or remaining > 0 and remaining or 0
    end

    for i = 2, 6 do
        local key, j = runeOrder[i], i - 1
        while j > 0 and runeRemaining[runeOrder[j]] > runeRemaining[key] do
            runeOrder[j + 1] = runeOrder[j]
            j = j - 1
        end
        runeOrder[j + 1] = key
    end
    return runeOrder
end

local PROGRESS_HOLD = 0.3 -- Longest a filled progress pip waits for the power its swing grants
local SECRET_MAX_PIPS = 5 -- A split bar's pips while the resource's maximum reads secret
-- Points a second, the last plain rate, first Blizzard's fallback (EssenceFramePlayer.lua)
local essenceRate = 0.2

-- The filling Essence's start and length (EssenceFramePlayer.lua)
---@return number? start, number? length
local function EssenceFill()
    local partial = UnitPartialPower('player', PowerType.Essence)
    local rate = GetPowerRegenForPowerType(PowerType.Essence)
    if rate and not issecretvalue(rate) and rate > 0 then
        essenceRate = rate
    end
    if issecretvalue(partial) then return nil end

    local length = 1 / essenceRate
    return GetTime() - partial / 1000 * length, length
end

-- Every pip of a split bar, a point pip gets an N-1 to N range fed the whole value
-- So the widget does the compare and a secret count still draws
---@param layer CDMLayer
---@param trigger CDMTrigger
local function UpdatePips(layer, trigger)
    local powerType, count, state = layer.powerType --[[@as Enum.PowerType]], layer.pipCount --[[@as number]], layer.state
    local progress = trigger.Mode == 'progress'
    state.recharging, state.waiting, state.charged = false, false, false
    layer.duration = nil

    if powerType == PowerType.Runes then
        local order, ready, now = SortedRunes(), 0, GetTime()
        for n = 1, count do
            local rune = order[n]
            local start, duration, isReady = GetRuneCooldown(rune)
            if isReady then
                ready = ready + 1
            end
            CDM:SetLayerPipSlot(layer, rune, n)
            local running = not isReady and start and duration and duration > 0
            -- Three runes regenerate at once, a queued one reports the start of its turn, still ahead
            local waiting = not isReady and not (running and start <= now + RUNE_START_SLACK)
            layer.pips[rune].waiting = waiting
            state.waiting = state.waiting or waiting
            if progress and running then
                CDM:SetLayerPipTimer(layer, rune, start, duration)
            else
                CDM:SetLayerPipValue(layer, rune, isReady and 1 or 0, 1, 0, not isReady, running and start or nil, running and duration or nil)
            end
            state.recharging = state.recharging or not isReady
        end
        layer.value, layer.max = ready, count
        return
    end

    if powerType == MAELSTROM_WEAPON then
        local stacks, max = MaelstromWeapon()
        for n = 1, count do
            CDM:SetLayerPipValue(layer, n, stacks, n, n - 1, false)
        end
        layer.value, layer.max = stacks, max
        return
    end

    -- Soul Shards move in tenths, so Progress scales the range for a partial shard to fill
    local mod = progress and UnitPowerDisplayMod(powerType) or 1
    if mod <= 0 then
        mod = 1
    end
    local value = UnitPower('player', powerType, progress)
    -- The player's charged points read plain in combat, as UnitPower does (probed)
    local charged = layer.readsCharged and GetUnitChargedPowerPoints('player')
    for n = 1, count do
        CDM:SetLayerPipValue(layer, n, value, n * mod, (n - 1) * mod, false)
        local isCharged = charged and tContains(charged, n) or false
        layer.pips[n].charged = isCharged
        state.charged = state.charged or isCharged
    end

    local current, max = UnitPower('player', powerType), UnitPowerMax('player', powerType)
    layer.value, layer.max = current, max
    if not progress then return end

    -- The next point's pip, which Essence and a progress source fill
    local filling = not issecretvalue(current) and not issecretvalue(max)
        and current < max and current < count and current + 1 or nil
    if filling and powerType == PowerType.Essence then
        local start, length = EssenceFill()
        if start then
            CDM:SetLayerPipTimer(layer, filling, start, length)
            state.recharging = true
        end
    end

    if trigger.ProgressCooldownID then
        layer.viewerHold = filling == nil
        local running = CDM:MirrorViewerBar(layer)
        -- The tracked bar ends a little before the power it grants, so the fill holds until then
        local held = false
        if running then
            layer.progressPip, layer.progressHoldEnd = filling, nil
        elseif filling and layer.progressPip == filling then
            local now = GetTime()
            if not layer.progressHoldEnd then
                layer.progressHoldEnd = now + PROGRESS_HOLD
                if layer.progressHoldTimer then
                    layer.progressHoldTimer:Cancel()
                end
                layer.progressHoldTimer = NewTimer(PROGRESS_HOLD, function()
                    layer.progressHoldTimer = nil
                    CDM:UpdateLayer(layer)
                end)
            end
            held = now < layer.progressHoldEnd
            if held then
                local source = CDM:GetLayerProgress(layer)
                source:SetValue((source:GetMinMaxValues()))
            else
                layer.progressPip = nil
            end
        else
            layer.progressPip, layer.progressHoldEnd = nil, nil
        end
        local shown = filling ~= nil and (running or held)
        if shown then
            layer.pips[filling].recharging = true
        end
        CDM:ShowLayerProgress(layer, shown, filling and layer.pips[filling] or nil)
        state.recharging = state.recharging or shown
    end
end

-- Trigger --

TriggerTypes.power = {
    Value = true, -- %p is the value and %t the max, not a time
    IsKnown = function() return true end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        if not POWER_NAMES[trigger.PowerType] then
            trigger.PowerType = 'primary'
        end
        if not CDM.IsChoice(CDM.POWER_MODES, trigger.Mode) then
            trigger.Mode = nil
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        local powerType = trigger.PowerType
        if powerType == 'primary' then
            powerType = UnitPowerType('player')
        end
        layer.powerType = powerType
        layer.spellID, layer.baseSpellID = nil, nil
        layer.staggerBand = nil
        powerLayers[layer] = trigger
        -- Only a Supercharged check reads the charged points, so nothing else pays for the table
        layer.readsCharged = CDM.CHARGED_POWER[powerType] and CDM:ConditionsUse(layer.owner.display, layer.index, 'charged') or nil
        if powerType == MAELSTROM_WEAPON then
            layer.max = select(2, MaelstromWeapon())
        elseif powerType == STAGGER then
            layer.max = UnitHealthMax('player')
        else
            ---@cast powerType Enum.PowerType
            layer.max = UnitPowerMax('player', powerType)
        end

        -- A split bar's pips and its progress source
        local plainMax = not issecretvalue(layer.max)
        local split = layer.isBar and trigger.Mode ~= 'bar' and SEGMENTED_POWER[powerType] == true
        if split then
            CDM:SetLayerPips(layer, powerType == PowerType.Runes and 6 or plainMax and layer.max or SECRET_MAX_PIPS)
        end
        if split and trigger.Mode == 'progress' and trigger.ProgressCooldownID then
            CDM:WatchViewerBar(layer, trigger.ProgressCooldownID, CDM:GetLayerProgress(layer))
        else
            CDM:ShowLayerProgress(layer, false)
        end

        -- Automatic ticks between whole points
        local ticks
        local segments = split and layer.pipCount or SEGMENTED_POWER[powerType] and plainMax and layer.max or 0
        if segments > 1 then
            ticks = {}
            for i = 1, segments - 1 do
                ticks[i] = i / segments
            end
        end
        layer.autoTicks = ticks
        CDM:DrawTicks(layer)

        -- Power Color from the unit frames' palette, runes by spec, Stagger by band in Update
        CDM:SetIconTexture(layer, nil)
        local specIndex = GetSpecialization()
        if layer.owner.style.BarColorMode == 'power' and powerType ~= STAGGER then
            local runeColor = powerType == PowerType.Runes and specIndex and NRSKNUI.Colors.runes[specIndex]
            local maelstromColor = NRSKNUI.Colors.power[powerType == MAELSTROM_WEAPON and PowerType.Maelstrom]
            local powerColor = NRSKNUI.Colors.power[powerType]
            local color = runeColor or maelstromColor or powerColor
            if color then
                CDM:PaintBar(layer, { color:GetRGB() })
            end
        end
    end,

    ---@param layer CDMLayer
    ---@param style NorskenCore.IconStyle|CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, style, trigger)
        local powerType = layer.powerType
        if layer.pipCount > 0 then
            UpdatePips(layer, trigger)
            CDM:UpdateTexts(layer)
            return
        end

        if powerType == PowerType.Runes then
            -- Runes never fire UNIT_POWER_*, each reports its own cooldown (RuneFrame.lua)
            local ready = 0
            for i = 1, layer.max do
                if select(3, GetRuneCooldown(i)) then
                    ready = ready + 1
                end
            end
            layer.value = ready

            local fill = style.Inverse and layer.max - ready or ready
            local sparkAlpha = (fill > 0 and fill < layer.max) and 1 or 0

            CDM:SetLayerValue(layer, fill, layer.max, sparkAlpha)
            CDM:UpdateTexts(layer)
            return
        end

        if powerType == MAELSTROM_WEAPON then
            local stacks, max = MaelstromWeapon()
            layer.value = stacks
            layer.max = max

            local fill = style.Inverse and max - stacks or stacks
            local sparkAlpha = (fill > 0 and fill < max) and 1 or 0

            CDM:SetLayerValue(layer, fill, max, sparkAlpha)
            CDM:UpdateTexts(layer)
            return
        end

        if powerType == STAGGER then
            local stagger = UnitStagger('player')
            local maxHealth = UnitHealthMax('player')
            layer.value = stagger
            layer.max = maxHealth

            local fill = style.Inverse and maxHealth - stagger or stagger
            local sparkAlpha = (fill > 0 and fill < maxHealth) and 1 or 0

            CDM:SetLayerValue(layer, fill, maxHealth, sparkAlpha)

            -- Light, moderate or heavy, painted again only when the band changes
            local share = maxHealth > 0 and stagger / maxHealth or 0
            local band = share >= STAGGER_HEAVY and 3 or share >= STAGGER_MODERATE and 2 or 1
            if style.BarColorMode == 'power' and band ~= layer.staggerBand then
                layer.staggerBand = band
                CDM:PaintBar(layer, { NRSKNUI.Colors.stagger[band]:GetRGB() })
            end

            CDM:UpdateTexts(layer)
            return
        end

        ---@cast powerType Enum.PowerType
        layer.value = UnitPower('player', powerType)
        layer.max = UnitPowerMax('player', powerType)

        local fill = style.Inverse and UnitPowerMissing('player', powerType) or layer.value
        local sparkAlpha = UnitPowerPercent('player', powerType, false, NRSKNUI.curves.BarSparkAlpha) --[[@as number]]

        CDM:SetLayerValue(layer, fill, layer.max, sparkAlpha)
        CDM:UpdateTexts(layer)
    end,

    IsActive = function() return true end,
}

---@param trigger CDMTrigger
---@return string? name
TriggerTypes.power.Name = function(trigger)
    return POWER_NAMES[trigger.PowerType]
end

---@param id string
TriggerTypes.power.Unwatch = function(id)
    for layer in pairs(powerLayers) do
        if layer.owner.id == id then
            powerLayers[layer] = nil
        end
    end
end

-- Events --

local powerFrame ---@type Frame?

-- A plain tick only moves the bar and its texts
-- Recharging and Maelstrom Weapon's Stacks feed conditions, so those run them too
local function OnPowerEvent(_, event)
    local powerTrigger = TriggerTypes.power
    local aura = event == 'UNIT_AURA'

    for layer, trigger in pairs(powerLayers) do
        if layer.owner.shown and (AURA_POWER[layer.powerType] == true) == aura then
            -- A new max or display power can change the pips, ticks and Power Color
            if event ~= 'UNIT_POWER_FREQUENT' and event ~= 'RUNE_POWER_UPDATE' and event ~= 'UNIT_POWER_POINT_CHARGE' and not aura then
                powerTrigger.Resolve(layer, trigger)
            end
            if layer.pipCount > 0 or layer.powerType == MAELSTROM_WEAPON then
                CDM:UpdateLayer(layer)
            else
                powerTrigger.Update(layer, layer.owner.style, trigger)
            end
        end
    end
end

local POWER_EVENTS = {
    'UNIT_POWER_FREQUENT',
    'UNIT_MAXPOWER',
    'UNIT_DISPLAYPOWER',
    'UNIT_POWER_POINT_CHARGE',
    'UNIT_AURA',
}

TriggerTypes.power.RegisterEvents = function()
    if not powerFrame then
        powerFrame = CreateFrame('Frame')
        powerFrame:SetScript('OnEvent', OnPowerEvent)
    end

    for _, event in ipairs(POWER_EVENTS) do
        powerFrame:RegisterUnitEvent(event, 'player')
    end
    powerFrame:RegisterEvent('RUNE_POWER_UPDATE')
end

TriggerTypes.power.UnregisterEvents = function()
    powerFrame:UnregisterAllEvents()
end

-- Conditions --

-- The value can be secret, so only a %p text's curve compares it
-- Recharging and Supercharged are plain, Stacks only Maelstrom Weapon's
CDM.ConditionChecks.power = {
    active     = { type = 'bool', get = TriggerTypes.power.IsActive },
    stacks     = { type = 'number', get = function(layer) return layer.powerType == MAELSTROM_WEAPON and layer.value or 0 end },
    percent    = { type = 'number', curve = true },
    value      = { type = 'number', curve = true }, -- A percent of the max, so it waits for a plain max
    recharging = {
        type = 'bool',
        get = function(layer, _, pip)
            if pip then
                return pip.recharging == true
            end
            return layer.state.recharging == true
        end,
    },
    waiting    = {
        type = 'bool',
        get = function(layer, _, pip)
            if pip then
                return pip.waiting == true
            end
            return layer.state.waiting == true
        end,
    },
    charged    = {
        type = 'bool',
        get = function(layer, _, pip)
            if pip then
                return pip.charged == true
            end
            return layer.state.charged == true
        end,
    },
}

-- Exports --

CDM.MAELSTROM_WEAPON = MAELSTROM_WEAPON
CDM.STAGGER = STAGGER
CDM.POWER_NAMES = POWER_NAMES
