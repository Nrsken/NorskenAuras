---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')

local CopyTable = CopyTable
local ipairs = ipairs
local pairs = pairs
local type = type

---@param into table
---@param from table
---@return table into
local function Merge(into, from)
    for key, value in pairs(from) do
        if type(value) == 'table' and type(into[key]) == 'table' then
            Merge(into[key], value)
        else
            into[key] = value
        end
    end

    return into
end

-- Styles --

-- Every new bar starts from this, the icon keys stay so a bar's icon reads as an icon's does
---@type CDMBarStyle
CDM.BAR_STYLE_TEMPLATE = Merge(CopyTable(NRSKNUI.ICON_STYLE_TEMPLATE), {
    Width = 200,
    Height = 20,
    DrawSwipe = false,
    UseGlobalBar = true,
    StatusBarTexture = 'NorskenUI',
    BarColorMode = 'custom',
    BarColor = { 0.35, 0.55, 0.85, 1 },
    BackgroundColor = { 0, 0, 0, 0.8 },
    Orientation = 'HORIZONTAL',
    ReverseFill = false,
    Inverse = false,
    Smooth = true,
    Spark = true,
    UseGlobalSpark = true,
    SparkTexture = 'Solid',
    SparkScale = 1,
    SparkWidth = 2,
    SparkColor = { 1, 1, 1, 1 },
    IconShow = true,
    IconSide = 'LEFT',
    LatencyColor = { 1, 0.2, 0.2, 0.5 },
    PipSpacing = 1,
})

-- A text fits its text, its size is only its cell in a Grid dynamic group
---@type NorskenCore.IconStyle
CDM.TEXT_STYLE_TEMPLATE = Merge(CopyTable(NRSKNUI.ICON_STYLE_TEMPLATE), {
    Width = 100,
    Height = 20,
    DrawSwipe = false,
})

-- An aura group's buttons start with no swipe, a reversed one when turned on
---@type NorskenCore.IconStyle
CDM.AURA_GROUP_STYLE_TEMPLATE = Merge(CopyTable(NRSKNUI.ICON_STYLE_TEMPLATE), {
    Width = 50,
    Height = 50,
    DrawSwipe = false,
    Reverse = true,
    Tooltip = true,
    TooltipHideInCombat = false,
    DispelIcon = false,
    DispelIconSize = 12,
})

---@type table<string, NorskenCore.IconStyle>
CDM.STYLE_TEMPLATES = {
    icon = NRSKNUI.ICON_STYLE_TEMPLATE,
    bar = CDM.BAR_STYLE_TEMPLATE,
    text = CDM.TEXT_STYLE_TEMPLATE,
    auragroup = CDM.AURA_GROUP_STYLE_TEMPLATE,
}

-- The middle of the screen
CDM.POSITION_TEMPLATE = { AnchorFrom = 'CENTER', AnchorTo = 'CENTER', XOffset = 0, YOffset = 0 }

-- A new dynamic group's layout
CDM.LAYOUT_TEMPLATE = { Grow = 'HORIZONTAL', Spacing = 2, UseLimit = false, Limit = 10 }

-- Triggers --

-- Choices a trigger saves as a value, in the options' order, which keep the labels
CDM.SHOW_ON = { 'always', 'cooldown', 'ready' }      -- Spell and item triggers
CDM.CAST_MODES = { 'all', 'specific' }
CDM.POWER_MODES = { 'bar', 'static', 'progress' }
CDM.CURRENT_SPEC = { 'any', 'current', 'other' }   -- Loot spec triggers
CDM.HUNT_TEXTS = { 'title', 'state', 'hint' }      -- What a prey trigger's %n reads

-- A new trigger of each type is a copy, a type without one doesn't exist
---@type table<string, CDMTrigger>
CDM.TRIGGER_TEMPLATES = {
    spell       = { Type = 'spell', ShowOn = 'always' },
    -- The same keys, as an aura beside other triggers becomes an overlay in place
    aura        = { Type = 'aura', Source = 'cdm', Unit = 'player', OwnOnly = true, Slot = 0 },
    auraoverlay = { Type = 'auraoverlay', Source = 'cdm', Unit = 'player', OwnOnly = true, Slot = 0 },
    item        = { Type = 'item', Item = 'trinket1', HidePassive = true, ShowOn = 'always', ShowNotOwned = false },
    timer       = { Type = 'timer', Duration = 8 },
    power       = { Type = 'power', Mode = 'bar' }, -- PowerType holds a number or a name, so its Conform fills it
    viewerbar   = { Type = 'viewerbar' },
    cast        = { Type = 'cast', Casts = 'all', HoldTime = 0.5, ShowLatency = true },
    stat        = { Type = 'stat', Stat = 'haste' },
    lootSpec    = { Type = 'lootSpec', CurrentSpec = 'any', SpecIDs = {} },
    prey        = { Type = 'prey', Text = 'title' },
    conditions  = { Type = 'conditions', Conditions = { State = { Always = true } } },
}

-- Sub elements --

---A new icon's elements, a 1px border with the time in the middle and charges in the corner
---@return NorskenCore.SubElement[]
function CDM:DefaultIconSubRegions()
    return {
        NRSKNUI:NewSubRegion('border'),
        NRSKNUI:NewSubRegion('text'),
        NRSKNUI:NewSubRegion('text', { Text = '%s', FontSize = 13, Position = { AnchorFrom = 'AUTO', AnchorTo = 'BOTTOMRIGHT', XOffset = -1, YOffset = 2 } }),
    }
