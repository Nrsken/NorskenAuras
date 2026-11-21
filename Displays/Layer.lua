---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local ConfigureText = CDM.Text.Configure
local AcquireText = CDM.Text.Acquire
local TEXT_PINS = CDM.Text.PINS

local CreateObjectPool = CreateObjectPool
local CreateFrame = CreateFrame
local sort = table.sort
local ipairs = ipairs
local unpack = unpack
local min = math.min

local GameTooltip = GameTooltip

-- A glow's level above its layer
CDM.GLOW_LEVEL = 3

-- An overlay's layer, aura host, container, button, swipe and pandemic border
local OVERLAY_LEVELS = 6

-- Pool --

---@param layer CDMLayer
local function OnCooldownDone(layer)
    layer.heldGCD = nil
    layer.timerDone = true
    CDM:UpdateLayer(layer)
    layer.timerDone = nil
end

---@param frame CDMIcon
local function OnEnter(frame)
    local layer = frame.activeLayer
    local spellID = layer and (layer.spellID or layer.viewerSpellID)
    -- The mouse is only on with Tooltip
    if not (layer and (spellID or layer.itemID)) then return end
    GameTooltip:SetOwner(frame, 'ANCHOR_RIGHT')
    if spellID then
        GameTooltip:SetSpellByID(spellID)
    else
        GameTooltip:SetItemByID(layer.itemID)
    end
    GameTooltip:Show()
end

---@param frame CDMIcon
---@return CDMLayer
local function CreateLayer(frame)
    local layer = CreateFrame('Frame', nil, frame) --[[@as CDMLayer]]
    layer:SetAllPoints()
    layer.owner = frame

    local icon = layer:CreateTexture(nil, 'ARTWORK')
    icon:SetAllPoints()
    icon:NCDisablePixelSnap()
    layer.Icon = icon

    local cooldown = CreateFrame('Cooldown', nil, layer, 'CooldownFrameTemplate')
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawBling(false)
    cooldown:SetScript('OnCooldownDone', function() OnCooldownDone(layer) end)
    layer.Cooldown = cooldown

    local textHost = CreateFrame('Frame', nil, layer)
    textHost:SetAllPoints()
    layer.textHost = textHost

    local borderHost = CreateFrame('Frame', nil, layer)
    borderHost:SetAllPoints()
    layer.borderHost = borderHost

    layer.texts = {}
    layer.textCount = 0
    layer.borders = {}
    layer.glows = {}
    layer.state = {}
    layer.pipCount = 0
    layer.pips = {}
    layer.pipEdges = {}
    layer.tickSets = {}
    layer.subRegions = {}
    return layer
end

---@return CDMIcon
local function CreateIcon()
    local frame = CreateFrame('Frame', nil, UIParent) --[[@as CDMIcon]]
    frame:Hide()

    frame.layers = {}
    frame.layerCount = 0
    frame:SetScript('OnEnter', OnEnter)
    frame:SetScript('OnLeave', GameTooltip_Hide)

    return frame
end

