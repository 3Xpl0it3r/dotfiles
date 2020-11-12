local tokynight = {
	foreground = "#c0caf5",
	background = "#24283b",
	cursor_bg = "#c0caf5",
	cursor_border = "#c0caf5",
	cursor_fg = "#24283b",
	selection_bg = "#364a82",
	selection_fg = "#c0caf5",
	ansi = { "#1d202f", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6" },
	brights = { "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5" },
	mantle = "#181825",
	crust = "#11111b",
	subtext1 = "#bac2de",
	subtext0 = "#a6adc8",
	overlay2 = "#9399b2",
	overlay1 = "#7f849c",
	overlay0 = "#6c7086",
	surface2 = "#585b70",
	surface1 = "#45475a",
	surface0 = "#313244",
	rosewater = "#f5e0dc",
	flamingo = "#f2cdcd",
	peach = "#fab387",
	text = "#cdd6f4",
    active_tab = "#98BB6C",
}

local colorscheme = {
	foreground = tokynight.foreground,
	background = tokynight.background,
	cursor_bg = tokynight.cursor_bg,
	cursor_border = tokynight.cursor_border,
	cursor_fg = tokynight.cursor_fg,
	selection_bg = tokynight.selection_bg,
	selection_fg = tokynight.selection_fg,
	ansi = tokynight.ansi,
	brights = tokynight.brights,
	tab_bar = {
		background = "#000000",
		active_tab = {
			bg_color = tokynight.selection_bg,
			fg_color = tokynight.active_tab,
		},
		inactive_tab = {
			bg_color = tokynight.selection_bg,
			fg_color = tokynight.selection_fg,
		},
		inactive_tab_hover = {
			bg_color = tokynight.selection_bg,
			fg_color = tokynight.selection_fg,
		},
		new_tab = {
			bg_color = tokynight.background,
			fg_color = tokynight.foreground,
		},
		new_tab_hover = {
			bg_color = tokynight.mantle,
			fg_color = tokynight.text,
			italic = true,
		},
	},
	visual_bell = tokynight.surface0,
	indexed = {
		[16] = tokynight.peach,
		[17] = tokynight.rosewater,
	},
	scrollbar_thumb = tokynight.surface2,
	split = tokynight.overlay0,
	compose_cursor = tokynight.flamingo, -- nightbuild only
}

return colorscheme
