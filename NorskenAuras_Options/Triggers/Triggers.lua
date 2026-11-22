---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local Shared = NRSKNUI.CDMOptions
local QUESTION_MARK = Shared.QUESTION_MARK
local Reopen = Shared.Reopen

local format = string.format
local tinsert = table.insert
local tremove = table.remove
local floor = math.floor
local sort = table.sort
local ipairs = ipairs
local pairs = pairs

local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName

local TRIGGER_TYPES = {
    { value = 'spell',       text = L['Cooldown'] },
    { value = 'aura',        text = L['Aura'] },
    { value = 'auraoverlay', text = L['Aura Overlay'] },
    { value = 'item',        text = L['Item'] },
    { value = 'timer',       text = L['Cast Timer'] },
    { value = 'event',       text = L['Events'] },
    { value = 'stat',        text = L['Player Stat'],         group = 'unit' },
    { value = 'lootSpec',    text = L['Loot Specialization'], group = 'unit' },
    { value = 'prey',        text = L['Prey Hunt'],           group = 'unit' },
    { value = 'durability',  text = L['Durability'],          group = 'unit' },
    { value = 'faction',     text = L['Faction Reputation'],  group = 'unit' },
    { value = 'conditions',  text = L['Conditions'],          group = 'unit' },
}
local BAR_TRIGGER_TYPES = {
    { value = 'cast',        text = L['Cast'] },
    { value = 'power',       text = L['Power'] },
    { value = 'aura',        text = L['Aura'] },
    { value = 'stat',        text = L['Player Stat'], group = 'unit' },
    { value = 'prey',        text = L['Prey Hunt'],   group = 'unit' },
    { value = 'durability',  text = L['Durability'],  group = 'unit' },
    { value = 'faction',     text = L['Faction Reputation'], group = 'unit' },
    { value = 'conditions',  text = L['Conditions'],  group = 'unit' },
    { value = 'viewerbar',   text = L['Cooldown Bar'] },
    { value = 'spell',       text = L['Cooldown'] },
    { value = 'item',        text = L['Item'] },
    { value = 'timer',       text = L['Cast Timer'] },
    { value = 'event',       text = L['Events'] },
    { value = 'auraoverlay', text = L['Aura Overlay'] },
}
local TRIGGER_NAMES = {}
for _, entry in ipairs(TRIGGER_TYPES) do
    TRIGGER_NAMES[entry.value] = entry.text
end
for _, entry in ipairs(BAR_TRIGGER_TYPES) do
    TRIGGER_NAMES[entry.value] = entry.text
end

-- A trigger's number and type, its name on the Conditions tab
---@param index number
---@param trigger table
---@return string
local function TriggerTitle(index, trigger)
    return format(L['Trigger %d: %s'], index, TRIGGER_NAMES[trigger.Type])
end

-- Tabs --

-- What a group's or aura group's position section builds from
---@param id string
---@return table
local function PositionConfig(id)
    local display = CDM:Get(id)
    local dynamic = display.type == 'dynamicgroup'
    local frame = dynamic and CDM.containers[id]
    return {
        db = display,
        -- Inside a static group, Screen means the group
        showAnchorFrameType = not CDM:IsDynamic(display.parent),
        showStrata = display.parent == nil,
        -- A dynamic group's saved AnchorFrom was never read, so its pick has a key of its own
        dbKeys = dynamic and { selfPoint = 'SelfPoint' } or nil,
        defaults = dynamic and { selfPoint = frame and CDM:GroupPoint(frame, display) } or nil,
        onChangeCallback = function() CDM:ApplySettings(Apply.Position, id) end,
    }
end

-- No auras, as an aura draws through a native aura button a text doesn't have
local TEXT_TRIGGER_TYPES = {
    { value = 'spell',      text = L['Cooldown'] },
    { value = 'power',      text = L['Power'] },
    { value = 'stat',       text = L['Player Stat'],           group = 'unit' },
    { value = 'cast',       text = L['Cast'] },
    { value = 'item',       text = L['Item'] },
    { value = 'timer',      text = L['Cast Timer'] },
    { value = 'event',      text = L['Events'] },
    { value = 'lootSpec',   text = L['Loot Specialization'],   group = 'unit' },
    { value = 'prey',       text = L['Prey Hunt'],             group = 'unit' },
    { value = 'durability', text = L['Durability'],            group = 'unit' },
    { value = 'faction',    text = L['Faction Reputation'],    group = 'unit' },
    { value = 'conditions', text = L['Conditions'],            group = 'unit' },
}
local TRIGGER_LISTS = { bar = BAR_TRIGGER_TYPES, text = TEXT_TRIGGER_TYPES }
-- The Type dropdown shows a group once, a second dropdown picks the type inside it
local TRIGGER_GROUPS = {
    unit = L['Player/Unit Info'],
}
local CAST_ICON = 'Interface\\Icons\\INV_Misc_PocketWatch_01'

