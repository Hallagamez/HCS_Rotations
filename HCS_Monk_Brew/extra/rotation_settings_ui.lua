--[[
    Rotation Settings UI – minimal stub for API compatibility.
    Replace with the full rotation_settings_ui from your build for the real custom window.
]]

local M = {}
M.is_stub = true  -- Stub: no real window; full module from build would set false or omit.

function M.new(opts)
    opts = opts or {}
    local id = opts.id or "rotation_ui"
    local enable_id = id .. "_show_custom_ui"
    local enable = core.menu.checkbox(false, enable_id)

    local ui = {
        menu = { enable = enable },
        _id = id,
        _tabs = {},
    }

    function ui:add_tab(tab_opts, builder_fn)
        if type(builder_fn) == "function" and (tab_opts.visible_when == nil or tab_opts.visible_when()) then
            self._tabs[#self._tabs + 1] = { opts = tab_opts, build = builder_fn }
        end
    end

    function ui:on_menu_render() end
    function ui:on_render() end
    function ui:register_section() end

    return ui
end

return M
