--[[
==README==

Put a rectangular clip in the first line.

Highlight that line and all the other lines you want to add the clip to.

Run, and the position-shifted clip will be added to those lines

]]--

script_name = "Clip shifter"
script_description = "Reads a rectangular clip from the first line and places it on the other highlighted ones."
script_version = "0.2.0"
script_author = "lyger"
script_namespace = "lyger.ClipShifter"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{
		{"lyger.LibLyger", version = "2.0.0", url = "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"},
		"aegisub.util"
	}
}
local LibLyger, util = rec:requireModules()
local libLyger = LibLyger()

function clip_shift(sub,sel)
	libLyger:set_sub(sub, sel)

	--Read in first line
	local first_line = libLyger.lines[sel[1]]

	--Read in the clip
	--No need to double check, since the validate function ensures this
	local _,_,sclip1,sclip2,sclip3,sclip4=
		first_line.text:find("\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)")
	sclip1=tonumber(sclip1)
	sclip2=tonumber(sclip2)
	sclip3=tonumber(sclip3)
	sclip4=tonumber(sclip4)


	--Get position
	sx, sy = libLyger:get_pos(first_line)

	for i=2,#sel,1 do
		--Read the line
		this_line = libLyger.lines[sel[i]]

		--Get its position
		tx, ty = libLyger:get_pos(this_line)

		--Deltas
		d_x,d_y=tx-sx,ty-sy

		--Remove any existing rectangular clip
		this_line.text=this_line.text:gsub("\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)","")

		--Add clip
		this_line.text=string.format("{\\clip(%d,%d,%d,%d)}",
			sclip1+d_x,sclip2+d_y,sclip3+d_x,sclip4+d_y)..this_line.text
		this_line.text=this_line.text:gsub("}{","")
		sub[sel[i]]=this_line
	end

	aegisub.set_undo_point(script_name)
end

--Make sure the first line contains a rectangular clip
function validate_clip_shift(sub,sel)
	return #sel>1 and
		sub[sel[1]].text:find("\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)")~=nil
end

rec:registerMacro(clip_shift, validate_clip_shift)