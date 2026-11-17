---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Pixel = NRSKNUI.Pixel

local CreateFrame = CreateFrame
local tremove = table.remove
local UIParent = UIParent
local floor = math.floor
local sort = table.sort
local wipe = table.wipe
local ipairs = ipairs
local max = math.max
local Mixin = Mixin
local pairs = pairs
local next = next
local type = type
local _G = _G

local PROBE_TEMPLATE = 'DisableUntrustedLayoutScriptsTemplate' -- Anchoring to an aura button needs it

-- Per grow, the group's own anchor, the chain's links and which axis the spacing pads
---@type table<string, CDMChainGrow>
local GROWS = {
    RIGHT      = { point = 'LEFT', first = 'LEFT', link = 'LEFT', to = 'RIGHT', horizontal = true, shift = 0 },
    LEFT       = { point = 'RIGHT', first = 'RIGHT', link = 'RIGHT', to = 'LEFT', horizontal = true, shift = 1 },
    HORIZONTAL = { point = 'CENTER', first = 'LEFT', link = 'LEFT', to = 'RIGHT', horizontal = true, shift = 0.5 },
    DOWN       = { point = 'TOP', first = 'TOP', link = 'TOP', to = 'BOTTOM', horizontal = false, shift = 0 },
    UP         = { point = 'BOTTOM', first = 'BOTTOM', link = 'BOTTOM', to = 'TOP', horizontal = false, shift = 1 },
    VERTICAL   = { point = 'CENTER', first = 'TOP', link = 'TOP', to = 'BOTTOM', horizontal = false, shift = 0.5 },
}

-- Layout --

-- A grow point lined up on the cross axis, TOP and LEFT make TOPLEFT
---@param point string
---@param grow CDMChainGrow
---@param align string?
---@return string
local function Aligned(point, grow, align)
    local onAxis = grow.horizontal and (align == 'TOP' or align == 'BOTTOM') or not grow.horizontal and (align == 'LEFT' or align == 'RIGHT')
    if not onAxis then
        return point
    end
    ---@cast align string
    if point == 'CENTER' then
        return align
    end
    return grow.horizontal and align .. point or point .. align
end

-- Sized to its children without reading the result back, so secret sizes are fine
---@param frame Frame
local function Measure(frame)
    frame:SetIgnoringChildrenForBounds(false)
    frame:SetSize(0.001, 0.001)
    frame:ResizeToBoundsRect()
    frame:SetIgnoringChildrenForBounds(true)
end

-- Icons in slots chained one after another, sized by probes so nothing secret is read
---@class CDMChainGroup : Frame
local ChainMixin = {}

---@param self CDMChainGroup
---@return number padX, number padY
local function Padding(self)
    local spacing = self.config.Spacing
    if self.grow.horizontal then
        return spacing, 0
    end
    return 0, spacing
end

