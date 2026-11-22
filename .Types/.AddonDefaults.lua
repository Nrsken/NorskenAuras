---@meta

-- NorskenAurasDB as Core/Defaults.lua fills it and the displays it holds

---@class NorskenAuras.DBObject : AceDBObject-3.0
---@field global CDMSettings

---@class CDMSettings
---@field HidePlayerCastBar boolean
---@field AnchorMinWidth number
---@field TrinketBlacklist table<number, true> trinkets whose on-use isn't worth tracking
---@field Version number
---@field Displays table<string, CDMDisplay> by 'cdm:N' key
---@field BrokenDisplays CDMSetAside[] set aside at login, see CDM.lua's SetAsideBroken
---@field SidebarCollapsed table<string, table<string, true>> by page, then section key
---@field Theme table
---@field Minimap table LibDBIcon's saved state

-- A saved display no repair could save, as it was saved
---@class CDMSetAside
---@field key string its key in Displays
---@field display any

-- Displays --

-- One class for every type, the fields a type doesn't use stay nil (Data/Store.lua)
---@class CDMDisplay
---@field type 'icon'|'bar'|'text'|'group'|'dynamicgroup'|'auragroup'
---@field name string
---@field uid string
---@field Enabled boolean
---@field parent string? the group it sits in
---@field order number? its place among its siblings
---@field Conditions CDMCondition[]
---@field Position NorskenCore.Position
---@field anchorFrameType string 'UIPARENT' or 'SELECTFRAME'
---@field ParentFrame string
---@field Strata string? its group's when nil
---@field Icon number|string? a group's tree icon
---@field Description string?
---@field Load table LoadConditions:GetDefaults()
---@field Triggers CDMTrigger[]? icon, bar and text
---@field Activation string? 'all' when every trigger must be active
---@field DynamicTrigger number? the trigger a dynamic display follows
---@field Style NorskenCore.IconStyle|CDMBarStyle?
---@field SubRegions NorskenCore.SubElement[]?
---@field Layout CDMLayout? dynamic groups and aura groups
---@field Trigger NorskenCore.AuraTrigger? aura groups
---@field maxFrameCount number? aura groups, per trigger
---@field previewLimit number? aura groups, the preview's dummies only
---@field sortMethod string? aura groups
---@field sortDirection string? aura groups
---@field MatchWidth string? the dynamic group a bar matches the width of
---@field MatchSide string? 'ABOVE' or below
---@field MatchGap number?
---@field UFAnchor string? 'primary' or 'secondary', the unit frames' anchor role
---@field builtin string? the built-in aura group it was made from
---@field preferToUpdate boolean? an import of this display updates it in place

-- A row of the display tree, from Store.lua's GetChildren and GetRoots
---@class CDMTreeEntry
---@field key string
---@field text string its name
---@field order number? nil on roots

-- What the conform always fills (CDM.LAYOUT_TEMPLATE, Data/Templates.lua)
---@class CDMLayout : NorskenCore.DynamicGroupConfig
---@field Grow string a key of CDM.CHAIN_GROWS or 'GRID'
---@field Spacing number

---@class CDMBarStyle : NorskenCore.IconStyle
---@field UseGlobalBar boolean
---@field StatusBarTexture string
---@field BarColorMode string
---@field BarColor number[]
---@field BackgroundColor number[]
---@field Orientation string
---@field ReverseFill boolean
---@field Inverse boolean
---@field Smooth boolean
---@field Spark boolean
---@field UseGlobalSpark boolean
---@field SparkTexture string
---@field SparkScale number
---@field SparkWidth number
---@field SparkColor number[]
---@field IconSide string
---@field LatencyColor number[]
---@field PipSpacing number

---@class NorskenCore.IconStyle
---@field ManualIcon number|string? the icon picked when IconSource is manual

---@class NorskenCore.TimerText
---@field Trigger number? whose countdown shows, nil for every layer but an aura overlay

-- Triggers --

