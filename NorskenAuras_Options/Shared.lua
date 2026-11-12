---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local IconPicker = NRSKNUI.CDMIconPicker
local Kaji = NRSKNUI.Kaji

local ipairs = ipairs
local CreateFrame = CreateFrame

-- What the CDM options files share: page keys, helpers and the trigger lists.
NRSKNUI.CDMOptions = {}
local Shared = NRSKNUI.CDMOptions

local PAGE = 'cooldownManager'
local GENERAL = 'cdm:general'
local NEW = 'cdm:new'
local GLOBAL = 'cdm:global'
local TRINKETS = 'cdm:trinkets'
local IMPORT = 'cdm:import'
local SECTION_LOADED = 'cdm:section:loaded'
local SECTION_UNLOADED = 'cdm:section:unloaded'
local QUESTION_MARK = 134400
local NEW_TILE_HEIGHT = 104
local NEW_TILE_ICON = 44
local NEW_TILE_PREVIEW = 74 -- a picture's width: fills a tile at the narrowest window
local POWER_MODES = {
    { value = 'bar',      text = L['Static Single Bar'],   description = L['One bar for all your %s.'] },
    { value = 'static',   text = L['Static Segments'],     description = L['One segment each, filled while it is ready, empty otherwise.'] },
    { value = 'progress', text = L['Recharging Segments'], description = L['Like Static Segments but each one fills up as it recharges.'] },
}

local TABS = {
    { id = 'group',       text = L['Group'] },
    { id = 'display',     text = L['Display'] },
    { id = 'trigger',     text = L['Trigger'] },
    { id = 'conditions',  text = L['Conditions'] },
    { id = 'load',        text = L['Load'] },
    { id = 'information', text = L['Information'] },
}

-- Several picked rows edit together, in the WA style: only what every display has, nothing that is one display's own.
local MULTI_TABS = {
    { id = 'display', text = L['Display'] },
    { id = 'load',    text = L['Load'] },
}

-- An aura group edits like a dynamic group of aura icons, with the triggers it draws from.
local AURA_GROUP_TABS = {
    { id = 'group',       text = L['Group'] },
    { id = 'display',     text = L['Display'] },
    { id = 'trigger',     text = L['Trigger'] },
    { id = 'conditions',  text = L['Conditions'] },
    { id = 'load',        text = L['Load'] },
    { id = 'information', text = L['Information'] },
}

local TYPE_NAMES = {
    icon = L['Icon'],
    bar = L['Progress Bar'],
    text = L['Text'],
    group = L['Group'],
    dynamicgroup = L['Dynamic Group'],
    auragroup = L['Aura Group'],
}

local expandedGroups = {} -- [group uid] = true, for the session; groups start collapsed. A uid is never reused, unlike an id

---@return table? tree
local function Tree()
    local window = NRSKNUI.GUIFrame
    return window and window.content.currentId == PAGE and window.content.miniSidebar or nil
end

