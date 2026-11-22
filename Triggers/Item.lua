---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local TriggerTypes = CDM.TriggerTypes
local IsPreviewing = CDM.IsPreviewingLayer
local PreviewDuration = CDM.PreviewDuration
local PREVIEW_LENGTH = CDM.PREVIEW_LENGTH
local GCD_SPELL = NRSKNUI.GCD_SPELL
local L = NRSKNUI.Libs.AL

local GetInventoryItemCooldown = GetInventoryItemCooldown
local GetInventoryItemID = GetInventoryItemID
local CreateFrame = CreateFrame
local format = string.format
local GetTime = GetTime
local ipairs = ipairs
local pairs = pairs

local CreateDuration = C_DurationUtil.CreateDuration
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetItemCooldown = C_Item.GetItemCooldown
local GetItemIconByID = C_Item.GetItemIconByID
local GetItemNameByID = C_Item.GetItemNameByID
local GetItemCount = C_Item.GetItemCount
local GetItemSpell = C_Item.GetItemSpell
local IsUsableItem = C_Item.IsUsableItem
local NewTimer = C_Timer.NewTimer

local INVSLOT_TRINKET1 = INVSLOT_TRINKET1
local INVSLOT_TRINKET2 = INVSLOT_TRINKET2

local ITEM_SLOTS = {
    trinket1 = INVSLOT_TRINKET1,
    trinket2 = INVSLOT_TRINKET2,
}

-- Items that share one cooldown, so any of them reads it, the first one in the bags is shown
---@type table<string, number[]>
local ITEM_FAMILIES = {
    healthstone = { 5512, 224464 }, -- Healthstone, Demonic Healthstone
    combatPotion = { 241308 },      -- Light's Potential, every combat potion shares its cooldown
}

local itemWatchers = {} ---@type table<string, true> icon ids with an item trigger

-- Trigger --

---@param layer CDMLayer
---@return boolean changed
local function RefreshUsable(layer)
    if not layer.itemID then return false end
    local usable = IsUsableItem(layer.itemID) == true
    local changed = usable ~= layer.state.usable
    layer.state.usable = usable
    return changed
end

-- The item IDs a trigger can read, the equipped trinket, a family or its own ID
---@param trigger CDMTrigger
---@return number[]
local function ItemIDs(trigger)
    local slot = ITEM_SLOTS[trigger.Item]
    if slot then
        return { GetInventoryItemID('player', slot) }
    end
    if trigger.Item == 'custom' then
        if not trigger.ItemID then
            return {}
        end
        return { trigger.ItemID }
    end
    return ITEM_FAMILIES[trigger.Item]
end

-- An equipped trinket, a family of items sharing a cooldown or one item by ID
TriggerTypes.item = {
    ---@param trigger CDMTrigger
    ---@return boolean
    IsKnown = function(trigger)
        local itemID = ItemIDs(trigger)[1]
        if not itemID then return false end
        -- A blacklisted trinket never loads, nor a passive one when the trigger hides those
        if ITEM_SLOTS[trigger.Item] then
            if CDM.db.TrinketBlacklist[itemID] then return false end
            if trigger.HidePassive and not GetItemSpell(itemID) then return false end
        end
        return true
    end,

    ---@param trigger CDMTrigger
    Conform = function(trigger)
        -- What this addon doesn't know takes the template's
        if not (ITEM_SLOTS[trigger.Item] or ITEM_FAMILIES[trigger.Item] or trigger.Item == 'custom') then
            trigger.Item = nil
        end
        CDM.ConformShowOn(trigger)
        if type(trigger.ItemID) ~= 'number' then
            trigger.ItemID = nil
        end
    end,

    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    Resolve = function(layer, trigger)
        local ids = ItemIDs(trigger)
        local owned
        for _, itemID in ipairs(ids) do
            if ITEM_SLOTS[trigger.Item] or GetItemCount(itemID, false, true) > 0 then
                owned = itemID
                break
            end
        end
        layer.itemID = owned or ids[1]
        layer.itemSlot = ITEM_SLOTS[trigger.Item]
        layer.itemFamily = not layer.itemSlot and ids or nil
        layer.spellID, layer.baseSpellID = nil, nil
        layer.watchUsable = CDM:ConditionsUse(layer.owner.display, layer.index, 'usable')
        itemWatchers[layer.owner.id] = true
        CDM:SetIconTexture(layer, layer.itemID and GetItemIconByID(layer.itemID))
    end,

    -- Item cooldowns are plain numbers, so the duration object is built here
    ---@param layer CDMLayer
    ---@param style NorskenCore.IconStyle|CDMBarStyle
    ---@param trigger CDMTrigger
    Update = function(layer, style, trigger)
        local itemID = layer.itemID
        if not itemID then return end

        -- The inventory one says 0 or 1 and whether it's the GCD, the item one false or true
        local start, duration, enabled, isOnGCD
        if layer.itemSlot then
            -- The stub lists three returns, the game gives a fourth (CooldownViewer.lua reads it)
            ---@diagnostic disable-next-line: unbalanced-assignments
            start, duration, enabled, isOnGCD = GetInventoryItemCooldown('player', layer.itemSlot)
        else
            start, duration, enabled = GetItemCooldown(itemID)
            -- A bag item has no GCD flag, its cooldown is the GCD while it matches the GCD spell's
            local gcd = GetSpellCooldown(GCD_SPELL)
            ---@diagnostic disable-next-line: secret-comparison
            isOnGCD = start == gcd.startTime and duration == gcd.duration
        end
        local onCooldown = enabled ~= false and enabled ~= 0 and not isOnGCD and duration > 0 and start + duration > GetTime()
        local preview = not onCooldown and IsPreviewing(layer)

        layer.itemDuration = layer.itemDuration or CreateDuration()
        if onCooldown then
            layer.itemDuration:SetTimeFromStart(start, duration)
            layer.duration = layer.itemDuration
        elseif preview then
            layer.duration = PreviewDuration(layer, PREVIEW_LENGTH)
        else
            layer.itemDuration:SetTimeFromStart(0, 0)
            layer.duration = layer.itemDuration
        end
        CDM:SetLayerTimer(layer, (onCooldown or preview) and layer.duration or nil)
        layer.endTime = (onCooldown and start + duration) or (preview and layer.previewEnd) or nil
        if layer.timerTicker then
            layer.timerTicker:Cancel()
        end
        layer.timerTicker = nil
        if onCooldown and trigger.ShowOn ~= 'always' then
            -- A hidden layer's Cooldown never fires OnCooldownDone, so When Ready would stay hidden
            layer.timerTicker = NewTimer(start + duration - GetTime(), function()
                layer.timerTicker = nil
                CDM:UpdateLayer(layer)
            end)
        end

        -- A family or custom item counts what's in the bags, a trinket is equipped
        local count
        if layer.itemFamily then
            count = 0
            for _, familyID in ipairs(layer.itemFamily) do
                count = count + GetItemCount(familyID, false, true)
            end
        end
        layer.count = count
        layer.state.onCooldown = onCooldown or preview
        layer.state.owned = not count or count > 0
        -- About 50 µs a call, so only for a condition that reads it
        if layer.watchUsable then
            RefreshUsable(layer)
        end

        CDM:UpdateTexts(layer)
    end,

    -- Not in the bags it only shows with Show When Not in Bags or a Show Display condition
    ---@param layer CDMLayer
    ---@param trigger CDMTrigger
    IsActive = function(layer, trigger)
        if layer.itemID == nil then return false end
        if IsPreviewing(layer) then return true end
        if layer.state.owned == false and not trigger.ShowNotOwned then return false end
        local showOn = trigger.ShowOn
        return showOn == 'always' or (layer.state.onCooldown == true) == (showOn == 'cooldown')
    end,

    ---@param layer CDMLayer
    IsStandby = function(layer) return layer.itemID ~= nil and layer.state.owned == false end,

    -- SPELL_UPDATE_USABLE covers items, only it tells a Gateway Control Shard went unusable
    RefreshUsable = RefreshUsable,
}

