--[[
==README==

Layer Increment

Basic utility that will make selected lines have increasing or decreasing layer numbers.

]]

script_name = "Layer increment"
script_description = "Makes increasing or decreasing layer numbers."
script_version = "1.1.0"
script_author = "lyger"
script_namespace = "lyger.LayerIncrement"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json"
}

local config = {
	{
		class="dropdown", name="updown",
		items={"Count up","Count down"},
		x=0,y=0,width=2,height=1,
		value="Count up"
	},
	{
		class="label",label="Interval",
		x=0,y=1,width=1,height=1
	},
	{
		class="intedit",name="int",
		x=1,y=1,width=1,height=1,
		min=1,value=1
	}
}

function layer_inc(sub,sel)
	local pressed, results = aegisub.dialog.display(config,{"Go","Cancel"})

	local min_layer = 0
	for _,li in ipairs(sel) do
		local line = sub[li]
		if line.layer>min_layer then
			min_layer = line.layer
		end
	end

	local start_layer = min_layer
	local factor=1
	local interval = results["int"]

	if results["updown"]=="Count down" then
		start_layer = min_layer + (#sel-1)*interval
		factor = -1
	end

	for j,li in ipairs(sel) do
		local line = sub[li]
		line.layer = start_layer + (j-1)*factor*interval
		sub[li] = line
	end

	return sel
end

rec:registerMacro(layer_inc)




