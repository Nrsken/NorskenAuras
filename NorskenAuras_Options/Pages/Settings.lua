---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight
local rowHL = Theme.rowHeightLast

local ipairs = ipairs

local GUI = NRSKNUI.GUI
local SharedPages = NRSKNUI.GUISharedPages
local Shared = NRSKNUI.CDMOptions
local PAGE, RefreshTree, ScheduleAnchorUpdate = Shared.PAGE, Shared.RefreshTree, Shared.ScheduleAnchorUpdate
local SETTINGS_PAGE, TRINKETS = Shared.SETTINGS_PAGE, Shared.TRINKETS
local BuildTrinketPage = Shared.BuildTrinketPage

local GENERAL_ITEM = 'general'

local function ShowTheme()
    NRSKNUI.GUIFrame:ShowPage(SETTINGS_PAGE, { itemKey = 'themePage' })
end

Shared.ShowTheme = ShowTheme

local SHARED_BUILDS = {
    globalFonts = function(page) SharedPages:BuildFonts(page) end,
    globalTextures = function(page) SharedPages:BuildTextures(page) end,
    globalDurationText = function(page) SharedPages:BuildDurationText(page) end,
    globalLanguage = function(page) SharedPages:BuildLanguage(page, NRSKNUI) end,
    themePage = function(page) SharedPages:BuildTheme(page, ShowTheme) end,
}

local GLOBAL_PAGES = {
    { key = 'globalFonts',        text = L['Fonts'] },
    { key = 'globalTextures',     text = L['Textures'] },
    { key = 'globalDurationText', text = L['Duration Text'] },
    { key = 'globalLanguage',     text = L['Language'] },
    { key = 'themePage',          text = L['Theme'] },
}

---@param page table
local function BuildGeneralPage(page)
    SharedPages:LauncherRow(page:Card(L['General'], 'all'), NRSKNUI, rowHL)

    local integration = page:Card(L['Integration'], 'all')
    integration:Row(rowH):Checkbox(L['Hide Blizzard Player Cast Bar'], {
        width = 1,
        value = CDM.db.HidePlayerCastBar,
        tooltip = L["For a cast bar of your own. Showing Blizzard's again takes a reload."],
        callback = function(checked)
            CDM.db.HidePlayerCastBar = checked
            if checked and CDM:IsEnabled() then
                CDM:HidePlayerCastBar()
            elseif not checked then
                NRSKNUI:CreatePrompt({
                    title = L['Reload UI'],
                    text = L["Blizzard's cast bar comes back after a reload. Reload now?"],
                    onAccept = ReloadUI,
                })
            end
        end,
    })
    if not C_AddOns.IsAddOnLoaded('NorskenUI_UnitFrames') then return end

    integration:Separator()
    integration:Row(rowHL, 0):Slider(L['Unit Frame Anchor Minimum Width'], {
        width = 1,
        min = 0,
        max = 600,
        step = 1,
        value = CDM.db.AnchorMinWidth,
        tooltip = L['The unit frame anchor is never narrower than this, so frames beside it keep their distance from a short group.'],
        callback = function(value)
            CDM.db.AnchorMinWidth = value
            ScheduleAnchorUpdate()
        end,
    })
end

---@return table[]
local function SettingsItems()
    local items = {
        { type = 'label', key = 'cdm:settings', text = L['Cooldown & Aura Manager'] },
        { key = GENERAL_ITEM, text = L['General'] },
        { key = TRINKETS, text = L['Trinket Blacklist'] },
    }
    for _, item in ipairs(SharedPages.ColorCategories) do
        items[#items + 1] = item
    end
    items[#items + 1] = { type = 'label', key = 'cdm:global', text = L['Global Settings'] }
    for _, item in ipairs(GLOBAL_PAGES) do
        items[#items + 1] = item
    end
    return items
end

GUI:RegisterPage(SETTINGS_PAGE, {
    mode = 'clean',
    sidebar = {
        items = SettingsItems,
        default = GENERAL_ITEM,
        buttons = {
            {
                text = L['Back'],
                onClick = function() NRSKNUI.GUIFrame:ShowPage(PAGE) end,
            },
        },
    },
    build = function(page, _, itemKey, item)
        if itemKey == GENERAL_ITEM then
            BuildGeneralPage(page)
        elseif itemKey == TRINKETS then
            Shared.trinketReturnKey = nil -- this way in has no trigger to go back to
            BuildTrinketPage(page)
        elseif item.specs then
            SharedPages:BuildColors(page, item)
        elseif SHARED_BUILDS[itemKey] then
            SHARED_BUILDS[itemKey](page)
        end
    end,
})
