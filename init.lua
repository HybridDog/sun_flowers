local load_time_start = os.clock()

local ast_hdif_max = 3

local function log(msg, lv, delay)
	print("[sun_flowers] "..msg)
end

local function stem(h, pr)
	local tab,n = {{0,h-1,0}},2
	local ast = 1
	for y = 0,h-2 do
		tab[n] = {0,y,0}
		n = n+1
		if ast ~= ast_hdif_max
		and pr:next(1,ast) == 1 then
			for i = -1,1,2 do
				for _,crd in pairs({
					{i,0},
					{0,i},
				}) do
					if pr:next(1,3) == 1 then
						tab[n] = {crd[1],y,crd[2]}
						n = n+1
					end
				end
				ast = ast_hdif_max
			end
		else
			ast = ast-1
		end
	end
	return tab--,n
end

local to_meta,num = {},1
local function do_metas(tag)
	local state = tag and 0 or 1
	for _,pos in pairs(to_meta) do
		minetest.get_meta(pos):set_int("state", state)
	end
	to_meta,num = {},1
end

local function panel_meta(pos)
	to_meta[num] = pos
	num = num+1
end

local c_stengl = minetest.get_content_id("default:fence_wood")
local c_stempel_tag = minetest.get_content_id("mesecons_solarpanel:solar_panel_on")
local c_stempel_nacht = minetest.get_content_id("mesecons_solarpanel:solar_panel_off")
local c_blutenblatt = minetest.get_content_id("doors:trapdoor")
local c_blutenblatt_geschlossen = minetest.get_content_id("doors:trapdoor_open")

local param2ps_list = {[0]={-1,0}, {0,-1}, {1,0}, {0,1}}
local function make_flower(h, pr, pos, area, data, param2s, shine)
	for _,crd in pairs(stem(h, pr)) do
		local z,y,x = unpack(crd)
		local vi = area:index(pos.x+x, pos.y+y, pos.z+z)
		data[vi] = c_stengl
	end
	local blutenblatt, stempel
	if shine then
		blutenblatt = c_blutenblatt
		stempel = c_stempel_tag
	else
		blutenblatt = c_blutenblatt_geschlossen
		stempel = c_stempel_nacht
	end
	local y = pos.y+h
	for par,crd in pairs(param2ps_list) do
		local z,x = unpack(crd)
		z = pos.z+z
		x = pos.x+x
		local vi = area:index(x, y, z)
		data[vi] = blutenblatt
		param2s[vi] = par
		panel_meta({x=x,y=y,z=z})
	end
	local vi = area:index(pos.x, y, pos.z)
	data[vi] = stempel
	param2s[vi] = 1
end

-- nicht zum generieren verwenden
local function spawn_flower(pos)
	local t1 = os.clock()

	local pr = PseudoRandom(pos.x+pos.y*3+pos.z*5+463)
	local h = pr:next(3,7)
	local tag = minetest.get_node_light(pos) >= 12

	local manip = minetest.get_voxel_manip()
	local emerged_pos1, emerged_pos2 = manip:read_from_map({x=pos.x-1, y=pos.y, z=pos.z-1},
		{x=pos.x+1, y=pos.y+h, z=pos.z+1})
	local area = VoxelArea:new({MinEdge=emerged_pos1, MaxEdge=emerged_pos2})
	local nodes = manip:get_data()
	local param2s = manip:get_param2_data()

	make_flower(h, pr, pos, area, nodes, param2s, tag)

	manip:set_data(nodes)
	manip:set_param2_data(param2s)
	manip:write_to_map()
	log("flower grew", 2, t1)
	t1 = os.clock()
	do_metas(tag)
	log("metas set", 2, t1)
	t1 = os.clock()
	manip:update_map()
	log("map updated", 2, t1)
end

minetest.register_node("sun_flowers:spawner", {
	node_placement_prediction = "",
	tiles = {"default_furnace_fire_fg.png"},
	inventory_image = "default_sapling.png^default_furnace_fire_fg.png",
	stack_max = 1024,
	groups = {snappy=2,dig_immediate=3},
	sounds = default.node_sound_leaves_defaults(),
	on_construct = function(pos)
		spawn_flower(pos)
	end,
})


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[sun_flowers] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
