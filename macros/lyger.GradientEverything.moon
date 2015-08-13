[[
==README==

Gradient Everything

Define "key" lines, and this will gradient almost anything.

If you've used the "frame-by-frame transform" script, this behaves very similarly. The typesetter
creates lines that he wants to morph into each other, then highlights them and runs the automation.

The automation cannot calculate how to draw the \clip statements unless you give it a bounding box.
This is essentially the smallest box that will enclose your entire typeset without cutting any part
of it off. Use the rectangular clip tool in aegisub to define a bounding box on any of the lines you
want to gradient, and the automation will detect it.

As a simple example, say you want to create a line with a gradient from red to blue. First typeset
the line and make it red. Then duplicate that line and make it blue. Use the rectancular clip tool
to draw a bounding box that encloses the typeset (it doesn't have to be super tight, but keep the
margins small or the gradient might not look right). You can do this on either of the lines, it
doesn't matter.

Now highlight both lines, go to the automation menu, and select "gradient everything". Check all the
tags you wish to be affected by the gradient. In this case, you want to be sure to check the color
tags. Select whether you want the gradient to be vertical or horizontal, and pick how many pixels
per strip you prefer (the fewer pixels per strip, the smoother the gradient, the more lines, and
the more lag). Press "Gradient" and you're done.

This script uses the same preset system as frame-by-frame transform. You can save, delete, and load
preset sets of options so you don't have to check the tags you want each time. If you name a preset
"Default", it will be the preset that's loaded when you open the automation.

If you are gradienting rotations, there is something to watch out for. If you want a line to start
with \frz10 and bend into \frz350, then with default options, the "gradient everything" automation will
make the line bend 340 degrees around the circle until it gets to 350. You probably wanted it to bend
only 20 degrees, passing through 0. The solution is to check the "Rotate in shortest direction" checkbox
from the popup window. This will cause the line to always pick the rotation direction that has a total
rotation of less than 180 degrees.

Furthermore, you don't have to gradient from only one line to one other line. You are allowed to have
as many lines as you want. For example, if you define three lines, one red, one yellow, and one green,
then "gradient everything" will make it red on the left, yellow in the center, and green on the right.

As such, the order of your lines matters. If you select "horizontal", then "gradient everything" will
gradient your lines in order from left to right. If you select "vertical", then it will gradient your
lines in order from top to bottom. If you want the gradient to go the other way, then change the order
of your lines. You must select all the lines that you wish to include in the gradient.

Much like "frame-by-frame transform", all the lines you are gradienting must have the exact same text
once tags are removed.

Oh yeah, I've tested this script on about four things so far, so don't be surprised if it's buggy.


TODO: Debug, debug, and keep debugging

]]

export script_name = "Gradient Everything"
export script_description = "This will gradient everything."
export script_version = "2.0.0"
export script_namespace = "lyger.GradientEverything"

DependencyControl = require "l0.DependencyControl"
rec = DependencyControl{
    feed: "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util", "aegisub.re",
        {"lyger.LibLyger", version: "2.0.0", url: "http://github.com/TypesettingTools/lyger-Aegisub-Scripts"},
        {"l0.ASSFoundation.Common", version: "0.2.0", url: "https://github.com/TypesettingTools/ASSFoundation",
         feed: "https://raw.githubusercontent.com/TypesettingTools/ASSFoundation/master/DependencyControl.json"},
        {"SubInspector.Inspector", version: "0.6.0", url: "https://github.com/TypesettingTools/SubInspector",
         feed: "https://raw.githubusercontent.com/TypesettingTools/SubInspector/master/DependencyControl.json",
         optional: true}
    }
}
util, re, LibLyger, Common, SubInspector = rec\requireModules!
have_SubInspector = rec\checkOptionalModules "SubInspector.Inspector"
logger, libLyger = rec\getLogger!, LibLyger!

-- tag list, grouped by dialog layout
tags_grouped = {
    {"c", "2c", "3c", "4c"},
    {"alpha", "1a", "2a", "3a", "4a"},
    {"fscx", "fscy", "fax", "fay"},
    {"frx", "fry", "frz"},
    {"bord", "shad", "fs", "fsp"},
    {"xbord", "ybord", "xshad", "yshad"},
    {"blur", "be"},
    {"pos", "org"}
}
tags_flat = table.join unpack tags_grouped

-- default settings for every preset
preset_defaults = { strip: 5, hv_select: "Horizontal", flip_rot: false, accel: 1.0,
                    tags: {tag, false for tag in *tags_flat }
}

