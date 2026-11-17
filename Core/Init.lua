---@class NorskenAuras
local NRSKNUI = select(2, ...)
local addonName = ...

local LibStub = LibStub
local _G = _G

local NorskenCore = _G.NorskenCore --[[@as NorskenCore]]
NorskenCore:NewAddon(NRSKNUI, addonName, function() return NRSKNUI.db and NRSKNUI.db.global.Theme end, 'AceEvent-3.0')
_G.NorskenAuras = NRSKNUI
NRSKNUI.Anchors.boxOnly = true

-- First thing, so every file after this loads in it
-- NorskenUI loads first and picks the same one when it's here, nothing else does without it
NRSKNUI:SetLanguage(NRSKNUI:GetSharedSettings().Language)

NRSKNUI.Libs = {
    AL = NRSKNUI.L,
} --[[@as NorskenAuras.Libraries]]

NRSKNUI.CDM = NRSKNUI:NewModule('CDM', 'AceEvent-3.0')

function NRSKNUI:OnInitialize()
    self.db = LibStub('AceDB-3.0'):New('NorskenAurasDB', self.Defaults, true) --[[@as NorskenAuras.DBObject]]
    self.GUI:ApplyTheme()
end

function NRSKNUI:OnEnable()
    self:RegisterLauncher(self.db.global.Minimap)
end
