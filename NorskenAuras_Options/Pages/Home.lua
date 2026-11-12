---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight
local rowHL = Theme.rowHeightLast
local GUI = NRSKNUI.GUI
local SharedPages = NRSKNUI.GUISharedPages
local Shared = NRSKNUI.CDMOptions
local Reopen = Shared.Reopen
local ScheduleAnchorUpdate = Shared.ScheduleAnchorUpdate
local ShowGlobalSettings = Shared.ShowGlobalSettings

local IsAddOnLoaded = C_AddOns.IsAddOnLoaded

local BUTTON_HEIGHT = 32

SharedPages:RegisterGlobalPage(GUI, NRSKNUI, ShowGlobalSettings)

---What shows with no display picked: the addon's own settings.
---@param page table
local function BuildHomePage(page)
    SharedPages:QuickActions(SharedPages:WelcomeCard(page, NRSKNUI, L['Welcome to NorskenAuras']), NRSKNUI)

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
                GUI:Prompt({
                    title = L['Reload UI'],
                    text = L["Blizzard's cast bar comes back after a reload. Reload now?"],
                    onAccept = ReloadUI,
                })
            end
        end,
    })
    if IsAddOnLoaded('NorskenUI_UnitFrames') then
        integration:Separator()
        integration:Row(rowHL, 0):Slider(L['Minimum Unit Frame Gap'], {
            width = 1,
            min = 0,
            max = 600,
            step = 1,
            value = CDM.db.AnchorMinWidth,
            tooltip = L['Unit frames anchored to your cooldowns stay at least this far apart, even when only a few cooldowns show.'],
            callback = function(value)
                CDM.db.AnchorMinWidth = value
                ScheduleAnchorUpdate()
            end,
        })
    end

    page:Card(L['Trinket Blacklist'], 'all'):Row(BUTTON_HEIGHT + 2):Button(L['Open Trinket Blacklist'], {
        width = 1,
        height = BUTTON_HEIGHT,
        yOffset = -2,
        tooltip = L['Trinkets that are never tracked, for on-use effects that only switch a mode.'],
        callback = function()
            Shared.trinketReturnKey = nil -- this way in has no trigger to go back to
            Reopen(Shared.TRINKETS)
        end,
    })

    SharedPages:SupportCard(page, NRSKNUI)
end

Shared.BuildHomePage = BuildHomePage
