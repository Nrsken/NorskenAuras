---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local PROPERTIES = CDM.ConditionProperties
local SubElement = CDM.ConditionRegions.SubElement
local PaintRegion = CDM.ConditionRegions.PaintRegion
local Apply = NRSKNUI.Enum.Apply

--[[
Runs a display's conditions, putting their changes on and taking them back off
Also keeps conditions on the right triggers and sub elements when those move
]]

local CreateColor = CreateColor
local tremove = table.remove
local tonumber = tonumber
local GetTime = GetTime
local sort = table.sort
local wipe = table.wipe
local ipairs = ipairs
local select = select
local unpack = unpack
local pairs = pairs
local next = next

local CreateNumericRuleFormatter = C_StringUtil.CreateNumericRuleFormatter
local CreateColorCurve = C_CurveUtil.CreateColorCurve
local NewTimer = C_Timer.NewTimer

local LuaCurveType = Enum.LuaCurveType

CDM.COMBINATIONS = { AND = true, OR = true }

local OPERATORS = {
    ['<']  = function(a, b) return a < b end,
    ['<='] = function(a, b) return a <= b end,
    ['=='] = function(a, b) return a == b end,
    ['>='] = function(a, b) return a >= b end,
    ['>']  = function(a, b) return a > b end,
    ['~='] = function(a, b) return a ~= b end,
}

---@param display CDMDisplay
---@param check CDMCheck
---@return CDMCheckDef?
local function CheckDef(display, check)
    local trigger = CDM:GetCheckTrigger(display, check.trigger)
    local checks = trigger and CDM.ConditionChecks[trigger.Type]
    return checks and checks[check.variable]
end

---@param display CDMDisplay
---@param check CDMCheck
---@return boolean
local function IsCurve(display, check)
    local def = CheckDef(display, check)
    return def ~= nil and def.curve == true
end

-- The one curve check inside an All of
---@param display CDMDisplay
---@param check CDMCheck
---@return CDMCheck?
local function CurvePart(display, check)
    if check.variable ~= 'AND' then return nil end

    for _, sub in ipairs(check.checks) do
        if IsCurve(display, sub) then
            return sub
        end
    end
end

---@param display CDMDisplay
---@param check CDMCheck
---@return boolean
local function GameDecided(display, check)
    local def = CheckDef(display, CurvePart(display, check) or check)
    return def ~= nil and (def.secret == true or def.curve == true)
end

---@param check CDMCheck
---@param display CDMDisplay
---@param frame CDMIcon|Frame a group's frame has no layers
---@param pip CDMPip? a split bar's pip, read instead of the whole bar
---@return boolean? matched nil when the check can't run here
local function Matches(check, display, frame, pip)
    if CDM.COMBINATIONS[check.variable] then
        local isAnd = check.variable == 'AND'
        local subs = check.checks
        if not subs[1] then return false end
        for _, sub in ipairs(subs) do
            local matched = Matches(sub, display, frame, pip) == true
            if matched ~= isAnd then
                return matched -- AND stops at the first miss, OR at the first hit
            end
        end
        return isAnd
    end

    local trigger = CDM:GetCheckTrigger(display, check.trigger)
    local checks = trigger and CDM.ConditionChecks[trigger.Type]
    local def = checks and checks[check.variable]
    if not def or def.secret or def.curve then return nil end

    local layer = frame.layers and frame.layers[check.trigger]
    if def.type == 'select' then
        return (def.match(check.value, layer, check) == true) ~= (check.op == '~=')
    end

    local value = def.get(layer, trigger, pip)
    if def.type == 'bool' then
        return value == (check.value ~= false)
    end

    local op = OPERATORS[check.op or '<']
    return op ~= nil and op(value, tonumber(check.value) or 0)
end

