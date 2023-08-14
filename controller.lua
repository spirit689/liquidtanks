
local CFG = liquidtanks.config
local Controller = {
    buckets = {},
    tanks = {}
}

Controller.get_node_name = function(self, source)
    local name = { 'tank' }

    if source then
        name[#name + 1] = table.concat(source:split(':'), "_")
    end

    return liquidtanks.modname .. ':' .. table.concat(name, '_')
end

Controller.get_item_name = function(self, source)
    local name = { 'inv' }

    if source then
        name[#name + 1] = table.concat(source:split(':'), "_")
    end

    return liquidtanks.modname .. ':' .. table.concat(name, '_')
end

Controller.register_tank = function(self, node_name, source, item_name)
    if self.tanks[node_name] then return end

    self.tanks[node_name] = {
        source = source,
        itemname = item_name
    }
end

Controller.register_bucket = function(self, itemname, source, amount, group)
    if self.buckets[itemname] then return end

    self.buckets[itemname] = {
        source = source,
        amount = amount or 1000,
        group = group
    }
end

Controller.get_bucket_item = function(self, source, group)
    local bucket

    for item_name, def in pairs(self.buckets) do
        if def.source == source and def.group == group then
            bucket = item_name
            break
        end
    end

    return bucket
end

Controller.update_node = function(self, pos, node_name, amount)
    local param = 0
    local metadata

    if amount > 0 then
        param = 192 + math.ceil(63 / CFG.amount * amount)
    end

    minetest.set_node(pos, {name = node_name, param2 = param})
    if amount > 0 then
        metadata = minetest.get_meta(pos)
        metadata:set_string(CFG.meta, amount)
    end
end

Controller.set = function(self, pos, source, amount)
    local node_name

    if amount > 0 then
        node_name = self:get_node_name(source)
    else
        node_name = self:get_node_name(nil)
    end

    self:update_node(pos, node_name, amount)
end

function Controller.take(self, pos, source, amount)
    local can_take, current_amount = self:can_take(pos, source, amount)

    if can_take then
        self:set(pos, source, current_amount)
        return amount
    end

    return 0
end

Controller.put = function(self, pos, source, amount)
    local can_put, current_amount = self:can_put(pos, source, amount)

    if can_put then
        self:set(pos, source, current_amount)
        return amount
    end

    return 0
end

Controller.can_take = function(self, pos, source, amount)
    local current_amount = self:amount(pos)
    local node = minetest.get_node(pos)
    local allow = false

    if self.tanks[node.name].source == source and amount <= current_amount then
        current_amount = current_amount - amount
        allow = true
    end

    return allow, current_amount
end

Controller.can_put = function(self, pos, source, amount)
    local current_amount = self:amount(pos)
    local node = minetest.get_node(pos)
    local allow = false

    if current_amount == 0 or self.tanks[node.name].source == source then
        if CFG.amount - current_amount >= amount then
            current_amount = current_amount + amount
            allow = true
        end
    end

    return allow, current_amount
end

Controller.amount = function(self, pos)
    local amount = tonumber(minetest.get_meta(pos):get_string(CFG.meta))
    if not amount then
        amount = 0
    end

    return amount
end

liquidtanks.controller = Controller
