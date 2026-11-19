---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local format = string.format
local CopyTable = CopyTable
local tostring = tostring
local sort = table.sort
local ipairs = ipairs
local abs = math.abs
local pairs = pairs
local next = next
local time = time
local type = type

local PREFIX = '!NAURAS1!'
local FORMAT_VERSION = 1
local MAX_DEPTH = 32

-- The parts an update can take from an import, as the import page lists them
CDM.IMPORT_CATEGORIES = {
    { key = 'name',        label = L['Names'],                    fields = { 'name' },                                                                                        default = true },
    { key = 'position',    label = L['Size & Position'],          fields = { 'Position', 'anchorFrameType', 'ParentFrame', 'Strata', 'MatchWidth', 'MatchSide', 'MatchGap' }, default = false },
    { key = 'display',     label = L['Display'],                  fields = {},                                                                                                default = true },
    { key = 'trigger',     label = L['Trigger'],                  fields = { 'Triggers', 'Trigger', 'Activation', 'DynamicTrigger' },                                         default = true },
    { key = 'conditions',  label = L['Conditions'],               fields = { 'Conditions' },                                                                                  default = true },
    { key = 'load',        label = L['Load'],                     fields = { 'Load', 'Enabled' },                                                                             default = true },
    { key = 'arrangement', label = L['Group Arrangement'],        fields = { 'Layout' },                                                                                      default = true },
    { key = 'metadata',    label = L['Meta Data'],                fields = { 'Description' },                                                                                 default = true },
    { key = 'newchildren', label = L['Add Missing Displays'],     fields = {},                                                                                                default = true },
    { key = 'oldchildren', label = L['Remove Obsolete Displays'], fields = {},                                                                                                default = true },
}

local FIELD_CATEGORY = {}
for _, category in ipairs(CDM.IMPORT_CATEGORIES) do
    for _, field in ipairs(category.fields) do
        FIELD_CATEGORY[field] = category.key
    end
end

-- Tree bookkeeping, never compared or copied between a match
local INTERNAL = { uid = true, parent = true, order = true, builtin = true, preferToUpdate = true }
local SIZE_KEYS = { Width = true, Height = true }

-- Shared --

-- Size and position are the root's own, inside a group they're how the group is arranged
---@param key string
---@param isRoot boolean
---@return string
local function FieldCategory(key, isRoot)
    local category = FIELD_CATEGORY[key] or 'display'
    if category == 'position' and not isRoot then
        return 'arrangement'
    end
    return category
end

