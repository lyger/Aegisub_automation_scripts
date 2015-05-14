--[[
==README==

Blur clip

There's really not much to explain here. \clip statements produce a sharp edge. This script
draws new \clip statements with decreasing alphas in order to imitate the effect of a blur.

The appearance won't always be perfect because of the limitations of precision with vector
clip coordinates. The "precision" parameter ameliorates this somewhat, but the odd jagged
line here and there is inevitable.

A note on the "precision" parameter: it scales exponentionally. If you want a 5-pixel blur,
then a precision of 1 produces 6 lines (5 for the blur, 1 for the center). Precision 2 will
generate 11 lines (10 for the blur, 1 for the center) and precision 3 will generate 21 lines
(20 for the blur, 1 for the center). As you've probably figured out, a precision of 4 will
create a whopping 41 lines. Use with caution.


]]--
script_name = "Blur clip"
script_description = "Blurs a vector clip."
script_version = "1.2.0"
script_author = "lyger"
script_namespace = "lyger.ClipBlur"

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

--Distance between two points
local function distance(x1,y1,x2,y2)
	return math.sqrt((x2-x1)^2+(y2-y1)^2)
end

--Sign of a value
local function sign(n)
	return n/math.abs(n)
end

--Haha I didn't know these functions existed. May as well just alias them
local todegree=math.deg
local torad=math.rad

--Parses vector shape and makes it into a table
function make_vector_table(vstring)
	local vtable={}
	local vexp=vstring:match("^([1-4]),")
	vexp=tonumber(vexp) or 1
	for vtype,vcoords in vstring:gmatch("([mlb])([%d%s%-]+)") do
		for vx,vy in vcoords:gmatch("([%d%-]+)%s+([%d%-]+)") do
			table.insert(vtable,{["class"]=vtype,["x"]=tonumber(vx),["y"]=tonumber(vy)})
		end
	end
	return vtable,vexp
end

--Reverses a vector table object
function reverse_vector_table(vtable)
	local nvtable={}
	if #vtable<1 then return nvtable end
	--Make sure vtable does not end in an m. I don't know why this would happen but still
	maxi=#vtable
	while vtable[maxi].class=="m" do
		maxi=maxi-1
	end

	--All vector shapes start with m
	nstart = util.copy(vtable[maxi])
	tclass=nstart.class
	nstart.class="m"
	table.insert(nvtable,nstart)

	--Reinsert coords in backwards order, but shift the class over by 1
	--because that's how vector shapes behave in aegi
	for i=maxi-1,1,-1 do
		tcoord = util.copy(vtable[i])
		_temp=tcoord.class
		tcoord.class=tclass
		tclass=_temp
		table.insert(nvtable,tcoord)
	end

	return nvtable
end

--Turns vector table into string
function vtable_to_string(vt)
	cclass=nil
	result=""

	for i=1,#vt,1 do
		if vt[i].class~=cclass then
			result=result..string.format("%s %d %d ",vt[i].class,vt[i].x,vt[i].y)
			cclass=vt[i].class
		else
			result=result..string.format("%d %d ",vt[i].x,vt[i].y)
		end
	end

	return result
end

--Rounds to the given number of decimal places
function round(n,dec)
	dec=dec or 0
	return math.floor(n*10^dec+0.5)/(10^dec)
end

--Grows vt outward by the radius r scaled by sc
function grow(vt,r,sc)
	ch=get_chirality(vt)
	local wvt=wrap(vt)
	local nvt={}
	sc=sc or 1

	--Grow
	for i=2,#wvt-1,1 do
		cpt=wvt[i]
		ppt=wvt[i].prev
		npt=wvt[i].next
		while distance(cpt.x,cpt.y,ppt.x,ppt.y)==0 do
			ppt=ppt.prev
		end
		while distance(cpt.x,cpt.y,npt.x,npt.y)==0 do
			npt=npt.prev
		end
		rot1=todegree(math.atan2(cpt.y-ppt.y,cpt.x-ppt.x))
		rot2=todegree(math.atan2(npt.y-cpt.y,npt.x-cpt.x))
		drot=(rot2-rot1)%360

		--Angle to expand at
		nrot=(0.5*drot+90)%180
		if ch<0 then nrot=nrot+180 end

		--Adjusted radius
		__ar=math.cos(torad(ch*90-nrot)) --<3
		ar=(__ar<0.00001 and r) or r/math.abs(__ar)

		newx=cpt.x*sc
		newy=cpt.y*sc

		if r~=0 then
			newx=newx+sc*round(ar*math.cos(torad(nrot+rot1)))
			newy=newy+sc*round(ar*math.sin(torad(nrot+rot1)))
		end

		table.insert(nvt,{["class"]=cpt.class,
			["x"]=newx,
			["y"]=newy})
	end

	--Check for "crossovers"
	--New data type to store points with same coordinates
	local mvt={}
	local wnvt=wrap(nvt)
	for i,p in ipairs(wnvt) do
		table.insert(mvt,{["class"]={p.class},["x"]=p.x,["y"]=p.y})
	end

	--Number of merges so far
	merges=0

	for i=2,#wnvt,1 do
		mi=i-merges
		dx=wvt[i].x-wvt[i-1].x
		dy=wvt[i].y-wvt[i-1].y
		ndx=wnvt[i].x-wnvt[i-1].x
		ndy=wnvt[i].y-wnvt[i-1].y

		if (dy*ndy<0 or dx*ndx<0) then
			--Multiplicities
			c1=#mvt[mi-1].class
			c2=#mvt[mi].class

			--Weighted average
			mvt[mi-1].x=(c1*mvt[mi-1].x+c2*mvt[mi].x)/(c1+c2)
			mvt[mi-1].y=(c1*mvt[mi-1].y+c2*mvt[mi].y)/(c1+c2)

			--Merge classes
			mvt[mi-1].class={unpack(mvt[mi-1].class),unpack(mvt[mi].class)}

			--Delete point
			table.remove(mvt,mi)
			merges=merges+1
		end
	end

	--Rebuild wrapped new vector table
	wnvt={}
	for i,p in ipairs(mvt) do
		for k,pclass in ipairs(p.class) do
			table.insert(wnvt,{["class"]=pclass,["x"]=p.x,["y"]=p.y})
		end
	end

	return unwrap(wnvt)
