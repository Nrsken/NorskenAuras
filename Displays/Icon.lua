---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')

local unpack = unpack

local QUESTION_MARK = NRSKNUI.QuestionMarkTexture

-- Icon --

---The trigger's texture unless the style picks one by hand, the manual icon when it has none
---@param layer CDMLayer
---@param texture (number|string)?
function CDM:SetIconTexture(layer, texture)
    local style = layer.owner.style
    if style.ManualIcon and (style.IconSource == 'manual' or not texture) then
        texture = style.ManualIcon
    end
    layer.Icon:SetTexture(texture or QUESTION_MARK)
end

---The icon art and its cooldown swipe, from the style
---@param layer CDMLayer
---@param style NorskenCore.IconStyle
function CDM:StyleIconParts(layer, style)
    local icon = layer.Icon
    NRSKNUI:ApplyTexCoords(icon, style)
    icon:SetVertexColor(unpack(style.Color))
    -- An aura placeholder dims it
    icon:SetAlpha(1)

    local cooldown = layer.Cooldown
    cooldown:SetDrawSwipe(style.DrawSwipe)
    cooldown:SetDrawEdge(style.DrawEdge)
    cooldown:SetReverse(style.Reverse)
    cooldown:SetSwipeColor(unpack(style.SwipeColor))
    cooldown:SetHideCountdownNumbers(not self:ShowsTimerText(layer, style))
    -- On every restyle, so a Duration Text change shows without a reload
    cooldown:SetCountdownFormatter(NRSKNUI:GetAuraDurationFormatter())
    NRSKNUI:StyleTimerText(cooldown, style)
end

---Whether a layer draws its icon, an icon's or a bar's by Show Icon
---@param layer CDMLayer
---@param style NorskenCore.IconStyle
---@param display CDMDisplay?
---@return boolean
function CDM:ShowsIcon(layer, style, display)
    if layer.isText then return false end
    if display and (display.type == 'icon' or display.type == 'auragroup') then
        return style.IconShow
    end
    -- An aura overlay on a bar is styled as an icon, not as the bar
    return not layer.isBar or style.IconShow
end

-- Timer Text --

---Whether this layer draws the Timer Text, the picked trigger's or any but an overlay's
---@param layer CDMLayer
---@param style NorskenCore.IconStyle
---@return boolean
function CDM:ShowsTimerText(layer, style)
    if style.HideCountdown then return false end
    local pick = style.TimerText.Trigger
    if pick then
        return pick == layer.index
    end
    local triggers = layer.owner.display.Triggers
    local trigger = triggers and triggers[layer.index] -- An aura group has no list of its own
    return not (trigger and trigger.Type == 'auraoverlay')
end
