--[[
README

Mass Modify Mocha Lines

Basically a more robust, automatic find-and-replace that lets you modify the appearance of mocha-tracked
frame-by-frame typesets, without having to re-apply the motion data.

Duplicate the first line of the typeset you want to modify. In the actor field, mark one of the duplicates
"orig" (for original) and one of the duplicates "mod" (for modified).

You can comment out the "orig" line for now, and alter the "mod" line until it looks the way you want it
to. DON'T TOUCH THE POSITIONING or anything else the mocha data might have affected. If you want to shift
the position of your typeset, use the position shifter automation.

Obviously, don't touch the "orig" line at all. The script will use that line for comparison, to determine
what needs to be modified in the rest of the lines.

Now highlight all the lines you want to change, as well as the "orig" and "mod" lines. Run this script.
Now every frame of the mocha-tracked typeset will be altered to look like the "modified" line. You can
add a letter-by-letter gradient, change the font size, even change the font.

The text of the line (without the tags) must be EXACTLY THE SAME as it was before. If you want to change
the text of the typeset, then for the love of god use find-and-replace. This script is meant for those
occasions when you would have to find-and-replace for a dozen different color codes and you're getting a
headache keeping track of them all.

]]--

script_name = "Mass modify mocha lines"
script_description = "Allows you to quickly change the appearance of mocha tracked lines without reapplying motion data."
script_version = "0.2.0"
script_author = "lyger"
script_namespace = "lyger.ModifyMocha"

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
local logger = rec:getLogger()

--Tags that are not worth dealing with in the scope of this script
local global_excludes = {
	"pos",
	"move",
	"org",
	"clip",
	"t",
	"r",
	"fad",
	"fade"
}

local function make_full_state_table(line_table)
	local this_state_table={}
	for i,val in ipairs(line_table) do
		this_state_table[i]={}
		local pstate = libLyger.line_exclude(val.tag,global_excludes)
		--\fn has special behavior, so check if it's there and if so, remove it
		--so the rest of the code doesn't have to deal with it
		pstate=pstate:gsub("\\fn([^\\{}]*)", function(a)
			this_state_table[i]["fn"]=a
			return ""
		end)
		for tagname,tagvalue in pstate:gmatch("\\([1-4]?%a+)([^\\{}]*)") do
			this_state_table[i][tagname]=tagvalue
		end
	end

	return this_state_table
end


--Modify the state tables so that all relevant tags in one table have corresponding partners in the other
--If do_default is true, then it will draw from style defaults when not previously overridden
local function match_state_tables(stable1,sstyle1,stable2,sstyle2,do_default)
	local current_state1={}
	local current_state2={}

	for i,val1 in ipairs(stable1) do
		--build current state tables
		for key1,param1 in pairs(val1) do
			current_state1[key1]=param1
		end
		for key2,param2 in pairs(stable2[i]) do
			current_state2[key2]=param2
		end

		--check if end is missing any tags that start has
		for key1,param1 in pairs(val1) do
			if stable2[i][key1]==nil then
				if current_state2[key1]==nil and do_default then
					stable2[i][key1]=sstyle2[key1]
				else
					stable2[i][key1]=current_state2[key1]
				end
			end
		end
		--check if start is missing any tags that end has
		for key2,param2 in pairs(stable2[i]) do
			if stable1[i][key2]==nil then
				if current_state1[key2]==nil and do_default then
					stable1[i][key2]=sstyle1[key2]
				else
					stable1[i][key2]=current_state1[key2]
				end
			end
		end
	end
	return stable1,stable2
end

