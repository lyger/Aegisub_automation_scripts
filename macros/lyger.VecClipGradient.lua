--[[
==README==

Clip Gradient

Intersects a vector clip with the highlighted rectangular-clipped gradient.

Only allows non-compound (i.e. only one "m") vector shapes with no bezier curves.

It turns out it is possible to do this by using two \clip tags in the same line.
This script can be better if you are concerned about lag in a big gradient, but
yeah, in essence this automation is redundant.

]]--

script_name = "Vector-Clip Gradient"
script_description = "Intersects the rectangular clips on a gradient with a specified vector clip."
script_version = "1.0.0"
script_author = "lyger"
script_namespace = "lyger.VecClipGradient"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{"aegisub.util"}
}
local util = rec:requireModules()

--Distance between two points
local function distance(x1,y1,x2,y2)
	return math.sqrt((x2-x1)^2+(y2-y1)^2)
end

--Sign of a value
local function sign(n)
	return n/math.abs(n)
end

--Parses vector shape and makes it into a table
--This modified version adds pointer fields to make the table into a circular linked list
--It also ignores the exponential factor because who uses that anyway
function make_linked_vector_table(vstring)
	local vtable={}
	for vtype,vcoords in vstring:gmatch("([mlb])([%d%s%-]+)") do
		for vx,vy in vcoords:gmatch("([%d%-]+)%s+([%d%-]+)") do
			table.insert(vtable,{["class"]=vtype,["x"]=tonumber(vx),["y"]=tonumber(vy)})
		end
	end

	for i=1,#vtable-1 do
		vtable[i].next=vtable[i+1]
	end
	vtable[#vtable].next=vtable[1]

	return vtable
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
	nstart=util.copy(vtable[maxi])
	tclass=nstart.class
	nstart.class="m"
	table.insert(nvtable,nstart)

	--Reinsert coords in backwards order, but shift the class over by 1
	--because that's how vector shapes behave in aegi
	for i=maxi-1,1,-1 do
		tcoord=util.copy(vtable[i])
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

--Returns chirality of vector shape. +1 if counterclockwise, -1 if clockwise
function get_chirality(vt)
	local wvt=wrap(vt)
	trot=0
	for i=2,#wvt-1,1 do
		rot1=math.atan2(wvt[i].y-wvt[i-1].y,wvt[i].x-wvt[i-1].x)
		rot2=math.atan2(wvt[i+1].y-wvt[i].y,wvt[i+1].x-wvt[i].x)
		drot=math.deg(rot2-rot1)%360
		if drot>180 then drot=360-drot else drot=-1*drot end
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

--Returns v value of intersection at a given u
function uintercept(u1,v1,u2,v2,uint)
	local m=(v2-v1)/(u2-u1)
	local c=v1-u1*m
	return m*uint+c
end

--Returns u value of intersection at a given v
function vintercept(u1,v1,u2,v2,vint)
	local m=(u2-u1)/(v2-v1)
	local c=u1-v1*m
	return m*vint+c
end


--Intersects the vector in vt (a linked vector table) with the given rectangular coords
function intersect(vt,tp,bm,lt,rt,vert,ch)

	--This is the function that's going to consume my soul =__=

	--CHIRALITY +1
	--Increasing y in the shape means inside is to the direction of increasing x
	--Increasing x in the shape means inside is to the direction of decreasing y
	--CHIRALITY -1
	--Increasing y in the shape means inside is to the direction of decreasing x
	--Increasing x in the shape means inside is to the direction of increasing y

	--Refactor into u and v coordinates, where u is the direction of the gradient
	--and v is the orthagonal
	--chmod is the chirality modifier. I'll figure out how it's used later.
	--ub and vb are the u and v bounds. 1 is lower, 2 is higher
	u="x"
	v="y"
	ub1=lt
	ub2=rt
	vb1=tp
	vb2=bm
	chmod=-1
	if vert then
		u="y"
		v="x"
		chmod=1
		ub1=tp
		ub2=bm
		vb1=lt
		vb2=rt
	end

	--Find minimum v
	minv=10000
	iminv=0
	for i,vect in ipairs(vt) do
		if vect[v]<minv then minv=vect[v] iminv=i end
	end

	--Start with the point of minimum v
	start=vt[iminv]

	--String storing the new vector shape
	nshape=""

	--Prevent infinite loops
	imaginebreaker=0

	repeat
		--Aborts operation if bad starting point
		abort=false

		--Current point and counter
		curr=start
		count=0

		--Class of the next point
		nclass="m"

		--Is the current shape open?
		open=false
		--Which side did it first cross?
		firstcross=0
		--Which side is inside? (1 for increasing v coord, -1 for decreasing v coord)
		inside=1
		--The v coordinate where it last exited
		exitv=0

		repeat
			vnext=curr.next

			--ZONE A
			------------------------- ub1
			--ZONE B
			------------------------- ub2
			--ZONE C

			--Zones of current and next points
			czone=""
			nzone=""

			if curr[u]>=ub2 then czone="c"
			elseif curr[u]<=ub1 then czone="a"
			else czone="b" end

			if vnext[u]>=ub2 then nzone="c"
			elseif vnext[u]<=ub1 then nzone="a"
			else nzone="b" end

			--Check ALL the conditions
			--Staying between the lines
			if czone=="b" and nzone=="b" then
				if vert then
					nshape=nshape..string.format(nclass.." %d %d ",curr[v],curr[u])
				else
					nshape=nshape..string.format(nclass.." %d %d ",curr[u],curr[v])
				end

				--If a shape is not already open, abort
				if not open then abort=true end

			--Entering from above or below
			elseif (czone=="a" or czone=="c") and nzone=="b" then
				uint=ub1
				if czone=="c" then uint=ub2 end
				newv=round(uintercept(curr[u],curr[v],vnext[u],vnext[v],uint))
				if vert then
					nshape=nshape..string.format(nclass.." %d %d ",newv,uint)
				else
					nshape=nshape..string.format(nclass.." %d %d ",uint,newv)
				end

				if open then
					--Abort if on the wrong side of the last exit v coordinate
					if sign(newv-exitv)~=inside then abort=true end
				--Otherwise open a new shape
				else
					open=true
					nclass="l"
					firstcross=uint
					inside=sign(vnext[u]-curr[u])*ch*chmod
				end
			--Exiting from above or below
			elseif czone=="b" and (nzone=="a" or nzone=="c") then
				uint=ub1
				if nzone=="c" then uint=ub2 end
				newv=round(uintercept(curr[u],curr[v],vnext[u],vnext[v],uint))
				if vert then
					nshape=nshape..
						string.format(nclass.." %d %d l %d %d ",
							curr[v],curr[u],newv,uint)
				else
					nshape=nshape..
						string.format(nclass.." %d %d l %d %d ",
							curr[u],curr[v],uint,newv)
				end

				if open then
					--Recrossing the line initially crossed closes a shape
					if uint==firstcross then
						open=false
						nclass="m"
					--Otherwise, this is the last exit point
					else
						exitv=newv
					end

				--If a shape is not already open, abort
				else
					abort=true
				end
			--Crossing both lines from below or above
			elseif (czone=="c" and nzone=="a") or (czone=="a" and nzone=="c") then
				uint1=ub1
				uint2=ub2
				if czone=="c" then
					uint1=ub2
					uint2=ub1
				end

				newv1=round(uintercept(curr[u],curr[v],vnext[u],vnext[v],uint1))
				newv2=round(uintercept(curr[u],curr[v],vnext[u],vnext[v],uint2))
				if vert then
					nshape=nshape..
						string.format(nclass.." %d %d l %d %d ",
							newv1,uint1,newv2,uint2)
				else
					nshape=nshape..
						string.format(nclass.." %d %d l %d %d ",
							uint1,newv1,uint2,newv2)
				end

				--If it's already open, this should close the shape
				if open then
					--Abort if it crosses on the wrong side
					if sign(newv1-exitv)~=inside then abort=true end
					open=false
					nclass="m"

				--Otherwise open a new shape
				else
					open=true
					nclass="l"
					firstcross=uint1
					inside=sign(vnext[u]-curr[u])*ch*chmod
				end
			end

			curr=vnext
			count=count+1
		until count>=#vt or abort

		if abort then
			nshape=""
			start=start.next
		end

		imaginebreaker=imaginebreaker+1
	until not abort or imaginebreaker>#vt

	return nshape
end

--Main execution function
function clip_clip(sub,sel)

	--GUI config
	config=
	{
		{
			class="label",
			label="Gradient type:",
			x=0,y=0,width=1,height=1
		},
		{
			class="dropdown",
			name="gtype",
			items={"horizontal","vertical"},
			value="horizontal",
			x=1,y=0,width=1,height=1
		},
		{
			class="label",
			label="Paste your clipping shape here:",
			x=0,y=1,width=2,height=1
		},
		{
			class="textbox",
			name="shape",
			x=0,y=2,width=20,height=6
		}
	}

	--Show dialog
	pressed,results=aegisub.dialog.display(config,{"Go","Cancel"})
	if pressed=="Cancel" then aegisub.cancel() end

	--String of the vector shape
	sshape=results["shape"]

	--Boolean that is true if the gradient is vertical, false if it's horizontal
	vertical=true
	if results["gtype"]=="horizontal" then vertical=false end

	--Enforce limitations on vector shape
	if sshape:match("b") then
		aegisub.dialog.display(
			{{class="label",x=0,y=0,width=1,height=1,
				label="This version does not support shapes with beziers."}},
			{"OK"})
		aegisub.cancel()
	end

	_,mcount=sshape:gsub("m","m")
	if mcount>1 then
		aegisub.dialog.display(
			{{class="label",x=0,y=0,width=1,height=1,
				label="This version does not support compound shapes (more than one \"m\")."}},
			{"OK"})
		aegisub.cancel()
	end

	--Vector table object for this shape
	svt=make_linked_vector_table(sshape)

	if #svt<3 then
		aegisub.dialog.display(
			{class="label",x=0,y=0,width=1,height=1,
				label="You're gonna need a bigger vector shape."},
			{"OK"})
		aegisub.cancel()

	end

	--Chirality
	chir=get_chirality(svt)

	--Table of lines to delete
	to_delete={}

	--Process selected lines
	for si,li in ipairs(sel) do

		--Progress report
		aegisub.progress.task("Processing line "..si.."/"..#sel)
		aegisub.progress.set(100*si/#sel)

		--Read in the line
		line=sub[li]

		--Find the clipping shape
		ctype,tvector=line.text:match("\\(i?clip)%(([^%(%)]+)%)")

		--Error
		if ctype==nil then
			aegisub.dialog.display(
				{{class="label",x=0,y=0,width=1,height=1,
					label="Where is your \\clip, foo'?"}},
				{"OK"})
			aegisub.cancel()
		end

		--Get the coords
		_left,_bottom,_right,_top=tvector:match("([%d%-]+),([%d%-]+),([%d%-]+),([%d%-]+)")

		_left=tonumber(_left)
		_bottom=tonumber(_bottom)
		_right=tonumber(_right)
		_top=tonumber(_top)

		--Error
		if _right==nil then
			aegisub.dialog.display(
				{{class="label",x=0,y=0,width=1,height=1,
					label="Rectangular clipped gradients only."}},
				{"OK"})
			aegisub.cancel()
		end

		--Make sure coords are correct
		if _top>_bottom then
			_temp=_top
			_top=_bottom
			_bottom=_temp
		end

		if _left>_right then
			_temp=_left
			_left=_right
			_right=_temp
		end

		--Calculate the new clip
		newclip=intersect(svt,_top,_bottom,_left,_right,vertical,chir)

		--Substitute
		line.text=line.text:gsub(ctype.."%(([^%(%)]+)%)",ctype.."("..newclip..")")

		if newclip=="" then
			table.insert(to_delete,li)
		end

		--Put the line back
		sub[li]=line

	end

	--Cleanup
	sub.delete(unpack(to_delete))

	aegisub.set_undo_point(script_name)
end

rec:registerMacro(clip_clip)