-- One class for every trigger type, the fields a type doesn't use stay nil
---@class CDMTrigger
---@field Type string a key of CDM.TRIGGER_TEMPLATES
---@field SpellID number?
---@field SpellIDs number[]?
---@field AlsoSpellIDs number[]? counted with SpellID
---@field IgnoreOverride boolean?
---@field CooldownID number? the Cooldown Manager's entry
---@field Source string? aura triggers: 'cdm' or 'custom'
---@field Unit string?
---@field OwnOnly boolean?
---@field Base string? custom aura triggers, 'HELPFUL' or 'HARMFUL'
---@field branches NorskenCore.AuraTriggerBranch[]? custom aura triggers
---@field Slot number? aura overlays: the trigger it lies over
---@field Placeholder boolean? a lone aura holds its place while missing
---@field MaxStacks number?
---@field BarMode string? 'duration' or 'stacks'
---@field Item string? 'trinket1', 'trinket2', 'healthstone', 'combatPotion' or 'custom'
---@field ItemID number? a custom item
---@field HidePassive boolean?
---@field ShowNotOwned boolean?
---@field ShowOn string? 'always', 'cooldown' or 'ready', a durability trigger's 'always' or 'value'
---@field Operator string? durability triggers, a CDM.OPERATORS key
---@field Threshold number? durability triggers, the percent Operator compares to
---@field FactionID number? faction triggers, nil until one is picked
---@field UseWatched boolean? faction triggers follow the watched faction
---@field Event string? event triggers, a CDM.EVENTS value
---@field EncounterCombat boolean? event triggers, a boss fight counts as combat to its end
---@field DeathLimit number? Unit Died on the group, deaths shown a window
---@field DeathWindow number? Unit Died on the group, the window in seconds
---@field Duration number? cast timers
---@field Casts string? cast triggers, 'all' or 'specific'
---@field HoldTime number?
---@field ShowLatency boolean?
---@field PowerType number|string? power triggers, a power type, a named one or 'primary'
---@field Mode string? power triggers, 'bar', 'static' or 'progress'
---@field ProgressCooldownID number?
---@field Stat string?
---@field SpecIDs number[]? loot spec triggers, empty is any spec
---@field CurrentSpec string? loot spec triggers, 'any', 'current' or 'other'
---@field Text string? 'title', 'state' or 'hint'
---@field Conditions table? a load table's shape, { State, Group }

-- Import --

-- What an import string holds, see Data/Transfer.lua
---@class CDMImportPayload
---@field _v number the string format
---@field _s number the SCHEMA_VERSION it was made with
---@field _a string the version that made it
---@field _t number when
---@field root string
---@field d table<string, CDMDisplay> by the key each had where it was made

---@class CDMImportPlan
---@field payload CDMImportPayload
---@field count number
---@field matches table<string, string> import key to the local id it updates
---@field added string[] import keys with no match
---@field modified table<string, table<string, true>> import key to the categories that differ
---@field removed string[] local ids the import doesn't have
---@field categories table<string, true> every category any match changes
---@field target string? the local display the root matched
---@field blocked boolean? a match of another type, so only a copy works

-- Conditions --

---@class CDMCondition
---@field check CDMCheck
---@field changes CDMChange[]
---@field linked boolean? Else If, follows the one above

---@class CDMCheck
---@field variable string? 'AND' or 'OR' for a combination
---@field trigger number? 0 global, -1 group, otherwise the trigger index
---@field op string?
---@field value any
---@field checks CDMCheck[]? a combination's parts
---@field entries table<number, boolean>? talent checks: an entry ID must be had or not

-- A check a trigger type offers, each trigger file adds its own to CDM.ConditionChecks
---@class CDMCheckDef
---@field type 'bool'|'number'|'select'
---@field secret boolean? the game decides it, so Lua never matches it
---@field curve boolean? built into a text's curve, never matched in Lua
---@field talents boolean? its value is a list of talent entries
---@field negatable boolean?
---@field get (fun(layer: CDMLayer, trigger: CDMTrigger, pip: CDMPip?): any)?
---@field match (fun(value: any, layer: CDMLayer?, check: CDMCheck): boolean)?
---@field options string?

---@class CDMChange
---@field property string? a property name, 'sub.N.name' for a sub element
---@field value any
