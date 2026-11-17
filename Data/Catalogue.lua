---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')

local CreateFrame = CreateFrame
local wipe = table.wipe
local ipairs = ipairs

local GetCooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo
local GetCategorySet = C_CooldownViewer.GetCooldownViewerCategorySet

local Category = Enum.CooldownViewerCategory

-- Blizzard's Cooldown Manager catalogue for the current spec, read only
---@class CDMCatalogue
local Catalogue = {
    entries = {}, ---@type table<number, CooldownViewerCooldown>
    lists = {}, ---@type table<number, number[]>
    bySpell = { cooldown = {}, aura = {} }, ---@type table<'cooldown'|'aura', table<number, number>>
    dirty = true,
}
CDM.Catalogue = Catalogue

Catalogue.CATEGORIES = {
    Category.Essential,
    Category.Utility,
    Category.TrackedBuff,
    Category.TrackedBar,
}

-- Building --

-- One spell can sit in a cooldown category and an aura category at once
local KIND = {
    [Category.Essential] = 'cooldown',
    [Category.Utility] = 'cooldown',
    [Category.TrackedBuff] = 'aura',
    [Category.TrackedBar] = 'aura',
}

function Catalogue:Rebuild()
    wipe(self.entries)
    wipe(self.lists)
    wipe(self.bySpell.cooldown)
    wipe(self.bySpell.aura)

    for _, category in ipairs(self.CATEGORIES) do
        local list, bySpell = {}, self.bySpell[KIND[category]]
        for _, cooldownID in ipairs(GetCategorySet(category, true)) do
            local info = GetCooldownInfo(cooldownID)
            if info then
                list[#list + 1] = cooldownID
                self.entries[cooldownID] = info
                if info.spellID then
                    bySpell[info.spellID] = cooldownID
                end
                if info.overrideSpellID then
                    bySpell[info.overrideSpellID] = cooldownID
                end
            end
        end
        self.lists[category] = list
    end

    self.dirty = false
end

---Rebuilt on the first lookup, as one change fires several rebuild events at once
function Catalogue:EnsureBuilt()
    if self.dirty then
        self:Rebuild()
    end
end

-- Lookups --

---@param cooldownID number
---@return CooldownViewerCooldown?
function Catalogue:GetEntry(cooldownID)
    self:EnsureBuilt()
    return self.entries[cooldownID]
end

---@param category number Enum.CooldownViewerCategory
---@return number[] cooldownIDs
function Catalogue:GetList(category)
    self:EnsureBuilt()
    return self.lists[category]
end

---@param spellID number
---@param kind 'cooldown'|'aura'
---@return number? cooldownID
function Catalogue:FindBySpell(spellID, kind)
    self:EnsureBuilt()
    return self.bySpell[kind][spellID]
end

---The spell an entry casts as now, overrideSpellID is spellID when nothing overrides it
---@param info CooldownViewerCooldown
---@return number?
function Catalogue:ResolveSpell(info)
    return info.overrideSpellID or info.spellID
end

---The spell Blizzard shows an entry as while its auras are down (CooldownViewerItemData.lua)
---An aura's base spell can be the passive granting it, so the tooltip spell comes first
---@param info CooldownViewerCooldown
---@return number?
function Catalogue:DisplaySpell(info)
    return info.overrideTooltipSpellID or self:ResolveSpell(info)
end

-- Events --

-- What Blizzard's own data provider rebuilds on (CooldownViewerSettingsDataProvider.lua)
local REBUILD_EVENTS = {
    'COOLDOWN_VIEWER_DATA_LOADED',
    'COOLDOWN_VIEWER_TABLE_HOTFIXED',
    'COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED',
    'TRAIT_CONFIG_UPDATED',
    'ACTIVE_PLAYER_SPECIALIZATION_CHANGED',
    'ACTIVE_COMBAT_CONFIG_CHANGED',
    'PLAYER_PVP_TALENT_UPDATE',
    'SPELLS_CHANGED',
    'PLAYER_EQUIPMENT_CHANGED',
}

local eventFrame ---@type Frame?

local function OnRebuildEvent()
    Catalogue.dirty = true
    CDM:OnCatalogueChanged()
end

function Catalogue:RegisterEvents()
    -- Nothing watched the spellbook while the CDM was off
    self.dirty = true

    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnRebuildEvent)
    end

    for _, event in ipairs(REBUILD_EVENTS) do
        eventFrame:RegisterEvent(event)
    end
end

function Catalogue:UnregisterEvents()
    eventFrame:UnregisterAllEvents()
end
