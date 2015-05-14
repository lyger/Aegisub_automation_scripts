--[[
README:

***ALSO REQUIRES(1) CONVERT.EXE STANDALONE FROM IMAGEMAGICK***

(1) Only if you want to use non-bitmap images or the resize capability.
	Save the binary to your Aegisub\automation\autoload directory:
	http://www.mediafire.com/download/zdxn75nte1n6cq6/convert.exe


Image to .ass

Converts a 24-bit or 32-bit bitmap image pixel-by-pixel into an .ass drawing.
Runs a basic compression algorithm on the resultant drawing. Compression
level can be adjusted from the interface (the higher the number, the more
compressed).

Time a line to the times you want the image to appear. If positioning or
alignment tags are present in the line, and you select "from line" for the
position handling, then these tags will be used on the drawing. Any other
text in the original line will be ignored.

Also allows you to use an alpha mask, which is a grayscale bitmap loaded
separately. Black represents solid and white represents transparent, just
like .ass color codes. This is inverted compared to, for example, Photoshop
alpha masks, so you may have to invert your mask before loading it.

If you're using an alpha mask, the original image should extend beyond the
mask. For example, if you have textured text on a white background as your
main image, the text will already be antialised to the white background.
When you apply the alpha mask, the antialiasing pixels will be antialiased
again, making a weird white glow. Instead, your main image should be the
solid texture, thus creating smooth antialiasing pixels when you apply the
mask.

Be aware that due to subpixel alignment errors in the current version of
xy-vsfilter, the image may appear transparent or have subpixel gaps if you
use certain alignments and positionings. Corner alignments and whole-number
positions are the most reliable.

Supports \move but you are strongly advised NOT to use it.

]]

script_name = "Image to .ass"
script_description = "Converts bitmap image to .ass lines."
script_version = "2.3.0"
script_author = "lyger"
script_namespace = "lyger.Image2ASS"

local DependencyControl = require("l0.DependencyControl")
local rec = DependencyControl{
	feed = "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
	{ "aegisub.util", "ffi" }
}
local util, ffi = rec:requireModules()

--[[ Detect whether to use *nix or Windows style paths. ]]--
local winpaths = ffi.os == "Windows"

function make_config()
	return
	{
		{x=0,y=0,height=1,width=1,class="label",label="Output drawing"},
		{x=1,y=0,height=1,width=1,class="dropdown",name="otype",
			items={"all on one line","with each row on a new line"},
			value="with each row on a new line"},
		{x=0,y=1,height=1,width=1,class="label",label="Position:"},
		{x=1,y=1,height=1,width=1,class="dropdown",name="postype",
			items={"from line","default"},value="from line"},
		{x=0,y=2,height=1,width=1,class="label",label="Compression:"},
		{x=1,y=2,height=1,width=1,class="intedit",name="tol",
			max=3000,min=1,value=40},
		{x=0,y=3,height=1,width=1,class="label",label="Resize image (%):"},
		{x=1,y=3,height=1,width=1,class="floatedit",name="resize",
			max=100,min=1,value=100},
		{x=0,y=4,height=1,width=1,class="label",label="Pixel size:"},
		{x=1,y=4,height=1,width=1,class="intedit",name="pxsize",
			max=250,min=1,value=1}
	}
end

--Parse out properties from a bitmap header
function parse_header(fn)
	--Open
	_file=io.open(fn,"rb")

	--Read irrelevant data
	_file:read(18)

	--Read in the pixel width of the image
	_width=_file:read(4)
	swidth=""
	for _w in _width:gmatch(".") do
		swidth=string.format("%02X",string.byte(_w))..swidth
	end
	_iw=tonumber(swidth,16)

	--Read the pixel height of the image, including its orientation
	_height=_file:read(4)
	sheight=""
	for _h in _height:gmatch(".") do
		sheight=string.format("%02X",string.byte(_h))..sheight
	end
	_ih=tonumber(sheight,16)

	--Handle two's complement. Good god this is hacky
	if _ih>tonumber("7FFFFFFF",16) then
		_ih=_ih-tonumber("FFFFFFFF",16)-1
	end

	_file:read(2)

	--Read in whether the bitmap is 24 or 32 bit (fuck handling anything less)
	bitsize=string.byte(_file:read(1))

	_ws=bitsize/8

	_file:close()

	--Return width, height, and wordsize
	return _iw, _ih, _ws
end

