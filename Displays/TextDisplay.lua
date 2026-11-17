---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')

local CreateFrame = CreateFrame
local ipairs = ipairs

-- Anchored to the shown text, as its size turns secret with the text and is never read back
---@param frame CDMIcon
local function FitText(frame)
    local layer = frame.activeLayer or frame.layers[1]
    local text = layer and layer.texts[1]
    if not text then return end
    if frame.fitText ~= text.fs then
        frame.fitText = text.fs
        local first, last = frame.fitProbes[1], frame.fitProbes[2]
        first:ClearAllPoints()
        first:SetPoint('TOPLEFT', text.fs, 'TOPLEFT')
        last:ClearAllPoints()
        last:SetPoint('BOTTOMRIGHT', text.fs, 'BOTTOMRIGHT')
    end
    CDM.MeasureBounds(frame)
end

---A text display's frame follows its text, unless it sits in a Grid dynamic group
---@param frame CDMIcon
---@param display CDMDisplay
function CDM:SetupTextFit(frame, display)
    -- A Grid dynamic group reads its children's sizes, so a text there keeps the style's box
    local fits = display.type == 'text' and not (self:IsDynamic(display.parent) and not self:WantsChain(display.parent))
    if fits and not frame.fitProbes then
        frame.fitProbes = {}
        for i = 1, 2 do
            local probe = CreateFrame('Frame', nil, frame)
            probe:SetSize(0.001, 0.001)
            frame.fitProbes[i] = probe
        end
    end
    -- Made the first time a text fits
    if frame.fitProbes then
        for _, probe in ipairs(frame.fitProbes) do
            probe:SetShown(fits)
        end
    end
    frame.fitsText, frame.fitText = fits, nil
    frame:SetScript('OnUpdate', fits and FitText or nil)
end
