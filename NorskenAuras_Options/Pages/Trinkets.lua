---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras
---@class CDMModule
local CDM = NRSKNUI:GetModule('CDM')
local L = NRSKNUI.Libs.AL
local Theme = NRSKNUI.Theme
local rowH = Theme.rowHeight

local pairs, ipairs = pairs, ipairs
local tostring = tostring
local format = string.format
local tonumber = tonumber

local GetItemIconByID = C_Item.GetItemIconByID
local GetItemNameByID = C_Item.GetItemNameByID

local Shared = NRSKNUI.CDMOptions
local GENERAL = Shared.GENERAL
local QUESTION_MARK = Shared.QUESTION_MARK
local Reopen = Shared.Reopen

---The trinket blacklist, its own page so the main page stays short; Back returns to the trigger it came from or home.
---@param page table
local function BuildTrinketPage(page)
    local blacklist = page:Card(L['Trinket Blacklist'], 'all')
    local returnKey = Shared.trinketReturnKey --[[@as string?]]
    if not (returnKey and CDM:Get(returnKey)) then
        returnKey = nil
    end
    blacklist:HeaderButton({
        texture = NRSKNUI.Media.GUITextures .. 'right-arrow.png',
        size = 20,
        rotation = math.pi, -- our right arrow, pointing back
        tooltip = returnKey and format(L['Back to %s'], CDM:GetName(returnKey)) or L['Back'],
        onClick = function() Reopen(returnKey or GENERAL) end,
    })
    blacklist:Rebuild(function(card)
        card:Row(rowH):EditBox(L['Add Trinket'], {
            width = 1,
            tooltip = L["An item ID. Trinkets on this list are never tracked, for on-use effects that only switch the trinket's mode."],
            callback = function(text)
                local itemID = tonumber(text)
                if not itemID then return end
                CDM.db.TrinketBlacklist[itemID] = true
                CDM:ApplySettings()
                card:Rebuild()
            end,
        })

        card:Separator()

        local ids = {}
        for itemID in pairs(CDM.db.TrinketBlacklist) do ids[#ids + 1] = itemID end
        table.sort(ids)
        for _, itemID in ipairs(ids) do
            card:Row(28):Icon({
                width = 1,
                size = 24,
                texture = GetItemIconByID(itemID) or QUESTION_MARK,
                text = { text = GetItemNameByID(itemID) or tostring(itemID), description = tostring(itemID) },
                tooltip = function(tooltip)
                    tooltip:SetItemByID(itemID)
                    tooltip:AddLine(L['Click to remove it from the blacklist.'], Theme.textSecondary[1], Theme.textSecondary[2], Theme.textSecondary[3], true)
                end,
                onClick = function(button)
                    if button ~= 'LeftButton' then return end
                    CDM.db.TrinketBlacklist[itemID] = nil
                    CDM:ApplySettings()
                    card:Rebuild()
                end,
            })
        end
    end)
end

Shared.BuildTrinketPage = BuildTrinketPage