---@param self CDMChainGroup
local function Relink(self)
    local order = self.order
    wipe(order)
    for _, record in pairs(self.records) do
        order[#order + 1] = record
    end
    sort(order, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.key < b.key
    end)

    local grow = self.grow
    local align = self.config.Align
    local first, link, to = Aligned(grow.first, grow, align), Aligned(grow.link, grow, align), Aligned(grow.to, grow, align)
    local previous
    for _, record in ipairs(order) do
        local slot = record.slot
        slot:ClearAllPoints()
        if previous then
            slot:SetPoint(link, previous, to)
        else
            slot:SetPoint(first, self.chain, first)
        end
        previous = slot
    end
end

---@param self CDMChainGroup
local function PlaceChain(self)
    local grow = self.grow
    local padX, padY = Padding(self)
    -- Each slot carries its spacing after it, so the anchor takes the last gap back
    local x = grow.horizontal and padX * grow.shift or 0
    local y = grow.horizontal and 0 or -padY * grow.shift
    if grow.shift == 0.5 then
        local total, unknown = 0, false
        for _, record in ipairs(self.order) do
            if record.logic then
                total = total + (grow.horizontal and record.width + padX or record.height + padY)
            elseif record.loaded and (next(record.auraProbes) or record.child.fitsText) then
                unknown = true
            end
        end
        local half = total / 2
        -- An odd sized group's centre sits on a half pixel, so the row is snapped from its edge
        local edge = self.extent / 2
        -- With auras or texts in the row we can't tell a whole pixel from a half
        -- So a quarter pixel off clears the half, where 0.001 slots split an icon and its border
        local nudge = unknown and Pixel.GetMult() * 0.25 or 0
        if grow.horizontal then
            x = floor(edge + x - half + 0.5) - edge + half - nudge
        else
            y = -(floor(edge - y - half + 0.5) - edge + half) + nudge
        end
    end
    local point = Aligned(grow.point, grow, self.config.Align)
    self.chain:ClearAllPoints()
    self.chain:SetPoint(point, self, point, x, y)
end

---@param self CDMChainGroup
local function Resize(self)
    local grow = self.grow
    local total, cross, count = 0, 0, 0
    for _, record in ipairs(self.order) do
        if record.loaded then
            count = count + 1
            total = total + (grow.horizontal and record.width or record.height)
            cross = max(cross, grow.horizontal and record.height or record.width)
        end
    end
    if count > 1 then
        total = total + (count - 1) * self.config.Spacing
    end
    total = max(1, total)
    self.extent = total
    -- Every loaded icon's size, for the mover and the unit frame anchor
    -- The row on screen is self.chain
    if grow.horizontal then
        self:NCSetSize(total, max(1, cross))
    else
        self:NCSetSize(max(1, cross), total)
    end
    -- The grid snap was worked out for the old size
    self:NCRefreshGridPoint()
    PlaceChain(self)
end

-- Sizes what Lua can know, an aura opens its own slot while it's up
---@param record CDMChainRecord
---@param padX number
---@param padY number
local function SizeRecord(record, padX, padY)
    local fits = record.child.fitsText
    if record.logic and not fits then
        record.measure:SetSize(record.width + padX, record.height + padY)
    else
        record.measure:SetSize(0.001, 0.001)
    end
    -- A text sizes itself, so the slot reaches to its far corner plus the spacing
    local slot = record.slot
    if fits then
        local probe = slot.textProbe or CreateFrame('Frame', nil, slot)
        probe:SetSize(0.001, 0.001)
        probe:ClearAllPoints()
        probe:SetPoint('TOPLEFT', record.child, 'BOTTOMRIGHT', padX, -padY)
        probe:SetShown(record.logic == true)
        slot.textProbe = probe
    elseif slot.textProbe then
        slot.textProbe:Hide()
    end
    if not record.loaded then
        slot:SetSize(0.001, 0.001)
    end

    -- Reused, since this runs every time an icon shows or hides
    local pad = record.child.chainPad or {}
    pad[1], pad[2] = padX, padY
    record.child.chainPad = pad
end

-- Group --

---@param config CDMLayout
function ChainMixin:SetConfig(config)
    self.config = config
    self.grow = GROWS[config.Grow]
    local padX, padY = Padding(self)
    for _, record in pairs(self.records) do
        SizeRecord(record, padX, padY)
    end
    Relink(self)
    Resize(self)
end

---@param grow string
---@return string
function ChainMixin:GetResolvedAnchor(grow)
    local entry = GROWS[grow]
    return Aligned(entry.point, entry, self.config.Align)
end

---Same placement as a DynamicGroup at the top level
---@param source CDMDisplay
---@param grow string
---@param extraX number added to the saved offset, not stored
---@param extraY number
function ChainMixin:UpdateGroupPosition(source, grow, extraX, extraY)
    local position = source.Position
    local parent = source.anchorFrameType == 'SELECTFRAME' and _G[source.ParentFrame] or UIParent
    self:ClearAllPoints()
    self:NCSetGridPoint(position.SelfPoint or self:GetResolvedAnchor(grow), parent, position.AnchorTo, position.XOffset + extraX, position.YOffset + extraY)
    self:SetFrameStrata(source.Strata or 'MEDIUM')
end

---@param child CDMIcon
---@param key string
---@param order number?
function ChainMixin:AttachChild(child, key, order)
    local record = self.records[key]
    if not record then
        local slot = tremove(self.spare) or CreateFrame('Frame', nil, self.chain)
        slot:SetCollapsesLayout(true)
        slot:SetIgnoringChildrenForBounds(true)
        slot:Show()

        local measure = slot.measure or CreateFrame('Frame', nil, self.holder)
        measure:SetCollapsesLayout(true)
        measure:ClearAllPoints()
        measure:SetPoint('TOPLEFT', slot, 'TOPLEFT')
        slot.measure = measure

        local probe = slot.probe or CreateFrame('Frame', nil, slot)
        probe:SetSize(0.001, 0.001)
        probe:ClearAllPoints()
        probe:SetPoint('TOPLEFT', measure, 'BOTTOMRIGHT')
        slot.probe = probe

        record = { key = key, slot = slot, measure = measure, probe = probe, auraProbes = slot.auraProbes or {}, width = 1, height = 1 }
        slot.auraProbes = record.auraProbes
        self.records[key] = record
    end
    record.child = child
    record.order = order or 0
    child:SetParent(self.holder)
    child:ClearAllPoints()
    child:SetPoint('TOPLEFT', record.slot, 'TOPLEFT')
    child.chainGroup = self
    local padX, padY = Padding(self)
    SizeRecord(record, padX, padY)
    -- An aura button made before the icon joined still has to open its slot
    for _, layer in ipairs(child.layers) do
        local refs = layer.auraRefs
        if refs and refs.button then
            self:WatchAuraButton(key, refs.button)
        end
    end
    Relink(self)
    Resize(self)
end

---@param childOrKey Frame|string
---@return CDMChainRecord?
function ChainMixin:GetRecord(childOrKey)
    if type(childOrKey) == 'string' then
        return self.records[childOrKey]
    end
    for _, record in pairs(self.records) do
        if record.child == childOrKey then
            return record
        end
    end
end

---@param childOrKey Frame|string
function ChainMixin:DetachChild(childOrKey)
    local record = self:GetRecord(childOrKey)
    if not record then return end
    self.records[record.key] = nil
    for _, probe in pairs(record.auraProbes) do
        probe:ClearAllPoints()
        probe:Hide()
    end
    wipe(record.auraProbes)
    record.slot:Hide()
    record.slot:ClearAllPoints()
    record.measure:Hide()
    if record.slot.textProbe then
        record.slot.textProbe:ClearAllPoints()
        record.slot.textProbe:Hide()
    end
    self.spare[#self.spare + 1] = record.slot
    local child = record.child
    if child.chainGroup == self then
        child.chainGroup = nil
        child.chainPad = nil
        child:ClearAllPoints() -- Still on the slot its size reads back secret
        child:SetParent(NRSKNUI.HiddenFrame)
    end
    Relink(self)
    Resize(self)
end

---@param childOrKey Frame|string
---@param order number
function ChainMixin:SetChildOrder(childOrKey, order)
    local record = self:GetRecord(childOrKey)
    if not record or record.order == order then return end
    record.order = order
    Relink(self)
end

---@param childOrKey Frame|string
---@param width number
---@param height number
function ChainMixin:NotifyChildResized(childOrKey, width, height)
    local record = self:GetRecord(childOrKey)
    if not record then return end
    record.width, record.height = width, height
    local padX, padY = Padding(self)
    SizeRecord(record, padX, padY)
    Resize(self)
end

---Loaded gives the icon a slot, logic is a trigger Lua can see on show
---@param key string
---@param loaded boolean
---@param logic boolean
function ChainMixin:SetChildVisible(key, loaded, logic)
    local record = self.records[key]
    if not record then return end
    logic = loaded and logic
    if record.loaded == loaded and record.logic == logic then return end
    record.loaded, record.logic = loaded, logic
    -- Kept shown at zero size, a hidden slot drops every slot after it from the row
    record.child:SetShown(loaded)
    record.measure:SetShown(logic)
    SizeRecord(record, Padding(self))
    Resize(self)
end

---Measure an aura button too, so the slot opens while the aura is up
---@param key string
---@param button table the real aura button, from its initializeFrame
function ChainMixin:WatchAuraButton(key, button)
    local record = self.records[key]
    if not record or record.auraProbes[button] or not NRSKNUI:CanAccessObject(button) then return end
    local probe = CreateFrame('Frame', nil, record.slot, PROBE_TEMPLATE)
    probe:SetSize(0.001, 0.001)
    probe:SetPoint('TOPLEFT', button, 'BOTTOMRIGHT')
    record.auraProbes[button] = probe
    PlaceChain(self) -- An aura in the row changes how it centres
end

-- Measuring --

-- An aura button shows and hides unseen, so every loaded slot is measured each frame
---@param self CDMChainGroup
local function OnUpdate(self)
    -- Collapse the row first, as last frame's width feeds its float noise back
    -- and texts on a pixel edge shake
    self.chain:SetSize(0.001, 0.001)
    for _, record in ipairs(self.order) do
        if record.loaded then
            Measure(record.slot)
        end
    end
    Measure(self.chain)
end

---A chained dynamic group for every grow but Grid, laid out by its first SetConfig
---@return CDMChainGroup
function CDM:CreateChainGroup()
    local group = CreateFrame('Frame', nil, UIParent) --[[@as CDMChainGroup]]
    group.isChain = true
    group.chain = CreateFrame('Frame', nil, group)
    group.chain:SetIgnoringChildrenForBounds(true)
    group.holder = CreateFrame('Frame', nil, group)
    group.holder:SetAllPoints()
    group.records = {}
    group.order = {}
    group.spare = {}
    group.extent = 1
    Mixin(group, ChainMixin)
    group:SetScript('OnUpdate', OnUpdate)
    return group
end

-- Exports --

CDM.CHAIN_GROWS = GROWS
CDM.MeasureBounds = Measure
