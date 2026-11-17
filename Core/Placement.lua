---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Anchors = NRSKNUI.Anchors
local Apply = NRSKNUI.Enum.Apply
local ToTenths = NRSKNUI.Pixel.ToTenths
local L = NRSKNUI.Libs.AL

--[[
Where a display sits, on the screen with a mover, in its group or matched to a group's width
Also keeps a display in place on screen when it moves to another group
]]

local scrubsecretvalues = scrubsecretvalues
local UIParent = UIParent
local ipairs = ipairs
local max = math.max
local min = math.min
local _G = _G

-- Placing --

---Give a display its box for the window, where its position lives and how it re-applies
---@param frame Frame
---@param id string
---@param locked boolean|string? something else places it, so it only selects; a string says what
function CDM:RegisterAnchor(frame, id, locked)
    local display = self:Get(id)
    Anchors:Register(self, id, frame, 'cooldownManager', {
        db = function() return CDM:Get(id) end,
        apply = function(aceModule) aceModule:ApplySettings(Apply.Position, id) end,
        displayName = self:GetName(id),
        bounds = display.type == 'group' and function() return CDM:GetGroupBounds(id) end or nil,
        locked = locked,
    })
end

---A static group's frame is a small handle, this is the area of what hangs off it
---@param id string
---@return number? left in UIParent's units, nil when nothing inside has a readable size
---@return number? bottom
---@return number? right
---@return number? top
function CDM:GetGroupBounds(id)
    local left, bottom, right, top
    local base = UIParent:GetEffectiveScale()

    for _, leaf in ipairs(self:GetLeaves(id)) do
        local frame = self.icons[leaf] or self.containers[leaf] or self:GetAuraHost(leaf)
        if frame and frame:IsShown() then
            local x, y, width, height = scrubsecretvalues(frame:GetRect())
            -- Empty slots keep a sliver of size and an icon holding an aura can have a secret one
            if x and y and width and height and width > 1 and height > 1 then
                local ratio = frame:GetEffectiveScale() / base
                local l, b, r, t = x * ratio, y * ratio, (x + width) * ratio, (y + height) * ratio
                left = left and min(left, l) or l
                bottom = bottom and min(bottom, b) or b
                right = right and max(right, r) or r
                top = top and max(top, t) or t
            end
        end
    end

    return left, bottom, right, top
end

---The point a dynamic group is pinned at, the picked one or its grow anchor
---@param frame Frame|NorskenCore.DynamicGroup|CDMChainGroup
---@param display CDMDisplay
---@return string?
function CDM:GroupPoint(frame, display)
    return display.Position.SelfPoint or frame:GetResolvedAnchor(display.Layout.Grow)
end

