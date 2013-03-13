--[[
==README==

Put a rectangular clip in the first line.

Highlight that line and all the other lines you want to add the clip to.

Run, and the position-shifted clip will be added to those lines

]]--
script_name="Clip shifter"
script_description="Reads a rectangular clip from the first line and places it on the other highlighted ones"
script_version="0.1"

include("karaskel.lua")

--Returns the position of a line
local function get_pos(line)
	local _,_,posx,posy=line.text:find("\\pos%(([%d%.%-]*),([%d%.%-]*)%)")
	if posx==nil then
		_,_,posx,posy=line.text:find("\\move%(([%d%.%-]*),([%d%.%-]*),")
		if posx==nil then
			posx=line.x
			posy=line.y
		end
	end
	return posx,posy
end

function clip_shift(sub,sel)
	
	--Get meta and style info
	local meta,styles = karaskel.collect_head(sub, false)
	
	--Read in first line
	first_line=sub[sel[1]]
	
	--Read in the clip
	--No need to double check, since the validate function ensures this
	local _,_,sclip1,sclip2,sclip3,sclip4=
		first_line.text:find("\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)")
	sclip1=tonumber(sclip1)
	sclip2=tonumber(sclip2)
	sclip3=tonumber(sclip3)
	sclip4=tonumber(sclip4)
	
	karaskel.preproc_line(sub,meta,styles,first_line)
	
	--Get position
	sx,sy=get_pos(first_line)
	
	for i=2,#sel,1 do
		--Read the line
		this_line=sub[sel[i]]
		karaskel.preproc_line(sub,meta,styles,this_line)
		
		--Get its position
		tx,ty=get_pos(this_line)
		
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

aegisub.register_macro(script_name,script_description,clip_shift)