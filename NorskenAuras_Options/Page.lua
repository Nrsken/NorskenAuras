---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local GUI = NRSKNUI.GUI
local IconPicker = NRSKNUI.CDMIconPicker

local ipairs = ipairs
local select = select

local Shared = NRSKNUI.CDMOptions
local AURA_GROUP_TABS = Shared.AURA_GROUP_TABS
local Applier = Shared.Applier
local BuildDisplayTab = Shared.BuildDisplayTab
local BuildGroupTab = Shared.BuildGroupTab
local BuildImportPage = Shared.BuildImportPage
local BuildInformationTab = Shared.BuildInformationTab
local BuildLoadTab = Shared.BuildLoadTab
local BuildAuraGroupTriggerTab = Shared.BuildAuraGroupTriggerTab
local BuildNewPage = Shared.BuildNewPage
local BuildTriggerTab = Shared.BuildTriggerTab
local BuildTrinketPage = Shared.BuildTrinketPage
local BuildHomePage = Shared.BuildHomePage
local ContextMenu = Shared.ContextMenu
local IMPORT = Shared.IMPORT
local MultiContextMenu = Shared.MultiContextMenu
local NEW = Shared.NEW
local PAGE = Shared.PAGE
local PreviewLevel = Shared.PreviewLevel
local RefreshTree = Shared.RefreshTree
local SectionIcons = Shared.SectionIcons
local TABS = Shared.TABS
local TRINKETS = Shared.TRINKETS
local TreeContent = Shared.TreeContent
local TriggerChip = Shared.TriggerChip
local TriggerTitle = Shared.TriggerTitle
local expandedGroups = Shared.expandedGroups
local EditTargets = Shared.EditTargets
local MULTI_TABS = Shared.MULTI_TABS
local Reopen = Shared.Reopen

GUI:RegisterPage(PAGE, {
    mode = 'tabs',
    search = { L['Cooldown & Aura Manager'], L['Sub Elements'], L['Swipe Settings'] },
    onEnter = function()
        CDM.onStateChanged = RefreshTree
    end,
    onLeave = function()
        CDM.onStateChanged = nil
        CDM:SetSelectionPreview(nil)
    end,
    sidebar = {
        width = 260,
        create = NRSKNUI.Kaji.CreateItemTree,
        items = TreeContent,
        actions = {
            { text = L['New'], icon = NRSKNUI.Media.GUITextures .. 'plus-sign.png', onClick = function() Reopen(NEW) end },
            { text = L['Import'], icon = NRSKNUI.Media.GUITextures .. 'arrow-down-to-line.png', onClick = function() Reopen(IMPORT) end },
        },
        onSelectionChanged = function(key)
            CDM:SetSelectionPreview(CDM:Get(key) and key or nil)
        end,
        onToggleExpanded = function(key, expanded)
            if CDM:IsGroup(key) then
                expandedGroups[CDM:Get(key).uid] = expanded or nil
            else
                NRSKNUI.db.global.SidebarCollapsed[PAGE][key] = (not expanded) or nil
            end
        end,
        onRename = function(key, text)
            CDM:Rename(key, text)
            RefreshTree()
        end,
        -- Into a group that can hold it, or next to a display inside one, the top level stays alphabetical.
        canDrop = function(item, target, position)
            if position == 'into' then return target.isGroup and CDM:CanContain(target.key, item.key) end
            local parent = CDM:Get(target.key).parent
            return parent ~= nil and CDM:CanContain(parent, item.key)
        end,
        onMove = function(keys, targetKey, position)
            -- A display inside a moved group travels with it.
            local moving, top = {}, {}
            for _, key in ipairs(keys) do moving[key] = true end
            for _, key in ipairs(keys) do
                local inside = false
                for _, ancestor in ipairs(CDM:GetAncestors(key)) do
                    if moving[ancestor] then
                        inside = true
                        break
                    end
                end
                if not inside then top[#top + 1] = key end
            end
            -- Into a group each one leads it, after a display each one follows it: reversed, they keep their order.
            local reverse = position ~= 'before'
            for i = reverse and #top or 1, reverse and 1 or #top, reverse and -1 or 1 do
                if position == 'into' then
                    CDM:SetParent(top[i], targetKey, true)
                else
                    CDM:MoveNextTo(top[i], targetKey, position)
                end
            end
            CDM:ApplySettings()
            RefreshTree()
        end,
        onMoveInGroup = function(key, delta)
            CDM:MoveInGroup(key, delta)
            CDM:ApplySettings(CDM:Get(key).parent)
            RefreshTree()
        end,
        onUngroup = function(key)
            CDM:Ungroup(key)
            CDM:ApplySettings()
            RefreshTree()
        end,
        onTogglePreview = function(key)
            CDM:SetPreview(key, CDM:GetPreview(key) == 2 and 0 or 2)
        end,
        onSectionPreview = function(sectionKey)
            for _, section in ipairs(TreeContent().sections) do
                if section.key == sectionKey then
                    local ids = SectionIcons(section)
                    local level = PreviewLevel(ids) ~= 2 and 2 or nil
                    for _, id in ipairs(ids) do CDM.preview[id] = level end
                    CDM:RefreshLoad()
                end
            end
        end,
        onContextMenu = function(key)
            if CDM:Get(key) then ContextMenu(key) end
        end,
        onMultiContextMenu = MultiContextMenu,
        -- a Ctrl/Shift pick turns the shown row's page into the multi edit and back
        onPicksChanged = function()
            local tree = Shared.Tree()
            Reopen(tree and tree:GetSelected())
        end,
    },
    tabs = function(itemKey)
        local display = CDM:Get(itemKey)
        -- the home, new and other pages have no tabs
        if not display then
            return {}
        end

        if select(2, EditTargets(itemKey)) then
            return MULTI_TABS
        end
        if display.type == 'auragroup' then
            return AURA_GROUP_TABS
        end

        -- a group has no triggers of its own and its children's work too differently to edit together
        local skip = CDM:IsGroup(itemKey) and 'trigger' or 'group'
        local tabs = {}
        for _, tab in ipairs(TABS) do
            if tab.id ~= skip then
                tabs[#tabs + 1] = tab
            end
        end
        return tabs
    end,
    build = function(page, tabId, itemKey)
        local display = CDM:Get(itemKey)
        if itemKey == IconPicker.PAGE then
            IconPicker:Build(page)
            return
        end
        IconPicker:Release()
        IconPicker.currentKey = itemKey

        if itemKey == TRINKETS then
            BuildTrinketPage(page)
            return
        elseif itemKey == IMPORT then
            BuildImportPage(page)
            return
        elseif itemKey == NEW then
            BuildNewPage(page)
            return
        elseif not display then
            BuildHomePage(page)
            return
        end

        if tabId == 'group' then
            BuildGroupTab(page, itemKey)
        elseif tabId == 'display' then
            BuildDisplayTab(page, itemKey)
        elseif tabId == 'trigger' and CDM.LAYERED_TYPES[display.type] then
            BuildTriggerTab(page, itemKey)
        elseif tabId == 'trigger' and display.type == 'auragroup' then
            BuildAuraGroupTriggerTab(page, itemKey)
        elseif tabId == 'conditions' then
            NRSKNUI.CDMConditionsTab:Build(page, itemKey, Applier(itemKey), TriggerTitle, TriggerChip)
        elseif tabId == 'load' then
            BuildLoadTab(page, itemKey)
        elseif tabId == 'information' then
            BuildInformationTab(page, itemKey)
        end
    end,
})
