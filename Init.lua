---@class NRSKNUI
local NRSKNUI = select(2, ...)
local addonName = ...

local LibStub = LibStub
local GetAddOnMetadata = C_AddOns.GetAddOnMetadata

local LDBIconPath = 'Interface\\AddOns\\NorskenUI\\Media\\Logo\\logocookingsPT1128x128OTBRED.png'

local NorskenCore = _G.NorskenCore --[[@as NorskenCoreAPI]]
NorskenCore:NewAddon(NRSKNUI, addonName, 'AceEvent-3.0')
_G.NorskenAuras = NRSKNUI

-- First thing, so these files load in it. Core is ready by now, and when NorskenUI is here it loaded first
-- and already picked the same one, nothing else picks it without NorskenUI.
NRSKNUI:SetLanguage(NRSKNUI:GetSharedSettings().Language)

NRSKNUI.Libs = {
    AL = NRSKNUI.L,
    KAJI = LibStub('LibKaji-1.0'),
    LDB = LibStub('LibDataBroker-1.1'),
    LDBIcon = LibStub('LibDBIcon-1.0'),
} --[[@as NRSKNUI.Libraries]]

NRSKNUI.Version = GetAddOnMetadata(addonName, 'Version')
if NRSKNUI.Version == '@project-version@' then
    NRSKNUI.Version = 'Development Version'
end

NRSKNUI.GUI = NRSKNUI.Libs.KAJI:New({
    store = function() return NRSKNUI.db and NRSKNUI.db.global.Theme end,
    classColorProvider = function() return NRSKNUI:GetPlayerClassColor() end,
})
NRSKNUI.Theme = NRSKNUI.GUI:GetTheme()
NRSKNUI.Anchors = NorskenCore:NewAnchors(NRSKNUI)
NRSKNUI.PreviewManager = NorskenCore:NewPreviewManager(NRSKNUI)

NRSKNUI.CDM = NRSKNUI:NewModule('CDM', 'AceEvent-3.0')

---@param msg string
function NRSKNUI:Print(msg)
    print(self:ColorTextByTheme('Norsken') .. 'Auras:|r ' .. msg)
end

local function SetupMinimapIcon()
    local L = NRSKNUI.Libs.AL
    local Theme = NRSKNUI.Theme
    local LDB = NRSKNUI.Libs.LDB
    local MyLDB = LDB:NewDataObject(addonName, {
        type = 'launcher',
        text = addonName,
        icon = LDBIconPath,
        iconR = Theme.accent[1],
        iconG = Theme.accent[2],
        iconB = Theme.accent[3],
        OnClick = function(_, button)
            if button == 'LeftButton' then
                NRSKNUI:ToggleOptions()
            elseif button == 'RightButton' then
                if NRSKNUI.Anchors then
                    NRSKNUI.Anchors:Toggle()
                end
            elseif button == 'MiddleButton' then
                if NRSKNUI.CDMWindow then
                    NRSKNUI.CDMWindow:ResetPosition()
                end
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(NRSKNUI:ColorTextByTheme('Norsken') .. '|cffb3b3b3Auras|r')
            tt:AddLine(L['Left-Click to open options'], 0.70, 0.70, 0.70)
            tt:AddLine(L['Right-Click to toggle anchors'], 0.70, 0.70, 0.70)
            tt:AddLine(L['Middle-Click to reset the options window position'], 0.70, 0.70, 0.70)
        end,
    })
    local minimapDB = NRSKNUI.db.profile.Minimap
    ---@cast minimapDB LibDBIcon.button.DB
    NRSKNUI.Libs.LDBIcon:Register(addonName, MyLDB, minimapDB)
end

function NRSKNUI:OnInitialize()
    self.db = LibStub('AceDB-3.0'):New('NorskenAurasDB', self.Defaults, true) --[[@as NRSKNUI.DBObject]]
    self.GUI:ApplyTheme()
end

function NRSKNUI:OnEnable()
    SetupMinimapIcon()
end
