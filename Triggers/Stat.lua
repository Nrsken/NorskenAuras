---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local TriggerTypes = CDM.TriggerTypes
local L = NRSKNUI.Libs.AL

local GetCombatRatingBonus = GetCombatRatingBonus
local GetMasteryEffect = GetMasteryEffect
local GetCombatRating = GetCombatRating
local GetCritChance = GetCritChance
local issecretvalue = issecretvalue
local GetAvoidance = GetAvoidance
local GetLifesteal = GetLifesteal
local setmetatable = setmetatable
local CreateFrame = CreateFrame
local format = string.format
local tconcat = table.concat
local strfind = string.find
local GetHaste = GetHaste
local GetSpeed = GetSpeed
local tostring = tostring
local ipairs = ipairs
local unpack = unpack
local pairs = pairs
local next = next
local _G = _G

local CR_VERSATILITY_DAMAGE_DONE = CR_VERSATILITY_DAMAGE_DONE

-- One rating point below another moves a gate about 10000px, well past GATE_REACH / 2
local GATE_LENGTH = 100000000
-- An open gate's clip, centred on the display's right edge, so any display fits inside
local GATE_REACH = 4000
-- Venomcursed procs push other secondaries below zero, a max under the min never fills
local RATING_FLOOR = -1000

-- Stats --

CDM.STATS = {
    { key = 'haste', name = L['Haste'], get = GetHaste, rating = 'CR_HASTE_MELEE' },
    { key = 'crit', name = L['Critical Strike'], get = GetCritChance, rating = 'CR_CRIT_MELEE' },
    {
        key = 'mastery',
        name = L['Mastery'],
        get = function()
            return (GetMasteryEffect()) -- The effect, not its coefficient
        end,
        rating = 'CR_MASTERY'
    },
    {
        key = 'versatility',
        name = L['Versatility'],
        get = function()
            return GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
        end,
        rating = 'CR_VERSATILITY_DAMAGE_DONE'
    },
    { key = 'leech', name = L['Leech'], get = GetLifesteal, rating = 'CR_LIFESTEAL' },
    { key = 'avoidance', name = L['Avoidance'], get = GetAvoidance, rating = 'CR_AVOIDANCE' },
    { key = 'speed', name = L['Speed'], get = GetSpeed, rating = 'CR_SPEED' },
    {
        key = 'highest',
        name = L['Highest Secondary'],
        gate = 'highest'
    },
    {
        key = 'lowest',
        name = L['Lowest Secondary'],
        gate = 'lowest'
    },
}
local STAT_BY_KEY = {}
for _, stat in pairs(CDM.STATS) do
    STAT_BY_KEY[stat.key] = stat
end
local SECONDARIES = {
    STAT_BY_KEY.haste,
    STAT_BY_KEY.crit,
    STAT_BY_KEY.mastery,
    STAT_BY_KEY.versatility
}

-- What PaperDollFrame refreshes its stats on
local EVENTS = {
    'COMBAT_RATING_UPDATE',
    'MASTERY_UPDATE',
    'SPEED_UPDATE',
    'LIFESTEAL_UPDATE',
    'AVOIDANCE_UPDATE',
    'PLAYER_DAMAGE_DONE_MODS',
}
local UNIT_EVENTS = {
    'UNIT_SPELL_HASTE',
    'UNIT_STATS',
    'UNIT_ATTACK_SPEED',
}

local statLayers = {} ---@type table<CDMLayer, CDMTrigger>
local ratings = {} -- Each secondary's rating, refilled on every stat event

---@param trigger CDMTrigger
---@return table
function CDM:GetStat(trigger)
    return STAT_BY_KEY[trigger.Stat]
end

-- Gates --