end

function merge_identical(vt)
	local mvt = util.copy(vt)
	i=2
	lx=mvt[1].x
	ly=mvt[1].y
	while i<#mvt do
		if mvt[i].x==lx and mvt[i].y==ly then
			table.remove(mvt,i)
		else
			lx=mvt[i].x
			ly=mvt[i].y
			i=i+1
		end
	end
	return mvt
end

--Returns chirality of vector shape. +1 if counterclockwise, -1 if clockwise
function get_chirality(vt)
	local wvt=wrap(vt)
	wvt=merge_identical(wvt)
	trot=0
	for i=2,#wvt-1,1 do
		rot1=math.atan2(wvt[i].y-wvt[i-1].y,wvt[i].x-wvt[i-1].x)
		rot2=math.atan2(wvt[i+1].y-wvt[i].y,wvt[i+1].x-wvt[i].x)
		drot=todegree(rot2-rot1)%360
		if drot>180 then drot=360-drot elseif drot==180 then drot=0 else drot=-1*drot end
		trot=trot+drot
	end
	return sign(trot)
end

--Duplicates first and last coordinates at the end and beginning of shape,
--to allow for wraparound calculations
function wrap(vt)
	local wvt={}
	table.insert(wvt,util.copy(vt[#vt]))
	for i=1,#vt,1 do
		table.insert(wvt,util.copy(vt[i]))
	end
	table.insert(wvt,util.copy(vt[1]))

	--Add linked list capability. Because. Hacky fix gogogogo
	for i=2,#wvt-1 do
		wvt[i].prev=wvt[i-1]
		wvt[i].next=wvt[i+1]
	end
	--And link the start and end
	wvt[2].prev=wvt[#wvt-1]
	wvt[#wvt-1].next=wvt[2]

	return wvt
end

--Cuts off the first and last coordinates, to undo the effects of "wrap"
function unwrap(wvt)
	local vt={}
	for i=2,#wvt-1,1 do
		table.insert(vt,util.copy(wvt[i]))
	end
	return vt
end

--Main execution function
function blur_clip(sub,sel)
	--GUI config
	config=
	{
		{
			class="label",
			label="Blur size:",
			x=0,y=0,width=1,height=1
		},
		{
			class="floatedit",
			name="bsize",
			min=0,step=0.5,value=1,
			x=1,y=0,width=1,height=1
		},
		{
			class="label",
			label="Blur position:",
			x=0,y=1,width=1,height=1
		},
		{
			class="dropdown",
			name="bpos",
			items={"outside","middle","inside"},
			value="outside",
			x=1,y=1,width=1,height=1
		},
		{
			class="label",
			label="Precision:",
			x=0,y=2,width=1,height=1
		},
		{
			class="intedit",
			name="bprec",
			min=1,max=4,value=2,
			x=1,y=2,width=1,height=1
		}
	}

	--Show dialog
	pressed,results=aegisub.dialog.display(config,{"Go","Cancel"})
	if pressed=="Cancel" then aegisub.cancel() end

	--Size of the blur
	bsize=results["bsize"]

	--Scale exponent for all the numbers
	sexp=results["bprec"]

	--How far to offset the blur by
	boffset=0
	if results["bpos"]=="inside" then boffset=bsize
	elseif results["bpos"]=="middle" then boffset=bsize/2 end

	--How far to offset the next line read
	lines_added=0

	libLyger:set_sub(sub, sel)
	for si,li in ipairs(sel) do
		--Progress report
		aegisub.progress.task("Processing line "..si.."/"..#sel)
		aegisub.progress.set(100*si/#sel)

		--Read in the line
		line = libLyger.lines[li]

		--Comment it out
		line.comment=true
		sub[li+lines_added]=line
		line.comment=false

		--Find the clipping shape
		ctype,tvector=line.text:match("\\(i?clip)%(([^%(%)]+)%)")

		--Cancel if it doesn't exist
		if tvector==nil then
			aegisub.log("Make sure all lines have a clip statement.")
			aegisub.cancel()
		end

		--Get position and add
		px,py = libLyger:get_pos(line)
		if line.text:match("\\pos")==nil and line.text:match("\\move")==nil then
			line.text=string.format("{\\pos(%d,%d)}",px,py)..line.text
		end

		--Round
		local function rnd(num)
			num=tonumber(num) or 0
			if num<0 then
				num=num-0.5
				return math.ceil(num)
			end
			num=num+0.5
			return math.floor(num)
		end
		--If it's a rectangular clip, convert to vector clip
		if tvector:match("([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),([%d%-%.]+)")~=nil then
			_x1,_y1,_x2,_y2=tvector:match("([%d%-%.]+),([%d%-%.]+),([%d%-%.]+),([%d%-%.]+)")
			tvector=string.format("m %d %d l %d %d %d %d %d %d",
				rnd(_x1),rnd(_y1),rnd(_x2),rnd(_y1),rnd(_x2),rnd(_y2),rnd(_x1),rnd(_y2))
		end

		--The original table and original scale exponent
		otable,oexp=make_vector_table(tvector)

		--Effective scale and scale exponent
		eexp=sexp-oexp+1
		escale=2^(eexp-1)
		--aegisub.log("Escale: %.2f",escale)

		--The innermost line
		iline = util.copy(line)
		itable={}
		if ctype=="iclip" then
			itable=grow(otable,bsize*2^(oexp-1)-boffset,escale)
		else
			itable=grow(otable,-1*boffset,escale)
		end
		iline.text=iline.text:gsub("\\i?clip%([^%(%)]+%)","\\"..ctype.."("..sexp..","..vtable_to_string(itable)..")")

		--Add it to the subs
		sub.insert(li+lines_added+1,iline)
		lines_added=lines_added+1

		--Set default alpha values
		dalpha={}
		dalpha[1]=alpha_from_style(line.styleref.color1)
		dalpha[2]=alpha_from_style(line.styleref.color2)
		dalpha[3]=alpha_from_style(line.styleref.color3)
		dalpha[4]=alpha_from_style(line.styleref.color4)

		--First tag block
		ftag=line.text:match("^{[^{}]*}")
		if ftag==nil then
			ftag="{}"
			line.text="{}"..line.text
		end

		--List of alphas not yet accounted for in the first tag
		unacc={}

		if ftag:match("\\alpha")==nil then
			if ftag:match("\\1a")==nil then table.insert(unacc,1) end
			if ftag:match("\\2a")==nil then table.insert(unacc,2) end
			if ftag:match("\\3a")==nil then table.insert(unacc,3) end
			if ftag:match("\\4a")==nil then table.insert(unacc,4) end
		end

		--Add tags if any are unaccounted for
		if #unacc>0 then
			--If all the unaccounted-for alphas are equal, only add an "alpha" tag
			_tempa=dalpha[unacc[1]]
			_equal=true
			for _k,_a in ipairs(unacc) do
				if dalpha[_a]~=_tempa then _equal=false end
			end

			if _equal then line.text=line.text:gsub("^{","{\\alpha"..dalpha[unacc[1]])
			else
				for _k,ui in ipairs(unacc) do
					line.text=line.text:gsub("^{","{\\"..ui.."a"..dalpha[ui])
				end
			end
		end

		prevclip=itable

		for j=1,math.ceil(bsize*escale*2^(oexp-1)),1 do

			--Interpolation factor
			factor=j/(bsize*escale+1)

			--Flip if it's an iclip
			if ctype=="iclip" then factor=1-factor end

			--Copy the line
			tline = util.copy(line)

			--Sub in the interpolated alphas
			tline.text=tline.text:gsub("\\alpha([^\\{}]+)",
				function(a) return "\\alpha"..interpolate_alpha(factor,a,"&HFF&") end)
			tline.text=tline.text:gsub("\\([1-4]a)([^\\{}]+)",
				function(a,b) return "\\"..a..interpolate_alpha(factor,b,"&HFF&") end)

			--Write the correct clip
			thisclip=grow(otable,j/escale-boffset,escale)
			clipstring=vtable_to_string(thisclip)..vtable_to_string(reverse_vector_table(prevclip))
			prevclip=thisclip

			tline.text=tline.text:gsub("\\i?clip%([^%(%)]+%)","\\clip("..sexp..","..clipstring..")")

			--Insert the line
			sub.insert(li+lines_added+1,tline)
			lines_added=lines_added+1
		end
	end
	aegisub.set_undo_point(script_name)
end

rec:registerMacro(blur_clip)