function convert_to_bmp(filename,scale)

	local cfname=filename:gsub("%.%a+$",".bmp")

	local prefix=aegisub.decode_path("?data").."\\automation\\autoload\\"

	--Make sure convert binary exists
	local cex=io.open(prefix.."convert.exe")
	if cex==nil then
		aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
			label="convert.exe not found. Make sure the\n"..
			"executable is in your automation\\autoload\n"..
			"directory."}},{"OK"})
		aegisub.cancel()
	else
		cex:close()
	end

	--Write the self-deleting batch and run it
	opts="-type TrueColor"
	if scale then
		opts=opts.." -resize "..scale.."%%"
		cfname=cfname:gsub("%.bmp$","_"..scale..".bmp")
	end

	--Make sure the filenames are different
	if cfname==filename then
		cfname=cfname:gsub("%.bmp$","_copy.bmp")
	end

	local command="\""..prefix.."convert.exe\" \""
		..filename.."\" "..opts.." BMP3:\""..cfname.."\""

	convertfile=io.open(prefix.."image2ass_converter.bat","wb")
	convertfile:write(command.."\ndel %0")
	convertfile:close()

	os.execute("\""..prefix.."image2ass_converter.bat\"")

	return cfname

end

function run_i2a(subs,sel)

	local ffilter = "Bitmap images (.bmp)|*.bmp"
	if winpaths then ffilter="All images (.bmp; .jpg; .png; .gif)|*.bmp;*.jpg;*.png;*.gif" end
	--Prompt for bitmap image
	fname=aegisub.dialog.open("Select image","","",ffilter,false,true)
	if not fname then aegisub.cancel() end

	cleanfiles={}
	--Convert to .bmp if not .bmp already
	if not fname:lower():match("%.bmp$") then
		fname=convert_to_bmp(fname)
		table.insert(cleanfiles,fname)
	end


	--Initialize some values
	dconfig=make_config()
	results=nil
	afname=""
	alpha=false
	buttons={"Convert","Add alpha mask","Cancel"}
	repeat
		--Show options
		pressed,results=aegisub.dialog.display(dconfig,buttons)

		if pressed=="Cancel" then aegisub.cancel()
		elseif pressed=="Add alpha mask" then

			--Prompt for bitmap image
			afname=aegisub.dialog.open("Select image to use as alpha mask","","",ffilter,false,true)
			if not afname then
				aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
					label="Error, invalid file."}},{"OK"})
			else
				alpha=true
				if not afname:lower():match(".bmp$") then
					afname=convert_to_bmp(afname)
					table.insert(cleanfiles,afname)
				end
				table.insert(dconfig,{x=0,y=5,height=1,width=2,class="label",
					label="Alpha mask loaded."})
				table.remove(buttons,2)
			end

		end
	until pressed=="Convert"

	if results["resize"]~=100 then
		fname=convert_to_bmp(fname,results["resize"])
		table.insert(cleanfiles,fname)
		if alpha then
			afname=convert_to_bmp(afname,results["resize"])
			table.insert(cleanfiles,afname)
		end
	end

	--Parse headers
	rowsize,imgheight,wordsize=parse_header(fname)
	awordsize=0
	if alpha then
		_aiw,_aih,awordsize=parse_header(afname)
		if _aiw~=rowsize or _aih~=imgheight then
			aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
					label="Error, alpha channel is not the same size\n"..
					"as image."}},{"OK"})
			aegisub.cancel()
		end
	end

	--Check wordsize
	if (wordsize~=3 and wordsize~=4) or (alpha and awordsize~=3 and awordsize~=4) then
		aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
				label="Error, images must be 24-bit or 32-bit bitmap."}},{"OK"})
		aegisub.cancel()
	end

	--Compile results
	tolerance=results["tol"]
	px=results["pxsize"]
	oneline=(results["otype"]=="all on one line")
	readpos=(results["postype"]=="from line")

	--Open the file
	file=io.open(fname,"rb")
	file:read(54)
	if alpha then
		afile=io.open(afname,"rb")
		afile:read(54)
	end

	--Distance in rgb space
	local function cdist(r1,g1,b1,r2,g2,b2)
		return math.sqrt((r1-r2)^2+(g1-g2)^2+(b1-b2)^2)
	end

	--Counter variables
	counter=0

	bytesread=0
	abytesread=0

	--Stores previous color used, standard deviation, last color
	_r,_g,_b=-1*tolerance-1,-1*tolerance-1,-1*tolerance-1
	sr,sg,sb=_r,_g,_b
	lr,lg,lb=_r,_g,_b

	--Stores current and previous alphas
	aval="00"
	praval="00"
	ppraval="00"

	--Previous color code used
	pcode=""

	--Width of next shape to draw
	width=1

	--String to store each line
	line=""

	--Table to store processed image
	imgtable={}

	--Force alpha tag if alpha channel is on
	if alpha then ppraval="GG" end

	while true do
		byte=file:read(wordsize)
		bytesread=bytesread+wordsize

		if byte==nil then break end

		b,g,r=byte:match("^(.)(.)(.)")

		if b==nil or g==nil or r==nil then break end

		r=string.byte(r)
		g=string.byte(g)
		b=string.byte(b)

		--Temporary old values of the average
		_tr,_tg,_tb=_r,_g,_b

		if _r>=0 then

			--Keep a running average of the rgb values
			_r=_r+(r-_r)/(width+1)
			_g=_g+(g-_g)/(width+1)
			_b=_b+(b-_b)/(width+1)

			--Keep a running standard deviation or the rbg values
			sr=sr+(r-_tr)*(r-_r)
			sg=sg+(g-_tg)*(g-_g)
			sb=sb+(b-_tb)*(b-_b)
		end

		--Read and average alpha channel
		if alpha then
			abyte=afile:read(awordsize)
			abytesread=abytesread+awordsize
			ab,ag,ar=abyte:match("^(.)(.)(.)")
			aval=string.format("%02X",
				math.floor((string.byte(ab)+string.byte(ag)+string.byte(ar))/3))
		end

		if ((cdist(lr,lg,lb,r,g,b)<tolerance
			and cdist(sr,sg,sb,0,0,0)<tolerance and aval==praval))
			or (aval=="FF" and aval==praval) then

			--Increase width
			width=width+1

		else

			--Only add the colors if this is not the first pixel in a row
			if _r>=0 then
				shape=string.format("m 0 0 l 0 %d %d %d %d 0",px,width*px,px,width*px)

				--Add color code
				code=string.format("%02X%02X%02X",_tb,_tg,_tr)

				line=line.."{"
				if praval~=ppraval then
					line=line.."\\alpha&H"..praval.."&"
				end
				if code~=pcode and praval~="FF" then
					line=line.."\\c&H"..code.."&"
					pcode=code
				end
				line=line.."}"..shape
			end

			--Reset width and colors
			width=1
			_r,_g,_b=r,g,b
			sr,sg,sb=0,0,0

			--Set last alpha value
			if alpha then
				ppraval=praval
				praval=aval
			end
		end

		--Set last r,g,b values
		lr,lg,lb=r,g,b

		counter=counter+1
		if counter%rowsize==0 then

			--Read filler bytes
			file:read(math.abs((4-bytesread)%4))
			if alpha then afile:read(math.abs((4-abytesread)%4)) end
			bytesread=0
			abytesread=0

			--Dump current shape on end of line
			code=string.format("%02X%02X%02X",_b,_g,_r)
			shape=string.format("m 0 0 l 0 %d %d %d %d 0",px,width*px,px,width*px)
			line=line.."{"
			if paval~=aval then
				line=line.."\\alpha&H"..aval.."&"
			end
			if pcode~=code then
				line=line.."\\c&H"..code.."&"
			end
			line=line.."}"..shape

			--Sometimes the algorithm inserts blank tags. I can't be bothered
			--to figure out why, so just remove them
			while line:match("0{}m") do
				line=line:gsub(
					"m 0 0 l 0 "..px.." (%d+) "..px.." %d+ 0{}m 0 0 l 0 "..px.." (%d+) "..px.." %d+ 0",
					function(w1,w2)
						local nw=tonumber(w1)+tonumber(w2)
						return string.format("m 0 0 l 0 %d %d %d %d 0",px,nw,px,nw)
					end)
			end

			--Add line to table
			if imgheight<0 then
				table.insert(imgtable,line)
			else
				table.insert(imgtable,1,line)
			end

			--Progress report
			rprog=math.floor(counter/rowsize)
			aegisub.progress.set(rprog*100/math.abs(imgheight))
			aegisub.progress.task(string.format("Processing %d/%d rows",rprog,math.abs(imgheight)))

			--Reset the line
			line=""

			--Reset previous colors
			_r=-1*tolerance-1
			_g=-1*tolerance-1
			_b=-1*tolerance-1
			sr,sg,sb=_r,_g,_b
			lr,lg,lb=_r,_g,_b

			--Reset alpha if alpha channel is on
			if alpha then praval="GG" end

			--Reset previous code
			pcode=""

			--Reset width
			width=1
		end
	end

	--Close files
	file:close()
	if alpha then afile:close() end

	aegisub.progress.task("Writing to subtitles...")--No progress bar because this should be near instant

	--Read in the line
	line=subs[sel[1]]
	line.comment=false

	--Get style info
	meta,styles=karaskel.collect_head(subs,false)
	lstyle=styles[line.style]

	--Estimate filesize
	fsize=0

	--New selection
	newsel={}

	--If the drawing is to be written all on one line
	if oneline then
		oline=util.copy(line)

		rtext="{"
		if readpos then
			if oline.text:match("\\move") then
				mtag=oline.text:match("(\\move%b())")
				rtext=rtext..mtag
			end
			if oline.text:match("\\pos") then
				ptag=oline.text:match("(\\pos%b())")
				rtext=rtext..ptag
			end
		end

		if lstyle.outline~=0 then rtext=rtext.."\\bord0" end
		if lstyle.shadow~=0 then rtext=rtext.."\\shad0" end

		rtext=rtext.."}"
		rtext=rtext:gsub("{}","")

		prefix="{\\p1}"
		eol="{\\p0}\\N"
		for i,row in ipairs(imgtable) do
			rtext=rtext..prefix..row
			if i~=#imgtable then rtext=rtext..eol end
		end

		oline.text=rtext
		fsize=#rtext+44+#oline.style+#oline.effect+#oline.actor

		subs.insert(sel[1]+1,oline)

		newsel={sel[1]+1}

	--If the drawing is to be written across multiple lines
	else
		prefix="{\\p1"
		pfmt="\\pos(%d,%d)"
		align="\\an7"
		bx,by,bx2,by2=0,0,0,0
		if readpos then
			if line.text:match("\\move") then
				mx1,my1,mx2,my2,msuf=line.text:match(
					"\\move%(([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)([^%)]*%))")
				bx=tonumber(mx1)
				by=tonumber(my1)
				bx2=tonumber(mx2)
				by2=tonumber(my2)
				pfmt="\\move(%d,%d,%d,%d"..msuf
			end
			if line.text:match("\\pos") then
				p_x,p_y=line.text:match("\\pos%(([%d%.%-]+),([%d%.%-]+)%)")
				bx=tonumber(p_x)
				by=tonumber(p_y)
			end
			align=line.text:match("\\an?%d%d?") or align
		end
		prefix=prefix..align..pfmt

		if lstyle.outline~=0 then prefix=prefix.."\\bord0" end
		if lstyle.shadow~=0 then prefix=prefix.."\\shad0" end

		prefix=prefix.."}"

		inserts=1
		for i,row in ipairs(imgtable) do
			_,alphanum=row:gsub("\\alpha","\\alpha")
			dowrite=true
			if alphanum==1 then
				alphavalue=row:match("\\alpha&H(..)&")
				if alphavalue=="FF" then dowrite=false end
			end
			if dowrite then
				nline=util.copy(line)
				nline.text=prefix:format(bx,by+(i-1)*px,bx2,by2+(i-1)*px)
				nline.text=nline.text..row
				subs.insert(sel[1]+inserts,nline)
				table.insert(newsel,sel[1]+inserts)
				inserts=inserts+1
				fsize=fsize+#nline.text+44+#nline.style+#nline.effect+#nline.actor
			end
		end
	end

	line.text=fname
	line.comment=true
	subs[sel[1]]=line

	mbytes=string.format("%.2f",fsize/1048576):gsub("0+$",""):gsub("%.$","")
	msg="Conversion finished.\nApproximate added filesize: "..mbytes.." MB."
	if mbytes=="0" then
		kbytes=string.format("%.2f",fsize/1025):gsub("0+$",""):gsub("%.$","")
		msg="Conversion finished.\nApproximate added filesize: "..kbytes.." kB."
	else
	end
	aegisub.dialog.display({{x=0,y=0,width=1,height=1,class="label",
		label=msg}},
		{"OK"})

	--Delete generated bitmap, if applicable
	for _,cleanf in ipairs(cleanfiles) do os.execute("del \""..cleanf.."\"") end

	aegisub.set_undo_point(script_name)
	return newsel
end

rec:registerMacro(run_i2a)