tag_section_split = re.compile "((?:\\{.*?\\})*)([^\\{]+)"
-- will be moved into ASSFoundation.Common
re.ggmatch = (str, pattern, ...) ->
    regex = type(pattern) == "table" and pattern._regex and pattern or re.compile pattern, ...
    chars = unicode.toCharTable str
    charCnt, last = #chars, 0
    ->
        return if last >= charCnt
        matches = regex\match table.concat chars, "", last+1, charCnt
        matchCnt = #matches
        return unless matches
        last += matches[1].last
        start = matchCnt == 1 and 1 or 2
        unpack [matches[i].str for i = start, matchCnt]

-- the default preset must always be available and cannot be deleted
config = rec\getConfigHandler {
    presets: {
        Default: {}
        "[Last Settings]": {description: "Repeats the last #{script_name} operation"}
    }
    startupPreset: "Default"
}
unless config\load!
    -- write example preset on first time load
    config.c.presets["Horizontal all"] = tags: {tag, true for tag in *tags_flat}
    config\write!

create_dialog = (preset) ->
    config\load!
    preset_names = [preset for preset, _ in pairs config.c.presets]
    table.sort preset_names
    dlg = {
        -- define pixels per strip
        {                        class: "label",     x: 0, y: 0, width: 2, height: 1,
          label:"Pixels per strip: "                                                   },
        { name: "strip",         class: "intedit",   x: 2, y: 0, width: 2, height: 1,
          min: 1, value: preset.c.strip, step: 1                                       },
        { name: "hv_select",     class: "dropdown",  x: 4, y: 0, width: 1, height: 1,
          items: {"Horizontal", "Vertical"}, value: preset.c.hv_select                 },
        -- Flip rotation
        { name: "flip_rot",      class: "checkbox",  x: 0, y: 9, width: 4, height: 1,
          label: "Rotate in shortest direction", value: preset.c.flip_rot              },
        -- Acceleration
        {                        class: "label",     x: 0, y: 10, width: 2, height: 1,
          label: "Acceleration: ",                                                     },
        { name: "accel",         class:"floatedit",  x: 2, y: 10, width: 2, height: 1,
          value: preset.c.accel, hint: "1 means no acceleration, >1 starts slow and ends fast, <1 starts fast and ends slow" },
        {                        class: "label",     x: 0, y: 11, width: 2, height: 1,
          label: "Preset: "                                                            },
        { name: "preset_select", class: "dropdown",  x: 2, y: 11, width: 2, height: 1,
          items: preset_names, value: preset.section[#preset.section]                  },
        { name: "preset_modify", class: "dropdown",  x: 4, y: 11, width: 2, height: 1,
          items: {"Load", "Save", "Delete", "Rename"}, value: "Load" }
    }

    -- generate tag checkboxes
    for y, group in ipairs tags_grouped
        dlg[#dlg+1] = { name: tag, class: "checkbox", x: x-1, y: y, width: 1, height: 1,
                        label: "\\#{tag}", value: preset.c.tags[tag] } for x, tag in ipairs group

    btn, res = aegisub.dialog.display dlg, {"OK", "Cancel", "Mod Preset", "Create Preset"}
    return btn, res, preset

save_preset = (preset, res) ->
    preset\import res, nil, true
    if res.__class != DependencyControl.ConfigHandler
        preset.c.tags[k] = res[k] for k in *tags_flat
    preset\write!

create_preset = (settings, name) ->
    msg = if not name
        "Onii-chan, what name would you like your preset to listen to?"
    elseif name == ""
        "Onii-chan, did you forget to name the preset?"
    elseif config.c.presets[name]
        "Onii-chan, it's not good to name a preset the same thing as another one~"

    if msg
        btn, res = aegisub.dialog.display {
            { class: "label", x: 0, y: 0, width: 2, height: 1, label: msg               }
            { class: "label", x: 0, y: 1, width: 1, height: 1, label: "Preset Name: "   },
            { class: "edit",  x: 1, y: 1, width: 1, height: 1, name: "name", text: name }
        }
        return btn and create_preset settings, res.name

    preset = config\getSectionHandler {"presets", name}, preset_defaults
    save_preset preset, settings
    return name

prepare_line = (i) ->
    line = libLyger.lines[libLyger.sel[i]]
    line.comment = true
    libLyger.sub[line.i] = line

    -- Figure out the correct position and origin values
    posx, posy = libLyger\get_pos line
    orgx, orgy = libLyger\get_org line
    -- Make sure each line starts with tags
    line.text = "{}#{line.text}" unless line.text\find "^{"
    -- Turn all \1c tags into \c tags, just for convenience
    line.text = line.text\gsub "\\1c", "\\c"
    -- The tables that store the line as objects consisting of a tag and the text that follows it
    -- Separate each line into a table of tags and text
    line_table = [{:tag, :text} for tag, text in line.text\gmatch "({[^{}]*})([^{}]*)"]

    return line, line_table, posx, posy, orgx, orgy

interpolate_point = (tag, text, sposx, eposx, sposy, eposy, factor) ->
    text = LibLyger.line_exclude text, {tag}
    posx = LibLyger.float2str util.interpolate factor, sposx, eposx
    posy = LibLyger.float2str util.interpolate factor, sposy, eposy
    return text\gsub "^{", "{\\#{tag}(#{posx},#{posy})"

-- The main body of code that runs the frame transform
gradient_everything = (sub, sel, res) ->
    -- save last settings
    preset = config\getSectionHandler {"presets", "[Last Settings]"}, preset_defaults
    save_preset preset, res

    line_cnt, lines, bounds = #sel, {}, {}
    libLyger\set_sub sub, sel
    -- nothing to if not at least 2 lines were selected
    return if line_cnt < 2
    -- These are the tags to transform
    transform_tags = [tag for tag in *tags_flat when preset.c.tags[tag]]

    -- Look for a clip statement in one of the lines
    for i, li in ipairs sel
        lines[i] = sub[li]
        lines[i].assi_exhaustive = true
        bounds = {lines[i].text\match "\\clip%(([%d%.%-]*),([%d%.%-]*),([%d%.%-]*),([%d%.%-]*)%)"}
        if #bounds > 0
            bounds = [tonumber(ord) for ord in *bounds]
            break

    if #bounds == 0
        -- Exit if neither a clip nor the SubInspector module have been found
        unless have_SubInspector
            aegisub.log "Please put a rectangular clip in one of the selected lines or install SubInspector."
            return

        -- if no rectangular clip was found, get the combined bounding box of all selected lines
        assi, msg = SubInspector sub
        assert assi, "SubInspector Error: %s."\format msg
        bounds, times = assi\getBounds lines
        assert bounds~=nil, "SubInspector Error: %s."\format times

        local left, top, right, bottom
        for i = 1, #times
            if b = bounds[i]
                left, top = math.min(b.x, left or b.x), math.min(b.y, top or b.y)
                right, bottom = math.max(b.x+b.w, right or 0), math.max(b.y+b.h, bottom or 0)

        if left
            bounds = {left+3, top+3, right+3, bottom+3}
        else
            aegisub.log "Nothing to gradient: The selected lines didn't render to any non-transparent pixels."
            return


    -- Make sure left is the left and right is the right
    if bounds[1] > bounds[3] then
        bounds[1], bounds[3] = bounds[3], bounds[1]

    -- Make sure top is the top and bottom is the bottom
    if bounds[2] > bounds[4] then
        bounds[2], bounds[4] = bounds[4], bounds[2]

    -- The pixel dimension of the relevant direction of gradient
    span = preset.c.hv_select == "Vertical" and bounds[4]-bounds[2] or bounds[3]-bounds[1]

    --Stores how many frames between each key line
    --Index 1 is how many frames between keys 1 and 2, and so on

    frames_per, prev_end_frame = {}, 0
    avg_frame_cnt = span / (preset.c.strip * (line_cnt-1))
    for i = 1, line_cnt-1
        curr_end_frame = math.ceil i*avg_frame_cnt
        frames_per[i] = curr_end_frame - prev_end_frame
        prev_end_frame = curr_end_frame

    -- IMPORTANT CONTROL VARIABLES
    -- Must be initialized here
    -- The cumulative pixel offset that indicates the start clip offset of the line
    cum_off = 0
    -- Store the index of insertion and the new selection
    new_sel, ins_index = {}, sel[line_cnt]+1

    -- Master control loop
    -- First cycle through all the selected "intervals" (pairs of two consecutive selected lines)
    for i = 2, line_cnt
        -- Read the first and last lines
        first_line, start_table, sposx, sposy, sorgx, sorgy = prepare_line i-1
        last_line, end_table, eposx, eposy, eorgx, eorgy = prepare_line i

        -- Make sure both lines have the same splits
        LibLyger.match_splits start_table, end_table

        -- Tables that store tables for each tag block, consisting of the state of all relevant tags
        -- that are in the transform_tags table
        start_state_table = LibLyger.make_state_table start_table, transform_tags
        end_state_table = LibLyger.make_state_table end_table, transform_tags

        -- Insert default values when not included for the state of each tag block,
        -- or inherit values from previous tag block
        start_style = libLyger\style_lookup first_line
        end_style =   libLyger\style_lookup last_line

        current_start_state, current_end_state = {}, {}

        for k, sval in ipairs start_state_table
            -- build current state tables
            for skey, sparam in pairs sval
                current_start_state[skey] = sparam

            for ekey, eparam in pairs end_state_table[k]
                current_end_state[ekey] = eparam

            -- check if end is missing any tags that start has
            for skey, sparam in pairs sval
                end_state_table[k][skey] or= current_end_state[skey] or end_style[skey]

            -- check if start is missing any tags that end has
            for ekey, eparam in pairs end_state_table[k]
                start_state_table[k][ekey] or= current_start_state[ekey] or start_style[ekey]

        -- Create a line table based on first_line, but without relevant tags
        stripped = LibLyger.line_exclude first_line.text, table.join transform_tags, {"clip"}
        this_table = [{:tag, :text} for tag, text in re.ggmatch stripped, tag_section_split]
        -- Inner control loop
        -- For the number of lines indicated by the frames_per table, create a gradient
        for j = 1, frames_per[i-1]
            -- The interpolation factor for this particular line
            -- Failsafe because dividing by 0 is bad
            factor = frames_per[i-1] < 2 and 1 or (j-1)^preset.c.accel / (frames_per[i-1]-1)^preset.c.accel

            -- Create this line
            this_line = util.deep_copy first_line

            -- Create the relevant clip tag
            -- As of this version, the 1 pixel overlap has been removed.
            -- Hopefully colors still look fine

            clip_tag = "\\clip(%d,%d,%d,%d)"
            if preset.c.hv_select == "Vertical"
                clip_tag = clip_tag\format bounds[1], bounds[2]+cum_off+(j-1)*preset.c.strip,
                                           bounds[3], bounds[2]+cum_off+j*preset.c.strip
            else
                clip_tag=clip_tag\format bounds[1]+cum_off+(j-1)*preset.c.strip, bounds[2],
                                         bounds[1]+cum_off+j*preset.c.strip, bounds[4]

            -- Interpolate all the relevant parameters and insert
            text = LibLyger.interpolate this_table, start_state_table, end_state_table,
                                        factor, preset
            this_line.comment = false

            -- Forcibly add \pos
            text = interpolate_point "pos", text, sposx, eposx, sposy, eposy, factor

            -- Handle org transform
            if preset.c.tags.org then
                text = interpolate_point "org", text, sorgx, eorgx, sorgy, eorgy, factor

            -- Oh yeah, and add the clip tag
            this_line.text = text\gsub "^{", "{#{clip_tag}"

            -- Reinsert the line
            sub.insert ins_index, this_line
            new_sel[#new_sel+1] = ins_index
            ins_index += 1

        -- Increase the cumulative offset
        cum_off += frames_per[i-1] * preset.c.strip
    return new_sel

validate_ge = (sub, sel) -> #sel>=2

ge_gui = (sub, sel, _, preset_name = config.c.startupPreset) ->
    preset = config\getSectionHandler {"presets", preset_name}, preset_defaults
    btn, res = create_dialog preset

    switch btn
        when "OK" do gradient_everything sub, sel, res
        when "Create Preset" do ge_gui sub, sel, nil, create_preset res
        when "Mod Preset"
            if preset_name != res.preset_select
                preset = config\getSectionHandler {"presets", res.preset_select}, preset_defaults
                preset_name = res.preset_select

            switch res.preset_modify
                when "Delete"
                    preset\delete!
                    preset_name = nil
                when "Save" do save_preset preset, res
                when "Rename"
                    preset_name = create_preset preset.userConfig, preset_name
                    preset\delete!
            ge_gui sub, sel, nil, preset_name

-- register macros
rec\registerMacro ge_gui, validate_ge, nil, true
for name, preset in pairs config.c.presets
    f = (sub, sel) -> gradient_everything sub, sel, config\getSectionHandler {"presets", name}
    rec\registerMacro "Presets/#{name}", preset.description, f, validate_ge, nil, true
