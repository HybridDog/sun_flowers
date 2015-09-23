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

local c_air = minetest.get_content_id("air")
local c_ignore = minetest.get_content_id("ignore")
local c_stengl = minetest.get_content_id("default:fence_wood")
local c_stempel_tag = minetest.get_content_id("mesecons_solarpanel:solar_panel_on")
local c_stempel_nacht = minetest.get_content_id("mesecons_solarpanel:solar_panel_off")
local c_blutenblatt = minetest.get_content_id("doors:trapdoor")
local c_blutenblatt_geschlossen = minetest.get_content_id("doors:trapdoor_open")

local param2ps_list = {[0]={-1,0}, {0,-1}, {1,0}, {0,1}}
local function make_flower(h, pr, area, data, param2s, shine, pz,py,px)
	for _,crd in pairs(stem(h, pr)) do
		local z,y,x = unpack(crd)
		local vi = area:index(px+x, py+y, pz+z)
		if data[vi] == c_air
		or data[vi] == c_ignore then
			data[vi] = c_stengl
		end
	end
	local blutenblatt, stempel
	if shine then
		blutenblatt = c_blutenblatt
		stempel = c_stempel_tag
	else
		blutenblatt = c_blutenblatt_geschlossen
		stempel = c_stempel_nacht
	end
	local y = py+h
	for par,crd in pairs(param2ps_list) do
		local z = pz+crd[1]
		local x = px+crd[2]
		local vi = area:index(x, y, z)
		if data[vi] == c_air
		or data[vi] == c_ignore then
			data[vi] = blutenblatt
			param2s[vi] = par
			panel_meta({x=x,y=y,z=z})
		end
	end
	local vi = area:index(px, y, pz)
	if data[vi] == c_air
	or data[vi] == c_ignore then
		data[vi] = stempel
		param2s[vi] = 1
	end
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

	make_flower(h, pr, area, nodes, param2s, tag, pos.z,pos.y,pos.x)

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


--mapgen
local function soil_node(id)
	local name = minetest.get_name_from_content_id(id)
	local def = minetest.registered_nodes[name]
	if not def
	or not def.groups
	or def.groups.soil ~= 1
	or not string.find(name, "grass") then
		return false
	end
	return true
end

local soils = {}
local function is_soil(id)
	local soil = soils[id]
	if soil ~= nil then
		return soil
	end
	soil = soil_node(id)
	soils[id] = soil
	return soil
end

local perlinmap
minetest.register_on_generated(function(minp, maxp, seed)
	--avoid calculating perlin noises for unneeded places
	if maxp.y <= -6
	or minp.y >= 150 then
		return
	end

	local t1 = os.clock()

	local x0,z0,x1,z1 = minp.x,minp.z,maxp.x,maxp.z	-- Assume X and Z lengths are equal
	local divs = (x1-x0)

	if not perlinmap then
		perlinmap = minetest.get_perlin_map({
			offset = 0,
			scale = 1,
			seed = 4213,
			octaves = 3,
			persist = 0.6,
			spread = {x=100, y=100, z=100},
		}, {x=divs+1, y=divs+1, z=1})
	end

	local tag = math.abs(minetest.get_timeofday()-0.5) < 0.25
	local pr = PseudoRandom(seed+42)

	local vm, area, data, param2s, pmap

	local heightmap = minetest.get_mapgen_object("heightmap")
	local hmi = 1

	local flower_placed = false
	for j=0,divs do
		for i=0,divs do
			local x,z = x0+i,z0+j
			if (x+z)%2 == 0 -- chess pattern to not make them connect so much
			and pr:next(1,8) == 1 then
				local y = heightmap[hmi] -- ground y
				if y > 4
				and y >= minp.y
				and y <= maxp.y then
					if not pmap then
						pmap = perlinmap:get2dMap_flat({x=x0, y=z0})
					end
					local noise = pmap[hmi]
					if noise > 0.9
					and (noise-0.9)*10 > pr:next(0,1000)/1000 then
						if not vm then
							local emin, emax
							vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
							area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
							data = vm:get_data()
							param2s = vm:get_param2_data()
						end
						if is_soil(data[area:index(x,y,z)]) then
							flower_placed = true
							make_flower(pr:next(3,7), pr, area, data, param2s, tag, z,y+1,x)
						end
					end
				end
			end
			hmi = hmi+1
		end
	end

	if not flower_placed then
		return
	end

	local t2 = os.clock()
	vm:set_data(data)
	vm:set_param2_data(param2s)
	vm:set_lighting({day=0, night=0})
	vm:calc_lighting()
	vm:write_to_map()
	log("data set", 2, t2)

	t2 = os.clock()
	do_metas(tag)
	log("metas set", 2, t2)

	log("done", 1, t1)
end)





local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[sun_flowers] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
