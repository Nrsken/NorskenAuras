---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local LITERAL_PERCENT = NRSKNUI.LITERAL_PERCENT

local AbbreviateLargeNumbers = AbbreviateLargeNumbers
local BreakUpLargeNumbers = BreakUpLargeNumbers
local AbbreviateNumbers = AbbreviateNumbers
local UnitPowerPercent = UnitPowerPercent
local CurveConstants = CurveConstants
local issecretvalue = issecretvalue
local setmetatable = setmetatable
local CreateFrame = CreateFrame
local format = string.format
local strfind = string.find
local gsub = string.gsub
local unpack = unpack
local type = type

local CreateDurationTextBinding = C_DurationUtil.CreateDurationTextBinding
local GetSpellDisplayCount = C_Spell.GetSpellDisplayCount
local TruncateWhenZero = C_StringUtil.TruncateWhenZero
local GetSpellCastCount = C_Spell.GetSpellCastCount
local GetSpellCharges = C_Spell.GetSpellCharges

local BindingProperty = Enum.DurationTextBindingProperty
local PowerType = Enum.PowerType

-- Number formats for value texts, each takes a secret (LocalizationDocumentation)
local ABBREVIATORS = {
    abbreviate = AbbreviateNumbers,
    large = AbbreviateLargeNumbers,
    breakup = BreakUpLargeNumbers
}

-- A text display's text, by its alignment
local TEXT_PINS = { LEFT = 'LEFT', RIGHT = 'RIGHT', CENTER = 'CENTER', AUTO = 'CENTER' }

-- What a text's color curve checks, each with what scales its threshold to the game's value
local TIME_SCALES = { remaining = 1 }

-- Value is the max, set per curve
local powerScales = { percent = 100 }

-- One SetFormattedText argument per token, refilled on every update
local args = {}

-- The shared Duration Text curve a %p or %t text follows, nil when it keeps its own color
---@param element NorskenCore.SubElement
---@return LuaColorCurveObject?
local function TimeCurve(element)
    return element.GlobalTimeColor and NRSKNUI:GetSharedDurationColorCurve() or nil
end

-- Configure --

-- Times and power values can be secret, so only a binding or SetFormattedText shows them

---@param layer CDMLayer
---@param index number
---@return CDMIconText
local function AcquireText(layer, index)
    local text = layer.texts[index]
    if not text then
        local host = CreateFrame('Frame', nil, layer.textHost)
        host:SetAllPoints()
        text = { fs = host:CreateFontString(nil, 'OVERLAY'), host = host, kind = 'static', format = '', tokens = 0, ordinal = index } --[[@as CDMIconText]]
        layer.texts[index] = text
    end

    return text
end

-- The game only reads a percent, so a Value threshold needs a plain max
---@param text CDMIconText
---@param display CDMDisplay
---@param index number the power trigger
---@param max any
local function PowerColorCurve(text, display, index, max)
    local plain = not issecretvalue(max)
    if plain then
        text.curveMax = max
    end

    powerScales.value = plain and max and max > 0 and max or nil
    text.valueCurve = CDM:TextColorCurve(display, index, powerScales, text.ordinal, text.element.Color)
end