local AURA_SOURCES = {
    { value = 'cdm',    text = L['Cooldown Manager'] },
    { value = 'custom', text = L['Custom'] },
}
local AURA_BAR_MODES = {
    { value = 'duration', text = L['Duration'] },
    { value = 'stacks',   text = L['Stacks'] },
}
local AURA_UNITS = {
    { value = 'player', text = L['Player'] },
    { value = 'target', text = L['Target'] },
}
local ITEMS = {
    { value = 'trinket1',     text = L['Trinket 1'] },
    { value = 'trinket2',     text = L['Trinket 2'] },
    { value = 'healthstone',  text = L['Healthstone'] },
    { value = 'combatPotion', text = L['Combat Potion'] },
    { value = 'custom',       text = L['Custom Item'] },
}
local SHOW_ON = Shared.ChoiceOptions(CDM.SHOW_ON, {
    always   = L['Always'],
    cooldown = L['On Cooldown'],
    ready    = L['When Ready'],
})
-- Which triggers are open this session, a lone trigger starts open
local triggerOpen = {}

-- The layer a trigger draws as the Conditions tab names it, icon and name or its title
---@param index number
---@param trigger table
---@return string
local function TriggerChip(index, trigger)
    local name = CDM:GetTriggerName(trigger)
    if not name then
        return TriggerTitle(index, trigger)
    end
    local texture = CDM:GetTriggerTexture(trigger)
    return texture and format('|T%s:0:0:0:0:64:64:5:59:5:59|t %s', texture, name) or name
end

-- A trigger's title and what it draws, its name on the Trigger tab
---@param index number
---@param trigger table
---@return string
local function TriggerLabel(index, trigger)
    local label = TriggerTitle(index, trigger)
    return CDM:GetTriggerName(trigger) and (label .. ' - ' .. TriggerChip(index, trigger)) or label
end