---@param frame CDMIcon
local function ResetIcon(_, frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    for _, layer in ipairs(frame.layers) do
        CDM:SetLayerTimer(layer, nil)
        layer.duration = nil
        layer.state = {}
        layer.realCooldown, layer.heldGCD = nil, nil
        layer.timerEnd = nil
        layer.previewEnd = nil
        if layer.previewTimer then
            layer.previewTimer:Cancel()
            layer.previewTimer = nil
        end
        if layer.timerTicker then
            layer.timerTicker:Cancel()
            layer.timerTicker = nil
        end
        CDM:ReleaseAuraLayer(layer)
    end
    CDM:ResetConditions(frame)
    frame.activeLayer = nil
    frame.id = nil
end

local pool = CreateObjectPool(CreateIcon, ResetIcon)

---@param id string
---@return CDMIcon
function CDM:AcquireIcon(id)
    local frame = pool:Acquire()
    frame.id = id
    return frame
end

---@param frame CDMIcon
function CDM:ReleaseIcon(frame)
    pool:Release(frame)
end

-- Style --

---@param layer CDMLayer
---@param style NorskenCore.IconStyle
---@param subRegions NorskenCore.SubElement[]
---@param spellName string
---@param triggers CDMTrigger[] the display's, which a text reading another trigger looks up
local function StyleLayer(layer, style, subRegions, spellName, triggers)
    CDM:StyleIconParts(layer, style)

    layer.subRegions = subRegions
    layer.sourced = false
    layer.shownName = nil
    layer.unitGUID = nil
    local textCount = 0
    for _, element in ipairs(subRegions) do
        if element.type == 'text' then
            textCount = textCount + 1
            local text = AcquireText(layer, textCount)
            local fs = text.fs
            fs:SetFontStyle(element, element.FontSize, nil, nil, true)
            NRSKNUI:PlaceText(fs, element, layer.isBar and layer.Bar or layer, layer.isText and TEXT_PINS[element.Justify] or nil)
            fs:SetTextColor(unpack(element.Color))
            fs:SetShown(element.Enabled)
            ConfigureText(text, element, spellName, layer, triggers)
            if text.source then
                layer.sourced = true
            end
        end
    end

    for i = textCount + 1, #layer.texts do
        local text = layer.texts[i]
        if text.binding then
            text.binding:SetToDefaults()
        end
        text.fs:Hide()
    end
    layer.textCount = textCount
end

---Glow sub elements, each on its own frame, shown as visibleOf says
---@param glows CDMGlow[]
---@param host fun(): Frame makes the frame a new glow draws on
---@param subRegions NorskenCore.SubElement[]
---@param width number
---@param height number
---@param visibleOf fun(index: number, element: NorskenCore.SubElement): boolean
---@param onTexture fun(texture: Texture)?
function CDM:StyleGlows(glows, host, subRegions, width, height, visibleOf, onTexture)
    local count = 0
    for index, element in ipairs(subRegions) do
        if element.type == 'glow' then
            count = count + 1
            local glow = glows[count]
            if not glow then
                glow = self:CreateGlow(host(), onTexture)
                glows[count] = glow
            end
            if visibleOf(index, element) then
                glow:Start(element, width, height)
            else
                glow:Stop()
            end
        end
    end
    for i = count + 1, #glows do
        glows[i]:Stop()
    end
end

---@param layer CDMLayer
---@return fun(): Frame
local function LayerGlowHost(layer)
    return function()
        local host = CreateFrame('Frame', nil, layer)
        host:SetAllPoints()
        host:SetFrameLevel(layer:GetFrameLevel() + CDM.GLOW_LEVEL)
        return host
    end
end

local function ElementEnabled(_, element) return element.Enabled == true end
local function Never() return false end

---@param frame CDMIcon
---@param display CDMDisplay
---@param style NorskenCore.IconStyle
function CDM:StyleIcon(frame, display, style)
    frame:NCSetSize(style.Width, style.Height)
    frame:SetAlpha(style.Alpha)
    frame:EnableMouse(style.Tooltip)

    local subRegions = display.SubRegions
    local triggers = display.Triggers
    local count = #triggers
    local elements = #subRegions
    -- One base layer shows at a time, all at this level
    local base = frame:GetFrameLevel() + 1

    -- Overlays in stacking order, by slot and then an earlier trigger above a later one
    local overlays = {}
    for i, trigger in ipairs(triggers) do
        if trigger.Type == 'auraoverlay' then
            overlays[#overlays + 1] = i
        end
    end
    local function SlotOf(i) return min(triggers[i].Slot, elements) end
    -- An overlay under every element that only swaps the art goes under the base swipe
    -- So the cooldown and GCD stay on it
    local artOnly, hasArtOnly = {}, false
    for _, i in ipairs(overlays) do
        if SlotOf(i) == 0 then
            local active = self:GetAuraConditionChanges(display, i)
            -- A condition that sets no swipe keeps the style's
            local swipe = style.DrawSwipe
            if active.auraSwipe ~= nil then
                swipe = active.auraSwipe
            end
            artOnly[i] = not (active.auraIcon == true and swipe)
            hasArtOnly = hasArtOnly or artOnly[i]
        end
    end
    sort(overlays, function(a, b)
        if SlotOf(a) ~= SlotOf(b) then
            return SlotOf(a) < SlotOf(b)
        end
        if (artOnly[a] == true) ~= (artOnly[b] == true) then
            return artOnly[a] == true
        end
        return a > b
    end)

    -- Element n sits at base + 2 + n over the icon, swipe and bar, up per overlay under it
    -- Overlays use the same levels, so their elements interleave with the base's in list order
    local overlayLevel, shiftOf = {}, {}
    local shift, nextOverlay, swipeLevel = 0, 1, nil
    for n = 0, elements do
        while overlays[nextOverlay] and SlotOf(overlays[nextOverlay]) == n do
            local i = overlays[nextOverlay]
            if hasArtOnly and not swipeLevel and not artOnly[i] then
                swipeLevel, shift = base + 3 + shift, shift + 1
            end
            overlayLevel[i] = base + 3 + n + shift
            shift = shift + OVERLAY_LEVELS + n
            nextOverlay = nextOverlay + 1
        end
        if hasArtOnly and not swipeLevel then
            swipeLevel, shift = base + 3 + shift, shift + 1
        end
        shiftOf[n + 1] = shift
    end
    local function BaseLevel(n) return base + 2 + n + shiftOf[n] end

    for i, trigger in ipairs(triggers) do
        local layer = frame.layers[i]
        if not layer then
            layer = CreateLayer(frame)
            frame.layers[i] = layer
        end
        local level = overlayLevel[i] or base
        local levelOf = BaseLevel
        if overlayLevel[i] then
            -- Its elements in rows above it draw over its own icon, under everything below the row
            local slot = SlotOf(i)
            levelOf = function(n) return n > slot and BaseLevel(n) or level + OVERLAY_LEVELS - 1 + n end
        end
        layer.levelOf = levelOf
        layer.index = i
        layer:SetFrameLevel(level)
        layer.Cooldown:SetFrameLevel(not overlayLevel[i] and swipeLevel or level + 1)
        layer.textHost:SetFrameLevel(level + 1)
        layer.borderHost:SetFrameLevel(level + 1)
        if layer.aura then
            layer.aura.host:SetFrameLevel(level + 1)
        end
        self:StyleBarLayer(layer, style, trigger.Type == 'auraoverlay' and 'icon' or display.type, level)
        self:StyleTicks(layer, subRegions)
        StyleLayer(layer, style, subRegions, self:GetTriggerName(trigger) or '', triggers)
        NRSKNUI:StyleBorders(layer.borders, layer.borderHost, layer, subRegions)
        -- An aura layer's own glows are only the preview's, as the aura button draws the real ones
        local secret = self.TriggerTypes[trigger.Type].Secret
        self:StyleGlows(layer.glows, LayerGlowHost(layer), subRegions, style.Width, style.Height, secret and Never or ElementEnabled)
        NRSKNUI:LevelElements(subRegions, layer.borders, layer.glows, layer.texts, levelOf, layer.tickSets)
    end
    for i = count + 1, #frame.layers do
        local layer = frame.layers[i]
        self:SetLayerTimer(layer, nil)
        layer:Hide()
    end
    frame.layerCount = count

    self:SetupTextFit(frame, display)

    self:AnchorBarOverlays(frame)
    -- Restyling put every layer back to its style, so conditions all apply again next update
    frame.conditionApplied, frame.conditionLayer = nil, nil
end

-- Exports --

-- What the aura button file shows its glows with
CDM.Layer = {
    ElementEnabled = ElementEnabled,
}