---A top-level display sits on the screen with a mover, one in a group hangs off its frame
---@param frame Frame
---@param id string
---@param display CDMDisplay
---@param point string? a dynamic group's grow anchor, used over Position.AnchorFrom
function CDM:Place(frame, id, display, point)
    local parent = display.parent and self:Get(display.parent)
    local position = display.Position
    ---@cast frame CDMPlaced
    local extraX, extraY = frame.conditionX or 0, frame.conditionY or 0 -- Offset conditions, never saved

    -- Anchored to the group's end icons so the bar stretches with them
    -- A group holding auras can't tell us its width
    local matched = display.MatchWidth and self.containers[display.MatchWidth]
    if matched then
        local above = display.MatchSide == 'ABOVE'
        local gap = display.MatchGap or 0
        local left, right, padX, padY = matched, matched, 0, 0

        if matched.isChain then
            ---@cast matched CDMChainGroup
            -- The visible row, whose slots each carry their spacing on the right or bottom
            left, right = matched.chain, matched.chain
            if matched.grow.horizontal then
                padX = matched.config.Spacing
            else
                padY = matched.config.Spacing
            end
        elseif matched.GetHorizontalEnds then
            ---@cast matched NorskenCore.DynamicGroup
            local first, last = matched:GetHorizontalEnds()
            if first and last then
                left, right = first, last
            end
        end

        local y = (above and gap or padY - gap) + extraY
        local edge, groupEdge = above and 'BOTTOM' or 'TOP', above and 'TOP' or 'BOTTOM'
        frame:SetParent(parent and self.containers[display.parent] or UIParent)
        frame:ClearAllPoints()
        frame:NCSetPoint(edge .. 'LEFT', left, groupEdge .. 'LEFT', extraX, y)
        frame:NCSetPoint(edge .. 'RIGHT', right, groupEdge .. 'RIGHT', extraX - padX, y)
        frame:SetFrameStrata(display.Strata or matched:GetFrameStrata())
        self:RegisterAnchor(frame, id, L["It matches a group's width, move the group instead."])
        return
    end

    -- Inside a group it hangs off the group's frame
    if parent then
        local host = self.containers[display.parent]
        frame:SetParent(host)
        frame:ClearAllPoints()

        -- A picked frame wins over the group, which still owns its visibility
        local target = display.anchorFrameType == 'SELECTFRAME' and _G[display.ParentFrame] or host
        -- The path a drag places with, anything else hops on release
        frame:NCSetGridPoint(point or position.AnchorFrom, target, position.AnchorTo, position.XOffset + extraX, position.YOffset + extraY)
        frame:SetFrameStrata(display.Strata or host:GetFrameStrata())
        self:RegisterAnchor(frame, id, self:IsDynamic(display.parent))
        return
    end

    -- On the screen it gets a mover
    frame:SetParent(UIParent)
    if point then
        ---@cast frame NorskenCore.DynamicGroup
        frame:UpdateGroupPosition(display, display.Layout.Grow, extraX, extraY)
    else
        frame:NCApplyPosition(display, nil, extraX, extraY)
    end

    self:RegisterAnchor(frame, id)
end

-- Keeping place --

---@param frame Frame
---@param point string
---@return number? x, number? y screen coordinates
local function PointCoords(frame, point)
    -- An icon in a group holding an aura has a secret position and size
    local left, bottom, width, height = scrubsecretvalues(frame:GetRect())
    if not (left and bottom and width and height) then return end

    local scale = frame:GetEffectiveScale()
    local x = point:find('LEFT') and left or point:find('RIGHT') and left + width or left + width / 2
    local y = point:find('TOP') and bottom + height or point:find('BOTTOM') and bottom or bottom + height / 2

    return x * scale, y * scale
end

---Rewrite a display's offsets so it stays where it is on screen under a new parent
---@param id string
---@param parentId string?
function CDM:KeepPlace(id, parentId)
    local display = self:Get(id)
    local position = display and display.Position
    local frame = self.containers[id] or self.icons[id] or self:GetAuraHost(id)
    if not (position and frame) then return end
    if display.anchorFrameType == 'SELECTFRAME' then return end -- Anchored to its frame, wherever its group goes

    local host = not parentId and UIParent or self.containers[parentId]
    if not host then return end

    local point = display.type == 'dynamicgroup' and self:GroupPoint(frame, display) or position.AnchorFrom
    local fx, fy = PointCoords(frame, point)
    local hx, hy = PointCoords(host, position.AnchorTo)
    if not (fx and hx) then return end

    -- What's on screen includes the offset conditions, which aren't saved
    local scale = frame:GetEffectiveScale()
    position.XOffset = ToTenths((fx - hx) / scale - (frame.conditionX or 0))
    position.YOffset = ToTenths((fy - hy) / scale - (frame.conditionY or 0))
end

-- Anchor roles --

-- The first shown group per unit frame anchor role, in tree order
---@param entries CDMTreeEntry[]
---@param found table<string, Frame>
local function FindAnchorGroups(entries, found)
    for _, entry in ipairs(entries) do
        local display = CDM:Get(entry.key)
        local container = CDM.containers[entry.key]
        if display.UFAnchor and not found[display.UFAnchor] and container and container:IsShown() then
            found[display.UFAnchor] = container
        end
        if display.type == 'group' then
            FindAnchorGroups(CDM:GetChildren(entry.key), found)
        end
    end
end

---The shown groups holding the unit frame anchor roles, the first in tree order wins
---@return Frame? primary, Frame? secondary
function CDM:GetAnchorGroups()
    local found = {}
    FindAnchorGroups(self:GetRoots(), found)

    if not found.primary then
        return found.secondary -- A lone secondary takes the primary role
    end

    return found.primary, found.secondary
end
