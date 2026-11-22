---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL

--[[
The pipeline every trigger type shares, each type's file fills CDM.TriggerTypes
Resolve what a trigger points at, Update its layer from the game, Derive which layer shows
]]

local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local format = string.format
local tonumber = tonumber
local GetTime = GetTime
local ipairs = ipairs
local pairs = pairs
local next = next

local CreateDuration = C_DurationUtil.CreateDuration
local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName
local NewTimer = C_Timer.NewTimer

CDM.TriggerTypes = {}
CDM.PREVIEW_LENGTH = 7
CDM.PREVIEW_PANDEMIC = 0.3 -- The pandemic border shows at 30% left

-- Items aren't in it as BAG_UPDATE_COOLDOWN covers bags and equipped slots
local SPELL_TYPES = { spell = true }

local spellIndex = {} ---@type table<number, table<string, true>> spellID -> icon ids watching it

---@param id string
---@return CDMDisplay
local function BuiltDisplay(id)
    return CDM.icons[id].display
end

-- Preview --

---@param layer CDMLayer
---@return boolean
function CDM.IsPreviewingLayer(layer)
    return CDM.previewing == true and layer.owner.shown == true
end

---A looping fake timer for the options preview
---@param layer CDMLayer
---@param length number
---@return LuaDurationObject
function CDM.PreviewDuration(layer, length)
    local now = GetTime()
    if not layer.previewEnd or now >= layer.previewEnd - 0.05 then
        layer.previewEnd = now + length
        -- A hidden layer's Cooldown never fires OnCooldownDone, so a timer starts it over
        if layer.previewTimer then
            layer.previewTimer:Cancel()
        end
        layer.previewTimer = NewTimer(length, function()
            layer.previewTimer = nil
            if CDM.IsPreviewingLayer(layer) then
                CDM:UpdateLayer(layer)
            end
        end)
    end

    layer.previewDuration = layer.previewDuration or CreateDuration()
    layer.previewDuration:SetTimeFromStart(layer.previewEnd - length, length)
    return layer.previewDuration
end

-- Countdowns --

---Start a layer's countdown of its timerLength over, on a Cast Timer's cast or an Events trigger's event
---@param layer CDMLayer
function CDM.StartCountdown(layer)
    local length = layer.timerLength
    if length <= 0 then return end

    layer.timerEnd = GetTime() + length
    -- Starting again restarts it instead of stacking a second one
    if layer.timerTicker then
        layer.timerTicker:Cancel()
    end
    -- No event fires when our own timer runs out, so this wakes the layer to go inactive
    layer.timerTicker = NewTimer(length, function()
        layer.timerTicker = nil
        CDM:UpdateLayer(layer)
    end)
    CDM:UpdateLayer(layer)
end

---End a running countdown before its time
---@param layer CDMLayer
function CDM.StopCountdown(layer)
    if not layer.timerTicker then return end

    layer.timerTicker:Cancel()
    layer.timerTicker, layer.timerEnd = nil, nil
    CDM:UpdateLayer(layer)
end

---A countdown layer's timer and texts, a looping one while previewing
---@param layer CDMLayer
function CDM.UpdateCountdown(layer)
    local running = layer.timerEnd ~= nil and GetTime() < layer.timerEnd
    layer.timerDuration = layer.timerDuration or CreateDuration()
    if running then
        layer.timerDuration:SetTimeFromStart(layer.timerEnd - layer.timerLength, layer.timerLength)
        layer.duration = layer.timerDuration
    else
        layer.timerEnd = nil
        -- Texts keep counting their last duration, so an ended timer hands them a zero one
        layer.timerDuration:SetTimeFromStart(0, 0)
        layer.duration = layer.timerDuration
        if CDM.IsPreviewingLayer(layer) and layer.timerLength > 0 then
            layer.duration = CDM.PreviewDuration(layer, layer.timerLength)
            running = true
        end
    end

    CDM:SetLayerTimer(layer, running and layer.duration or nil)
    layer.endTime = running and (layer.timerEnd or layer.previewEnd) or nil
    CDM:UpdateTexts(layer)
end

---@param layer CDMLayer
---@return boolean
function CDM.IsCountdownActive(layer)
    return (layer.timerEnd ~= nil and GetTime() < layer.timerEnd) or (CDM.IsPreviewingLayer(layer) and layer.timerLength > 0)
end

-- Watchers --

---Update an icon whenever a spell changes
---@param spellID number?
---@param id string
function CDM:WatchSpell(spellID, id)
    if not spellID then return end

    local watchers = spellIndex[spellID]
    if not watchers then
        watchers = {}
        spellIndex[spellID] = watchers
    end
    watchers[id] = true
