--[[
==README==

Move with Clip

Turns lines with \pos and a rectangular \clip into lines with \move and \t that moves
the clip correspondingly.

Quick-and-dirty script with no failsafes. Requires \pos tag and rectangular \clip tag
to be present in selected line(s) in order to work.

]]

script_name="Move with clip"
script_description="Moves both position and rectangular clip"
script_version="1.0"

config=
{
	{class="label",label="x change:",x=0,y=0,width=1,height=1},
	{class="floatedit",name="d_x",x=1,y=0,width=1,height=1,value=0},
	{class="label",label="y change:",x=0,y=1,width=1,height=1},
	{class="floatedit",name="d_y",x=1,y=1,width=1,height=1,value=0}
}

--Convert float to neatly formatted string
local function f2s(f) return string.format("%.3f",f):gsub("%.(%d-)0+$","%.%1"):gsub("%.$","") end

function move_clip(sub,sel)
	pressed,results=aegisub.dialog.display(config,{"Move","Cancel"})
	
	d_x=results["d_x"]
	d_y=results["d_y"]
	
	for _,li in ipairs(sel) do
		line=sub[li]
		
		if line.text:match("\\clip%([%d%-%.]+,[%d%-%.]+,[%d%-%.]+,[%d%-%.]+%)")~= nil
			and line.text:match("\\pos%([%d%-%.]+,[%d%-%.]+%)")~= nil then
			
			dur=line.end_time-line.start_time
			
			line.text=line.text:gsub("\\pos%(([%d%-%.]+),([%d%-%.]+)%)",
				function(x1,y1)
					x1=tonumber(x1)
					y1=tonumber(y1)
					return string.format("\\move(%s,%s,%s,%s)",
						f2s(x1),f2s(y1),f2s(x1+d_x),f2s(y1+d_y))
				end)
			
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




