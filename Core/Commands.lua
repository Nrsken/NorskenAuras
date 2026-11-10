---@class NRSKNUI
local NRSKNUI = _G.NorskenAuras

-- Commands --

NRSKNUI:RegisterCommands({ '/nauras' })

function _G.NorskenAuras_OnCompartmentClick()
    NRSKNUI:ToggleOptions()
end