-- A bar is full only at value >= max, so nested clips on its fill open for the winner
---@param layer CDMLayer
---@param index number
---@return CDMStatGate
local function CreateGate(layer, index)
    local gate = { bars = {}, others = {}, source = {}, texts = {} } --[[@as CDMStatGate]]
    local parent = layer
    for other = 1, #SECONDARIES do
        if other ~= index then
            local bar = CreateFrame('StatusBar', nil, layer)
            bar:SetStatusBarTexture(NRSKNUI.WhiteTexture)
            bar:GetStatusBarTexture():SetAlpha(0)
            bar:SetSize(GATE_LENGTH, 1)
            bar:SetPoint('RIGHT', layer, 'RIGHT', GATE_REACH / 2, 0)

            local clip = CreateFrame('Frame', nil, parent)
            clip:SetClipsChildren(true)
            clip:SetSize(GATE_REACH, GATE_REACH)
            clip:SetPoint('RIGHT', bar:GetStatusBarTexture(), 'RIGHT')
            gate.root = gate.root or clip
            gate.bars[#gate.bars + 1] = bar
            gate.others[#gate.others + 1] = other
            parent = clip
        end
    end
    gate.inner = parent
    return gate
end

---@param layer CDMLayer
local function HideGates(layer)
    if layer.statGates then
        for _, gate in ipairs(layer.statGates) do
            gate.root:Hide()
        end
    end
    -- A text pool never shrinks, so every gated text is still there
    if layer.gatedTexts then
        for i in pairs(layer.gatedTexts) do
            layer.texts[i].host:SetAlpha(1)
        end
    end
    layer.gatedTexts, layer.gateSource = nil, nil
end

-- The texts on a layer reading the stat layer, all its own, a %N.n, %N.p or %N.t elsewhere
---@param layer CDMLayer
---@param statLayer CDMLayer
---@return table<number, true>?
local function GatedTexts(layer, statLayer)
    local pattern = '%%' .. statLayer.index .. '%.[npt]'
    local gated
    for i = 1, layer.textCount do
        if layer == statLayer or strfind(layer.texts[i].element.Text, pattern) then
            gated = gated or {}
            gated[i] = true
        end
    end
    return gated
end

-- The gated texts and the stat's bar fill copied into one gate per secondary
-- The originals stay, invisible, as the display's size
---@param layer CDMLayer
---@param statLayer CDMLayer
---@param gated table<number, true>
local function StyleGates(layer, statLayer, gated)
    layer.statGates = layer.statGates or {}
    layer.gatedTexts, layer.gateSource = gated, statLayer
    -- A fitting text display must never measure the huge comparison bars
    layer:SetIgnoringChildrenForBounds(true)
    -- The host, so a spell trigger's countdown alpha can't bring it back
    for i in pairs(gated) do
        layer.texts[i].host:SetAlpha(0)
    end
    local style = layer.owner.style
    local triggers = layer.owner.display.Triggers
    for index, stat in ipairs(SECONDARIES) do
        local gate = layer.statGates[index] or CreateGate(layer, index)
        layer.statGates[index] = gate
        gate.root:Show()
        -- The copies see the stat trigger as this gate's stat, so %n, %N.n and %N.p all read it
        local asStat = setmetatable({ [statLayer.index] = { Type = 'stat', Stat = stat.key } }, { __index = triggers })
        for _, copy in pairs(gate.texts) do
            copy.fs:Hide()
        end
        for i in pairs(gated) do
            local copy = CDM:StyleTextCopy(layer, i, gate.texts[i], gate.inner, layer == statLayer and stat.name or nil, asStat)
            gate.texts[i] = copy
            if copy then
                -- A condition's Visible stays on the original between changes
                copy.fs:SetShown(layer.texts[i].fs:IsShown())
            end
        end

        if layer == statLayer and layer.isBar then
            local fill = gate.fill or CreateFrame('StatusBar', nil, gate.inner)
            gate.fill = fill
            fill:SetAllPoints(layer.Bar)
            fill:SetFrameLevel(layer.Bar:GetFrameLevel() + 1)
            fill:SetStatusBarTexture(NRSKNUI:GetStatusbar(style))
            fill:SetOrientation(style.Orientation == 'VERTICAL' and 'VERTICAL' or 'HORIZONTAL')
            fill:SetReverseFill(style.ReverseFill)

            local color = layer.barColor or style.BarColor
            fill:SetStatusBarColor(unpack(color))
            fill:SetMinMaxValues(0, 100)
            fill:Show()
        elseif gate.fill then
            gate.fill:Hide()
        end
    end
end

-- The ratings read once for every reader's gates, the stat layer's texts run in its Update
---@param statLayer CDMLayer
---@param lowest boolean
local function UpdateGates(statLayer, lowest)
    for index, stat in ipairs(SECONDARIES) do
        ratings[index] = GetCombatRating(_G[stat.rating])
    end

    for _, layer in ipairs(statLayer.gateReaders) do
        for index, gate in ipairs(layer.statGates) do
            for i, bar in ipairs(gate.bars) do
                local other = ratings[gate.others[i]]
                if lowest then
                    bar:SetMinMaxValues(RATING_FLOOR, ratings[index])
                    bar:SetValue(other)
                else
                    bar:SetMinMaxValues(RATING_FLOOR, other)
                    bar:SetValue(ratings[index])
                end
            end
            gate.source.value = SECONDARIES[index].get()
            gate.source.max = ratings[index]
        end

        if layer ~= statLayer then
            CDM:UpdateTexts(layer)
        end
    end
end

---Feed a layer's gate copies after its own texts, each reading what its original does
---@param layer CDMLayer
function CDM:UpdateStatCopies(layer)
    local statIndex = layer.gateSource.index
    local layers = layer.owner.layers

    for _, gate in ipairs(layer.statGates) do
        for i in pairs(layer.gatedTexts) do
            local reads = layer.texts[i].source or layer.index
            local copy = gate.texts[i]

            if copy then
                self:UpdateTextCopy(copy, reads == statIndex and gate.source or layers[reads])
            end
        end

        if gate.fill then
            gate.fill:SetValue(gate.source.value)
        end
    end
end

-- Trigger --

-- One secondary or the highest or lowest, %p its percent, %t its rating
-- Ratings are secret in combat, so the game picks the winner and only its text is revealed
TriggerTypes.stat = {
    Value = true,
    -- Rounded as the character sheet does (PaperDollFrame_SetLabelAndText)
    Decimals = 0,

    IsKnown = function() return true end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        if not STAT_BY_KEY[trigger.Stat] then
            trigger.Stat = nil
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        layer.spellID, layer.baseSpellID = nil, nil
        statLayers[layer] = trigger
        CDM:SetIconTexture(layer, nil)
        layer.gateReaders = nil
        if not CDM:GetStat(trigger).gate then return end
        local readers = {}
        for i, other in ipairs(layer.owner.display.Triggers) do
            local reader = layer.owner.layers[i]
            local gated = GatedTexts(reader, layer)
            local ownGates = other.Type == 'stat' and CDM:GetStat(other).gate
            local auraTexts = TriggerTypes[other.Type].Secret -- Drawn inside its aura button
            -- A layer reads one Highest or Lowest trigger, the first
            if reader == layer or (gated and not ownGates and not auraTexts and not reader.gateSource) then
                StyleGates(reader, layer, gated or {})
                readers[#readers + 1] = reader
            end
        end
        layer.gateReaders = readers
    end,

    ---@param layer CDMLayer
    ---@param style NorskenCore.IconStyle|CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, style, trigger)
        local stat = CDM:GetStat(trigger)
        if stat.gate then
            UpdateGates(layer, stat.gate == 'lowest')
            -- Resolve gave the stat layer its own gates
            local first = layer.statGates[1]
            layer.value, layer.max = first.source.value, first.source.max
            CDM:SetLayerValue(layer, 0, 100)
            CDM:UpdateTexts(layer)
            return
        end
        layer.value = stat.get()
        layer.max = GetCombatRating(_G[stat.rating])
        CDM:SetLayerValue(layer, layer.value, 100)
        CDM:UpdateTexts(layer)
    end,

    IsActive = function() return true end,

    ---@param id string
    Unwatch = function(id)
        for layer in pairs(statLayers) do
            if layer.owner.id == id then
                -- A pooled frame may come back with other triggers
                if layer.gateReaders then
                    for _, reader in ipairs(layer.gateReaders) do
                        HideGates(reader)
                    end
                end
                HideGates(layer)
                layer.gateReaders = nil
                statLayers[layer] = nil
            end
        end
    end,
}

-- Debug --

---@param value any
---@return string
local function Plain(value)
    return issecretvalue(value) and 'secret' or format('%.2f', value)
end

---The debug report's gates, each comparison and whether its clip reaches the display
---@param lines string[]
---@param layer CDMLayer
TriggerTypes.stat.DebugLines = function(lines, layer)
    -- Only a Highest or Lowest trigger has gates
    if not layer.gateReaders then return end

    for _, reader in ipairs(layer.gateReaders) do
        lines[#lines + 1] = format('  Gates on trigger %d', reader.index)
        local first = next(reader.gatedTexts)
        for index, gate in ipairs(reader.statGates) do
            local bars = {}
            for i, bar in ipairs(gate.bars) do
                local _, max = bar:GetMinMaxValues()
                bars[i] = format('%s %s/%s', SECONDARIES[gate.others[i]].key, Plain(bar:GetValue()), Plain(max))
            end
            local valid, clip = true, gate.inner
            while clip ~= reader do
                valid = valid and clip:IsRectValid()
                clip = clip:GetParent()
            end
            local edge, right = gate.inner:GetRight(), reader:GetRight()
            local fs = first and gate.texts[first] and gate.texts[first].fs
            local text = fs and fs:GetText()
            lines[#lines + 1] = format('    Gate %s: root %s, visible %s, rects %s, clip edge %s, text %s, vs %s', SECONDARIES[index].key,
                gate.root:IsShown() and 'shown' or 'hidden', gate.inner:IsVisible() and 'yes' or 'no', valid and 'valid' or 'INVALID',
                (issecretvalue(edge) or issecretvalue(right)) and 'secret' or (edge and right) and Plain(edge - right) or '-',
                fs and (issecretvalue(text) and 'secret' or format('"%s" alpha %.2f', tostring(text), fs:GetAlpha())) or 'none',
                tconcat(bars, ', '))
        end
    end
end

---@param trigger CDMTrigger
---@return string name
TriggerTypes.stat.Name = function(trigger)
    return CDM:GetStat(trigger).name
end

-- Events --

local eventFrame ---@type Frame?

local function OnStatEvent()
    local statTrigger = TriggerTypes.stat
    for layer, trigger in pairs(statLayers) do
        if layer.owner.shown then
            statTrigger.Update(layer, layer.owner.style, trigger)
        end
    end
end

TriggerTypes.stat.RegisterEvents = function()
    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnStatEvent)
    end

    for _, event in pairs(EVENTS) do
        eventFrame:RegisterEvent(event)
    end
    for _, event in pairs(UNIT_EVENTS) do
        eventFrame:RegisterUnitEvent(event, 'player')
    end
end

TriggerTypes.stat.UnregisterEvents = function()
    eventFrame:UnregisterAllEvents()
end

-- Conditions --

-- Its value is secret in combat, so nothing compares it
CDM.ConditionChecks.stat = {
    active = { type = 'bool', get = function() return true end },
}