-- Later changes win, Else If stops at the first match
---@param conditions CDMCondition[]
---@param display CDMDisplay
---@param frame CDMIcon|Frame
---@param pip CDMPip?
---@param overrides table<string, any> property to the value it takes
---@param matches table<number, boolean> by condition index
local function Collect(conditions, display, frame, pip, overrides, matches)
    local chainMatched, lastDecided = false, false
    for index, condition in ipairs(conditions) do
        local check = condition.check
        local matched = Matches(check, display, frame, pip) == true
        -- An Else If chain breaks around a check the game decides
        local decided = GameDecided(display, check)
        if condition.linked and index > 1 and not (decided or lastDecided) then
            matched = matched and not chainMatched
            chainMatched = chainMatched or matched
        else
            chainMatched = matched
        end
        lastDecided = decided
        matches[index] = matched

        if matched then
            for _, change in ipairs(condition.changes) do
                if change.property and change.property ~= 'sound' then
                    overrides[change.property] = change.value
                end
            end
        end
    end
end

-- Evaluate --

local pipOverrides, pipMatches, pipKeys = {}, {}, {}

-- Seconds until a remaining-time check flips
---@param check CDMCheck
---@param frame CDMIcon
---@param now number
---@return number? seconds from now
local function NextFlip(check, frame, now)
    if CDM.COMBINATIONS[check.variable] then
        local soonest
        for _, sub in ipairs(check.checks) do
            local flip = NextFlip(sub, frame, now)
            if flip and (not soonest or flip < soonest) then
                soonest = flip
            end
        end
        return soonest
    end

    if check.variable ~= 'remaining' then return nil end

    local layer = frame.layers[check.trigger]
    local endTime = layer and layer.endTime
    if not endTime then return nil end

    local flip = endTime - (tonumber(check.value) or 0) - now
    if flip > 0 then
        return flip
    end
end

---@param frame CDMIcon
---@param display CDMDisplay
local function PlaceOffset(frame, display)
    if CDM:IsDynamic(display.parent) then return end

    -- One per frame, the combat queue dedupes by identity
    frame.placeOffset = frame.placeOffset or function()
        local current = CDM:Get(frame.id)
        if current and not CDM:IsDynamic(current.parent) then
            CDM:Place(frame, frame.id, current)
        end
    end

    -- Hung off a picked frame it can join a protected anchor family,
    -- so it waits for combat to end
    local current = display
    while current do
        if current.anchorFrameType == 'SELECTFRAME' and current.ParentFrame and current.ParentFrame ~= 'UIParent' then
            NRSKNUI:RunWhenSafe(frame.placeOffset)
            return
        end
        current = current.parent and CDM:Get(current.parent)
    end
    frame.placeOffset()
end

-- An Each Rune text or border change, decided per pip
---@param display CDMDisplay
---@param layer CDMLayer
---@param key string
---@return NorskenCore.SubElement? element, number? ordinal, string? name
local function PipRegionChange(display, layer, key)
    local name, sub = CDM:SplitProperty(key)
    if not sub or (name ~= 'visible' and name ~= 'subColor') then return nil end
    local element, ordinal = SubElement(display, sub)
    if not element or (element.type ~= 'text' and element.type ~= 'border') then return nil end
    local own = layer[element.type == 'text' and 'texts' or 'borders'][ordinal]
    if not (own and own.eachPip) then return nil end
    return element, ordinal, name
end

