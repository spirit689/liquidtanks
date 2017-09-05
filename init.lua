liquidtanks = {}
liquidtanks.liquids = {}

-- place empty tank at pos -----------------------------------------------------
liquidtanks.set_empty_node = function(pos, group)
    for node_name, def in pairs(liquidtanks.liquids) do
        if def.group == group and def.amount == 0 then
            minetest.set_node(pos, {name = node_name})
        end
    end
end

-- place tank with liquid at pos -----------------------------------------------
liquidtanks.set_node = function (pos, node_name, source, amount)
    if not liquidtanks.liquids[node_name] then
        return
    end
    local n = liquidtanks.liquids[node_name].amount
    local param = 0
    if not amount then
        n = 0
    end
    if amount < n then
        n = amount
    end
    param = math.ceil(63 / liquidtanks.liquids[node_name].amount * n)
    minetest.set_node(pos, {name = node_name, param2 = param})
    local metadata = minetest.get_meta(pos)
    metadata:set_string('liquid_amount', n)
end

-- update liquid amount --------------------------------------------------------
liquidtanks.add_liquid = function(pos, source, amount)
    local node = minetest.get_node_or_nil(pos)
    if not node then return end
    if not liquidtanks.liquids[node.name] then
        return
    end
    -- get amount
    local n = tonumber(minetest.get_meta(pos):get_string('liquid_amount'))
    local group = liquidtanks.liquids[node.name].group
    if not n then
        n = 0
    end
    n = n + amount
    -- we can't pour more than there is
    if n < 0 or n > liquidtanks.liquids[node.name].amount then
        return
    end
    if n > 0 then
        -- update the node, if the liquid match
        if source == liquidtanks.liquids[node.name].source then
            liquidtanks.set_node(pos, node.name, source, n)
        end
    else
        liquidtanks.set_empty_node(pos, group)
    end
end

-- on dig node -----------------------------------------------------------------
-- this is from builtin, but save meta to drop itemstack
liquidtanks.tank_dig = function (pos, node, digger)
	local def = minetest.registered_nodes[node.name]

	if minetest.is_protected(pos, digger:get_player_name()) and
        not minetest.check_player_privs(digger, "protection_bypass") then
		    minetest.log("action", digger:get_player_name()
				.. " tried to dig " .. node.name .. " at protected position "
				.. minetest.pos_to_string(pos))
		minetest.record_protection_violation(pos, digger:get_player_name())
		return
	end

	minetest.log('action', digger:get_player_name() .. " digs "
		.. node.name .. " at " .. minetest.pos_to_string(pos))

	local wielded = digger:get_wielded_item()
	local drops = minetest.get_node_drops(node.name, wielded:get_name())
	local wdef = wielded:get_definition()
	local tp = wielded:get_tool_capabilities()
	local dp = minetest.get_dig_params(def and def.groups, tp)
	if wdef and wdef.after_use then
		wielded = wdef.after_use(wielded, digger, node, dp) or wielded
	else
		-- Wear out tool
		if not minetest.settings:get_bool("creative_mode") then
			wielded:add_wear(dp.wear)
			if wielded:get_count() == 0 and wdef.sound and wdef.sound.breaks then
				minetest.sound_play(wdef.sound.breaks, {pos = pos, gain = 0.5})
			end
		end
	end
	digger:set_wielded_item(wielded)

    -- minetest.handle_node_drops(pos, drops, digger)
    ------------------------------------------------
    if digger:get_inventory() then
		local _, dropped_item, dropped_stack
        -- get amount and save meta
        local amount = tonumber(minetest.get_meta(pos):get_string('liquid_amount'))
        if not amount then
            amount = 0
        end
		for _, dropped_item in ipairs(drops) do
            dropped_stack = ItemStack(dropped_item)
            dropped_stack:get_meta():set_string('liquid_amount', amount)
            dropped_stack:set_wear(65535 - math.ceil(65530 / liquidtanks.liquids[node.name].amount * amount))
			local left = digger:get_inventory():add_item("main", dropped_stack)
			if not left:is_empty() then
				local p = {
					x = pos.x + math.random()/2-0.25,
					y = pos.y + math.random()/2-0.25,
					z = pos.z + math.random()/2-0.25,
				}
				minetest.add_item(p, left)
			end
		end
	end
    -------------------------------------------------

	local oldmetadata = nil
	if def and def.after_dig_node then
		oldmetadata = minetest.get_meta(pos):to_table()
	end

	-- Remove node and update
	minetest.remove_node(pos)

	-- Run callback
	if def and def.after_dig_node then
		-- Copy pos and node because callback can modify them
		local pos_copy = {x=pos.x, y=pos.y, z=pos.z}
		local node_copy = {name=node.name, param1=node.param1, param2=node.param2}
		def.after_dig_node(pos_copy, node_copy, oldmetadata, digger)
	end
	-- Run script hook
	local _, callback
	for _, callback in ipairs(minetest.registered_on_dignodes) do
		local origin = minetest.callback_origins[callback]
		if origin then
			minetest.set_last_run_mod(origin.mod)
		end
		-- Copy pos and node because callback can modify them
		local pos_copy = {x=pos.x, y=pos.y, z=pos.z}
		local node_copy = {name=node.name, param1=node.param1, param2=node.param2}
		callback(pos_copy, node_copy, digger)
	end
