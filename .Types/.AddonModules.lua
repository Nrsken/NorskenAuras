---@meta

---@class NorskenAuras : NorskenCore
---@field CDM CDMModule NorskenAuras' one module
---@field Libs NorskenAuras.Libraries its own, in place of Core's
---@field db NorskenAuras.DBObject
---@field GUIFrame KajiGUIWindow its settings window, from NorskenAuras_Options/Window.lua
---@field Defaults { global: CDMSettings }

---@class NorskenAuras.Libraries
---@field AL table<string, string> the strings in the picked language

---@overload fun(self: NorskenAuras, name: "CDM", silent?: boolean): CDMModule
---@param name string
---@param silent? boolean
---@return AceModule
function NorskenAuras:GetModule(name, silent) end

---@overload fun(self: NorskenAuras, name: "CDM", ...: string): CDMModule
---@param name string
---@param ... string
---@return AceModule
function NorskenAuras:NewModule(name, ...) end

---@class CDMModule : NorskenCore.ModuleBase, AceEvent-3.0
---@field db CDMSettings NorskenAurasDB's global, the only scope it has
---@field icons table<string, CDMIcon>
---@field containers table<string, Frame|NorskenCore.DynamicGroup> static group frames and dynamic groups
---@field spareStatic Frame[]
---@field spareDynamic NorskenCore.DynamicGroup[]
---@field spareChain CDMChainGroup[]
---@field BAR_STYLE_TEMPLATE table
---@field TEXT_STYLE_TEMPLATE table
---@field BAR_ELAPSED number Enum.StatusBarTimerDirection.ElapsedTime
---@field BAR_REMAINING number Enum.StatusBarTimerDirection.RemainingTime
---@field POWER_TYPES table[] power trigger choices, { value, text }
---@field IsPreviewingLayer fun(layer: CDMLayer): boolean
---@field PreviewDuration fun(layer: CDMLayer, length: number): LuaDurationObject
---@field Catalogue CDMCatalogue
---@field TriggerTypes table<string, { IsKnown: fun(trigger: table): boolean, Resolve: fun(frame: CDMIcon, trigger: table), Update: fun(frame: CDMIcon, style: table) }>
---@field preview table<string, number> icon id to preview level, 1 selected and 2 pinned
---@field selectionPreview string[] icons the current selection raised to level 1
---@field previewing boolean? the options page is open
---@field onStateChanged fun()? set by the options page while it is open
