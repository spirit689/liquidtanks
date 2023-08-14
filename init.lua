-- Liquid Tanks

local mod_name = minetest.get_current_modname()
local mod_path = minetest.get_modpath(mod_name)
local S = minetest.get_translator(mod_name)

liquidtanks = {
    modname = mod_name,
    modpath = mod_path,
    config = {
        meta = 'liquidtanks:amount',
        amount = 16000,
        description = S('Liquid tank')
    }
}

dofile(mod_path .. "/controller.lua")
dofile(mod_path .. "/register.lua")
