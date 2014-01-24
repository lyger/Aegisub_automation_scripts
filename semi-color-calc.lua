--[[
Semitransparent Color Calculator

Does what it says. Use the eyedropper to select the background color
and the target color (that is, the color the original sign looks like.
For example, a semitransparent red sign on a white background will
look pink. That pink is your target color).

Then input your estimate of the opacity (which is in percent, and not
the 0-255 scale the \alpha tag uses, because percentages are easier to
get an intuition for. Also, 100% is solid alpha, not 0%).

Check which colors to apply to, and the script does the rest.
]]
require 'utils'

script_name="Semitransparent color calculator"
script_description="Input a target and background color to calculate the original color"
script_version="1.0"

conf=
{
	{x=0,y=0,width=4,height=1,class="label",label="Color(s):"},
	["c1"]={x=0,y=1,width=1,height=1,class="checkbox",name="c1",label="1",value=false},
	["c2"]={x=1,y=1,width=1,height=1,class="checkbox",name="c2",label="2",value=false},
	["c3"]={x=2,y=1,width=1,height=1,class="checkbox",name="c3",label="3",value=false},
	["c4"]={x=3,y=1,width=1,height=1,class="checkbox",name="c4",label="4",value=false},
	{x=0,y=2,width=2,height=1,class="label",label="Background:"},
	["bg"]={x=2,y=2,width=2,height=1,class="color",name="bg"},
	{x=0,y=3,width=2,height=1,class="label",label="Target:"},
	["tg"]={x=2,y=3,width=2,height=1,class="color",name="tg"},
	{x=0,y=4,width=2,height=1,class="label",label="Opacity (%):"},
	["al"]={x=2,y=4,width=2,height=1,class="floatedit",max=100,min=0,name="al",value=50,step=1}
}

function choke(v,min,max)
	if v<min then return min,true
	elseif v>max then return max,true end
	return v,false
end

function c_calc(sub,sel)
	local pressed,results=aegisub.dialog.display(conf,{"Go","Cancel"},{ok="Go",cancel="Cancel"})
	if pressed=="Cancel" then aegisub.cancel() end
	
	--Update conf for convenience
	for k,v in pairs(results) do
		conf[k].value=v
	end
	
	--Calculate the color
	local bg={}
	bg[1],bg[2],bg[3]=extract_color(results.bg)
	
	local tg={}
	tg[1],tg[2],tg[3]=extract_color(results.tg)
	
	f=results.al/100
	
	local c={}
	local warning=false
	for i=1,3 do
		c[i],_w=choke((tg[i]-bg[i])/f+bg[i],0,255)
		warning=warning or _w
	end
	
	local cstr=ass_color(c[1],c[2],c[3])
	
	local at={}
	local astr=ass_alpha(255*(1-f))
	
	for i=1,4 do
		if results["c"..i] then table.insert(at,i) end
	end
	
	if #at==0 then aegisub.cancel() end
	
	--Handle inserting into lines
	for si,li in ipairs(sel) do
		local line=sub[li]
		line.text=
			line.text:gsub("\\c","\\1c"):gsub("\\alpha[Hh&%x]+",""):gsub("\\[1-4]a[Hh&%x]+","")
		
		local tags=""
		
		if #at==4 then tags="\\alpha"..astr
		else
			for _,an in ipairs(at) do
				tags=tags..string.format("\\%da%s",an,astr)
			end
		end
		
		for _,an in ipairs(at) do
			line.text=line.text:gsub("\\"..an.."c[Hh&%x]+","")
			tags=tags.."\\"..an.."c"..cstr
		end
		
		if not line.text:match("^{") then line.text="{}"..line.text end
		
		line.text=line.text:gsub("^{","{"..tags):gsub("\\1c","\\c")
		
		sub[li]=line
	end
	
	if warning then
		aegisub.dialog.display(
			{{x=0,y=0,width=1,height=1,class="label",
			label="WARNING: Calculated color out of bounds.\n"..
			"Try increasing your opacity."}},{"OK"},{ok="OK"})
	end
	
	aegisub.set_undo_point(script_name)
end

aegisub.register_macro(script_name,script_description,c_calc)