---Apply the display's conditions over what its triggers drew
---@param id string
---@param frame CDMIcon
---@param display CDMDisplay
function CDM:EvaluateConditions(id, frame, display)
    local conditions = display.Conditions
    local applied = frame.conditionApplied or {}
    frame.conditionApplied = applied
    local wasActive = frame.conditionActive or {}
    frame.conditionActive = wasActive

    if frame.conditionTimer then
        frame.conditionTimer:Cancel()
        frame.conditionTimer = nil
    end

    -- Show Display can bring a standby layer up
    local overrides, matches = {}, {}
    Collect(conditions, display, frame, nil, overrides, matches)

    -- Re-run when a remaining-time check flips
    local now, soonest = GetTime(), nil
    for _, condition in ipairs(conditions) do
        local flip = NextFlip(condition.check, frame, now)
        if flip and (not soonest or flip < soonest) then
            soonest = flip
        end
    end

    -- Max Stacks on every layer, an aura bar is never active
    local maxStacks = overrides.maxStacks
    overrides.maxStacks = nil
    if frame.conditionMaxStacks ~= maxStacks then
        frame.conditionMaxStacks = maxStacks
        for _, each in ipairs(frame.layers) do
            PROPERTIES.maxStacks.apply(frame, each, maxStacks, display)
        end
    end

    -- On the frame, a cast bar has no layer between casts
    local x, y = tonumber(overrides.xOffset) or 0, tonumber(overrides.yOffset) or 0
    overrides.xOffset, overrides.yOffset = nil, nil
    if (frame.conditionX or 0) ~= x or (frame.conditionY or 0) ~= y then
        frame.conditionX, frame.conditionY = x, y
        PlaceOffset(frame, display)
    end

    -- On our frame, so a lone aura gets it too
    -- Set every pass, a restyle puts the style's alpha back
    local alpha = overrides.alpha
    overrides.alpha = nil
    if alpha ~= nil or frame.conditionAlpha ~= nil then
        frame:SetAlpha(alpha or frame.style.Alpha)
    end
    frame.conditionAlpha = alpha

    local layer = frame.activeLayer
    local show = overrides.show
    overrides.show = nil
    if show == true and not layer and frame.standbyLayer then
        layer = frame.standbyLayer
        layer:Show()
        frame.activeLayer, frame.hasActive = layer, true
    end
    frame.forceHidden = show == false

    -- Per pip changes wait for the pip pass below
    local pipCount = layer and layer.isBar and layer.pipCount or 0
    if pipCount > 0 then
        ---@cast layer CDMLayer
        overrides.barColor = nil
        wipe(pipKeys)
        for _, condition in ipairs(conditions) do
            for _, change in ipairs(condition.changes) do
                if change.property and PipRegionChange(display, layer, change.property) then
                    pipKeys[change.property] = true
                end
            end
        end

        for key in pairs(pipKeys) do
            overrides[key] = nil
        end
    end

    -- Play sounds once, on the first match
    for index, condition in ipairs(conditions) do
        local matched = layer ~= nil and not frame.forceHidden and matches[index]
        if matched and not wasActive[index] then
            for _, change in ipairs(condition.changes) do
                if change.property == 'sound' and change.value then
                    NRSKNUI:PlaySafeSound(change.value)
                end
            end
        end
        wasActive[index] = matched or nil
    end

    -- Restore the look of a layer no longer shown
    local lastLayer = frame.conditionLayer
    if lastLayer and lastLayer ~= layer then
        for key in pairs(applied) do
            local name, sub = self:SplitProperty(key)
            local prop = PROPERTIES[name]
            if prop and prop.base then
                prop.apply(frame, lastLayer, prop.base(frame, lastLayer, display, sub), display, sub)
            end
        end
        wipe(applied)
    end
    frame.conditionLayer = layer

    -- Apply new changes, remove stopped ones
    if layer then
        for key, value in pairs(overrides) do
            if applied[key] ~= value then
                local name, sub = self:SplitProperty(key)
                local prop = PROPERTIES[name]
                if prop then
                    prop.apply(frame, layer, value, display, sub)
                end
                applied[key] = value
            end
        end

        for key in pairs(applied) do
            if overrides[key] == nil then
                local name, sub = self:SplitProperty(key)
                local prop = PROPERTIES[name]
                if prop and prop.base then
                    prop.apply(frame, layer, prop.base(frame, layer, display, sub), display, sub)
                end
                applied[key] = nil
            end
        end

        -- The trigger resets desaturation every update
        if overrides.desaturate ~= nil then
            PROPERTIES.desaturate.apply(frame, layer, overrides.desaturate, display)
        end
    end

    -- Run the conditions again for each pip
    if pipCount > 0 then
        ---@cast layer CDMLayer
        for i = 1, pipCount do
            local pip = layer.pips[i]
            wipe(pipOverrides)
            Collect(conditions, display, frame, pip, pipOverrides, pipMatches)
            self:SetLayerPipColor(layer, i, pipOverrides.barColor)
            for key in pairs(pipKeys) do
                local element, ordinal, name = PipRegionChange(display, layer, key)
                ---@cast element table
                ---@cast name 'visible'|'subColor'
                local value = pipOverrides[key]
                if value == nil then
                    value = PROPERTIES[name].base(frame, layer, display, select(2, self:SplitProperty(key)))
                end
                local region = pip[element.type == 'text' and 'texts' or 'borders'][ordinal]
                if region then
                    PaintRegion(element, region, name, value)
                end
            end
        end
    end

    if soonest then
        frame.conditionTimer = NewTimer(soonest + 0.01, function() -- Just past the flip, so it reads flipped
            frame.conditionTimer = nil
            if frame.id == id then
                self:Derive(id)
            end
        end)
    end