---Every display a tab edits for the shown row: with two or more rows picked (it among them) each picked display,
---a picked group standing for everything inside it; else a group's displays or the row alone.
---@param id string
---@return string[] ids each once, in tree order
---@return boolean multi whether it's a multi selection
local function EditTargets(id)
    local tree = Tree()
    local picked = tree and tree.picked and tree.picked[id] and tree:GetPicked()
    if not (picked and picked[2]) then
        return CDM:IsGroup(id) and CDM:GetLeaves(id) or { id }, false
    end

    local ids, seen = {}, {}
    for _, key in ipairs(picked) do
        for _, leaf in ipairs(CDM:IsGroup(key) and CDM:GetLeaves(key) or { key }) do
            if not seen[leaf] then
                seen[leaf] = true
                ids[#ids + 1] = leaf
            end
        end
    end
    return ids, true
end

local treeDirty = false
-- made with the tree, so its draw waits for the window to show
local drawer ---@type Frame

---Draw the tree now, which a queued draw then doesn't repeat.
---@param tree table
---@return table leaves
local function DrawTree(tree)
    treeDirty = false
    return tree:SetItems()
end

local function DrawIfDirty()
    local tree = Tree()
    if not (treeDirty and tree) then return end

    if tree.frame:IsVisible() then
        DrawTree(tree)
    else
        drawer:NCScheduleUpdate() -- a slider let go as the window closed
    end
end

local function RefreshTree()
    local tree = Tree()
    if not tree then return end

    treeDirty = true
    if not drawer then
        drawer = CreateFrame('Frame', nil, tree.frame)
        -- one draw for all of a frame's changes, once the window shows and no slider is held
        drawer:NCSetScheduledUpdate(function()
            Kaji.AfterSliderDrag(DrawIfDirty)
        end, true)
    end
    drawer:NCScheduleUpdate()
end

-- the tree's own drop or rename draws at once: a frame later its rows flash the old state
local function RedrawTree()
    local tree = Tree()
    if tree then
        DrawTree(tree)
    end
end

local function Reopen(selectKey)
    local window = NRSKNUI.GUIFrame
    if not window then return end

    if selectKey and CDM:Get(selectKey) then
        for _, ancestor in ipairs(CDM:GetAncestors(selectKey)) do
            expandedGroups[CDM:Get(ancestor).uid] = true
        end
    end

    -- on the open page the tree stays: it draws once and the row is selected as a click does
    local tree = Tree()
    if not (tree and window:IsShown()) then
        window:ShowPage(PAGE, selectKey and { itemKey = selectKey } or nil)
        return
    end

    local key = selectKey or tree:GetSelected()
    CDM:SetSelectionPreview(CDM:Get(key) and key or nil) -- before the draw, so it shows the preview
    local found = false
    for _, data in ipairs(DrawTree(tree)) do
        if data.key == key then
            found = true
            break
        end
    end
    tree:Select(found and key or GENERAL, true) -- picks stay while the key is among them
end

IconPicker.navigate = Reopen

---@param itemKey string? the Global Settings item to open on
local function ShowGlobalSettings(itemKey)
    NRSKNUI.GUIFrame:ShowPage(PAGE, { itemKey = GLOBAL, subItemKey = itemKey })
end

---What rebuilds when a display joins or leaves a group: a dynamic group lays out its
---displays, a static one draws nothing, so there only the display itself.
---@param groupId string?
---@param id string
---@return string
local function Holder(groupId, id)
    return CDM:IsDynamic(groupId) and groupId --[[@as string]] or id
end

---@param id string?
---@return fun()
local function Applier(id)
    return function() CDM:ApplySettings(id) end
end

---@param key string
---@return boolean
local function IsCollapsed(key)
    return NRSKNUI.db.global.SidebarCollapsed[PAGE][key] == true
end

Shared.AURA_GROUP_TABS = AURA_GROUP_TABS
Shared.MULTI_TABS = MULTI_TABS
Shared.EditTargets = EditTargets
Shared.Applier = Applier
Shared.GENERAL = GENERAL
Shared.GLOBAL = GLOBAL
Shared.Holder = Holder
Shared.IMPORT = IMPORT
Shared.NEW = NEW
Shared.IsCollapsed = IsCollapsed
Shared.NEW_TILE_HEIGHT = NEW_TILE_HEIGHT
Shared.NEW_TILE_ICON = NEW_TILE_ICON
Shared.NEW_TILE_PREVIEW = NEW_TILE_PREVIEW
Shared.PAGE = PAGE
Shared.POWER_MODES = POWER_MODES
Shared.QUESTION_MARK = QUESTION_MARK
Shared.RedrawTree = RedrawTree
Shared.RefreshTree = RefreshTree
Shared.Reopen = Reopen
Shared.SECTION_LOADED = SECTION_LOADED
Shared.SECTION_UNLOADED = SECTION_UNLOADED
Shared.ShowGlobalSettings = ShowGlobalSettings
Shared.TABS = TABS
Shared.TRINKETS = TRINKETS
Shared.TYPE_NAMES = TYPE_NAMES
Shared.Tree = Tree
Shared.expandedGroups = expandedGroups
