---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
local L = NRSKNUI.Libs.AL
local GUI = NRSKNUI.GUI

local PreviewManager = NRSKNUI.PreviewManager
local SharedPages = NRSKNUI.GUISharedPages
local Shared = NRSKNUI.CDMOptions
local GENERAL = Shared.GENERAL
local PAGE = Shared.PAGE
local Reopen = Shared.Reopen
local ShowGlobalSettings = Shared.ShowGlobalSettings
local UpdateBox = Shared.UpdateBox

local LOGO = 'Interface\\AddOns\\NorskenCore\\Media\\Logo\\'
local AURAS_MEDIA = 'Interface\\AddOns\\NorskenAuras\\Media\\Logo\\'

-- a slider on a position card moves the overlay it belongs to
GUI.services.positionSync = {
    Changed = function()
        if NRSKNUI.Anchors:IsActive() then
            NRSKNUI.Anchors:OnExternalPositionChange()
        end
    end,
}

local window ---@type GUIFrame declared first, onShow below refers to it
window = GUI:CreateGUIWindow({
    name = 'NorskenAurasFrame',
    size = { 950, 700 },
    minSize = { 800, 700 },
    defaultPage = PAGE,
    logo = {
        layers = {
            {
                texture = LOGO .. 'logocookingsPT1128x128OT.png',
                glow = LOGO .. 'logocookingsPT1128x128OT_glow.png',
                size = 64,
                anchor = { 'LEFT', 'LEFT', -10, 1 },
                color = 'accent',
                alpha = 0.7,
            },
            {
                texture = AURAS_MEDIA .. 'logocookingsPT2128x128OT.png',
                size = 128,
                anchor = { 'LEFT', 1, 'RIGHT', -22, -4 },
                color = 'textSecondary'
            },
        },
    },
    state = {
        load = function()
            return NRSKNUI.db.global.GUIState
        end,
        save = function(data)
            data.currentPage = nil
            NRSKNUI.db.global.GUIState = data
        end,
    },
    onShow = function()
        NRSKNUI.GUIOpen = true
        PreviewManager:SetGUIOpen(true)
        PreviewManager:SetPage(window.content.currentId)
    end,
    onClose = function()
        NRSKNUI.GUIOpen = false
        NRSKNUI:PromptPendingReload()
        PreviewManager:SetGUIOpen(false)
    end,
    onCombatDefer = function()
        NRSKNUI:Print(L['Options will open after combat ends.'])
    end,
})

window:AddHeaderButton(SharedPages:HeaderButton('close', function() window:Hide() end))
window:AddHeaderButton(SharedPages:HeaderButton('home', function() Reopen(GENERAL) end))
window:AddHeaderButton(SharedPages:HeaderButton('global', function() ShowGlobalSettings() end))
window:AddHeaderButton(SharedPages:HeaderButton('theme', function() ShowGlobalSettings(SharedPages.THEME_ITEM) end))
local gridButton = window:AddHeaderButton(SharedPages:HeaderButton('grid', function(btn)
    local shown = not NRSKNUI:GetAnchorsSettings().Grid
    NRSKNUI.Anchors:SetGrid(shown)
    btn:SetActive(shown)
end))

window.content.onPageChanged = function(pageId, previousId)
    PreviewManager:SetPage(pageId)
    UpdateBox()
    if pageId ~= previousId then
        NRSKNUI:PromptPendingReload()
    end
end

-- the frame's own scripts, so anchors mode putting the window away takes the box too
window.frame:HookScript('OnShow', function()
    -- account-wide, anchors mode may have changed it
    gridButton:SetActive(NRSKNUI:GetAnchorsSettings().Grid)
    UpdateBox()
end)
window.frame:HookScript('OnHide', UpdateBox)

SharedPages:AddSupportFooter(window, NRSKNUI)

NRSKNUI.GUIFrame = window --[[@as GUIFrame]]