---@param a any
---@param b any
---@return boolean
local function Equal(a, b)
    if type(a) == 'number' and type(b) == 'number' then
        return abs(a - b) < 1e-6
    end
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return a == b
    end
    for key, value in pairs(a) do
        if not Equal(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

---@param value any
---@return any
local function Copy(value)
    return type(value) == 'table' and CopyTable(value) or value
end

---@param id string
---@param into string[]
---@return string[]
local function CollectSubtree(id, into)
    into[#into + 1] = id
    for _, child in ipairs(CDM:GetChildren(id)) do
        CollectSubtree(child.key, into)
    end

    return into
end

-- A payload display's children in their saved order
---@param d table<string, CDMDisplay>
---@param parentKey string
---@return string[]
local function PayloadChildren(d, parentKey)
    local keys = {}
    for key, display in pairs(d) do
        if display.parent == parentKey then
            keys[#keys + 1] = key
        end
    end

    sort(keys, function(a, b)
        local oa, ob = d[a].order or 0, d[b].order or 0
        if oa ~= ob then
            return oa < ob
        end
        return a < b
    end)
    return keys
end

-- Export --

---A display and everything inside it as an import string
---@param id string
---@return string? text
function CDM:Export(id)
    if not self:Get(id) then return nil end

    local d = {}
    for _, key in ipairs(CollectSubtree(id, {})) do
        local copy = CopyTable(self:Get(key))
        -- A shared built-in is the importer's own
        copy.builtin, copy.preferToUpdate = nil, nil
        d[key] = copy
    end
    d[id].parent = nil
    d[id].order = nil
    for _, copy in pairs(d) do
        if copy.MatchWidth and not d[copy.MatchWidth] then
            copy.MatchWidth = nil
        end
    end

    local payload = { _v = FORMAT_VERSION, _s = self.SCHEMA_VERSION, _a = NRSKNUI.Version, _t = time(), root = id, d = d }
    local encoded = NRSKNUI:EncodeTable(payload)
    if not encoded then return nil end

    return PREFIX .. encoded
end

-- Decode --

-- A missing or wrongly typed field takes the default, nested tables too, in the WA style
-- A field the default doesn't have is left alone
---@param input table
---@param default table
local function Conform(input, default)
    for key, value in pairs(default) do
        local have = input[key]
        if type(value) == 'table' then
            if type(have) ~= 'table' then
                input[key] = CopyTable(value)
            else
                Conform(have, value)
            end
        elseif type(have) ~= type(value) then
            input[key] = value
        end
    end
end

-- A missing or wrongly typed field takes the template's
-- A table is only filled when missing, deeper would add choices to a trigger's own options
---@param trigger CDMTrigger
local function ConformTrigger(trigger)
    -- An empty list is saved as none, as the options save it
    if type(trigger.SpellIDs) ~= 'table' or not trigger.SpellIDs[1] then
        trigger.SpellIDs = nil
    end
    local conform = CDM.TriggerTypes[trigger.Type].Conform
    if conform then
        conform(trigger)
    end
    for key, value in pairs(CDM.TRIGGER_TEMPLATES[trigger.Type]) do
        if type(trigger[key]) ~= type(value) then
            trigger[key] = type(value) == 'table' and CopyTable(value) or value
        end
    end
end

-- A grow no group knows takes the template's
---@param layout CDMLayout
---@param default string
local function ConformGrow(layout, default)
    if not NRSKNUI:HasDynamicGroupGrower(layout.Grow) then
        layout.Grow = default
    end
end

-- An icon's look, which an aura group's buttons share
---@param display CDMDisplay
local function ConformLook(display)
    if type(display.SubRegions) ~= 'table' then
        display.SubRegions = display.type == 'auragroup' and NRSKNUI:DefaultAuraGroupSubRegions() or {}
    end
    Conform(display, { Style = CDM.STYLE_TEMPLATES[display.type] })
    for _, element in ipairs(display.SubRegions) do
        Conform(element, NRSKNUI.SUBREGION_TEMPLATES[element.type])
    end
end

-- All of and Any of need their list, a plain check its trigger
-- Talent checks get their entry list only with fill, so a refused display stays as saved
---@param display CDMDisplay
---@param check any
---@param fill boolean
---@return boolean ok
local function ConformCheck(display, check, fill)
    if type(check) ~= 'table' then return false end

    if CDM.COMBINATIONS[check.variable] then
        if type(check.checks) ~= 'table' then return false end
        for _, sub in ipairs(check.checks) do
            if not ConformCheck(display, sub, fill) then return false end
        end
        return true
    end

    if type(check.trigger) ~= 'number' then return false end
    if check.entries ~= nil then
        return type(check.entries) == 'table'
    end
    local trigger = CDM:GetCheckTrigger(display, check.trigger)
    local checks = trigger and CDM.ConditionChecks[trigger.Type]
    local def = checks and checks[check.variable]
    if fill and def and def.talents then
        check.entries = {}
    end
    return true
end

-- What no default fills, as dropping a trigger, element or condition moves numbers after it
---@param display table
---@return boolean
local function Repairable(display)
    if not CDM.DISPLAY_TYPES[display.type] then return false end

    if CDM.LAYERED_TYPES[display.type] then
        if type(display.Triggers) ~= 'table' then return false end
        for _, trigger in ipairs(display.Triggers) do
            if type(trigger) ~= 'table' or not CDM.TRIGGER_TEMPLATES[trigger.Type] then return false end
        end
    end
    if type(display.SubRegions) == 'table' then
        for _, element in ipairs(display.SubRegions) do
            if type(element) ~= 'table' or not NRSKNUI.SUBREGION_TEMPLATES[element.type] then return false end
        end
    end
    if type(display.Conditions) == 'table' then
        for _, condition in ipairs(display.Conditions) do
            if type(condition) ~= 'table' or not ConformCheck(display, condition.check, false) then return false end
        end
    end
    return true
end

---Fill in an imported or saved display so nothing reads a missing field, in the WA style
---False only for what can't be filled, as a trigger or condition number would move
---@param display table
---@param id string its key, the name when it has none
---@return boolean ok
function CDM:ConformDisplay(display, id)
    if not Repairable(display) then return false end

    if type(display.name) ~= 'string' then
        display.name = id
    end
    if type(display.uid) ~= 'string' then
        display.uid = self:NewUid()
    end
    if type(display.Enabled) ~= 'boolean' then
        display.Enabled = false
    end
    if type(display.anchorFrameType) ~= 'string' then
        display.anchorFrameType = 'UIPARENT'
    end
    if type(display.ParentFrame) ~= 'string' then
        display.ParentFrame = 'UIParent'
    end
    if type(display.Conditions) ~= 'table' then
        display.Conditions = {}
    end
    for _, condition in ipairs(display.Conditions) do
        ConformCheck(display, condition.check, true)
        if type(condition.changes) ~= 'table' then
            condition.changes = {}
        end
    end
    Conform(display, { Position = CDM.POSITION_TEMPLATE })

    if CDM.LAYERED_TYPES[display.type] then
        for _, trigger in ipairs(display.Triggers) do
            ConformTrigger(trigger)
        end
        ConformLook(display)
        Conform(display, { Load = NRSKNUI.LoadConditions:GetDefaults() })
    elseif display.type == 'auragroup' then
        if type(display.Trigger) ~= 'table' then
            display.Trigger = NRSKNUI.AuraTriggers:New()
        end
        local unit = display.Trigger.Unit
        if not NRSKNUI:IsValidUnitToken(unit) then
            NRSKNUI:Print(format(L['Aura group "%s" had an unusable unit (%s), so it now watches the player.'], display.name, tostring(unit)))
            display.Trigger.Unit = 'player'
        end
        Conform(display, CDM.AURA_GROUP_TEMPLATE)
        ConformGrow(display.Layout, CDM.AURA_GROUP_TEMPLATE.Layout.Grow)
        ConformLook(display)
        Conform(display, { Load = NRSKNUI.LoadConditions:GetDefaults() })
    else
        -- A group draws nothing of its own, so a look it carries is dropped
        display.Style = nil
        display.SubRegions = nil
        if display.type == 'dynamicgroup' then
            Conform(display, { Layout = CDM.LAYOUT_TEMPLATE })
            ConformGrow(display.Layout, CDM.LAYOUT_TEMPLATE.Grow)
        end
    end
    return true
end

-- Every display in a payload is reachable from the root and the tree follows the group rules
---@param d table<string, CDMDisplay>
---@param root string
---@return string? error
local function ValidateTree(d, root)
    local uids = {}
    for key, display in pairs(d) do
        if type(key) ~= 'string' or type(display) ~= 'table' or not CDM:ConformDisplay(display, key) then
            return L['The string is damaged.']
        end
        -- A uid twice would match two displays to one, so the second gets its own
        if uids[display.uid] then
            display.uid = CDM:NewUid()
        end
        uids[display.uid] = true

        if key == root then
            if display.parent ~= nil then
                return L['The string is damaged.']
            end
        else
            local parent = d[display.parent]
            if not parent or not CDM:HoldsType(parent.type, display.type) then
                return L['The string is damaged.']
            end

            local walk, depth = display, 0
            while walk.parent ~= nil do
                depth = depth + 1
                if depth > MAX_DEPTH then
                    return L['The string is damaged.']
                end
                walk = d[walk.parent]
                if not walk then
                    return L['The string is damaged.']
                end
            end
        end

        -- A Match Width group that didn't come along is dropped
        if display.MatchWidth ~= nil and (type(display.MatchWidth) ~= 'string' or not d[display.MatchWidth]) then
            display.MatchWidth = nil
        end
    end
end

---Read an import string, nil with an error the page can show when it isn't one
---@param text string
---@return CDMImportPayload?
---@return string? error
function CDM:DecodeImport(text)
    -- Base64 has no whitespace, so a string copied in wrapped lines still reads
    text = text:gsub('%s+', '')
    if text == '' then return nil end
    if text:sub(1, #PREFIX) ~= PREFIX then
        return nil, L['This is not a NorskenAuras string.']
    end

    local payload = NRSKNUI:DecodeTable(text:sub(#PREFIX + 1))
    if not payload or type(payload.d) ~= 'table' or type(payload.root) ~= 'string'
        or type(payload.d[payload.root]) ~= 'table' or type(payload._s) ~= 'number' then
        return nil, L['The string is damaged.']
    end
    if payload._s > self.SCHEMA_VERSION then
        return nil, L['This string was made with a newer NorskenAuras; update to import it.']
    end
    if payload._s < self.SCHEMA_VERSION then
        return nil, L['The string is damaged.']
    end

    local treeError = ValidateTree(payload.d, payload.root)
    if treeError then
        return nil, treeError
    end

    return payload
end

-- Match --

-- Which categories differ between a local display and its import
---@param old CDMDisplay
---@param new CDMDisplay
---@param isRoot boolean
---@param into table<string, true>
local function Differences(old, new, isRoot, into)
    local sizeCategory = isRoot and 'position' or 'arrangement'
    local function Compare(key)
        if INTERNAL[key] then return end
        if key == 'Style' then
            for styleKey in pairs(SIZE_KEYS) do
                if not Equal(old.Style[styleKey], new.Style[styleKey]) then
                    into[sizeCategory] = true
                end
            end
            for styleKey, value in pairs(old.Style) do
                if not SIZE_KEYS[styleKey] and not Equal(value, new.Style[styleKey]) then
                    into.display = true
                end
            end
            for styleKey in pairs(new.Style) do
                if not SIZE_KEYS[styleKey] and old.Style[styleKey] == nil then
                    into.display = true
                end
            end
        elseif not Equal(old[key], new[key]) then
            into[FieldCategory(key, isRoot)] = true
        end
    end
    for key in pairs(old) do
        Compare(key)
    end
    for key in pairs(new) do
        if old[key] == nil then
            Compare(key)
        end
    end
end

---What importing a payload would do, a match to update or a plain copy
---@param payload CDMImportPayload
---@return CDMImportPlan
function CDM:PlanImport(payload)
    local d, root = payload.d, payload.root
    local count = 0
    for _ in pairs(d) do
        count = count + 1
    end
    local plan = { payload = payload, count = count, matches = {}, added = {}, modified = {}, removed = {}, categories = {} }

    local target = self:GetByUid(d[root].uid)
    if not target or self:Get(target).type ~= d[root].type then
        -- The same uid on another kind of display, so only a copy makes sense
        plan.blocked = target ~= nil
        return plan
    end

    local localByUid = {}
    for _, id in ipairs(CollectSubtree(target, {})) do
        localByUid[self:Get(id).uid] = id
    end
    plan.target = target
    plan.matches[root] = target
    for key, display in pairs(d) do
        local id = key ~= root and localByUid[display.uid]
        if id then
            if self:Get(id).type ~= display.type then
                plan.blocked = true
                return plan
            end
            plan.matches[key] = id
        end
    end

    local matchedLocal = {}
    for key, id in pairs(plan.matches) do
        matchedLocal[id] = key
        local changed = {}
        Differences(self:Get(id), d[key], key == root, changed)
        if next(changed) then
            plan.modified[key] = changed
            for category in pairs(changed) do
                plan.categories[category] = true
            end
        end
        -- A matched display moved to another group
        if key ~= root and plan.matches[d[key].parent] ~= self:Get(id).parent then
            plan.categories.arrangement = true
        end
    end
    for key in pairs(d) do
        if not plan.matches[key] then
            plan.added[#plan.added + 1] = key
        end
    end
    for _, id in ipairs(CollectSubtree(target, {})) do
        if not matchedLocal[id] then
            plan.removed[#plan.removed + 1] = id
        end
    end
    if plan.added[1] then
        plan.categories.newchildren = true
    end
    if plan.removed[1] then
        plan.categories.oldchildren = true
    end

    -- Sibling order changed among displays both sides have
    for key, id in pairs(plan.matches) do
        if CDM.GROUP_TYPES[d[key].type] then
            local newOrder, oldOrder = {}, {}
            for _, childKey in ipairs(PayloadChildren(d, key)) do
                if plan.matches[childKey] then
                    newOrder[#newOrder + 1] = plan.matches[childKey]
                end
            end
            for _, child in ipairs(self:GetChildren(id)) do
                if matchedLocal[child.key] and plan.matches[d[matchedLocal[child.key]].parent] == id then
                    oldOrder[#oldOrder + 1] = child.key
                end
            end
            if not Equal(newOrder, oldOrder) then
                plan.categories.arrangement = true
            end
        end
    end

    return plan
end

-- Apply --

---@param parentId string
local function Renumber(parentId)
    for index, child in ipairs(CDM:GetChildren(parentId)) do
        CDM:Get(child.key).order = index
    end
end

-- An import as new displays at the top level, uids already in use get fresh ones
---@param payload CDMImportPayload
---@return string rootId
local function ImportAsCopy(payload)
    local d, root = payload.d, payload.root
    local store = CDM.db.Displays
    local used = {}
    for _, display in pairs(store) do
        used[display.uid] = true
    end

    local ids = {}
    for key, display in pairs(d) do
        local id = CDM.NextId()
        local copy = CopyTable(display)
        if used[copy.uid] then
            copy.uid = CDM:NewUid()
        end
        used[copy.uid] = true
        store[id] = copy
        ids[key] = id
    end
    for key, id in pairs(ids) do
        local display = store[id]
        display.parent = d[key].parent and ids[d[key].parent]
        display.MatchWidth = display.MatchWidth and ids[display.MatchWidth]
    end

    store[ids[root]].order = nil
    return ids[root]
end

-- The matched displays updated in place with the picked categories
---@param plan CDMImportPlan
---@param picked table<string, boolean>
local function ImportAsUpdate(plan, picked)
    local d, root = plan.payload.d, plan.payload.root
    local store = CDM.db.Displays
    local sizeCategory = function(key) return key == root and 'position' or 'arrangement' end

    -- Final id of every import key that ends up in the store
    local ids = {}
    for key, id in pairs(plan.matches) do
        ids[key] = id
    end
    if picked.newchildren then
        local used = {}
        for _, display in pairs(store) do
            used[display.uid] = true
        end
        for _, key in ipairs(plan.added) do
            local id = CDM.NextId()
            local copy = CopyTable(d[key])
            -- Moved out of the group locally, so it stays a separate display
            if used[copy.uid] then
                copy.uid = CDM:NewUid()
            end
            used[copy.uid] = true
            store[id] = copy
            ids[key] = id
        end
        for _, key in ipairs(plan.added) do
            local copy = store[ids[key]]
            copy.MatchWidth = copy.MatchWidth and ids[copy.MatchWidth]
        end
    end

    for key, id in pairs(plan.matches) do
        local old, new = store[id], d[key]
        local keys = {}
        for field in pairs(old) do
            keys[field] = true
        end
        for field in pairs(new) do
            keys[field] = true
        end
        for field in pairs(keys) do
            if not INTERNAL[field] and field ~= 'Style' and picked[FieldCategory(field, key == root)] then
                -- MatchWidth holds an import key, so it needs the id that key got here
                if field == 'MatchWidth' then
                    old.MatchWidth = new.MatchWidth and ids[new.MatchWidth]
                else
                    old[field] = Copy(new[field])
                end
            end
        end
        if new.Style then
            local style = picked.display and CopyTable(new.Style) or old.Style
            for sizeKey in pairs(SIZE_KEYS) do
                style[sizeKey] = picked[sizeCategory(key)] and new.Style[sizeKey] or old.Style[sizeKey]
            end
            old.Style = style
        end
    end

    -- The import's tree when Group Arrangement is picked, else the local one
    local touched = {}
    for key, id in pairs(ids) do
        if key ~= root and (picked.arrangement or not plan.matches[key]) then
            -- A new display's parent is always here, as missing ones come together or not at all
            local parentId = ids[d[key].parent]
            if parentId then
                store[id].parent = parentId
                store[id].order = d[key].order
                touched[parentId] = true
            end
        end
    end

    -- A new display goes after the one before it in the import, when that one is here too
    if not picked.arrangement then
        for _, key in ipairs(plan.added) do
            local id = ids[key]
            if id then
                local siblings, previous = PayloadChildren(d, d[key].parent), nil
                for _, sibling in ipairs(siblings) do
                    if sibling == key then break end
                    if ids[sibling] then
                        previous = ids[sibling]
                    end
                end
                local parentId = store[id].parent
                -- Between it and the next, Renumber evens it out
                if previous and store[previous].parent == parentId then
                    store[id].order = (store[previous].order or 0) + 0.5
                else
                    store[id].order = math.huge
                end
            end
        end
    end

    if picked.oldchildren then
        local removed = CopyTable(plan.removed)
        sort(removed, function(a, b) return CDM:GetDepth(a) > CDM:GetDepth(b) end)
        for _, id in ipairs(removed) do
            if CDM:Get(id) and not (CDM:IsGroup(id) and CDM:GetChildren(id)[1]) then
                touched[store[id].parent or ''] = true
                CDM:Delete(id)
            end
        end
    end

    for parentId in pairs(touched) do
        if store[parentId] then
            Renumber(parentId)
        end
    end
end

---Add or update displays from a planned import, the caller refreshes what shows
---@param plan CDMImportPlan
---@param mode 'copy'|'update'
---@param picked table<string, boolean> the update categories that were ticked
---@return string rootId
function CDM:ApplyImport(plan, mode, picked)
    local target = plan.target
    if mode == 'update' and target and not plan.blocked then
        ImportAsUpdate(plan, picked)
        -- A newer version of this string defaults to Update next time
        self:Get(target).preferToUpdate = true
        return target
    end
    return ImportAsCopy(plan.payload)
end
