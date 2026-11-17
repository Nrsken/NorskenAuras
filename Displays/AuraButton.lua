---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local ElementEnabled = CDM.Layer.ElementEnabled
local ConfigureText = CDM.Text.Configure
local TIME_SCALES = CDM.Text.TIME_SCALES
local TimeCurve = CDM.Text.TimeCurve

local setmetatable = setmetatable
local CreateFrame = CreateFrame
local ipairs = ipairs
local pairs = pairs

local GetSpellName = C_Spell.GetSpellName

local AuraFilters = AuraUtil.AuraFilters

-- A trigger saved before it chose a type follows its unit, as spellID matching only holds
-- for buffs on friends and debuffs on enemies
local AURA_FILTERS = { player = 'HELPFUL', target = 'HARMFUL' } ---@type table<string, string>

-- Cast by Me, the token Blizzard's own viewer filters casters with
local OWN_ONLY = { [AuraFilters.Player] = true }

-- Styling --

---The texts an aura's button leaves empty per aura trigger, see Core:DroppedAuraTexts
---@param display CDMDisplay
---@return table<table, string> dropped each text and the slot an earlier one took
function CDM:DroppedAuraTexts(display)
    -- An aura group keeps one Trigger, its branches standing in for triggers
    if display.type == 'auragroup' then
        return NRSKNUI:DroppedGroupTexts(display.SubRegions, display.Trigger)
    end

    local dropped = {}
    for index, trigger in ipairs(display.Triggers) do
        if trigger.Type == 'aura' or trigger.Type == 'auraoverlay' then
            for element, slot in pairs(NRSKNUI:DroppedAuraTexts(display.SubRegions, index)) do
                dropped[element] = slot
            end
        end
    end
    return dropped
end

-- What ApplyAuraLook reads, refilled on every pass so the hooks below find the layer in it
local look = {} ---@type CDMAuraLook

---@param pass CDMAuraLook
---@param ordinal number
---@param element NorskenCore.SubElement
---@return LuaColorCurveObject? curve
local function TimeColor(pass, ordinal, element)
    return CDM:TextColorCurve(pass.display, pass.index, TIME_SCALES, ordinal, element.Color, TimeCurve(element))
end

---@param pass CDMAuraLook
---@param ordinal number
---@return NumericRuleFormatter? formatter
local function CountFormatter(pass, ordinal)
    return CDM:StackCountFormatter(pass.display, pass.index, ordinal)
end

-- Another trigger's time or charges, fed by UpdateTexts, which only a non-aura trigger has
---@param pass CDMAuraLook
---@param entry table the text's frame
---@param fs FontString
---@param element NorskenCore.SubElement
---@param source number
---@param ordinal number
---@return boolean shown
local function SourcedText(pass, entry, fs, element, source, ordinal)
    local triggers = pass.triggers
    local sourceType = triggers and triggers[source] and CDM.TriggerTypes[triggers[source].Type]
    if not sourceType or sourceType.Secret then return false end

    local layer = pass.layer
    entry.sourced = entry.sourced or { fs = fs, kind = 'static', format = '', tokens = 0, ordinal = ordinal }
    pass.sourcedCount = pass.sourcedCount + 1
    layer.auraRefs.sourced[pass.sourcedCount] = entry.sourced
    ConfigureText(entry.sourced, element, pass.spellName, layer, triggers)
    return true
end