end

---Re-read only the spell triggers on a spell, in the icons watching it
---@param spellID number?
function CDM:UpdateWatchers(spellID)
    local watchers = spellID and spellIndex[spellID]
    if not watchers then return end

    for id in pairs(watchers) do
        self:UpdateTriggers(id, SPELL_TYPES, spellID)
    end
end

---@param types table<string, true>
function CDM:UpdateAllTriggers(types)
    for id in pairs(self.icons) do
        self:UpdateTriggers(id, types)
    end
end

---Whirling Dragon Punch's usability flips on other spells' cooldowns and no event names it
function CDM:RefreshUsable()
    for id, frame in pairs(self.icons) do
        if frame.shown then
            local display = BuiltDisplay(id)
            local changed = false
            for i, trigger in ipairs(display.Triggers) do
                local layer = frame.layers[i]
                local refresh = layer.watchUsable and self.TriggerTypes[trigger.Type].RefreshUsable
                if refresh and refresh(layer) then
                    changed = true
                end
            end

            if changed then
                self:Derive(id, frame, display)
            end
        end
    end
end

---Re-derive only the icons whose conditions read a global (0) or player/unit (-1) check
---@param triggerIndex number
---@param variable string
---@param other string?
function CDM:DeriveUsing(triggerIndex, variable, other)
    for id in pairs(self.icons) do
        local display = BuiltDisplay(id)
        if self:ConditionsUse(display, triggerIndex, variable) or (other and self:ConditionsUse(display, triggerIndex, other)) then
            self:Derive(id)
        end
    end
end

---Before a re-resolve or when the pooled frame moves to another display
---@param id string
function CDM:UnwatchIcon(id)
    for _, triggerType in pairs(self.TriggerTypes) do
        if triggerType.Unwatch then
            triggerType.Unwatch(id)
        end
    end

    for spellID, watchers in pairs(spellIndex) do
        watchers[id] = nil
        if not next(watchers) then
            spellIndex[spellID] = nil
        end
    end
end

-- Trigger info --

---Whether a saved value is one of a choice list's, such as CDM.SHOW_ON
---@param choices string[]
---@param value any
---@return boolean
function CDM.IsChoice(choices, value)
    for _, choice in ipairs(choices) do
        if choice == value then return true end
    end
    return false
end

---A spell or item trigger's Show this addon doesn't know, put back to the template's
---@param trigger CDMTrigger
function CDM.ConformShowOn(trigger)
    if not CDM.IsChoice(CDM.SHOW_ON, trigger.ShowOn) then
        trigger.ShowOn = nil
    end
end

---A custom aura goes by its own first ID, not one left from a Cooldown Manager pick
---@param trigger CDMTrigger
---@return number?
function CDM:GetTriggerSpell(trigger)
    if trigger.Type == 'aura' or trigger.Type == 'auraoverlay' then
        if trigger.Source == 'custom' then
            return trigger.SpellIDs and trigger.SpellIDs[1]
        end

        local info = trigger.CooldownID and self.Catalogue:GetEntry(trigger.CooldownID)
        if info then
            return self.Catalogue:DisplaySpell(info)
        end
    end

    return trigger.SpellID or (trigger.SpellIDs and trigger.SpellIDs[1])
end

---@param trigger CDMTrigger
---@return (number|string)? texture
function CDM:GetTriggerTexture(trigger)
    local texture = self.TriggerTypes[trigger.Type].Texture
    if texture then
        return texture(trigger)
    end

    local spellID = self:GetTriggerSpell(trigger)
    return spellID and GetSpellTexture(spellID)
end

---@param trigger CDMTrigger
---@return string? name
function CDM:GetTriggerName(trigger)
    local name = self.TriggerTypes[trigger.Type].Name
    if name then
        return name(trigger)
    end

    local spellID = self:GetTriggerSpell(trigger)
    return spellID and GetSpellName(spellID)
end

