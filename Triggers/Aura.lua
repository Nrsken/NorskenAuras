---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local TriggerTypes = CDM.TriggerTypes
local IsPreviewing = CDM.IsPreviewingLayer
local PreviewDuration = CDM.PreviewDuration
local PREVIEW_LENGTH = CDM.PREVIEW_LENGTH
local PREVIEW_PANDEMIC = CDM.PREVIEW_PANDEMIC
local QUESTION_MARK = NRSKNUI.QuestionMarkTexture
local L = NRSKNUI.Libs.AL

local CreateFrame = CreateFrame
local format = string.format
local tconcat = table.concat
local tostring = tostring
local GetTime = GetTime
local sort = table.sort
local ceil = math.ceil
local ipairs = ipairs
local unpack = unpack
local pairs = pairs
local next = next

local NewTimer = C_Timer.NewTimer

-- Stand-in --

-- A lone aura's own parts, as the preview stand-in or the placeholder
---@param layer CDMLayer
---@param display CDMDisplay
---@param style NorskenCore.IconStyle|CDMBarStyle
---@param changes table<string, any> a placeholder's While Missing changes
---@param textsShown boolean false hides texts no change shows
local function PaintStandIn(layer, display, style, changes, textsShown)
    local alpha = changes.alpha or 1

    local desaturate = changes.desaturate
    if desaturate == nil then
        desaturate = style.Desaturate
    end

    layer.Icon:SetVertexColor(unpack(changes.color or style.Color))
    layer.Icon:SetDesaturated(desaturate)
    layer.Icon:SetAlpha(alpha)
    layer.borderHost:SetAlpha(alpha)
    layer.textHost:SetAlpha(alpha)
    if layer.isBar then
        ---@cast style CDMBarStyle
        layer.Bar:SetAlpha(alpha)
        layer.Bar.bg:SetVertexColor(unpack(changes.backgroundColor or style.BackgroundColor))
    end

    local borders, texts = 0, 0
    for n, element in ipairs(display.SubRegions) do
        local visible = changes['sub.' .. n .. '.visible']
        local color = changes['sub.' .. n .. '.color'] or element.Color

        if element.type == 'border' then
            borders = borders + 1
            if visible == nil then
                visible = element.Enabled
            end
            local border = layer.borders[borders]
            border:SetShown(visible)
            for _, edge in ipairs(border.edges) do
                edge:SetColorTexture(unpack(color))
            end
        elseif element.type == 'text' then
            texts = texts + 1
            if visible == nil then
                visible = textsShown and element.Enabled
            end
            local text = layer.texts[texts]
            text.fs:SetShown(visible)
            text.fs:SetTextColor(unpack(color))
        end
    end
end

---The aura spells a trigger watches, from its Cooldown Manager entry or its own list
---@param trigger CDMTrigger
---@return table<number, true>? spellIDs
function CDM:GetAuraSpellIDs(trigger)
    local ids = {}
    if trigger.Source ~= 'custom' then
        local info = trigger.CooldownID and self.Catalogue:GetEntry(trigger.CooldownID)
        if info then
            if info.spellID then
                ids[info.spellID] = true
            end
            if info.overrideSpellID then
                ids[info.overrideSpellID] = true
            end
            for _, linked in ipairs(info.linkedSpellIDs) do
                ids[linked] = true
            end
        elseif trigger.SpellID then
            ids[trigger.SpellID] = true
        end
        -- An empty list is saved as none
    elseif trigger.SpellIDs then
        for _, spellID in ipairs(trigger.SpellIDs) do
            ids[spellID] = true
        end
    end
    if next(ids) == nil then return nil end
    return ids
end