-- The condition an overlay starts with, its aura's own icon while it's up
---@param condition table
---@param index number
---@param exact boolean only the untouched one we added, not one the user has built on
---@return boolean
local function IsOverlayIcon(condition, index, exact)
    local check, changes = condition.check, condition.changes
    if check.trigger ~= index or check.variable ~= 'active' or check.value == false or check.checks then return false end

    for _, change in ipairs(changes) do
        if change.property == 'auraIcon' and change.value == true then
            return not exact or (#changes == 1 and not condition.linked)
        end
    end
    return false
end

-- Alone an aura is the icon, beside other triggers an overlay starting with its own icon
-- Back to alone drops that starting condition again, as a lone aura ignores it
---@param display table
local function NormalizeAuraTypes(display)
    local triggers = display.Triggers
    local alone = #triggers == 1
    local conditions = display.Conditions
    for index, trigger in ipairs(triggers) do
        if trigger.Type == 'aura' and not alone then
            trigger.Type = 'auraoverlay'
            local has = false
            for _, condition in ipairs(conditions) do
                has = has or IsOverlayIcon(condition, index, false)
            end
            if not has then
                tinsert(conditions, { check = { trigger = index, variable = 'active', value = true }, changes = { { property = 'auraIcon', value = true } } })
            end
        elseif trigger.Type == 'auraoverlay' and alone then
            trigger.Type = 'aura'
            for i = #conditions, 1, -1 do
                if IsOverlayIcon(conditions[i], index, true) then
                    tremove(conditions, i)
                end
            end
        end
    end
end

-- A new trigger for the Cooldown Manager aura sharing a spell with a cooldown trigger
---@param display table
---@return table? trigger
local function LinkedAuraTrigger(display)
    for _, trigger in ipairs(display.Triggers) do
        local cooldownID = trigger.Type == 'spell' and trigger.SpellID and CDM.Catalogue:FindBySpell(trigger.SpellID, 'aura')
        local info = cooldownID and CDM.Catalogue:GetEntry(cooldownID)
        if info then
            local new = CDM:NewTrigger('aura')
            new.CooldownID, new.SpellID = cooldownID, info.spellID
            return new
        end
    end
end

-- Every Cooldown Manager spell in these categories, unknown ones dimmed at the end
---@param categories number[] Enum.CooldownViewerCategory values
---@return table[] options
local function CatalogueOptions(categories)
    local known, unknown = {}, {}
    local muted = Theme.textMuted
    local tint = format('%d:%d:%d', floor(muted[1] * 255 + 0.5), floor(muted[2] * 255 + 0.5), floor(muted[3] * 255 + 0.5))
    for _, category in ipairs(categories) do
        for _, cooldownID in ipairs(CDM.Catalogue:GetList(category)) do
            local info = CDM.Catalogue:GetEntry(cooldownID)
            local shown = info and CDM.Catalogue:DisplaySpell(info)
            if shown then
                local texture = GetSpellTexture(shown) or QUESTION_MARK
                local name = GetSpellName(shown) or shown
                if info.isKnown then
                    known[#known + 1] = { value = cooldownID, spellID = info.spellID, text = format('|T%d:16:16:0:0:64:64:5:59:5:59|t %s', texture, name) }
                else
                    unknown[#unknown + 1] = {
                        value = cooldownID,
                        spellID = info.spellID,
                        text = format('|T%d:16:16:0:0:64:64:5:59:5:59:%s|t %s', texture, tint, name),
                        color = muted,
                    }
                end
            end
        end
    end
    for _, option in ipairs(unknown) do
        known[#known + 1] = option
    end
    return known
end

---@param trigger table
---@param display table
---@param id string
---@param apply fun(part: NorskenCore.Apply)
---@return fun(cooldownID: number)
local function CataloguePicker(trigger, display, id, apply)
    return function(cooldownID)
        local info = CDM.Catalogue:GetEntry(cooldownID)
        if not info or cooldownID == trigger.CooldownID then return end
        -- A new icon or one still named after its spell takes the new spell's name
        if display.name == L['New Icon'] or display.name == CDM:GetTriggerName(trigger) then
            display.name = GetSpellName(CDM.Catalogue:DisplaySpell(info)) or display.name
        end
        trigger.SpellID = info.spellID
        trigger.CooldownID = cooldownID
        apply(Apply.All)
        Reopen(id)
    end
end

-- Rows per trigger type, the first row opens with the Type dropdown
local TriggerRows = {} ---@type CDMTriggerRowSet

-- Text codes --

-- What each trigger type's codes show, filled by its own file
local TextCodes = {} ---@type CDMTextCodeSet
local TEXT_ORDER = { 'p', 't', 's', 'n', 'i' }

-- The text panel's section per trigger, %N. on every code
---@param triggers CDMTrigger[]
---@return AuraLookCodeSection[]
local function TextSections(triggers)
    local sections = {}
    for n, trigger in ipairs(triggers) do
        local labels = TextCodes[trigger.Type]
        local tips = labels.tips
        local prefix = '%' .. n .. '.'
        local codes = {}
        for _, code in ipairs(TEXT_ORDER) do
            if labels[code] then
                codes[#codes + 1] = { prefix .. code, labels[code], tips and tips[code] }
            end
        end

        local tokens = CDM.TriggerTypes[trigger.Type].Tokens
        if tokens then
            local names = {}
            for name in pairs(tokens) do
                names[#names + 1] = name
            end
            sort(names)
            for _, name in ipairs(names) do
                codes[#codes + 1] = { prefix .. name, labels.tokens[name], tips and tips[name] }
            end
        end

        if labels.extra then
            for _, extra in ipairs(labels.extra) do
                if not extra.shows or extra.shows(trigger) then
                    local code = (extra.perTrigger and prefix or '%') .. extra.code
                    codes[#codes + 1] = { code, extra.label, tips and tips[extra.code] }
                end
            end
        end
        sections[n] = { title = TriggerTitle(n, trigger), codes = codes }
    end
    return sections
end

-- Exports --

Shared.AURA_BAR_MODES = AURA_BAR_MODES
Shared.AURA_SOURCES = AURA_SOURCES
Shared.AURA_UNITS = AURA_UNITS
Shared.CAST_ICON = CAST_ICON
Shared.CatalogueOptions = CatalogueOptions
Shared.CataloguePicker = CataloguePicker
Shared.ITEMS = ITEMS
Shared.LinkedAuraTrigger = LinkedAuraTrigger
Shared.NormalizeAuraTypes = NormalizeAuraTypes
Shared.PositionConfig = PositionConfig
Shared.SHOW_ON = SHOW_ON
Shared.TextCodes = TextCodes
Shared.TextSections = TextSections
Shared.TRIGGER_GROUPS = TRIGGER_GROUPS
Shared.TRIGGER_LISTS = TRIGGER_LISTS
Shared.TRIGGER_TYPES = TRIGGER_TYPES
Shared.TriggerChip = TriggerChip
Shared.TriggerLabel = TriggerLabel
Shared.TriggerRows = TriggerRows
Shared.TriggerTitle = TriggerTitle
Shared.triggerOpen = triggerOpen