---Style the slot from the icon's style and sub elements, with what conditions, overlays,
---bars and chain groups change on top
---@param layer CDMLayer
---@param trigger CDMTrigger
function CDM:StyleAuraButton(layer, trigger)
    local refs = layer.auraRefs
    local style = layer.owner.style
    -- A pooled or deleted owner's button can still be handed over
    local display = layer.owner.id and self:Get(layer.owner.id)
    if not display then return end
    if not (refs and refs.button) then return end
    local button = refs.button

    -- A lone aura is the icon itself, an overlay only what its While Up conditions put on it
    local active, pandemicColor, pandemic = self:GetAuraConditionChanges(display, layer.index)
    local overlay = trigger.Type == 'auraoverlay'
    local isBar = display.type == 'bar' and not overlay
    local showIcon = active.auraIcon == true
    if not overlay then
        showIcon = self:ShowsIcon(layer, style, display)
    end

    local subRegions = layer.subRegions
    if overlay then
        local list = {}
        for n, element in ipairs(subRegions) do
            local own = element.type == 'glow' or element.type == 'text'
            ---@type NorskenCore.SubElement
            local view = setmetatable({
                Enabled = own and active['sub.' .. n .. '.visible'] == true,
                Color = active['sub.' .. n .. '.color'] or element.Color,
            }, { __index = element })
            list[n] = view
        end
        subRegions = list
    end

    local color, desaturate, swipe, reverse = style.Color, style.Desaturate, style.DrawSwipe, style.Reverse
    if overlay then
        color = active.auraColor or color
        if active.auraDesaturate ~= nil then
            desaturate = active.auraDesaturate
        end
        if active.auraSwipe ~= nil then
            swipe = active.auraSwipe
        end
        if active.auraInverse ~= nil then
            reverse = active.auraInverse
        end
    end

    local textParent = refs.inner
    if isBar then
        textParent = self:StyleAuraBar(layer, button, refs, style, trigger)
        swipe = false
        self:SetStackTicks(layer, trigger)
        self:StyleAuraTicks(layer, refs, subRegions)
    else
        self:ClearAuraBar(button, refs)
    end

    -- Texts that read another trigger drop their bindings before the pass hands them out again
    refs.sourced = refs.sourced or {}
    for i = 1, refs.sourcedCount or 0 do
        local binding = refs.sourced[i].binding
        if binding then
            binding:SetToDefaults()
        end
    end

    local spellID = self:GetTriggerSpell(trigger)
    look.style, look.subRegions = style, subRegions
    look.color, look.desaturate, look.swipe, look.reverse = color, desaturate, swipe, reverse
    look.showIcon, look.bar = showIcon, isBar
    -- An overlay shows the aura's icon unless While Up picks one, Icon Source is the base's
    look.iconTexture = overlay and active.auraTexture or (not overlay and style.IconSource == 'manual' and style.ManualIcon)
    look.timerText = self:ShowsTimerText(layer, style)
    look.pandemicColor = pandemicColor
    look.textParent = textParent
    look.spellName = spellID and GetSpellName(spellID) or ''
    look.texture = self:GetTriggerTexture(trigger)
    look.triggers, look.index, look.reader = display.Triggers, layer.index, self
    look.group = layer.isGroupButton
    look.levelOf = overlay and layer.levelOf
    look.timeColor, look.countFormatter, look.sourced = TimeColor, CountFormatter, SourcedText
    look.display, look.layer, look.sourcedCount = display, layer, 0
    local levelOf = NRSKNUI:ApplyAuraLook(refs, look)

    local sourcedCount = look.sourcedCount
    for i = sourcedCount + 1, #refs.sourced do
        refs.sourced[i] = nil
    end
    refs.sourcedCount = sourcedCount
    layer.auraSourced = sourcedCount > 0
    if sourcedCount > 0 then
        self:UpdateTexts(layer)
    end

    -- In a chain group the size comes from the style, as reading it back would be secret
    -- The chain's spacing goes on the button, elsewhere it fills what a matched bar stretches
    local inner = refs.inner
    if layer.owner.chainGroup and not layer.isGroupButton then
        button:ClearAllPoints()
        button:SetPoint('TOPLEFT', layer.aura.host, 'TOPLEFT')
        local pad = layer.owner.chainPad
        local padX, padY = pad[1], pad[2]
        inner:SetSize(style.Width, style.Height)
        button:SetSize(style.Width + padX, style.Height + padY)
    elseif not layer.isGroupButton then
        button:ClearAllPoints()
        button:SetPoint('TOPLEFT', layer.aura.host, 'TOPLEFT')
        button:SetPoint('BOTTOMRIGHT', layer.aura.host, 'BOTTOMRIGHT')
        inner:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT')
    end

    -- Glows inside the button, shown ones with the aura and pandemic ones only in its window
    local width, height = style.Width, style.Height
    local function Host()
        local host = CreateFrame('Frame', nil, button)
        host:SetAllPoints(refs.inner)
        host:SetFrameLevel(refs.borderHost:GetFrameLevel() + 1)
        return host
    end
    refs.glows = refs.glows or {}
    refs.pandemicGlows = refs.pandemicGlows or {}
    self:StyleGlows(refs.glows, Host, subRegions, width, height, ElementEnabled)
    self:StyleGlows(refs.pandemicGlows, Host, subRegions, width, height, function(index)
        return pandemic['sub.' .. index .. '.visible'] == true
    end, function(texture) button:AddPandemicRegion(texture) end)
    NRSKNUI:LevelElements(subRegions, nil, refs.glows, nil, levelOf)
    NRSKNUI:LevelElements(subRegions, nil, refs.pandemicGlows, nil, levelOf)

    if display.type == 'bar' and overlay then
        refs.barOverlay = refs.barOverlay or {}
        self:PaintBarOverlay(layer, refs.barOverlay, button, active)
    end
end

-- Slots --

-- The client shows the slot while the aura is up, so nothing secret is touched here

---Buffs or debuffs, a trigger saved before it chose follows its unit
---@param trigger CDMTrigger
---@return string base HELPFUL or HARMFUL
function CDM:GetAuraBase(trigger)
    return trigger.Base or AURA_FILTERS[trigger.Unit == 'target' and 'target' or 'player']
end

---Point a layer's aura slot at its trigger, building the display first, out of combat only
---@param layer CDMLayer
---@param trigger CDMTrigger
---@param spellIDs table<number, true>
function CDM:ConfigureAuraLayer(layer, trigger, spellIDs)
    local unit = trigger.Unit == 'target' and 'target' or 'player'

    local aura = layer.aura
    if not aura then
        aura = NRSKNUI:NewAuraDisplay(layer, {
            shape = 'slots',
            style = function(entry)
                layer.auraRefs = entry.refs
                -- The chain measures the button, which only exists once the game hands it over
                local chain = layer.owner.chainGroup
                if chain then
                    chain:WatchAuraButton(layer.owner.id, entry.refs.button)
                end
                self:StyleAuraButton(layer, layer.auraTrigger)
            end,
        })
        aura.host:SetAllPoints()
        layer.aura = aura
    end
    aura.host:SetShown(not (self.previewing and layer.owner.shown))

    -- Set before the display reads them, as SetSlot can hand a button over at once
    layer.auraTrigger = trigger
    local style = layer.owner.style
    aura:SetLayout({ width = style.Width, height = style.Height, disableMouse = true })
    aura:SetSlot(1, {
        Type = NRSKNUI.AuraTriggers.Types.AuraFilter,
        Base = self:GetAuraBase(trigger),
        branches = { { tokens = trigger.OwnOnly and OWN_ONLY or nil, candidates = { includeSpellIDs = spellIDs } } },
    })
    aura:SetUnit(unit)
    aura:Refresh()
    layer.auraRefs = aura.slots[1].refs
end

---Stop a layer's aura display, its trigger is no longer an aura or its icon is pooled
---@param layer CDMLayer
function CDM:ReleaseAuraLayer(layer)
    local aura = layer.aura
    if not aura then return end

    layer.auraKey, layer.auraConfigured = nil, nil
    aura:Release()
end
