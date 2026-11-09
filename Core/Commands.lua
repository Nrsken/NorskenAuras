---@class NRSKNUI
local NRSKNUI = select(2, ...)

-- Commands --

NRSKNUI:RegisterCommands({ '/nauras' })

function _G.NorskenAuras_OnCompartmentClick()
    NRSKNUI:ToggleOptions()
end