---@param warnings string[]
---@param i number the trigger
---@param spellID number
function CDM:WarnUnknownSpell(warnings, i, spellID)
    if not GetSpellName(spellID) then
        warnings[#warnings + 1] = format(L['Trigger %d: spell ID %d does not exist.'], i, spellID)
    end
end

---Problems found from the settings alone, for the Information tab
---@param id string
---@return string[]
function CDM:GetWarnings(id)
    local display = self:Get(id)
    local warnings = {}

    -- The first child will do, as the tree asks this of every group on each draw
    if self:IsGroup(id) then
        for _, other in pairs(self.db.Displays) do
            if other.parent == id then
                return warnings
            end
        end
        warnings[1] = L['This group is empty.']
        return warnings
    end

    -- What a %N. token can read
    local readable
    if display.type == 'auragroup' then
        -- An aura group's trigger branch N
        readable = NRSKNUI:CountTriggerBranches(display.Trigger)
    else
        readable = #display.Triggers
        for i, trigger in ipairs(display.Triggers) do
            local warn = self.TriggerTypes[trigger.Type].Warnings
            if warn then
                warn(i, trigger, warnings)
            end
        end
    end

    local dropped = self:DroppedAuraTexts(display)
    local textIndex = 0
    for _, element in ipairs(display.SubRegions) do
        if element.type == 'text' then
            textIndex = textIndex + 1
            for source in element.Text:gmatch('%%(%d+)%.[ptsn]') do
                local n = tonumber(source)
                if n < 1 or n > readable then
                    warnings[#warnings + 1] = format(L['Text %d reads trigger %d, which does not exist.'], textIndex, n)
                end
            end
            if dropped[element] then
                warnings[#warnings + 1] = format(L["Text %d stays empty: an earlier text already shows the aura's timer, stacks, caster or name."], textIndex)
            end
        end
    end

    return warnings
end

-- Resolve --

---@param frame CDMIcon
---@param display CDMDisplay
function CDM:ResolveTriggers(frame, display)
    self:UnwatchIcon(frame.id)

    for i, trigger in ipairs(display.Triggers) do
        local layer = frame.layers[i]
        local triggerType = self.TriggerTypes[trigger.Type]
        local secret = triggerType.Secret == true

        -- An aura layer is drawn by its aura button, so its own parts hide
        layer.Icon:SetShown(not secret and self:ShowsIcon(layer, frame.style, display))
        if layer.isBar then
            layer.Bar:SetShown(not secret)
        end
        layer.Cooldown:SetShown(not secret)
        layer.textHost:SetShown(not secret)
        layer.borderHost:SetShown(not secret)
        if not secret then
            self:ReleaseAuraLayer(layer)
        end

        -- One left by another trigger type would stand in for this one's %s
        layer.count = nil
        triggerType.Resolve(layer, trigger)
    end
end

---Spell and timer triggers on a base spell or all, an override never changes what loads
---@param baseSpellID number?
function CDM:ResolveOverrides(baseSpellID)
    local ids = self.icons
    if baseSpellID then
        -- Spell and timer triggers watch their own spell, so a spell no one watches is on no trigger
        ids = spellIndex[baseSpellID]
        if not ids then return end
    end
    for id in pairs(ids) do
        local frame, display = self.icons[id], BuiltDisplay(id)
        local changed = false
        for i, trigger in ipairs(display.Triggers) do
            if (trigger.Type == 'spell' or trigger.Type == 'timer') and (not baseSpellID or trigger.SpellID == baseSpellID) then
                local layer = frame.layers[i]
                local before, wasOverridden = layer.spellID, layer.overridden
                self.TriggerTypes[trigger.Type].Resolve(layer, trigger)
                -- An Ignore Override icon keeps its spell, but its Overridden condition still flips
                changed = changed or layer.spellID ~= before or layer.overridden ~= wasOverridden
            end
        end

        if changed then
            self:UpdateIcon(id)
        end
    end
end

---Re-read every spell and timer icon, a talent can swap one with no override event
function CDM:RefreshSpellTextures()
    for id, frame in pairs(self.icons) do
        for i, trigger in ipairs(BuiltDisplay(id).Triggers) do
            local layer = frame.layers[i]
            if layer.spellID and (trigger.Type == 'spell' or trigger.Type == 'timer') then
                local icon, original = GetSpellTexture(layer.spellID)
                -- An Ignore Override spell trigger keeps the base spell's own icon, as its Resolve does
                self:SetIconTexture(layer, trigger.Type == 'spell' and trigger.IgnoreOverride and original or icon)
            end
        end
    end
end

-- Visibility --

---Any or All in the WA style, the first active trigger shows unless one is pinned
---@param frame CDMIcon
---@param display CDMDisplay
function CDM:SelectLayer(frame, display)
    local triggers = display.Triggers
    -- Not while editing, one inactive trigger would blank the preview
    local requireAll = display.Activation == 'all' and not self.previewing
    local first, blocked, standby = nil, false, nil

    -- The first active trigger, with All any inactive one blocks
    for i, trigger in ipairs(triggers) do
        local triggerType = self.TriggerTypes[trigger.Type]
        if not triggerType.Secret then
            if triggerType.IsActive(frame.layers[i], trigger) then
                first = first or i
            else
                if requireAll then
                    blocked = true
                end
                if not standby and triggerType.IsStandby and triggerType.IsStandby(frame.layers[i], trigger) then
                    standby = i
                end
            end
        end
    end

    if blocked then
        first = nil
    end

    -- Hidden but ready, a condition's Show Display can bring it up
    frame.standbyLayer = not blocked and standby and frame.layers[standby] or nil

    local pin = display.DynamicTrigger
    local pinTrigger = pin and triggers[pin]
    if not pinTrigger then
        pin = nil
    end
    local pinSecret = pinTrigger and self.TriggerTypes[pinTrigger.Type].Secret == true
    -- A pin needs something active and an aura might be
    local pinned = pin ~= nil and (first ~= nil or pinSecret)

    -- Show the chosen layer
    local maybeAura, placeholder = false, false
    for i, trigger in ipairs(triggers) do
        local secret = self.TriggerTypes[trigger.Type].Secret == true
        local show
        if blocked then
            show = false
        elseif trigger.Type == 'auraoverlay' then
            show = true
        elseif pinned then
            show = i == pin
        elseif secret then
            -- Unreadable, so it covers the active layer while up
            show = first == nil or i < first
        else
            show = i == first
        end

        -- Its aura may be up, so keep the icon visible
        if secret and show then
            maybeAura = true
        end
        if secret and show and trigger.Placeholder and trigger.Type == 'aura' then
            placeholder = true
        end
        frame.layers[i]:SetShown(show)
    end

    frame.placeholder = placeholder
    if pinned then
        frame.activeLayer = not pinSecret and frame.layers[pin] or nil
    else
        frame.activeLayer = first and frame.layers[first] or nil
    end
    frame.hasActive = frame.activeLayer ~= nil or maybeAura
end

---Shown while loaded and active or while previewed, a hidden icon frees its group slot
---@param id string
---@param frame CDMIcon
function CDM:ApplyVisibility(id, frame)
    local visible = frame.shown and (self.previewing or (frame.hasActive and not frame.forceHidden)) or false
    local group = frame.groupId and self.containers[frame.groupId]

    if group and group.isChain then
        ---@cast group CDMChainGroup
        -- Show Display off hides the aura too, not only the slot
        local loaded = frame.shown == true and (self.previewing or not frame.forceHidden)
        -- A placeholder keeps its slot open while the aura is missing
        local logic = frame.activeLayer ~= nil or frame.placeholder
        group:SetChildVisible(id, loaded, self.previewing or logic)
        return
    end

    ---@cast group NorskenCore.DynamicGroup?
    if group then
        if visible then
            group:ActivateChild(id)
        else
            group:DeactivateChild(id)
        end
    else
        frame:SetShown(visible)
    end
end

-- Update --

---@param frame CDMIcon
---@param trigger CDMTrigger
---@param i number
local function RunTrigger(frame, trigger, i)
    local triggerType = CDM.TriggerTypes[trigger.Type]
    triggerType.Update(frame.layers[i], frame.style, trigger)

    -- Conditions override this after, an aura layer's icon is set by its Update
    if not triggerType.Secret then
        frame.layers[i].Icon:SetDesaturated(frame.style.Desaturate)
    end
end

---@param id string
---@param frame CDMIcon
---@param display CDMDisplay
local function Settle(id, frame, display)
    -- A %N.p text reads a trigger that may have updated after its own
    for i = 1, #display.Triggers do
        local layer = frame.layers[i]
        if layer.sourced or layer.auraSourced then
            CDM:UpdateTexts(layer)
        end
    end

    CDM:Derive(id, frame, display)
end

-- Only shown icons update, a hidden one catches up when RefreshLoad shows it again
---@param id string
---@return CDMIcon? frame
---@return CDMDisplay? display
local function Live(id)
    local frame = CDM.icons[id]
    if frame and frame.shown then
        return frame, BuiltDisplay(id)
    end
end

---Every trigger re-read, for builds and settings, combat events use the narrower ones below
---@param id string
function CDM:UpdateIcon(id)
    local frame, display = Live(id)
    if not frame then return end

    ---@cast display -nil
    for i, trigger in ipairs(display.Triggers) do
        RunTrigger(frame, trigger, i)
    end

    Settle(id, frame, display)
end

---Re-read the triggers of these types, only those on a spell when given
---@param id string
---@param types table<string, true>
---@param spellID number?
function CDM:UpdateTriggers(id, types, spellID)
    local frame, display = Live(id)
    if not frame then return end

    ---@cast display -nil
    local ran = false
    for i, trigger in ipairs(display.Triggers) do
        local layer = frame.layers[i]
        if types[trigger.Type] and (not spellID or layer.spellID == spellID or layer.baseSpellID == spellID) then
            RunTrigger(frame, trigger, i)
            ran = true
        end
    end

    if ran then
        Settle(id, frame, display)
    end
end

---Re-read the one trigger behind a layer, for its own timers and events
---@param layer CDMLayer
function CDM:UpdateLayer(layer)
    -- A released frame's timers can still fire
    local id = layer.owner.id
    if not id then return end
    local frame, display = Live(id)
    if not frame then return end
    ---@cast display -nil
    -- A layer past the last trigger, left over from a removed one
    local trigger = display.Triggers[layer.index]
    if not trigger then return end

    RunTrigger(frame, trigger, layer.index)
    Settle(id, frame, display)
end

---Pick the shown layer and re-run conditions and visibility, reading no trigger
---@param id string
---@param frame CDMIcon?
---@param display CDMDisplay?
function CDM:Derive(id, frame, display)
    if not frame then
        frame, display = Live(id)
    end
    if not frame then return end

    ---@cast display -nil
    self:SelectLayer(frame, display)
    self:EvaluateConditions(id, frame, display)
    self:ApplyVisibility(id, frame)
end

-- Events --

local eventFrame, resolveAllFrame, loadCheckFrame ---@type Frame, Frame, Frame
local resolvePending = false

local function ResolveAllScheduled()
    CDM:ResolveAll()
end

local function CheckLoadScheduled()
    if CDM:KnownChanged() then
        CDM:RefreshLoad(true)
    end
end

-- What every trigger reacts to, each trigger type registers its own events besides
local handlers = {
    SPELL_UPDATE_CHARGES = function()
        -- No payload, so every spell trigger re-reads
        CDM:UpdateAllTriggers(SPELL_TYPES)
    end,
    SPELL_UPDATE_USES = function(spellID, baseSpellID)
        CDM:UpdateWatchers(spellID)
        if baseSpellID ~= spellID then
            CDM:UpdateWatchers(baseSpellID)
        end
    end,
    SPELL_UPDATE_USABLE = function()
        CDM:RefreshUsable()
    end,
    PLAYER_REGEN_DISABLED = function()
        CDM.inCombat = true
        CDM:DeriveUsing(0, 'combat')
    end,
    PLAYER_REGEN_ENABLED = function()
        CDM.inCombat = false
        CDM:DeriveUsing(0, 'combat')
        if resolvePending then
            resolvePending = false
            resolveAllFrame:NCScheduleUpdate()
        end
    end,
    PLAYER_TARGET_CHANGED = function()
        CDM:DeriveUsing(0, 'hasTarget', 'attackable')
        -- Usability can change with the target
        CDM:RefreshUsable()
    end,
    GROUP_ROSTER_UPDATE = function()
        CDM:DeriveUsing(-1, 'classInGroup')
    end,
    SPELL_UPDATE_ICON = function(spellID)
        CDM:ResolveOverrides(spellID)
    end,
    COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED = function(baseSpellID)
        CDM:ResolveOverrides(baseSpellID)
    end,
}

---The catalogue rebuilt (SPELLS_CHANGED and others), so every display re-resolves once
function CDM:OnCatalogueChanged()
    if self.inCombat then
        resolvePending = true
        loadCheckFrame:NCScheduleUpdate()
        self:RefreshSpellTextures()
        return
    end

    resolveAllFrame:NCScheduleUpdate()
end

local function OnEvent(_, event, ...)
    handlers[event](...)
end

function CDM:RegisterTriggerEvents()
    -- A reload mid-fight misses the REGEN_DISABLED edge
    self.inCombat = InCombatLockdown()

    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnEvent)
        resolveAllFrame = CreateFrame('Frame')
        resolveAllFrame:NCSetScheduledUpdate(ResolveAllScheduled)
        loadCheckFrame = CreateFrame('Frame')
        loadCheckFrame:NCSetScheduledUpdate(CheckLoadScheduled)
    end

    for event in pairs(handlers) do
        eventFrame:RegisterEvent(event)
    end

    for _, triggerType in pairs(self.TriggerTypes) do
        if triggerType.RegisterEvents then
            triggerType.RegisterEvents()
        end
    end
end

function CDM:UnregisterTriggerEvents()
    eventFrame:UnregisterAllEvents()

    for _, triggerType in pairs(self.TriggerTypes) do
        if triggerType.UnregisterEvents then
            triggerType.UnregisterEvents()
        end
    end
end

-- Exports --

CDM.SPELL_TYPES = SPELL_TYPES
