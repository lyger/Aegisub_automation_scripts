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
script_version = "1.1.0"
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
	local vtable, v = {}, 0
	for vtype,vcoords in vstring:gmatch("([mlb])([%d%s%-]+)") do
		for vx,vy in vcoords:gmatch("([%d%-]+)%s+([%d%-]+)") do
			v = v + 1
			vtable[v] = {class = vtype, x = tonumber(vx), y = tonumber(vy)}
		end
	end

	for i=1, v-1 do
		vtable[i].next=vtable[i+1]
	end
	vtable[v].next=vtable[1]

	return vtable
end

--Reverses a vector table object
function reverse_vector_table(vtable)
	local nvtable={}
	if #vtable<1 then return nvtable end
	--Make sure vtable does not end in an m. I don't know why this would happen but still
	local maxi = #vtable
	while vtable[maxi].class=="m" do
		maxi=maxi-1
	end

	--All vector shapes start with m
	nvtable[1] = util.copy(vtable[maxi])
	local tclass = nvtable[1].class
	nvtable[1].class = "m"

	--Reinsert coords in backwards order, but shift the class over by 1
	--because that's how vector shapes behave in aegi
	for i=maxi-1,1,-1 do
		local tcoord = util.copy(vtable[i])
		tcoord.class, tclass = tclass, tcoord.tclass
		nvtable[#nvtable+1] = tcoord
	end

	return nvtable
end

--Turns vector table into string
function vtable_to_string(vt)
	local result, cclass = {}

	for i=1,#vt,1 do
		if vt[i].class~=cclass then
			result[i] = string.format("%s %d %d ",vt[i].class,vt[i].x,vt[i].y)
			cclass = vt[i].class
		else
			result[i] = string.format("%d %d ",vt[i].x,vt[i].y)
		end
	end

	return table.concat(result)
end

--Rounds to the given number of decimal places
function round(n,dec)
	dec=dec or 0
	return math.floor(n*10^dec+0.5)/(10^dec)
end

--Returns chirality of vector shape. +1 if counterclockwise, -1 if clockwise
function get_chirality(vt)
	local wvt, trot = wrap(vt), 0
	for i = 2, #wvt - 1 do
		local rot1=math.atan2(wvt[i].y-wvt[i-1].y,wvt[i].x-wvt[i-1].x)
		local rot2=math.atan2(wvt[i+1].y-wvt[i].y,wvt[i+1].x-wvt[i].x)
		local drot=math.deg(rot2-rot1)%360
		if drot>180 then drot=360-drot else drot=-1*drot end
		trot=trot+drot
	end
	return sign(trot)
end

--Duplicates first and last coordinates at the end and beginning of shape,
--to allow for wraparound calculations
function wrap(vt)
	local wvt = {util.copy(vt[#vt])}
	for i = 1, #vt do
		wvt[i+1] = util.copy(vt[i])
	end
	wvt[#vt+1] = util.copy(vt[1])
	return wvt
end

--Cuts off the first and last coordinates, to undo the effects of "wrap"
function unwrap(wvt)
	local vt={}
	for i = 2, #wvt - 1 do
		vt[i-1] = util.copy(wvt[i])
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
	local u, v = "x", "y"
	local ub1, ub2, vb1, vb2 = lt, rt, tp, bm
	local chmod = -1
	if vert then
		u, v = "y", "x"
		chmod=1
		ub1, ub2, vb1, vb2 = tp, bm, lt, rt
	end

	--Find minimum v
	local minv, iminv = 10000, 0
	for i,vect in ipairs(vt) do
		if vect[v]<minv then
			minv, iminv = vect[v], i
		end
	end

	--Start with the point of minimum v
	local start = vt[iminv]

	--String storing the new vector shape
	local nshape, n = {}

	--Prevent infinite loops
	local imaginebreaker = 0

	repeat
		--Aborts operation if bad starting point
		local abort = false

		--Current point and counter
		local curr, count = start, 0

		--Class of the next point
		local nclass = "m"

		--Is the current shape open?
		local open = false
		--Which side did it first cross?
		local firstcross = 0
		--Which side is inside? (1 for increasing v coord, -1 for decreasing v coord)
		local inside = 1
		--The v coordinate where it last exited
		local exitv = 0

		repeat
			local vnext = curr.next

			--ZONE A
			------------------------- ub1
			--ZONE B
			------------------------- ub2
			--ZONE C

			--Zones of current and next points
			local czone, nzone

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
					nshape[n+1] = string.format(nclass.." %d %d ", curr[v], curr[u])
				else
					nshape[n+1] = string.format(nclass.." %d %d ", curr[u], curr[v])
				end
				n = n + 1
				--If a shape is not already open, abort
				if not open then abort = true end

			--Entering from above or below
			elseif (czone=="a" or czone=="c") and nzone=="b" then
				local uint = czone == "c" and ub2 or ub1

				local newv = round(uintercept(curr[u], curr[v], vnext[u], vnext[v], uint))
				if vert then
					nshape[n+1] = string.format(nclass.." %d %d ", newv, uint)
				else
					nshape[n+1] = string.format(nclass.." %d %d ", uint, newv)
				end
				n = n + 1

				if open and sign(newv-exitv) ~= inside then
					--Abort if on the wrong side of the last exit v coordinate
					abort = true
				--Otherwise open a new shape
				elseif not open then
					open = true
					nclass="l"
					firstcross=uint
					inside=sign(vnext[u]-curr[u])*ch*chmod
				end
			--Exiting from above or below
			elseif czone=="b" and (nzone=="a" or nzone=="c") then
				local uint = nzone == "c" and ub2 or ub1

				local newv = round(uintercept(curr[u], curr[v], vnext[u], vnext[v], uint))
				if vert then
					nshape[n+1] = string.format(nclass.." %d %d l %d %d ",
							                   curr[v], curr[u], newv, uint)
				else
					nshape[n+1] = string.format(nclass.." %d %d l %d %d ",
							                    curr[u], curr[v], uint, newv)
				end
				n = n + 1

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
				local uint1, uint2 = ub1, ub2
				if czone == "c" then
					uint1, uint2 = ub2, ub1
				end

				local newv1 = round(uintercept(curr[u], curr[v], vnext[u], vnext[v], uint1))
				local newv2 = round(uintercept(curr[u], curr[v], vnext[u], vnext[v], uint2))
				if vert then
					nshape[n+1] = string.format(nclass.." %d %d l %d %d ",
							                    newv1, uint1, newv2, uint2)
				else
					nshape[n+1] = string.format(nclass.." %d %d l %d %d ",
							                    uint1, newv1, uint2, newv2)
				end
				n = n +1

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
			nshape = {}
			start=start.next
		end

		imaginebreaker=imaginebreaker+1
	until not abort or imaginebreaker>#vt

	return table.concat(nshape)
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
	local pressed, results = aegisub.dialog.display(config,{"Go","Cancel"})
	if pressed=="Cancel" then aegisub.cancel() end

	--String of the vector shape
	local sshape = results.shape

	--Boolean that is true if the gradient is vertical, false if it's horizontal
	local vertical= results.gtype ~= "horizontal"

	--Enforce limitations on vector shape
	if sshape:match("b") then
		aegisub.dialog.display(
			{{class="label",x=0,y=0,width=1,height=1,
				label="This version does not support shapes with beziers."}},
			{"OK"})
		aegisub.cancel()
	end

	local _, mcount = sshape:gsub("m","m")
	if mcount>1 then
		aegisub.dialog.display(
			{{class="label",x=0,y=0,width=1,height=1,
				label="This version does not support compound shapes (more than one \"m\")."}},
			{"OK"})
		aegisub.cancel()
	end

	--Vector table object for this shape
	local svt = make_linked_vector_table(sshape)

	if #svt<3 then
		aegisub.dialog.display(
			{class="label",x=0,y=0,width=1,height=1,
				label="You're gonna need a bigger vector shape."},
			{"OK"})
		aegisub.cancel()

	end

	--Chirality
	local chir = get_chirality(svt)

	--Table of lines to delete
	local to_delete = {}

	--Process selected lines
	for si,li in ipairs(sel) do

		--Progress report
		aegisub.progress.task("Processing line "..si.."/"..#sel)
		aegisub.progress.set(100*si/#sel)

		--Read in the line
		local line = sub[li]

		--Find the clipping shape
		local ctype, tvector = line.text:match("\\(i?clip)%(([^%(%)]+)%)")

		--Error
		if not ctype then
			aegisub.dialog.display(
				{{class="label",x=0,y=0,width=1,height=1,
					label="Where is your \\clip, foo'?"}},
				{"OK"})
			aegisub.cancel()
		end

		--Get the coords
		local left, bottom, right, top = tvector:match("([%d%-]+),([%d%-]+),([%d%-]+),([%d%-]+)")

		left = tonumber(left)
		bottom = tonumber(nottom)
		right = tonumber(right)
		top = tonumber(top)

		--Error
		if not right then
			aegisub.dialog.display(
				{{class="label",x=0,y=0,width=1,height=1,
					label="Rectangular clipped gradients only."}},
				{"OK"})
			aegisub.cancel()
		end

		--Make sure coords are correct
		if top > bottom then
			top, bottom = bottom, top
		end

		if left > right then
			left, right = right, left
		end

		--Calculate the new clip
		local newclip = intersect(svt, top, bottom, left, right, vertical, chir)

		--Substitute
		line.text = line.text:gsub(ctype.."%(([^%(%)]+)%)", ctype.."("..newclip..")")

		if newclip == "" then
			to_delete[#to_delete] = li
		end

		--Put the line back
		sub[li]=line

	end

	--Cleanup
	sub.delete(to_delete)

	aegisub.set_undo_point(script_name)
end

rec:registerMacro(clip_clip)