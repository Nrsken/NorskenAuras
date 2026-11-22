---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras
local Apply = NRSKNUI.Enum.Apply
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight

local Shared = NRSKNUI.CDMOptions
local TriggerRows = Shared.TriggerRows
local TextCodes = Shared.TextCodes

TextCodes.faction = {
    p = L['Standing progress'],
    t = L['Size of the standing'],
    n = L['Faction name'],
    i = L['Faction icon'],
    tokens = {
        standing = L['Standing, e.g. Honored'],
        standingId = L['Standing number'],
        percentRep = L['Standing percent'],
        level = L['Level, rank or renown'],
        maxLevel = L['Highest level'],
    },
    tips = { standingId = L['Hated is 1 and Exalted 8, friendship and renown are 0.'] },
}

local tinsert = table.insert
local ipairs = ipairs

local GetFactionDataByID = C_Reputation.GetFactionDataByID

local factionOptions ---@type table[]?

-- Names don't change in a session, so the list is built once
---@return table[]
local function FactionOptions()
    if factionOptions then
        return factionOptions
    end

    factionOptions = {}
    for _, group in ipairs(Shared.FACTIONS) do
        local header = GetFactionDataByID(group.header)
        local headerAt = #factionOptions + 1
        for _, factionID in ipairs(group) do
            local data = GetFactionDataByID(factionID)
            -- The other side's factions read nil, a plain header has no standing to follow
            if data and not (data.isHeader and not data.isHeaderWithRep) then
                factionOptions[#factionOptions + 1] = { value = factionID, text = data.name }
            end
        end
        if header and #factionOptions >= headerAt then
            tinsert(factionOptions, headerAt, { value = 'header:' .. group.header, text = header.name, header = true })
        end
    end
    return factionOptions
end

---@param card KajiGUIFluentCard
---@param typeRow KajiGUIFluentRow
---@param trigger CDMTrigger
---@param apply fun(part: NorskenCore.Apply)
function TriggerRows.faction(card, typeRow, _, trigger, _, apply)
    typeRow:Checkbox(L['Use Watched Faction'], {
        width = 1,
        tooltip = L['Follows the faction watched on the experience bar.'],
        value = trigger.UseWatched,
        callback = function(checked)
            trigger.UseWatched = checked
            apply(Apply.All)
            card:Rebuild()
        end,
    })
    if trigger.UseWatched then return end

    card:Row(rowH):Dropdown(L['Faction'], {
        width = 1,
        searchable = true,
        tooltip = L["Factions this character can't earn are left out."],
        options = FactionOptions(),
        value = trigger.FactionID,
        callback = function(value)
            trigger.FactionID = value
            apply(Apply.All)
        end,
    })
end