--The main body that performs the modification
function modify_mocha(sub,sel)
	libLyger:set_sub(sub, sel)

	--Find the "original" and "modified" lines
	local oline,mline
	local oindex,mindex

	for si,li in ipairs(sel) do
		checkline = libLyger.lines[li]
		if checkline.actor:lower():find("^orig$") then
			oline = libLyger.lines[li]
			oindex = li
		elseif checkline.actor:lower():find("^mod$") then
			mline = libLyger.lines[li]
			mindex = li
		end
		if oline and mline then break end
	end

	if not (oline and mline) then
		aegisub.dialog.display({ {class="label", label="Please mark the original line with \"orig\"\n"..
			"and the modified line with \"mod\" in the\nactor field"} })
		return
	end

	--Break them into line tables and match the splits
	local otable, mtable = {}, {}

	local x = 1
	for thistag,thistext in oline.text:gmatch("({[^{}]*})([^{}]*)") do
		otable[x]={tag=thistag,text=thistext}
		x = x + 1
	end

	x = 1
	for thistag,thistext in mline.text:gmatch("({[^{}]*})([^{}]*)") do
		mtable[x]={tag=thistag,text=thistext}
		x = x + 1
	end

	otable, mtable = libLyger.match_splits(otable,mtable)
	--Parse the line tables into full state tables
	--(requires new code, since previous state table depended on a list of tags to search for)

	local o_state_table = make_full_state_table(otable)
	local m_state_table = make_full_state_table(mtable)

	--Compare the state tables and store the differences in a new state table
	--This state table will go along with the modified line's line table

	local ostyle=libLyger:style_lookup(oline)
	local mstyle=libLyger:style_lookup(mline)

	o_state_table, m_state_table = match_state_tables(o_state_table,ostyle,m_state_table,mstyle,true)

	local delta_state_table = {}

	--Find differences and add to delta
	for i,mval in ipairs(m_state_table) do
		delta_state_table[i]={}
		for mtag,mparam in pairs(mval) do
			if o_state_table[i][mtag]~=mparam or
				(m_state_table[i-1]~=nil and m_state_table[i-1][mtag]~=mparam) then
					delta_state_table[i][mtag]=mparam
			end
		end
	end

	--Now scan all the remaining lines
	--(being sure to store the indices of the original/modified lines so they can be skipped)
	for si,li in ipairs(sel) do
		if li~=mindex and li~=oindex then
			aegisub.progress.set((si-1)/#sel*100)
			local this_line = libLyger.lines[li]

			--Make sure this line starts with tags
			if this_line.text:find("^{")==nil then this_line.text="{}"..this_line.text end

			--Split it into a line table
			local this_table, x = {}, 1
			for thistag,thistext in this_line.text:gmatch("({[^{}]*})([^{}]*)") do
				this_table[x]={tag=thistag,text=thistext}
				x = x + 1
			end

			local mtable_copy = util.deep_copy(mtable)
			local delta_state_copy = util.deep_copy(delta_state_table)

			--Custom match split on the copied modified line and the current line,
			--which modifies state table too
			local j=1
			while(j<=#mtable_copy) do
				local mtext, mtag = mtable_copy[j].text, mtable_copy[j].tag
				local ttext, ttag = this_table[j].text, this_table[j].tag

				--If the mtable item has longer text, break it in two based on the text of this_table
				if mtext:len() > ttext:len() then
					local newtext = mtext:match(ttext.."(.*)")
					for k=#mtable_copy,j+1,-1 do
						mtable_copy[k+1]=mtable_copy[k]
						delta_state_copy[k+1]=delta_state_copy[k]
					end
					delta_state_copy[j]={}
					mtable_copy[j]={tag=mtag,text=ttext}
					mtable_copy[j+1]={tag="{}",text=newtext}
				--If the this_table item has longer text, break it in two based on the text of mtable
				elseif mtext:len() < ttext:len() then
					local newtext = ttext:match(mtext.."(.*)")
					for k=#this_table,j+1,-1 do
						this_table[k+1]=this_table[k]
					end
					this_table[j]={tag=ttag,text=mtext}
					this_table[j+1]={tag="{}",text=newtext}
				end
				j=j+1
			end

			--Generate state table
			local this_state_table = make_full_state_table(this_table)

			--Match state tables
			local this_style = libLyger:style_lookup(this_line)

			delta_state_copy,this_state_table=
				match_state_tables(delta_state_copy,mstyle,this_state_table,this_style,false)

			--[[DEBUG]]--
			--[[for i,val in ipairs(delta_state_table) do
				for tag,param in pairs(val) do
					aegisub.log("In tag block "..i.." will replace "..tag.." tag with "..param.."\n")
				end
			end]]--

			--For each tag block in the current line, remove the relevant tags in the delta state table
			local rebuilt_line = {}
			for i,tval in ipairs(this_table) do
				for dtag,dparam in pairs(delta_state_copy[i]) do
					if dtag=="fn" then tval.tag=tval.tag:gsub("\\"..dtag.."[^\\{}]*","")
					else tval.tag=tval.tag:gsub("\\"..dtag.."%A[^\\{}]*","") end
					tval.tag=tval.tag:gsub("}","\\"..dtag..dparam.."}")
				end
				rebuilt_line[i*2-1], rebuilt_line[i*2] = tval.tag, tval.text
			end

			--Re-insert
			this_line.text = table.concat(rebuilt_line):gsub("{}","")
			sub[li] = this_line
		end
	end

	oline.comment = true
	oline.actor = "*"..oline.actor
	sub[oindex] = oline
end

rec:registerMacro(modify_mocha)