end

---A new bar's elements, a 1px border with the name left and the time or value right
---@return NorskenCore.SubElement[]
function CDM:DefaultBarSubRegions()
    return {
        NRSKNUI:NewSubRegion('border'),
        NRSKNUI:NewSubRegion('text', { Text = '%n', FontSize = 12, Position = { AnchorFrom = 'AUTO', AnchorTo = 'LEFT', XOffset = 4, YOffset = 0 } }),
        NRSKNUI:NewSubRegion('text', { Text = '%p', FontSize = 12, Position = { AnchorFrom = 'AUTO', AnchorTo = 'RIGHT', XOffset = -4, YOffset = 0 } }),
    }
end

-- Built-in aura groups --

-- What the built-in aura groups share, each one below changes only what sets it apart
local BUILTIN_BASE = {
    Enabled = true,
    Style = CDM.AURA_GROUP_STYLE_TEMPLATE,
    Layout = { Grow = 'GRID', Align = 'CENTER', Spacing = 1, RowSpacing = 1, GridType = 'LU', GridWidth = 6 },
    maxFrameCount = 6,
    previewLimit = 6,
    sortMethod = 'ExpirationOnly',
    sortDirection = 'Normal',
    anchorFrameType = 'UIPARENT',
    ParentFrame = 'UIParent',
}
-- Any aura group's own fields, which the conform fills in
CDM.AURA_GROUP_TEMPLATE = BUILTIN_BASE

---@param overrides table
---@return table
local function Builtin(overrides)
    return Merge(CopyTable(BUILTIN_BASE), overrides)
end

-- What a new profile starts with in General Trackers, each trigger from its preset
CDM.BUILTIN_AURA_GROUPS = {
    {
        key = 'builtin:advancedDebuffs',
        presets = { 'preset:advancedDebuffs' },
        look = { auraType = { DispelUntyped = true } },
        display = Builtin({
            name = 'Advanced Debuffs',
            Icon = 1396978,
            Style = { DispelIcon = true },
            Position = { AnchorFrom = 'BOTTOMRIGHT', AnchorTo = 'TOPRIGHT', XOffset = 0, YOffset = 120 },
        }),
    },
    {
        key = 'builtin:defensives',
        -- The externals are their own trigger, so only they say who cast them
        presets = { 'preset:personalDefensives', 'preset:externals' },
        look = { caster = 2 },
        display = Builtin({
            name = 'Defensives & Externals',
            Icon = 132360,
            Position = { AnchorFrom = 'BOTTOMRIGHT', AnchorTo = 'TOPRIGHT', XOffset = 0, YOffset = 40 },
        }),
    },
    {
        key = 'builtin:generalBuffs',
        presets = { 'preset:generalBuffs' },
        look = { timer = { FontSize = 14 }, stacks = { FontSize = 12 } },
        display = Builtin({
            name = 'General Buffs',
            Icon = 4374707,
            Style = { Width = 36, Height = 36 },
            Layout = { GridWidth = 1 },
            maxFrameCount = 10,
            previewLimit = 5,
            sortMethod = 'AuraInstanceIDOnly',
            Position = { AnchorFrom = 'BOTTOMRIGHT', AnchorTo = 'TOPLEFT', XOffset = -30, YOffset = 120 },
        }),
    },
    {
        key = 'builtin:speed',
        presets = { 'preset:speed' },
        display = Builtin({
            name = 'Speed',
            Icon = 648208,
            Style = { Width = 42, Height = 42 },
            Position = { AnchorFrom = 'RIGHT', AnchorTo = 'LEFT', XOffset = -1, YOffset = 0 },
        }),
    },
}
-- Also by key, which saved displays look them up by
for _, builtin in ipairs(CDM.BUILTIN_AURA_GROUPS) do
    CDM.BUILTIN_AURA_GROUPS[builtin.key] = builtin
end

-- The group a new profile's built-ins live in
CDM.BUILTIN_FOLDER = { name = 'General Trackers', Icon = 464820, Strata = 'HIGH' }

---A built-in aura group as it shipped, its trigger fresh from its preset
---@param key string
---@return CDMDisplay?
function CDM:NewBuiltinAuraGroup(key)
    local builtin = CDM.BUILTIN_AURA_GROUPS[key]
    if not builtin then return nil end

    local display = CopyTable(builtin.display)
    display.type = 'auragroup'
    display.builtin = key
    display.SubRegions = NRSKNUI:DefaultAuraGroupSubRegions(builtin.look)
    -- A trigger per preset, each its own aura group with texts of its own
    local AuraTriggers = NRSKNUI.AuraTriggers
    local trigger
    for _, presetKey in ipairs(builtin.presets) do
        local added = AuraTriggers:ToAuraFilter({ Type = AuraTriggers.Types.Preset, Preset = presetKey, Unit = 'player' })
        if not trigger then
            trigger = added
        else
            for _, branch in ipairs(added.branches) do
                local branchType = branch.type or added.Base
                branch.type = branchType ~= trigger.Base and branchType or nil
                trigger.branches[#trigger.branches + 1] = branch
            end
        end
    end
    display.Trigger = trigger
    display.Load = NRSKNUI.LoadConditions:GetDefaults()
    -- Reset builds it here without StartDisplay, keeping the old uid
    display.Conditions = {}
    return display
end
