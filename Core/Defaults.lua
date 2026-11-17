---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras

local CopyTable = CopyTable

-- Displays are account wide and load conditions do the work, so there are no profiles
NRSKNUI.Defaults = {
    global = {
        HidePlayerCastBar = true,
        AnchorMinWidth = 230,
        TrinketBlacklist = {}, -- [itemID] = true, trinkets whose on-use isn't worth tracking
        Version = 0,
        Displays = {}, -- 'cdm:N' keys, user data only
        BrokenDisplays = {}, -- Saved displays no repair could save, kept for a bug report
        SidebarCollapsed = { ['*'] = {} }, -- [page][section key] = true
        Theme = CopyTable(NRSKNUI.ThemeDefaults),
        Minimap = { hide = false },
    },
}
