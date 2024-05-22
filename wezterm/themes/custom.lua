local default_color = require("themes.colors.tokyonight")

local colorscheme = {
	foreground = default_color.foreground,
	background = default_color.background,
	cursor_bg = default_color.cursor_bg,
	cursor_border = default_color.cursor_border,
	cursor_fg = default_color.cursor_fg,
	selection_bg = default_color.selection_bg,
	selection_fg = default_color.selection_fg,
	ansi = default_color.ansi,
	brights = default_color.brights,
	tab_bar = {
		background = default_color.background,
		active_tab = {
			bg_color = default_color.selection_bg,
			fg_color = default_color.active_tab,
		},
		inactive_tab = {
			bg_color = default_color.selection_bg,
			fg_color = default_color.selection_fg,
		},
		inactive_tab_hover = {
			bg_color = default_color.selection_bg,
			fg_color = default_color.selection_fg,
		},
		new_tab = {
			bg_color = default_color.background,
			fg_color = default_color.foreground,
		},
		new_tab_hover = {
			bg_color = default_color.mantle,
			fg_color = default_color.text,
			italic = true,
		},
	},
	visual_bell = default_color.surface0,
	indexed = {
		[16] = default_color.peach,
		[17] = default_color.rosewater,
	},
	scrollbar_thumb = default_color.surface2,
	split = default_color.overlay0,
	compose_cursor = default_color.flamingo, -- nightbuild only
}

return colorscheme