end

---Drop what conditions put on a frame, as it returns to the pool
---@param frame CDMIcon
function CDM:ResetConditions(frame)
    if frame.conditionTimer then
        frame.conditionTimer:Cancel()
    end
    frame.conditionTimer, frame.conditionApplied, frame.conditionActive, frame.conditionLayer = nil, nil, nil, nil
    frame.forceHidden, frame.standbyLayer = nil, nil
    frame.conditionX, frame.conditionY = nil, nil
    frame.conditionMaxStacks, frame.conditionAlpha = nil, nil
end

-- Groups --

local movedGroups, rebuiltCurves = {}, {}

-- Stable functions, the combat queue dedupes by identity
local function RebuildCurves()
    local ids = {}
    for id in pairs(rebuiltCurves) do
        ids[#ids + 1] = id
    end
    wipe(rebuiltCurves)
    -- The curves live in the texts
    CDM:ApplySettings(Apply.Text, ids)
end

local function PlaceMovedGroups()
    for id in pairs(movedGroups) do
        local display = CDM:Get(id)
        local frame = CDM.containers[id]
        if display and frame then
            CDM:Place(frame, id, display, display.type == 'dynamicgroup' and CDM:GroupPoint(frame, display) or nil)
        elseif display then
            local host = CDM:GetAuraHost(id)
            if host then
                CDM:Place(host, id, display)
            end
        end
    end
    wipe(movedGroups)
end

---Put a group's offset conditions on its frame, read by Place
---@param display CDMDisplay
---@param frame Frame
---@return boolean changed
function CDM:EvaluateGroupConditions(display, frame)
    ---@cast frame CDMPlaced
    local overrides, matches = {}, {}
    Collect(display.Conditions, display, frame, nil, overrides, matches)

    local x, y = tonumber(overrides.xOffset) or 0, tonumber(overrides.yOffset) or 0
    if frame.conditionX == x and frame.conditionY == y then return false end
    frame.conditionX, frame.conditionY = x, y
    return true
end

---Re-run the conditions that read spec or talents
function CDM:RefreshPlayerConditions()
    for id, display in pairs(self.db.Displays) do
        if self:ConditionsUse(display, -1, 'spec') or self:ConditionsUse(display, -1, 'talent') then
            local frame = self.icons[id]
            local group = self.containers[id] or self:GetAuraHost(id)
            if frame then
                self:Derive(id)
            elseif group and self:EvaluateGroupConditions(display, group) then
                movedGroups[id] = true
            end

            -- Gated curves live in the texts, restyle them
            if frame and self:CurveGates(display) ~= frame.curveGates then
                rebuiltCurves[id] = true
            end
        end
    end

    -- A loading screen can come in combat
    if next(rebuiltCurves) then
        NRSKNUI:RunWhenSafe(RebuildCurves)
    end

    if next(movedGroups) then
        NRSKNUI:RunWhenSafe(PlaceMovedGroups)
    end
end

-- Curves --

local EDGE = 0.001 -- Seconds either side of a color change

-- Nil while a spec or talent check beside the curve fails
---@param display CDMDisplay
---@param check CDMCheck
---@return CDMCheck?
local function CurveCheck(display, check)
    if check.variable ~= 'AND' then
        return check
    end

    local curve
    for _, sub in ipairs(check.checks) do
        if sub.trigger == -1 and CDM.GROUP_CHECKS[sub.variable] then
            if not CheckDef(display, sub).match(sub.value, nil, sub) then return nil end
        elseif curve or not IsCurve(display, sub) then
            return nil
        else
            curve = sub
        end
    end
    return curve
end

---Which gated curves build now, as '10', nil without any
---A build keeps it, so a spec change rebuilds only where it moved
---@param display CDMDisplay
---@return string?
function CDM:CurveGates(display)
    local gates
    for _, condition in ipairs(display.Conditions) do
        local check = condition.check
        if CurvePart(display, check) then
            gates = (gates or '') .. (CurveCheck(display, check) and '1' or '0')
        end
    end
    return gates
end

---A text's color curve from its curve checks on one trigger
---@param display CDMDisplay
---@param triggerIndex number the trigger whose time or power the text shows
---@param scales table<string, number> what turns each check's threshold into the game's number
---@param ordinal number the text's place among the display's texts
---@param ownColor number[] the text's own color
---@param baseCurve LuaColorCurveObject? the shared Duration Text curve when the text follows it
---@return LuaColorCurveObject? curve nil or the base curve when no condition steps over it
function CDM:TextColorCurve(display, triggerIndex, scales, ordinal, ownColor, baseCurve)
    -- Lazy, a cast restyles %n texts every time
    local steps
    for _, condition in ipairs(display.Conditions) do
        local check = CurveCheck(display, condition.check)
        local scale = check and check.trigger == triggerIndex and scales[check.variable]
        if scale then
            for _, change in ipairs(condition.changes) do
                local name, sub = self:SplitProperty(change.property or '')
                if name == 'subColor' then
                    local element, textOrdinal = SubElement(display, sub)
                    if element and element.type == 'text' and textOrdinal == ordinal then
                        local above = check.op == '>' or check.op == '>='
                        steps = steps or {}
                        steps[#steps + 1] = { above = above, at = (tonumber(check.value) or 0) / scale, color = change.value }
                    end
                end
            end
        end
    end
    if not steps then
        return baseCurve
    end

    -- Later conditions win
    local function ColorAt(value)
        local color
        for _, step in ipairs(steps) do
            if (step.above and value > step.at) or (not step.above and value < step.at) then
                color = step.color
            end
        end
        if color then
            return CreateColor(unpack(color))
        end
        return baseCurve and baseCurve:Evaluate(value) or CreateColor(unpack(ownColor))
    end

    local points, seen = {}, {}
    for _, step in ipairs(steps) do
        if not seen[step.at] then
            seen[step.at] = true
            points[#points + 1] = step.at
        end
    end

    if baseCurve then
        for _, point in ipairs(baseCurve:GetPoints()) do
            if not seen[point.x] then
                seen[point.x] = true
                points[#points + 1] = point.x
            end
        end
        sort(points)

        -- Read either side of each change, so a linear curve
        -- holds steps flat and keeps the base's fade between them
        local curve = CreateColorCurve()
        local last
        for _, at in ipairs(points) do
            for _, x in ipairs({ at - EDGE, at + EDGE }) do
                if not last or x > last then
                    curve:AddPoint(x, ColorAt(x))
                    last = x
                end
            end
        end
        return curve
    end
    sort(points)

    -- Read each step halfway to the next, the first below 0
    local curve = CreateColorCurve()
    curve:SetType(LuaCurveType.Step)
    local first = (points[1] < 0 and points[1] or 0) - 1
    curve:AddPoint(first, ColorAt(first))
    for i, at in ipairs(points) do
        local after = points[i + 1]
        curve:AddPoint(at, ColorAt(after and (at + after) / 2 or at + 1))
    end
    return curve
end

---A stack text's formatter from its Stacks checks, nil when none color it
---@param display CDMDisplay
---@param triggerIndex number the aura trigger whose count the text shows
---@param ordinal number the text's place among the display's texts
---@return NumericRuleFormatter? formatter for SetApplicationCount
function CDM:StackCountFormatter(display, triggerIndex, ordinal)
    local steps
    for _, condition in ipairs(display.Conditions) do
        local check = CurveCheck(display, condition.check)
        if check and check.trigger == triggerIndex and check.variable == 'stacks' then
            for _, change in ipairs(condition.changes) do
                local name, sub = self:SplitProperty(change.property or '')
                if name == 'subColor' then
                    local element, textOrdinal = SubElement(display, sub)
                    if element and element.type == 'text' and textOrdinal == ordinal then
                        steps = steps or {}
                        steps[#steps + 1] = { above = check.op == '>=', at = tonumber(check.value) or 0, color = change.value }
                    end
                end
            end
        end
    end
    if not steps then return nil end

    -- The count is secret, so the game picks the color
    -- Later conditions win
    local function FormatAt(value)
        local color
        for _, step in ipairs(steps) do
            if (step.above and value >= step.at) or (not step.above and value < step.at) then
                color = step.color
            end
        end
        return color and CreateColor(unpack(color)):WrapTextInColorCode('%d') or '%d'
    end

    -- One breakpoint per step, one color across each range
    local points, seen = { 2 }, { [2] = true }
    for _, step in ipairs(steps) do
        if step.at > 2 and not seen[step.at] then
            seen[step.at] = true
            points[#points + 1] = step.at
        end
    end
    sort(points)

    -- One stack stays blank, as Blizzard's own count does
    local breakpoints = { { threshold = 0, format = '' } }
    for _, at in ipairs(points) do
        breakpoints[#breakpoints + 1] = { threshold = at, format = FormatAt(at) }
    end

    local formatter = CreateNumericRuleFormatter()
    formatter:SetBreakpoints(breakpoints)
    return formatter
end

-- Remap --

---Follow triggers that moved, nil from map drops their checks
---@param display CDMDisplay
---@param map fun(index: number): number?
function CDM:RemapConditionTriggers(display, map)
    if display.DynamicTrigger then
        display.DynamicTrigger = map(display.DynamicTrigger)
    end

    local timer = display.Style.TimerText
    if timer.Trigger then
        timer.Trigger = map(timer.Trigger)
    end

    ---@return boolean keep false when its trigger is gone
    local function Remap(check)
        if CDM.COMBINATIONS[check.variable] then
            for i = #check.checks, 1, -1 do
                if not Remap(check.checks[i]) then
                    tremove(check.checks, i)
                end
            end
            return true
        end

        local new = check.trigger <= 0 and check.trigger or map(check.trigger) -- Global and group checks stay put
        check.trigger = new
        return new ~= nil
    end

    local conditions = display.Conditions
    for index = #conditions, 1, -1 do
        local check = conditions[index].check
        if check and not Remap(check) then
            tremove(conditions, index)
        end
    end
end

---Follow sub elements that moved, nil from map drops their changes
---@param display CDMDisplay
---@param map fun(index: number): number?
function CDM:RemapConditionSubRegions(display, map)
    for _, condition in ipairs(display.Conditions) do
        local changes = condition.changes
        for i = #changes, 1, -1 do
            local index, name = (changes[i].property or ''):match('^sub%.(%d+)%.(%a+)$')
            if index then
                local new = map(tonumber(index))
                if new then
                    changes[i].property = 'sub.' .. new .. '.' .. name
                else
                    tremove(changes, i)
                end
            end
        end
    end
end

-- Queries --

---@param check CDMCheck
---@param triggerIndex number
---@param variable string
---@return boolean
local function Uses(check, triggerIndex, variable)
    if CDM.COMBINATIONS[check.variable] then
        for _, sub in ipairs(check.checks) do
            if Uses(sub, triggerIndex, variable) then return true end
        end
        return false
    end

    return check.trigger == triggerIndex and check.variable == variable
end

---Whether any condition reads this check, so unread work can be skipped
---@param display CDMDisplay
---@param triggerIndex number
---@param variable string
---@return boolean
function CDM:ConditionsUse(display, triggerIndex, variable)
    for _, condition in ipairs(display.Conditions) do
        if Uses(condition.check, triggerIndex, variable) then return true end
    end
    return false
end

-- Exports --

CDM.OPERATORS = OPERATORS -- A durability trigger's Show At Value compares as a condition does
