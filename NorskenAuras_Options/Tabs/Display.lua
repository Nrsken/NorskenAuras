---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

local ipairs = ipairs

local Shared = NRSKNUI.CDMOptions
local Applier = Shared.Applier
local RefreshTree = Shared.RefreshTree
local TriggerChip = Shared.TriggerChip
local EditTargets = Shared.EditTargets

local format = string.format

-- a group or selection holding several types: a block per type, in this order
local TYPE_ORDER = { 'icon', 'bar', 'text' }
local TYPE_TITLES = { icon = L['Icons (%d)'], bar = L['Bars (%d)'], text = L['Texts (%d)'] }

---@param page table
---@param id string
local function BuildDisplayTab(page, id)
    local targets, multi = EditTargets(id)
    -- an aura group's buttons take an icon's look, applied to the group
    if not multi and CDM:Get(id).type == 'auragroup' then
        NRSKNUI.CDMDisplayTab:Build(page, { id }, Applier(id), RefreshTree, TriggerChip)
        return
    end

    -- icons, bars and texts edit together; an aura group keeps its look on its own page
    local ids, byType, kinds = {}, {}, 0
    for _, key in ipairs(targets) do
        local kind = CDM:Get(key).type
        if CDM.LAYERED_TYPES[kind] then
            ids[#ids + 1] = key
            if not byType[kind] then
                byType[kind] = {}
                kinds = kinds + 1
            end
            local list = byType[kind]
            list[#list + 1] = key
        end
    end

    -- A look change rebuilds only these, wherever they sit; a full apply on every slider step was the multi edit lag.
    local DisplayTab = NRSKNUI.CDMDisplayTab
    if kinds <= 1 then
        DisplayTab:Build(page, ids, function() CDM:ApplyDisplays(ids) end, RefreshTree, TriggerChip)
        return
    end

    -- several types: a block each editing only its own; what they all share sits on the All card
    for _, kind in ipairs(TYPE_ORDER) do
        local list = byType[kind]
        if list then
            DisplayTab:Build(page, list, function() CDM:ApplyDisplays(list) end, RefreshTree, TriggerChip, {
                title = format(TYPE_TITLES[kind], #list),
                noGeneral = true,
            })
        end
    end
    DisplayTab:BuildShared(page, ids, function() CDM:ApplyDisplays(ids) end)
end

Shared.BuildDisplayTab = BuildDisplayTab
