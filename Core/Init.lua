---@class NRSKNUI
local NRSKNUI = select(2, ...)
local addonName = ...

local _G = _G
local LibStub = LibStub

local NorskenCore = _G.NorskenCore --[[@as NRSKNUI]]
NorskenCore:NewAddon(NRSKNUI, addonName, function() return NRSKNUI.db and NRSKNUI.db.global.Theme end, 'AceEvent-3.0')
_G.NorskenAuras = NRSKNUI

-- First thing, so these files load in it. Core is ready by now and when NorskenUI is here it loaded first
-- and already picked the same one, nothing else picks it without NorskenUI.
NRSKNUI:SetLanguage(NRSKNUI:GetSharedSettings().Language)

NRSKNUI.Libs = {
    AL = NRSKNUI.L,
} --[[@as NRSKNUI.Libraries]]

NRSKNUI.CDM = NRSKNUI:NewModule('CDM', 'AceEvent-3.0')

function NRSKNUI:OnInitialize()
    self.db = LibStub('AceDB-3.0'):New('NorskenAurasDB', self.Defaults, true) --[[@as NRSKNUI.DBObject]]
    self.GUI:ApplyTheme()
end

function NRSKNUI:OnEnable()
    self:RegisterLauncher(self.db.global.Minimap)
end
