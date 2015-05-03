[[
README

This file is a library of commonly used functions across all my automation
scripts. This way, if there are errors or updates for any of these functions,
I'll only need to update one file.

The filename is a bit vain, perhaps, but I couldn't come up with anything else.

]]

DependencyControl = require("l0.DependencyControl")
version = DependencyControl{
    name: "LibLyger",
    version: "1.1.0",
    description: "Library of commonly used functions across all of lyger's automation scripts.",
    author: "lyger",
    url: "http://github.com/TypesettingTools/lyger-Aegisub-Scripts",
    moduleName: "lyger.LibLyger",
    feed: "https://raw.githubusercontent.com/TypesettingTools/lyger-Aegisub-Scripts/master/DependencyControl.json",
    {
        "aegisub.util", "karaskel"
    }
}
util = version\requireModules!
logger = version\getLogger!

class LibLyger
    msgs = {
        preproc_lines: {
            bad_type: "Error: argument #1 must be either a line object, an index into the subtitle object or a table of indexes; got a %s."
        }
    }
    new: (sub, sel, generate_furigana) =>
        @set_script sub, sel, generate_furigana if sub

    set_sub: (@sub, @sel = {}, generate_furigana = false) =>
        local has_script_info

        @script_info, @lines, @dialogue, @dlg_cnt = {}, {}, {}, 0
        for i, line in ipairs sub
            @lines[i] = line
            switch line.class
                when "info" then @script_info[line.key] = line.value
                when "dialogue"
                    @dlg_cnt += 1
                    @dialogue[@dlg_cnt], line.i = line, i

        @meta, @styles = karaskel.collect_head @sub, generate_furigana
        @preproc_lines @sel

    preproc_lines: (lines) =>
        val_type = type lines
        -- indexes into the subtitles object
        if val_type == "number"
            lines, val_type = {@lines[lines]}, "table"
        assert val_type == "table", msgs.preproc_lines.bad_type\format val_type

        -- line objects
        if lines.raw and lines.section and not lines.duration
            karaskel.preproc_line @sub, @meta, @styles, lines
        -- tables of line numbers/objects such as the selection
        else @preproc_lines line for line in *lines

    -- returns a "Lua" portable version of the string
    exportstring: (s) -> string.format "%q", s

    --Lookup table for the nature of each kind of parameter
    param_type: {
        alpha: "alpha"
        "1a":  "alpha"
        "2a":  "alpha"
        "3a":  "alpha"
        "4a":  "alpha"
        c:     "color"
        "1c":  "color"
        "2c":  "color"
        "3c":  "color"
        "4c":  "color"
        fscx:  "number"
        fscy:  "number"
        frz:   "angle"
        frx:   "angle"
        fry:   "angle"
        shad:  "number"
        bord:  "number"
        fsp:   "number"
        fs:    "number"
        fax:   "number"
        fay:   "number"
        blur:  "number"
        be:    "number"
        xbord: "number"
        ybord: "number"
        xshad: "number"
        yshad: "number"
        }

    --Convert float to neatly formatted string
    float2str: (f) -> "%.3f"\format(f)\gsub("%.(%d-)0+$","%.%1")\gsub "%.$", ""

    --Escapes string for use in gsub
    esc: (str) -> str\gsub "([%%%(%)%[%]%.%*%-%+%?%$%^])","%%%1"

    [[
    Tags that can have any character after the tag declaration: \r, \fn
    Otherwise, the first character after the tag declaration must be:
    a number, decimal point, open parentheses, minus sign, or ampersand
    ]]

    -- Remove listed tags from the given text
    line_exclude: (text, exclude) =>
        remove_t = false
        new_text = text\gsub "\\([^\\{}]*)", (a) ->
            if a\match "^r"
                for val in *exclude
                    return "" if val == "r"
            elseif a\match "^fn"
                for val in *exclude
                    return "" if val == "fn"
            else
                tag = a\match "^[1-4]?%a+"
                for val in *exclude
                    if val == tag
                        --Hacky exception handling for \t statements
                        if val == "t"
                            remove_t = true
                            return "\\#{a}"
                        elseif a\match "%)$"
                            return a\match("%b()") and "" or ")"
                        else
                            return ""
            return "\\"..a

        if remove_t
            new_text = new_text:gsub "\\t%b()", ""

        return new_text

    -- Remove all tags except the given ones
    line_exclude_except: (text, exclude) =>
        remove_t = true
        new_text=text\gsub "\\([^\\{}]*)", (a) ->
            if a\match "^r"
                for val in *exclude
                    return "\\#{a}" if val == "r"
            elseif a\match "^fn"
                for val in *exclude
                    return "\\#{a}" if val == "fn"
            else
                tag = a\match "^[1-4]?%a+"
                for val in *exclude
                    if val == tag
                        remove_t = false if val == "t"
                        return "\\#{a}"

            if a\match "^t"
                return "\\#{a}"
            elseif a\match "%)$"
                return a\match("%b()") and "" or ")"
            else return ""

        if remove_t
            new_text = new_text\gsub "\\t%b()", ""

        return new_text

    -- Returns the position of a line
    get_default_pos: (line, align_x, align_y) =>
        @preproc_lines line
        x = {
            @script_info.PlayResX - line.eff_margin_r,
            line.eff_margin_l,
            line.eff_margin_l + (@script_info.PlayResX - line.eff_margin_l - line.eff_margin_r) / 2
        }
        y = {
            @script_info.PlayResY - line.eff_margin_b,
            @script_info.PlayResY / 2
            line.eff_margin_t
        }
        return x[align_x], y[align_y]

    get_pos: (line) =>
        posx, posy = line.text\match "\\pos%(([%d%.%-]*),([%d%.%-]*)%)"
        unless posx
            posx, posy = line.text\match "\\move%(([%d%.%-]*),([%d%.%-]*),"
        return tonumber(posx), tonumber(posy) if posx

        -- \an alignment
        if align = tonumber line.text\match "\\an([%d%.%-]+)"
            return @get_default_pos line, align%3 + 1, math.ceil align/3
        -- \a alignment
        elseif align = tonumber line.text\match "\\a([%d%.%-]+)"
            return @get_default_pos line, align%4,
                                   align > 8 and 2 or align> 4 and 3 or 1
        -- no alignment tags (take karaskel values)
        else return line.x, line.y

    -- Returns the origin of a line
    get_org: (line) =>
        orgx, orgy = line.text\match "\\org%(([%d%.%-]*),([%d%.%-]*)%)"
        if orgx
            return orgx, orgy
        else return @get_pos line

    -- Returns a table of default values
    style_lookup: (line) =>
        @preproc_lines line
        return {
            alpha: "&H00&"
            "1a":  util.alpha_from_style line.styleref.color1
            "2a":  util.alpha_from_style line.styleref.color2
            "3a":  util.alpha_from_style line.styleref.color3
            "4a":  util.alpha_from_style line.styleref.color4
            c:     util.color_from_style line.styleref.color1
            "1c":  util.color_from_style line.styleref.color1
            "2c":  util.color_from_style line.styleref.color2
            "3c":  util.color_from_style line.styleref.color3
            "4c":  util.color_from_style line.styleref.color4
            fscx:  line.styleref.scale_x
            fscy:  line.styleref.scale_y
            frz:   line.styleref.angle
            frx:   0
            fry:   0
            shad:  line.styleref.shadow
            bord:  line.styleref.outline
            fsp:   line.styleref.spacing
            fs:    line.styleref.fontsize
            fax:   0
            fay:   0
            xbord: line.styleref.outline
            ybord: line.styleref.outline
            xshad: line.styleref.shadow
            yshad: line.styleref.shadow
            blur:  0
            be:    0
        }

    :version

return version\register LibLyger