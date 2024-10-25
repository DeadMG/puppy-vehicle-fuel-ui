local gui = require("__flib__.gui")

local windowName = "vehicle_fuel_ui"

function toolbarHeight(scale)
    return scale * 135
end

function renderTime(seconds)
    seconds = math.floor(seconds)
    
    if seconds < 60 then
        return {"time-symbol-seconds-short", seconds }
    end

    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return {"",  {"time-symbol-minutes-short", minutes }, " ", {"time-symbol-seconds-short", seconds % 60 } }
    end
    
    local hours = math.floor(seconds / 3600)
    return {"",  {"time-symbol-hours-short", hours }, " ", {"time-symbol-minutes-short", minutes % 60 }, " ", {"time-symbol-seconds-short", seconds % 60 } }
end

function itemPrototype(item)
    if type(item) == 'string' then return prototypes.item[item] end
    if item.object_name == "LuaItemPrototype" then return item end
    if item.prototype then return item.prototype end
    return item
end

function syncDataToUI(player_index)
    local player = game.get_player(player_index)
    local ui_state = storage.ui_state[player_index]
    
    if not ui_state.dialog then return end
    
    local vehicle = ui_state.vehicle
    local burner = vehicle.burner
    
    local total = burner.remaining_burning_fuel
    for _, fuel in ipairs(burner.inventory.get_contents()) do
        local proto = prototypes.item[fuel.name]
        if proto then
            total = total + fuel.count * proto.fuel_value
        end
    end
    
    if burner.currently_burning then
        local proto = itemPrototype(burner.currently_burning.name)
        ui_state.dialog.fuel_remaining.value = burner.remaining_burning_fuel / proto.fuel_value
        ui_state.dialog.item_icon.sprite = "item/" .. proto.name
        ui_state.dialog.item_count.caption = burner.inventory.get_item_count(proto.name)
    else
        ui_state.dialog.fuel_remaining.value = 0
        ui_state.dialog.item_icon.sprite = ""
        ui_state.dialog.item_count.caption = 0
    end
    
    local vehicleProto = prototypes.entity[vehicle.name]
    
    if vehicleProto.type == 'car' then
        -- You would think consumption should be in Watts, but it actually seems to be Joules per tick rather than per second
        local consumption_rate = vehicle.consumption_modifier * vehicleProto.consumption * 60
        ui_state.dialog.estimated_time.caption = {"vehicle-fuel-ui.estimated-remaining", renderTime(total / consumption_rate) }
    else
        local consumption_rate = vehicleProto.max_energy_usage * 60
        ui_state.dialog.estimated_time.caption = {"vehicle-fuel-ui.estimated-remaining", renderTime(total / consumption_rate) }
    end
end

local function is_position_off_screen(position, resolution)
    return position.x < 0 or position.y < 0 or
           position.x > (resolution.width - 20) or
           position.y > (resolution.height - 20)
end

function ensureWindow(player_index)
    local player = game.get_player(player_index)

    local rootgui = player.gui.screen
    
    if rootgui[windowName] then return end
    
    local dialog = gui.add(rootgui, {
        {type="frame", direction="vertical", name=windowName, style_mods={left_padding=0,left_margin=0, bottom_margin=0}, children={
            {type="flow", style_mods={left_padding=0,left_margin=-6}, children={
                {type = "empty-widget", style="draggable_space",  style_mods={left_padding=0, left_margin=0}, drag_target=windowName, style_mods={width=8, height=45} },
                {type="flow", direction="vertical", children = {
                    {type="flow", name="main_container", style_mods= {vertical_align="center", left_margin=0}, children={
                        {type="sprite", elem_type="item", sprite=nil, name="item_icon", resize_to_sprite=false, style_mods= { height = 16, width = 16 } },
                        {type="label", name="item_count" },
                        {type="progressbar", name="fuel_remaining", style_mods= { color={r=1, g=0.667, b=0.2}, vertical_align="center", width="120" } }}},
                    {type="label", name="estimated_time", caption=nil },
                }}    
            }}}}})
            
    storage.ui_state[player_index].dialog = dialog    
    
    local ui_state = storage.ui_state[player_index]
    if ui_state.location and not is_position_off_screen(ui_state.location, player.display_resolution) then
        dialog[windowName].location = storage.ui_state[player_index].location
    else
        dialog[windowName].location = { 0, player.display_resolution.height - toolbarHeight(player.display_scale) }
    end
end

function openGui(player_index)
    local player = game.get_player(player_index)
    local rootgui = player.gui.screen
    if not rootgui[windowName] then createWindow(player_index) end
end

function closeGui(player_index)
    local player = game.get_player(player_index)
    local rootgui = player.gui.screen
    if rootgui[windowName] then
        rootgui[windowName].destroy()	
        if storage.ui_state and storage.ui_state[player_index] then
            storage.ui_state[player_index].dialog = nil
        end
    end
end

function syncData()
    storage.ui_state = storage.ui_state or {}

    for player_index, ui_state in pairs(storage.ui_state) do
        local player = game.get_player(player_index)
        if not player.vehicle or not player.vehicle.valid or not player.vehicle.burner or not player.vehicle.burner.valid then
            closeGui(player_index)
        else
            syncDataToUI(player_index)
        end
    end
end

function playerDrivingStateChanged(player_index, vehicle)
    storage.ui_state = storage.ui_state or {}
  
    local player = game.get_player(player_index)
    if vehicle == nil or not player.vehicle then
        closeGui(player_index)
        return
    end
    
    if not vehicle.valid then return end    
    if not vehicle.burner or not vehicle.burner.valid then return end
    
    storage.ui_state[player_index] = storage.ui_state[player_index] or {}
    storage.ui_state[player_index].vehicle = vehicle
    
    ensureWindow(player_index)
    syncDataToUI(player_index)
end

script.on_event(defines.events.on_gui_location_changed, function(e)
    if not e.element or e.element.name ~= windowName then return end
    
    storage.ui_state = storage.ui_state or {}
    storage.ui_state[e.player_index] = storage.ui_state[e.player_index] or {}
    storage.ui_state[e.player_index].location = e.element.location
end)

script.on_nth_tick(60, syncData)

script.on_event(defines.events.on_player_driving_changed_state, function(e) 
    playerDrivingStateChanged(e.player_index, e.entity)
end)

script.on_init(function()
  storage.ui_state = {}
end)
