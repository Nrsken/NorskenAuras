---@class NRSKNUI
local NRSKNUI = select(2, ...)

-- Displays are account wide and load conditions do the work, so there are no profiles.
NRSKNUI.Defaults = {
    global = {
        HidePlayerCastBar = false,
        AnchorMinWidth = 0,
        TrinketBlacklist = {}, -- [itemID] = true, trinkets whose on-use isn't worth tracking
        Version = 0,
        Displays = {}, -- 'cdm:N' keys, user data only
        SidebarCollapsed = { ['*'] = {} }, -- [page][section key] = true
        Theme = CopyTable(NRSKNUI.ThemeDefaults),
        Minimap = { hide = false },
    },
}
