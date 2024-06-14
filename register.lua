
local LC = liquidtanks.controller
local CFG = liquidtanks.config

local supports_node_io = minetest.global_exists("node_io")
local supports_fluid_lib = minetest.global_exists("fluid_lib")

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

local function preserve_node_meta(pos, oldnode, oldmeta, drops)
    local meta = drops[1]:get_meta()
    local amount = oldmeta[CFG.meta]
    if not amount then
        amount = 0
    end

    meta:set_string(CFG.meta, amount)
    meta:set_string('description', minetest.registered_nodes[oldnode.name].description .. '\n' .. amount .. ' mB')
    drops[1]:set_wear(65530 - math.ceil(65530 / CFG.amount * amount))
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

    local amount = tonumber(itemstack:get_meta():get_string(CFG.meta))
    if not amount then
        amount = 0
    end

    for node_name, def in pairs(LC.tanks) do
        if itemstack:get_name() == def.itemname then
            LC:set(pos, def.source, amount)
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
    local lc_bucket = LC.buckets[wielded_name]
    local lc_tank = LC.tanks[node.name]

    if not lc_bucket then return end

    local inventory = clicker:get_inventory()
    local count = wielded:get_count() - 1
    local item_source = lc_bucket.source
    local s, amount, item_name

    if lc_bucket.source then
        amount = LC:put(pos, lc_bucket.source, lc_bucket.amount)
        if amount > 0 then
            item_source = nil
        end
    else
        amount = LC:take(pos, lc_tank.source, lc_bucket.amount)
        if amount > 0 then
            item_source = lc_tank.source
        end
    end

    if is_creative_mode(clicker) then
        return wielded
    end

    item_name = LC:get_bucket_item(item_source, lc_bucket.group)

    if item_name then
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
    end

    return wielded
end

local function register_fluid_def(node_name)
    local ndef = {}
    local def = minetest.registered_nodes[node_name]
    local groups = def.groups

    if supports_fluid_lib then
        groups['fluid_container'] = 1
        ndef.groups = groups

        ndef.fluid_buffers = {
            buffer = {
                capacity  = CFG.amount,
                accepts   = true,
                drainable = true,
            }
        }
    end

    if supports_node_io then
        ndef.after_place_node = node_io.update_neighbors

        ndef.after_dig_node = node_io.update_neighbors

        local can_put_liquid = function (pos, node, side, liquid, millibuckets)
            return CFG.amount - LC:amount(pos)
        end
        ndef.node_io_room_for_liquid = can_put_liquid
        ndef.node_io_can_put_liquid = can_put_liquid

        ndef.node_io_can_take_liquid = function (pos, node, side)
            return LC:amount(pos) > 0
        end

        ndef.node_io_accepts_millibuckets = function(pos, node, side)
            return true
        end

        ndef.node_io_put_liquid = function(pos, node, side, putter, liquid, millibuckets)
            local can_put, current_amount = LC:can_put(pos, liquid, millibuckets)
            local leftovers = CFG.amount - current_amount

            if can_put then
                LC:set(pos, liquid, current_amount)
                return leftovers
            end

            return 0
        end

        ndef.node_io_take_liquid = function(pos, node, side, taker, want_liquid, want_millibuckets)
            local amount = LC:take(pos, want_liquid, want_millibuckets)
            return {
                name = want_liquid,
                millibuckets = amount
            }
        end

        ndef.node_io_get_liquid_size = function (pos, node, side)
            return 1
        end

        ndef.node_io_get_liquid_name = function(pos, node, side, index)
            return LC.tanks[node.name].source or ''
        end

        ndef.node_io_get_liquid_stack = function(pos, node, side, index)
            local amount = LC:amount(pos)

            if amount > 1000 then
                amount = 1000
            end

            if LC.tanks[node.name].source then
                return ItemStack(LC.tanks[node.name].source .. ' ' .. amount)
            end

            return ItemStack(nil)
        end
    end

    if ndef then
        minetest.override_item(node_name, ndef)
    end
end

-- add new source
liquidtanks.register = function(source)
    local node_name = LC:get_node_name(source)
    local item_name = LC:get_item_name(source)
    local base_image = 'liquidtanks_tank_inv_base.png'
    local overlay_image = 'liquidtanks_tank_inv_overlay.png'
    local colorstr = minetest.rgba(0,0,0)
    local color

    if LC.tanks[node_name] then return end

    if not source then
        minetest.register_node(node_name, {
            description = CFG.description,
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
            description = CFG.description,
            inventory_image = 'liquidtanks_tank_inv_base.png',
            stack_max = 99,
            on_place = place_node
        })

        LC:register_tank(node_name, nil, item_name)
        register_fluid_def(node_name)
        return
    end

    if not minetest.registered_nodes[source] then return end
    local def = minetest.registered_nodes[source]

    local ndef = {
        description = CFG.description .. ' [' .. def.description .. ']',
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
    register_fluid_def(node_name)

    local idef = {
        description = CFG.description .. ' (' .. def.description .. ')',
        -- inventory_image = overlay_image .. '^[multiply:' .. colorstr .. '^' .. base_image,
        inventory_image  = overlay_image .. get_overlay_texture(def) .. '^' .. base_image,
        on_place = place_node,
        groups = {not_in_creative_inventory = 1}
    }

    minetest.register_tool(item_name, idef)
    LC:register_tank(node_name, source, item_name)
end

-- add our own stuff as buckets
-- items from the same group replace each other
liquidtanks.register_bucket = function(itemname, source, amount, group)
    LC:register_bucket(itemname, source, amount, group)
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
