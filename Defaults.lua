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
        Theme = {
            mode           = "preset",
            selectedPreset = "NUI Neon",
            customColors   = {},
            fontFace       = "Interface\\AddOns\\NorskenCore\\Media\\Fonts\\Expressway.TTF",
            fontSizeNormal = 12,
            fontSizeSmall  = 12,
            fontSizeLarge  = 16,
            fontOutline    = "OUTLINE",
            fontShadow     = false,
            windowOpacity  = 1,     -- how solid the settings window is, 0.3-1
            zoneContrast   = 1,     -- spacing between the window zones' tones, 0.5-2
            surfaceTint    = 1,     -- how much of the base hue the surfaces carry, 0-3
        },
    },
}