end

-- on place item ---------------------------------------------------------------
liquidtanks.tank_place = function (itemstack, placer, pointed_thing)
    if pointed_thing.type ~= "node" then
        return
    end
    local pos = pointed_thing.under
    local node = minetest.get_node_or_nil(pos)
    local def = node and minetest.registered_nodes[node.name]
    if not def or not def.buildable_to then
        pos = pointed_thing.above
        node = minetest.get_node_or_nil(pos)
        def = node and minetest.registered_nodes[node.name]
        if not def or not def.buildable_to then
            return itemstack
        end
    end

    -- find and place node
    local amount = tonumber(itemstack:get_meta():get_string('liquid_amount'))
    if not amount then
        amount = 0
    end
    for node_name, def in pairs(liquidtanks.liquids) do
        if itemstack:get_name() == def.item_name then
            if def.amount > 0 then
                liquidtanks.set_node(pos, node_name, def.source, amount)
            else
                liquidtanks.set_empty_node(pos, def.group)
            end
            break
        end
    end
    return ItemStack('')
end

-- on click with a bucket ------------------------------------------------------
liquidtanks.tank_rightclick = function (pos, node, clicker, itemstack, pointed_thing)
    local ldef = liquidtanks.liquids[node.name]
    local wielded = itemstack
    local node_name
    local n = tonumber(minetest.get_meta(pos):get_string('liquid_amount'))
    if not n then
        n = 0
    end

    for source, def in pairs(bucket.liquids) do
        if itemstack:get_name() == def.itemname then
            if ldef.amount == 0 then
                for node_name, def in pairs(liquidtanks.liquids) do
                    if def.group == ldef.group and def.source == source then
                        liquidtanks.set_node(pos, node_name, source, 1000)
                        wielded = ItemStack('bucket:bucket_empty')
                        break
                    end
                end
            elseif ldef.amount - n >= 1000 and ldef.source == source then
                liquidtanks.add_liquid(pos, source, 1000)
                wielded = ItemStack('bucket:bucket_empty')
            end
        end
    end

    if itemstack:get_name() == 'bucket:bucket_empty' then
        if n >= 1000 then
            liquidtanks.add_liquid(pos, ldef.source, -1000)
            wielded = ItemStack(bucket.liquids[ldef.source].itemname)
        end
    end
    return wielded
end

