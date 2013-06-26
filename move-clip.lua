--[[
==README==

Move with Clip

Turns lines with \pos and a rectangular \clip into lines with \move and \t that moves
the clip correspondingly.

Quick-and-dirty script with no failsafes. Requires \pos tag and rectangular \clip tag
to be present in selected line(s) in order to work.

]]

include("karaskel.lua")

script_name="Move with clip"
script_description="Moves both position and rectangular clip"
script_version="1.1"

config=
{
	{class="label",label="x change:",x=0,y=0,width=1,height=1},
	{class="floatedit",name="d_x",x=1,y=0,width=1,height=1,value=0},
	{class="label",label="y change:",x=0,y=1,width=1,height=1},
	{class="floatedit",name="d_y",x=1,y=1,width=1,height=1,value=0}
}

--Convert float to neatly formatted string
local function f2s(f) return string.format("%.3f",f):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end


--Returns the position of a line
local function get_pos(line)
	local _,_,posx,posy=line.text:find("\\pos%(([%d%.%-]*),([%d%.%-]*)%)")
	if posx==nil then
		_,_,posx,posy=line.text:find("\\move%(([%d%.%-]*),([%d%.%-]*),")
		if posx==nil then
			_,_,align_n=line.text:find("\\an([%d%.%-]*)")
			if align_n==nil then
				_,_,align_dumb=line.text:find("\\a([%d%.%-]*)")
				if align_dumb==nil then
					--If the line has no alignment tags
					posx=line.x
					posy=line.y
				else
					--If the line has the \a alignment tag
					vid_x,vid_y=aegisub.video_size()
					align_dumb=tonumber(align_dumb)
					if align_dumb>8 then
						posy=vid_y/2
					elseif align_dumb>4 then
						posy=line.eff_margin_t
					else
						posy=vid_y-line.eff_margin_b
					end
					_temp=align_dumb%4
					if _temp==1 then
						posx=line.eff_margin_l
					elseif _temp==2 then
						posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
					else
						posx=vid_x-line.eff_margin_r
					end
				end
			else
				--If the line has the \an alignment tag
				vid_x,vid_y=aegisub.video_size()
				align_n=tonumber(align_n)
				_temp=align_n%3
				if align_n>6 then
					posy=line.eff_margin_t
				elseif align_n>3 then
					posy=vid_y/2
				else
					posy=vid_y-line.eff_margin_b
				end
				if _temp==1 then
					posx=line.eff_margin_l
				elseif _temp==2 then
					posx=line.eff_margin_l+(vid_x-line.eff_margin_l-line.eff_margin_r)/2
				else
					posx=vid_x-line.eff_margin_r
				end
			end
		end
	end
	return posx,posy
end

function move_clip(sub,sel)
	pressed,results=aegisub.dialog.display(config,{"Move","Cancel"})
	
	d_x=results["d_x"]
	d_y=results["d_y"]
	
	meta,styles=karaskel.collect_head(sub,false)
	
	for _,li in ipairs(sel) do
		line=sub[li]
		
		if line.text:match("\\clip%([%d%-%.]+,[%d%-%.]+,[%d%-%.]+,[%d%-%.]+%)")~= nil then
			
			karaskel.preproc_line(sub,meta,styles,line)
			
			dur=line.end_time-line.start_time
			
			ox,oy=get_pos(line)
			
			line.text=line.text:gsub("\\pos%([%d%-%.]+,[%d%-%.]+%)","")
			line.text=line.text:gsub("\\move%([%d%-%.,]+%)","")
			line.text=line.text:gsub("{",
				function()
					x1=tonumber(ox)
					y1=tonumber(oy)
					return string.format("{\\move(%s,%s,%s,%s,%d,%d)",
						f2s(x1),f2s(y1),f2s(x1+d_x),f2s(y1+d_y),0,dur)
				end,1)
			
			line.text=line.text:gsub("\\clip%(([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),([%d%-%.]+)%)",
				function(x1,y1,x2,y2)
					x1=tonumber(x1)
					x2=tonumber(x2)
					y1=tonumber(y1)
					y2=tonumber(y2)
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




