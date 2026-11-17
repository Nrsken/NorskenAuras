---@class NorskenAuras
local NRSKNUI = _G.NorskenAuras

-- Commands --

NRSKNUI:RegisterCommands({ '/nauras' })

NRSKNUI:RegisterBindings({
    NORSKENAURAS_TOGGLE = 'Toggle Options',
})

function _G.NorskenAuras_OnCompartmentClick()
    NRSKNUI:ToggleOptions()
end
