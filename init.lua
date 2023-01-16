-- Liquid Tanks

liquidtanks = {}

local mod_name = minetest.get_current_modname()
local S = minetest.get_translator(mod_name)

local _tanks = {}
local _buckets = {}
local _liquids = {}

local _config = {
    meta = 'liquidtanks:amount',
    amount = 16000,
    description = S('Liquid tank')
}

local function get_node_name(source)
    local name = { 'tank' }

    if source then
        name[#name + 1] = table.concat(source:split(':'), "_")
    end

    return mod_name .. ':' .. table.concat(name, '_')
end

local function get_item_name(itemname)
    local name = { 'inv' }

    if itemname then
        name[#name + 1] = table.concat(itemname:split(':'), "_")
    end

    return mod_name .. ':' .. table.concat(name, '_')
end

local function is_creative_mode(player)
    return minetest.check_player_privs(player, 'creative') or minetest.is_creative_enabled(player:get_player_name())
end

local function get_overlay_texture(def)
    local str, color

    if def.tiles then
        if type(def.tiles[1]) == 'string' then
            str = '^[mask:' .. def.tiles[1]
        end
        if type(def.tiles[1].name) == 'string' then
            str = '^[mask:' .. def.tiles[1].name
        end
    end

    if not str and def.post_effect_color then
        color = def.post_effect_color
        str =  '^[multiply:' .. minetest.rgba(color.r, color.g, color.b)
    end

    if not str then
        str = '^[multiply:' .. minetest.rgba(0, 0, 0)
    end

    return str
end

local function update_node(pos, node_name, amount)
    local param = 0
    local metadata
    if amount > 0 then
        param = math.ceil(63 / _config.amount * amount)
    end

    minetest.set_node(pos, {name = node_name, param2 = param})
    if amount > 0 then
        metadata = minetest.get_meta(pos)
        metadata:set_string(_config.meta, amount)
    end
end

local function preserve_node_meta(pos, oldnode, oldmeta, drops)
    local meta = drops[1]:get_meta()
    local amount = oldmeta[_config.meta]
    if not amount then
        amount = 0
    end

    meta:set_string(_config.meta, amount)
    meta:set_string('description', minetest.registered_nodes[oldnode.name].description .. '\n' .. amount .. ' mb')
    drops[1]:set_wear(65530 - math.ceil(65530 / _config.amount * amount))
end

local function place_node(itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return
    end
    local pos = pointed_thing.under
    local node = minetest.get_node_or_nil(pos)
    local def = node and minetest.registered_nodes[node.name]
    local count = itemstack:get_count()

    if not def or not def.buildable_to then
        pos = pointed_thing.above
        node = minetest.get_node_or_nil(pos)
        def = node and minetest.registered_nodes[node.name]
        if not def or not def.buildable_to then
            return itemstack
        end
    end

    local amount = tonumber(itemstack:get_meta():get_string(_config.meta))
    if not amount then
        amount = 0
    end

    for node_name, def in pairs(_tanks) do
        if itemstack:get_name() == def.itemname then
            update_node(pos, node_name, amount)
            break
        end
    end

    if not is_creative_mode(placer) then
        itemstack:set_count(count - 1)
    end

    return itemstack
end

local function rightclick_node(pos, node, clicker, itemstack, pointed_thing)
    local wielded = itemstack
    local wielded_name = wielded:get_name()

    if not _buckets[wielded_name] then return end

    local amount = tonumber(minetest.get_meta(pos):get_string(_config.meta))
    if not amount then
        amount = 0
    end

    local item_source
    local node_source
    local old_amount = amount
    local inventory = clicker:get_inventory()
    local count = wielded:get_count() - 1
    local s

    if _buckets[wielded_name].source then
        if amount == 0 or _tanks[node.name].source == _buckets[wielded_name].source then
            if math.abs(_config.amount - amount) >= _buckets[wielded_name].amount then
                amount = amount + _buckets[wielded_name].amount
                if(is_creative_mode(clicker)) then
                    item_source = _buckets[wielded_name].source
                else
                    item_source = nil
                end
                node_source = _buckets[wielded_name].source
            end
        end
    else
        if amount >= _buckets[wielded_name].amount then
            amount = amount - _buckets[wielded_name].amount
            item_source = nil
            if not is_creative_mode(clicker) then
                item_source = _tanks[node.name].source
            end
            node_source = _tanks[node.name].source
            if amount == 0 then
                node_source = nil
            end
        end
    end

    if old_amount == amount then
        return wielded
    end

    for node_name, def in pairs(_tanks) do
        if def.source == node_source then
            update_node(pos, node_name, amount)
            break
        end
    end

    if is_creative_mode(clicker) then
        return wielded
    end

    for item_name, def in pairs(_buckets) do
        if def.group == _buckets[wielded_name].group and def.source == item_source then
            if count == 0 then
                wielded = ItemStack(item_name)
            else
                s = ItemStack(item_name)
                wielded:set_count(count)
                if inventory:room_for_item("main", s) then
                    inventory:add_item("main", {name = item_name, count = 1})
                else
                    minetest.add_item(clicker:get_pos(), s)
                end
            end
            break
        end
    end

    return wielded
end

liquidtanks.liquids = function()
    return _liquids
end

-- add new source
liquidtanks.register = function(source)
    local node_name = get_node_name(source)
    local item_name = get_item_name(source)
    local base_image = 'liquidtanks_tank_inv_base.png'
    local overlay_image = 'liquidtanks_tank_inv_overlay.png'
    local colorstr = minetest.rgba(0,0,0)
    local color

    if _tanks[node_name] then return end

    if not source then
        minetest.register_node(node_name, {
            description = _config.description,
            tiles = { 'liquidtanks_tank.png' },
            drawtype = "glasslike_framed",
            paramtype = "light",
            sunlight_propagates = true,
            drop = item_name,
            groups = {cracky = 3, oddly_breakable_by_hand = 3, not_in_creative_inventory = 1},
            sounds = default.node_sound_glass_defaults(),
            on_rightclick = rightclick_node
        })

        minetest.register_craftitem(item_name, {
            description = _config.description,
            inventory_image = 'liquidtanks_tank_inv_base.png',
            stack_max = 99,
            on_place = place_node
        })

        _tanks[node_name] = {
            source = nil,
            itemname = item_name
        }
        return
    end

    if not minetest.registered_nodes[source] then return end
    local def = minetest.registered_nodes[source]

    local exist = 0
    for i,s in ipairs(_liquids) do
        if s == source then
            exist = 1
        end
    end

    if not exist then _liquids[#_liquids + 1] = source end

    local ndef = {
        description = _config.description .. ' [' .. def.description .. ']',
        tiles = { 'liquidtanks_tank.png' },
        special_tiles = def.tiles,
        drawtype = "glasslike_framed",
        paramtype = "light",
        paramtype2 = "glasslikeliquidlevel",
        sunlight_propagates = true,
        drop = item_name,
        groups = {cracky = 3, oddly_breakable_by_hand = 3, not_in_creative_inventory = 1},
        sounds = default.node_sound_glass_defaults(),
        on_rightclick = rightclick_node,
        preserve_metadata = preserve_node_meta
    }

    if def.light_source then
        ndef.light_source = def.light_source
    end

    minetest.register_node(node_name, ndef)

    local idef = {
        description = _config.description .. ' (' .. def.description .. ')',
        -- inventory_image = overlay_image .. '^[multiply:' .. colorstr .. '^' .. base_image,
        inventory_image  = overlay_image .. get_overlay_texture(def) .. '^' .. base_image,
        on_place = place_node,
        groups = {not_in_creative_inventory = 1}
    }

    minetest.register_tool(item_name, idef)

    _tanks[node_name] = {
        source = source,
        itemname = item_name
    }
end

-- add our own stuff as buckets
-- items from the same group replace each other
liquidtanks.register_bucket = function(itemname, source, amount, group)
    if _buckets[itemname] then return end

    _buckets[itemname] = {
        source = source,
        amount = amount or 1000,
        group = group
    }
end

liquidtanks.register()
liquidtanks.register_bucket('bucket:bucket_empty', nil, 1000, 'bucket')

for source, def in pairs(bucket.liquids) do
    liquidtanks.register(def.source)
    liquidtanks.register_bucket(def.itemname, def.source, 1000, 'bucket')
end

minetest.register_craft({
    output = "liquidtanks:inv",
    recipe = {
        {"default:steel_ingot", "default:glass", "default:steel_ingot"},
        {"default:glass", "", "default:glass"},
        {"default:steel_ingot", "default:glass", "default:steel_ingot"},
    },
})
