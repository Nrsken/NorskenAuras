---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
local L = NRSKNUI.Libs.AL
local GUI = NRSKNUI.GUI
local Theme = NRSKNUI.Theme

local format = format

local PreviewManager = NRSKNUI.PreviewManager
local Shared = NRSKNUI.CDMOptions
local PAGE, SETTINGS_PAGE = Shared.PAGE, Shared.SETTINGS_PAGE

local TEX = NRSKNUI.Media.GUITextures
local LOGO = 'Interface\\AddOns\\NorskenCore\\Media\\Logo\\'
local AURAS_MEDIA = 'Interface\\AddOns\\NorskenAuras\\Media\\Logo\\'
local SOCIAL = 'Interface\\AddOns\\NorskenCore\\Media\\SupportLogos\\'

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
        version = NRSKNUI:GetVersionText(),
        versionAnchor = { 'LEFT', 1, 'RIGHT', 100, -7 },
        versionColor = 'textSecondary',
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

window:AddHeaderButton({
    icon = TEX .. 'NorskenCustomCrossv3.png',
    glow = TEX .. 'NorskenCustomCrossv3_glow.png',
    size = 22,
    rotation = 45,
    onClick = function()
        window:Hide()
    end,
    tooltip = L['Close Settings'],
})
window:AddHeaderButton({
    icon = TEX .. 'cogwheel.png',
    glow = TEX .. 'cogwheel_glow.png',
    size = 18,
    onClick = function()
        window:ShowPage(window.content.currentId == SETTINGS_PAGE and PAGE or SETTINGS_PAGE)
    end,
    tooltip = L['Cooldown & Aura Manager Settings'],
})
window:AddHeaderButton({
    icon = TEX .. 'anchor.png',
    glow = TEX .. 'anchor_glow.png',
    size = 22,
    onClick = function()
        NRSKNUI.Anchors:Enter()
    end,
    tooltip = L['Open Anchors'],
})
window:AddHeaderButton({
    icon = TEX .. 'fill.png',
    glow = TEX .. 'fill_glow.png',
    size = 18,
    onClick = Shared.ShowTheme,
    tooltip = L['Open Theme Settings'],
})
window:AddHeaderButton({
    icon = TEX .. 'eye.png',
    glow = TEX .. 'eye_glow.png',
    size = 24,
    onClick = function(btn)
        PreviewManager:SetForceAll(not PreviewManager:IsForceAll())
        btn:SetActive(PreviewManager:IsForceAll())
    end,
    tooltip = L['Preview Every Display'],
})

window.content.onPageChanged = function(pageId, previousId)
    PreviewManager:SetPage(pageId)
    if pageId ~= previousId then
        NRSKNUI:PromptPendingReload()
    end
end

-- Footer socials: auto-packed left -> right. The copy prompt stays addon-side.
local function CopyPrompt(title, link, icon, glow)
    NRSKNUI:CreatePrompt({
        title = title,
        text = link,
        editBox = true,
        editBoxLabel = L['CTRL-C to copy'],
        texture = {
            path = icon,
            glow = glow,
            width = 21,
            height = 21,
            color = {
                r = Theme.accent[1],
                g = Theme.accent[2],
                b = Theme.accent[3]
            },
        },
    })
end

window:AddFooterSocial({
    icon = SOCIAL .. 'twitchv2W.png',
    glow = SOCIAL .. 'twitchv2W_glow.png',
    text = 'Twitch',
    width = 62,
    onClick = function()
        CopyPrompt(format(L['Support My %s'], '|cff9146FFTwitch|r'), 'www.twitch.tv/norskenwow', SOCIAL .. 'twitchv2W.png', SOCIAL .. 'twitchv2W_glow.png')
    end,
})
window:AddFooterSocial({
    icon = SOCIAL .. 'discordv2W.png',
    glow = SOCIAL .. 'discordv2W_glow.png',
    text = 'Discord',
    width = 68,
    onClick = function()
        CopyPrompt(format(L['Join My %s'], '|cff5865F2Discord|r'), 'https://discord.com/invite/23bS8pHfuX', SOCIAL .. 'discordv2W.png', SOCIAL .. 'discordv2W_glow.png')
    end,
})
window:AddFooterSocial({
    icon = SOCIAL .. 'github2W.png',
    glow = SOCIAL .. 'github2W_glow.png',
    text = 'GitHub',
    width = 68,
    onClick = function()
        CopyPrompt(format(L['Support My %s'], '|cffffffffGitHub|r'), 'https://github.com/Nrsken/NorskenUI', SOCIAL .. 'github2W.png', SOCIAL .. 'github2W_glow.png')
    end,
})

NRSKNUI.GUIFrame = window --[[@as GUIFrame]]