--[[
    Register a new tank
    def.source = name of the source node
    def.item_name = name of the inventory item
    def.description = description of the inventory item
    def.node_name = name of the node
    def.tiles = texture of the tank node
    def.liquid_texture = texture of the liquid
    def.inventory_image = texture of the tank item, this is item frame and so on
    def.inventory_image_base = base texture of the tank item, leave it white, this will be painted in def.color
    def.color = texture color of the tank item
    def.amount = maximum amount of liquid in the tank, it would be better if it is the same for the group
    def.group = nodes in one group will replace each other if necessary,
    def.light_source = if specified, the tank will emit light
]]
liquidtanks.register = function (def)
    liquidtanks.liquids[def.node_name] = {
        amount = def.amount,
        group = def.group,
        source = def.source,
        item_name = def.item_name
    }

    local ndef = {
        description = def.description,
        tiles = def.tiles,
        special_tiles = { def.liquid_texture },
        drawtype = "glasslike_framed",
        paramtype = "light",
        paramtype2 = "glasslikeliquidlevel",
        sunlight_propagates = true,
        drop = def.item_name,
        groups = {cracky = 3, oddly_breakable_by_hand = 3, not_in_creative_inventory = 1},
        sounds = default.node_sound_glass_defaults(),
        on_rightclick = liquidtanks.tank_rightclick,
        on_dig = liquidtanks.tank_dig
    }
    if def.light_source then
        ndef.light_source = def.light_source
    end
    minetest.register_node(def.node_name, ndef)

    local idef = {
        description = def.description,
        inventory_image = def.inventory_image_base..'^[multiply:'..def.color..'^'..def.inventory_image,
        on_place = liquidtanks.tank_place,
        groups = {not_in_creative_inventory = 1}
    }
    minetest.register_tool(def.item_name, idef)
end

----------------------------------------------

liquidtanks.register({
    source = 'default:water_source',
    amount = 8000,
    description = 'Liquid Tank (Water)',
    group = 'liquid_tank',
    liquid_texture = 'default_water.png',
    node_name = 'liquidtanks:tank_water',
    tiles = { 'liquidtanks_tank.png' },
    item_name = 'liquidtanks:tank_water_inv',
    inventory_image = 'liquidtanks_tank_inv_base.png',
    inventory_image_base = 'liquidtanks_tank_inv_overlay.png',
    color = '#0445F8'
})

liquidtanks.register({
    source = 'default:river_water_source',
    amount = 8000,
    description = 'Liquid Tank (River Water)',
    group = 'liquid_tank',
    liquid_texture = 'default_river_water.png',
    node_name = 'liquidtanks:tank_river_water',
    tiles = { 'liquidtanks_tank.png' },
    item_name = 'liquidtanks:tank_river_water_inv',
    inventory_image = 'liquidtanks_tank_inv_base.png',
    inventory_image_base = 'liquidtanks_tank_inv_overlay.png',
    color = '#3b81ff'
})

liquidtanks.register({
    source = 'default:lava_source',
    amount = 8000,
    description = 'Liquid Tank (Lava)',
    group = 'liquid_tank',
    liquid_texture = 'default_lava.png',
    node_name = 'liquidtanks:tank_lava',
    tiles = { 'liquidtanks_tank.png' },
    item_name = 'liquidtanks:tank_lava_inv',
    inventory_image = 'liquidtanks_tank_inv_base.png',
    inventory_image_base = 'liquidtanks_tank_inv_overlay.png',
    color = '#f53400',
    light_source = 14
})

minetest.register_node('liquidtanks:tank_empty', {
    description = 'Liquid Tank (Empty)',
    tiles = { 'liquidtanks_tank.png' },
    drawtype = "glasslike_framed",
    paramtype = "light",
    sunlight_propagates = true,
    drop = 'liquidtanks:tank_empty_inv',
    groups = {cracky = 3, oddly_breakable_by_hand = 3, not_in_creative_inventory = 1},
    sounds = default.node_sound_glass_defaults(),
    on_rightclick = liquidtanks.tank_rightclick
})

minetest.register_tool('liquidtanks:tank_empty_inv', {
    description = 'Liquid Tank (Empty)',
    inventory_image = 'liquidtanks_tank_inv_base.png',
    on_place = liquidtanks.tank_place
})

liquidtanks.liquids['liquidtanks:tank_empty'] = {
    amount = 0,
    group = 'liquid_tank',
    item_name = 'liquidtanks:tank_empty_inv'
}

----------------------------------------------

minetest.register_craft({
	output = "liquidtanks:tank_empty_inv",
	recipe = {
		{"default:steel_ingot", "default:glass", "default:steel_ingot"},
		{"default:glass", "default:glass", "default:glass"},
		{"default:steel_ingot", "default:glass", "default:steel_ingot"},
	},
})