---@param text CDMIconText
---@param element NorskenCore.SubElement
---@param spellName string
---@param layer CDMLayer
---@param triggers CDMTrigger[]
local function ConfigureText(text, element, spellName, layer, triggers)
    text.element = element
    -- A spell trigger hides short countdowns through it
    text.fs:SetAlpha(1)
    text.usesName = strfind(element.Text, '%%n') ~= nil
    text.abbreviate, text.valueCurve, text.percent, text.colorsByValue, text.curveMax = nil, nil, nil, nil, nil
    text.colorCurve = nil

    local own = triggers[layer.index]
    local raw = NRSKNUI:ExpandText(element, spellName, own and CDM:GetTriggerTexture(own), triggers, CDM)
    local hasDuration, hasCharges, source = NRSKNUI:ClassifyText(raw)
    if source == layer.index or not (hasDuration or hasCharges) then
        source = nil
    end
    text.source = source

    -- Whose conditions can color it
    local display = text.ordinal and layer.owner.display
    local reads = triggers[source or layer.index]
    local readsType = reads and CDM.TriggerTypes[reads.Type]

    -- An Each Rune %p is that rune's recharge
    -- Anywhere else a value trigger's %p is its value and %t its max
    local perPip = element.EachPip and reads and reads.Type == 'power' and reads.Mode ~= 'bar' and layer.isBar
    if readsType and readsType.Value and not perPip and (hasDuration or hasCharges) then
        if text.binding then
            text.binding:SetToDefaults()
        end

        local mode = element.NumberFormat
        -- One count for every token or one per token
        local auto = mode == 'auto' and readsType.Decimals
        local percent = mode == 'percent' and reads.Type == 'power'
        local order = {}
        local pattern = gsub(gsub(raw, '%%', '%%%%'), '%%%%%d*%.?([pts])', function(token)
            order[#order + 1] = token
            local decimals = mode == 'decimals' and element.Decimals or (type(auto) == 'table' and auto[token] or auto)
            if percent and token == 'p' then
                decimals = 0
            end
            if token == 's' or not decimals then
                return '%s'
            end

            -- SetFormattedText takes secrets in number specs too
            return format('%%.%df', decimals)
        end)
        text.format = gsub(pattern, LITERAL_PERCENT, '%%%%')
        text.order, text.kind = order, 'value'
        text.abbreviate, text.percent = ABBREVIATORS[mode], percent

        if display and reads.Type == 'power' then
            local index = source or layer.index
            text.colorsByValue = CDM:ConditionsUse(display, index, 'value') or nil
            PowerColorCurve(text, display, index, (source and layer.owner.layers[source] or layer).max)
        end
        return
    end

    -- Another trigger's aura time stays inside its own button and a missing trigger has none
    local sourceType = source and triggers[source] and CDM.TriggerTypes[triggers[source].Type]
    if source and not (sourceType and not sourceType.Secret) then
        if text.binding then
            text.binding:SetToDefaults()
        end
        text.kind, text.source = 'static', nil
        text.fs:SetText('')
        return
    end

    if hasDuration then
        text.binding = text.binding or CreateDurationTextBinding()
        local binding = text.binding
        -- The only way to drop a color curve an earlier style set
        binding:SetToDefaults()
        binding:SetFontString(text.fs)
        binding:SetTextFormat(NRSKNUI:DurationTextFormat(raw, element))
        binding:SetZeroDurationText('')
        binding:SetExpiredText('')
        local curve = TimeCurve(element)
        if display then
            curve = CDM:TextColorCurve(display, source or layer.index, TIME_SCALES, text.ordinal, element.Color, curve)
        end
        if curve then
            binding:SetTextColorCurve(curve, BindingProperty.RemainingDuration)
        end
        text.colorCurve = curve
        binding:SetEnabled(true)
        text.kind = 'duration'
        return
    end

    if text.binding then
        text.binding:SetToDefaults()
    end

    text.hideZero = element.HideZero
    if hasCharges then
        -- Every other % is escaped, so only the %s tokens take the count
        local pattern, tokens = gsub(gsub(raw, '%%', '%%%%'), '%%%%%d*%.?s', '%%s')
        text.format, text.tokens, text.kind = gsub(pattern, LITERAL_PERCENT, '%%%%'), tokens, 'charges'
    else
        text.kind = 'static'
        text.fs:SetText((gsub(raw, LITERAL_PERCENT, '%%')))
    end
end

-- Update --

---@param from CDMLayer
---@param token string?
---@param abbreviate (fun(value: number): string)? the number format, which takes a secret
---@param percent boolean? %p as a share of the max, 0 to 100
---@return any
local function ValueOf(from, token, abbreviate, percent)
    local value
    if token == 'p' and percent then
        local powerType = from.powerType
        -- These read plain, but a real power's percent can be secret, so the game scales that one
        if powerType == CDM.MAELSTROM_WEAPON or powerType == CDM.STAGGER or powerType == PowerType.Runes then
            local max = from.max or 0
            return max > 0 and (from.value or 0) / max * 100 or 0
        end
        return UnitPowerPercent('player', powerType --[[@as Enum.PowerType]], false, CurveConstants.ScaleTo100)
    elseif token == 'p' then
        value = from.value or 0
    elseif token == 't' then
        value = from.max or 0
    else
        return token and '' or nil
    end

    if abbreviate then
        return abbreviate(value)
    end

    return value
end

---@param text CDMIconText
---@param from CDMLayer the layer whose trigger the text reads
local function UpdateText(text, from)
    if text.kind == 'duration' then
        if from.duration then
            text.binding:SetDuration(from.duration)
        end
    elseif text.kind == 'charges' then
        local hideZero = text.hideZero
        local charges = from.count
        local spellID = from.spellID
        if charges and hideZero then
            charges = TruncateWhenZero(charges)
        end
        if not charges and spellID then
            if from.state.hasCharges and hideZero then
                -- The display count is a string, so a zero only blanks from the secret number behind it
                charges = TruncateWhenZero(GetSpellCharges(spellID).currentCharges)
            elseif from.state.hasCharges then
                charges = GetSpellDisplayCount(spellID)
            else
                -- Stacks without charges like Soul Fragments count as casts, where zero reads blank
                charges = TruncateWhenZero(GetSpellCastCount(spellID))
            end
        end

        if charges then
            for i = 1, text.tokens do
                args[i] = charges
            end
            text.fs:SetFormattedText(text.format, unpack(args, 1, text.tokens))
        else
            text.fs:SetText('')
        end
    elseif text.kind == 'value' then
        local order, abbreviate, percent = text.order, text.abbreviate, text.percent
        for i = 1, #order do
            args[i] = ValueOf(from, order[i], abbreviate, percent)
        end
        text.fs:SetFormattedText(text.format, unpack(args, 1, #order))

        -- A Value condition's share moves with the max (talents), a secret max keeps the last one
        local max = from.max
        if text.colorsByValue and not issecretvalue(max) and max ~= text.curveMax then
            PowerColorCurve(text, CDM:Get(from.owner.id), from.index, max)
        end

        -- The curve takes the percent even when it's secret and gives back a usable color
        if text.valueCurve and (from.powerType == CDM.MAELSTROM_WEAPON or from.powerType == CDM.STAGGER) then
            text.fs:SetTextColor(text.valueCurve:Evaluate((from.value or 0) / (from.max or 1)):GetRGBA())
        elseif text.valueCurve and from.powerType then
            local color = UnitPowerPercent('player', from.powerType --[[@as Enum.PowerType]], false, text.valueCurve) --[[@as colorRGBA]]
            text.fs:SetTextColor(color:GetRGBA())
        end
    end
end

---Feed a layer's texts their trigger's latest timing, charges and values
---@param layer CDMLayer
function CDM:UpdateTexts(layer)
    local layers = layer.owner.layers
    for i = 1, layer.textCount do
        local text = layer.texts[i]
        UpdateText(text, text.source and layers[text.source] or layer)
    end

    local refs = layer.auraRefs
    if refs and refs.sourced then
        for i = 1, refs.sourcedCount do
            local text = refs.sourced[i]
            UpdateText(text, layers[text.source])
        end
    end

    if layer.gatedTexts then
        self:UpdateStatCopies(layer)
    end
end

-- Copies --

---A copy of a layer's text on another parent, read with another name
---@param layer CDMLayer
---@param ordinal number which of the layer's texts
---@param copy CDMIconText? the copy made last time
---@param parent Frame
---@param name string? what its %n reads, the layer's trigger name when nil
---@param triggers CDMTrigger[]? what its %N tokens read, the display's triggers when nil
---@return CDMIconText?
function CDM:StyleTextCopy(layer, ordinal, copy, parent, name, triggers)
    local own = layer.texts[ordinal]
    local element = own and own.element
    if not element then
        return copy
    end

    copy = copy or { kind = 'static', format = '', tokens = 0, ordinal = ordinal } --[[@as CDMIconText]]
    if not copy.fs then
        copy.fs = parent:CreateFontString(nil, 'OVERLAY')
    end

    local fs = copy.fs
    fs:SetFontStyle(element, element.FontSize, nil, nil, true)
    NRSKNUI:PlaceText(fs, element, layer.isBar and layer.Bar or layer, layer.isText and TEXT_PINS[element.Justify] or nil)
    fs:SetTextColor(unpack(element.Color))
    fs:SetShown(element.Enabled)

    triggers = triggers or layer.owner.display.Triggers
    ConfigureText(copy, element, name or self:GetTriggerName(triggers[layer.index]) or '', layer, triggers)
    -- It reads what it's handed, never another trigger
    copy.source = nil
    return copy
end

---Feed a text copy its values, as UpdateTexts feeds a layer's own texts
---@param copy CDMIconText
---@param from table anything with the fields a text reads (value, max, duration)
function CDM:UpdateTextCopy(copy, from)
    UpdateText(copy, from)
end

-- Live text --

---A cast's spell name for the layer's %n texts, set per cast instead of at styling
---@param layer CDMLayer
---@param name string
function CDM:SetLayerName(layer, name)
    if layer.shownName == name then return end

    layer.shownName = name
    for i = 1, layer.textCount do
        local text = layer.texts[i]
        if text.usesName then
            ConfigureText(text, text.element, name, layer, layer.owner.display.Triggers)
        end
    end
end

---A condition's Display Text on one of a layer's texts, read like the element's own
---@param layer CDMLayer
---@param text CDMIconText
---@param element NorskenCore.SubElement
---@param value string
function CDM:SetDisplayText(layer, text, element, value)
    local triggers = layer.owner.display.Triggers
    local trigger = triggers[layer.index]
    local name = layer.shownName or (trigger and self:GetTriggerName(trigger)) or ''
    ConfigureText(text, setmetatable({ Text = value }, { __index = element }), name, layer, triggers)
    if text.source then
        layer.sourced = true
    end
    UpdateText(text, text.source and layer.owner.layers[text.source] or layer)
end

-- Exports --

-- What the layer, aura button and bar pip files build their texts with
CDM.Text = {
    Acquire = AcquireText,
    Configure = ConfigureText,
    PINS = TEXT_PINS,
    TIME_SCALES = TIME_SCALES,
    TimeCurve = TimeCurve,
}