-- What an aura slot is set up for, so an unchanged trigger skips the out of combat rebuild
---@param trigger CDMTrigger
---@param spellIDs table<number, true>
---@return string
local function AuraKey(trigger, spellIDs)
    local ids = {}
    for spellID in pairs(spellIDs) do
        ids[#ids + 1] = spellID
    end
    sort(ids)
    return tconcat(ids, ',') .. '|' .. trigger.Unit .. '|' .. tostring(trigger.OwnOnly) .. '|' .. CDM:GetAuraBase(trigger)
end

-- Trigger --

-- Secret, as we never learn the aura is up, its slot shows itself while it is
TriggerTypes.aura = {
    Secret = true,

    ---@param trigger CDMTrigger
    ---@return boolean
    IsKnown = function(trigger) return CDM:GetAuraSpellIDs(trigger) ~= nil end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        -- Switching a bar to stacks sets its cap, a save from before that read 10
        if trigger.BarMode == 'stacks' and type(trigger.MaxStacks) ~= 'number' then
            trigger.MaxStacks = 10
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        local spellIDs = CDM:GetAuraSpellIDs(trigger)
        if not spellIDs then
            CDM:ReleaseAuraLayer(layer)
            return
        end

        local key = AuraKey(trigger, spellIDs)
        layer.auraKey = key
        local function Apply()
            -- Read when it runs, as a later resolve in the same combat replaces this one
            if layer.auraKey ~= key then return end
            if layer.auraConfigured ~= key then
                CDM:ConfigureAuraLayer(layer, trigger, spellIDs)
                layer.auraConfigured = key
            end
            layer.auraTrigger = trigger -- An edit can keep the key with new settings
            layer.aura:Restyle()
        end
        -- One function per layer, as a closure per catalogue change piles up in the combat queue
        layer.applyAura = Apply
        layer.runAura = layer.runAura or function()
            local apply = layer.applyAura
            layer.applyAura = nil
            if apply then
                apply()
            end
        end
        NRSKNUI:RunWhenSafe(layer.runAura)
    end,

    -- The container only shows real auras, the preview fakes one with the layer's own parts
    ---@param layer CDMLayer
    ---@param style NorskenCore.IconStyle|CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, style, trigger)
        CDM:SetStackTicks(layer, trigger)
        local preview = IsPreviewing(layer)
        local display = layer.owner.display
        local active, pandemicColor, pandemic, missing = CDM:GetAuraConditionChanges(display, layer.index)
        local overlay = trigger.Type == 'auraoverlay'
        local showIcon = not overlay or active.auraIcon == true

        layer.Icon:SetShown(preview and showIcon and CDM:ShowsIcon(layer, style, display))
        layer.Cooldown:SetShown(preview and showIcon)
        layer.textHost:SetShown(preview)
        layer.borderHost:SetShown(preview and not overlay)
        if layer.isBar then
            layer.Bar:SetShown(preview)
        end
        if layer.aura then
            layer.aura.host:SetShown(not preview and layer.auraKey ~= nil)
        end
        if overlay and display.type == 'bar' and (preview or layer.previewOverlayShown) then
            layer.previewOverlay = layer.previewOverlay or {}
            CDM:PaintBarOverlay(layer, layer.previewOverlay, layer, preview and active or {})
            layer.previewOverlayShown = preview
        end
        if layer.previewPandemicTimer then
            layer.previewPandemicTimer:Cancel()
            layer.previewPandemicTimer = nil
        end
        if not preview then
            if layer.previewPandemic then
                layer.previewPandemic:Hide()
            end
            for _, glow in ipairs(layer.glows) do
                glow:Stop()
            end
            if trigger.Placeholder and not overlay then
                -- Under the aura button, which covers them while it's up, painted with While Missing
                CDM:SetIconTexture(layer, CDM:GetTriggerTexture(trigger))
                layer.Icon:SetShown(CDM:ShowsIcon(layer, style, display))
                PaintStandIn(layer, display, style, missing, false)
                layer.Cooldown:Clear()
                layer.borderHost:Show()
                layer.textHost:Show()
                if layer.isBar then
                    layer.Bar:SetMinMaxValues(0, 1)
                    layer.Bar:SetValue(0)
                    layer.Bar.spark:SetAlpha(0)
                    layer.Bar:Show()
                end
            end
            return
        end

        if overlay then
            layer.Icon:SetAlpha(1)
            layer.Icon:SetTexture(active.auraTexture or CDM:GetTriggerTexture(trigger) or QUESTION_MARK)
        else
            CDM:SetIconTexture(layer, CDM:GetTriggerTexture(trigger))
            PaintStandIn(layer, display, style, {}, true)
        end
        layer.duration = PreviewDuration(layer, PREVIEW_LENGTH)
        CDM:SetLayerTimer(layer, layer.duration)
        layer.Cooldown:SetShown(showIcon) -- Setting a timer shows a Cooldown frame again
        layer.count = 1
        if layer.isBar and trigger.BarMode == 'stacks' then
            -- An explicit value takes the bar off the preview timer, the timer still loops the stand-in
            local maxStacks = CDM:GetMaxStacks(layer, trigger)
            layer.count = ceil(maxStacks * 0.6)
            layer.Bar:SetMinMaxValues(0, maxStacks)
            layer.Bar:SetValue(layer.count)
            layer.Bar.spark:SetAlpha(1)
        end

        if overlay and showIcon then
            local desaturate, swipe, reverse = active.auraDesaturate, active.auraSwipe, active.auraInverse
            if desaturate == nil then
                desaturate = style.Desaturate
            end
            if swipe == nil then
                swipe = style.DrawSwipe
            end
            if reverse == nil then
                reverse = style.Reverse
            end
            layer.Icon:SetVertexColor(unpack(active.auraColor or style.Color))
            layer.Icon:SetDesaturated(desaturate)
            layer.Cooldown:SetDrawSwipe(swipe)
            layer.Cooldown:SetReverse(reverse)
        end
        CDM:UpdateTexts(layer)

        if overlay then
            local ordinal = 0
            for index, element in ipairs(display.SubRegions) do
                if element.type == 'text' then
                    ordinal = ordinal + 1
                    layer.texts[ordinal].fs:SetShown(active['sub.' .. index .. '.visible'] == true)
                end
            end
        end

        local window = PREVIEW_LENGTH * PREVIEW_PANDEMIC
        local remaining = layer.previewEnd - GetTime()
        local inWindow = remaining <= window

        -- A glow element shows as the aura would, by its own Enabled, while active or in the window
        local hasPandemicGlow = false
        for key in pairs(pandemic) do
            if key:find('%.visible$') then
                hasPandemicGlow = true
                break
            end
        end
        for index, element in ipairs(display.SubRegions) do
            if element.type == 'glow' then
                local key = 'sub.' .. index .. '.visible'
                local shown = active[key]
                if shown == nil then
                    shown = not overlay and element.Enabled
                end
                if inWindow and pandemic[key] then
                    shown = true
                end
                local glow = layer.glows[CDM:GlowOrdinal(display, index)]
                if shown then
                    glow:Start(element, style.Width, style.Height)
                else
                    glow:Stop()
                end
            end
        end
        if (pandemicColor or hasPandemicGlow) and not inWindow then
            layer.previewPandemicTimer = NewTimer(remaining - window, function()
                layer.previewPandemicTimer = nil
                CDM:UpdateLayer(layer)
            end)
        end

        local border = layer.previewPandemic
        if not pandemicColor then
            if border then
                border:Hide()
            end
            return
        end
        if not border then
            local host = CreateFrame('Frame', nil, layer)
            host:SetAllPoints()
            border = host:CreateTexture(nil, 'OVERLAY')
            border:SetTexture(NRSKNUI.AURA_OVERLAY_TEXTURE)
            border:NCSetInside(layer)
            layer.previewPandemic = border
        end
        border:GetParent():SetFrameLevel(layer:GetFrameLevel() + 2) -- Over the swipe, under the sub elements
        border:SetVertexColor(unpack(pandemicColor))
        border:SetShown(inWindow)
    end,

    IsActive = function() return false end,
}
TriggerTypes.auraoverlay = TriggerTypes.aura