---@param trigger CDMTrigger
---@return number? texture
TriggerTypes.item.Texture = function(trigger)
    local itemID = ItemIDs(trigger)[1]
    return itemID and GetItemIconByID(itemID)
end

---@param trigger CDMTrigger
---@return string? name
TriggerTypes.item.Name = function(trigger)
    local itemID = ItemIDs(trigger)[1]
    return itemID and GetItemNameByID(itemID)
end

---@param i number
---@param trigger CDMTrigger
---@param warnings string[]
TriggerTypes.item.Warnings = function(i, trigger, warnings)
    if trigger.Item ~= 'custom' then return end
    if not trigger.ItemID then
        warnings[#warnings + 1] = format(L['Trigger %d: no item ID.'], i)
    elseif not GetItemInfoInstant(trigger.ItemID) then
        warnings[#warnings + 1] = format(L['Trigger %d: item ID %d does not exist.'], i, trigger.ItemID)
    end
end

---@param id string
TriggerTypes.item.Unwatch = function(id)
    itemWatchers[id] = nil
end

-- Events --

local ITEM_TYPES = { item = true }

local function UpdateItems()
    for id in pairs(itemWatchers) do
        CDM:UpdateTriggers(id, ITEM_TYPES)
    end
end

-- A swapped trinket or a bag change can change which item shows and whether it loads
local function ResolveItems()
    local itemType = TriggerTypes.item
    for id in pairs(itemWatchers) do
        local frame = CDM.icons[id]
        for i, trigger in ipairs(frame.display.Triggers) do
            if trigger.Type == 'item' then
                itemType.Resolve(frame.layers[i], trigger)
            end
        end
    end
    CDM:RefreshLoad(true)
    UpdateItems() -- A display that stayed loaded may now show another item or count
end

-- Usability is CDM:RefreshUsable's, these catch what changes with cooldowns and combat
local handlers = {
    BAG_UPDATE_COOLDOWN = UpdateItems,
    PLAYER_REGEN_DISABLED = UpdateItems,
    PLAYER_REGEN_ENABLED = UpdateItems,
    BAG_UPDATE_DELAYED = ResolveItems,
    PLAYER_EQUIPMENT_CHANGED = ResolveItems,
}

local eventFrame ---@type Frame?

local function OnEvent(_, event)
    handlers[event]()
end

TriggerTypes.item.RegisterEvents = function()
    if not eventFrame then
        eventFrame = CreateFrame('Frame')
        eventFrame:SetScript('OnEvent', OnEvent)
    end

    for event in pairs(handlers) do
        eventFrame:RegisterEvent(event)
    end
end

TriggerTypes.item.UnregisterEvents = function()
    eventFrame:UnregisterAllEvents()
end

-- Conditions --

CDM.ConditionChecks.item = {
    active     = { type = 'bool', get = TriggerTypes.item.IsActive },
    onCooldown = { type = 'bool', get = function(layer) return layer.state.onCooldown == true end },
    remaining  = { type = 'number', get = function(layer) return layer.endTime and layer.endTime - GetTime() or 0 end },
    count      = { type = 'number', get = function(layer) return layer.count or 0 end },
    owned      = { type = 'bool', get = function(layer) return layer.state.owned ~= false end },
    usable     = { type = 'bool', get = function(layer) return layer.state.usable == true end },
}
