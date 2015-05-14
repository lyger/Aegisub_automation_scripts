--[[
==README==

Move with Clip

Turns lines with \pos and a rectangular \clip into lines with \move and \t that moves
the clip correspondingly.

Quick-and-dirty script with no failsafes. Requires \pos tag and rectangular \clip tag
to be present in selected line(s) in order to work.

]]

script_name = "Move with clip"
script_description = "Moves both position and rectangular clip."
script_version = "1.2.0"
script_author = "lyger"
script_namespace = "lyger.MoveClip"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{
		{"lyger.LibLyger", version = "2.0.0", url = "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"}
	}
}
local LibLyger = rec:requireModules()
local libLyger = LibLyger()

local config = {
	{class="label",label="x change:",x=0,y=0,width=1,height=1},
	{class="floatedit",name="d_x",x=1,y=0,width=1,height=1,value=0},
	{class="label",label="y change:",x=0,y=1,width=1,height=1},
	{class="floatedit",name="d_y",x=1,y=1,width=1,height=1,value=0}
}

function move_clip(sub, sel)
	local pressed, results = aegisub.dialog.display(config,{"Move","Cancel"})
	local d_x, d_y = results["d_x"], results["d_y"]
	local f2s = libLyger.float2str
	libLyger:set_sub(sub, sel)

	for _,li in ipairs(sel) do
		local line = libLyger.lines[li]

		if line.text:match("\\clip%([%d%-%.]+,[%d%-%.]+,[%d%-%.]+,[%d%-%.]+%)") then
			local dur = line.end_time-line.start_time
			local ox, oy = libLyger:get_pos(line)

			line.text=line.text:gsub("\\pos%([%d%-%.]+,[%d%-%.]+%)","")
			line.text=line.text:gsub("\\move%([%d%-%.,]+%)","")
			line.text=line.text:gsub("{",
				function()
					local x1=tonumber(ox)
					local y1=tonumber(oy)
					return string.format("{\\move(%s,%s,%s,%s,%d,%d)",
						f2s(x1),f2s(y1),f2s(x1+d_x),f2s(y1+d_y),0,dur)
				end,1)

			line.text=line.text:gsub("\\clip%(([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),([%d%-%.]+)%)",
				function(x1,y1,x2,y2)
					local x1=tonumber(x1)
					local x2=tonumber(x2)
					local y1=tonumber(y1)
					local y2=tonumber(y2)
					return string.format("\\clip(%s,%s,%s,%s)\\t(%d,%d,\\clip(%s,%s,%s,%s))",
						f2s(x1),f2s(y1),f2s(x2),f2s(y2),0,dur,
						f2s(x1+d_x),f2s(y1+d_y),f2s(x2+d_x),f2s(y2+d_y))
				end)
		end

		sub[li]=line
	end

	return sel
end

aegisub.register_macro(script_name,script_description,move_clip)