---@param i number
---@param trigger CDMTrigger
---@param warnings string[]
TriggerTypes.aura.Warnings = function(i, trigger, warnings)
    if trigger.Source ~= 'custom' then
        if not (trigger.CooldownID or trigger.SpellID) then
            warnings[#warnings + 1] = format(L['Trigger %d: no aura chosen.'], i)
        end
    elseif trigger.SpellIDs then
        for _, spellID in ipairs(trigger.SpellIDs) do
            CDM:WarnUnknownSpell(warnings, i, spellID)
        end
    else
        warnings[#warnings + 1] = format(L['Trigger %d: no aura spell IDs.'], i)
    end
end

-- Conditions --

-- A lone aura is the icon, so only its pandemic, time color and placeholder look are left
-- An overlay draws nothing until While Up adds to it
CDM.ConditionChecks.aura = {
    pandemic  = { type = 'bool', secret = true },
    missing   = { type = 'bool', secret = true },
    remaining = { type = 'number', curve = true },
    stacks    = { type = 'number', curve = true },
}

CDM.ConditionChecks.auraoverlay = {
    active    = { type = 'bool', secret = true },
    pandemic  = { type = 'bool', secret = true },
    remaining = { type = 'number', curve = true },
    stacks    = { type = 'number', curve = true },
}
