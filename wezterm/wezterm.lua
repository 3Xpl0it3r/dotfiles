local wezterm = require("wezterm")
local themes = require("themes.custom")
local keybindings = require("config.key-bindings")
local launch_menu = require("config.launch-menu")
local ssh_domains = require("config.ssh-domains")
local shell = require("config.shell")

-- require("config.right-status").setup()
require("config.notify").setup()
require("config.tab-title").setup()

local font_family = {
	agave = "agave Nerd Font",
	agave_mono = "agave Nerd Font Mono",
	firacode = "FiraCode Nerd Font",
	recursive = "Recursive",
	comic = "Comic Code",
}

wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
	window:gui_window():maximize()
end)



return {
	-- fonts
	font = wezterm.font(font_family.firacode, { bold = true }),
	font_size = 14,
	term = "xterm-256color",

	-- colour scheme
	colors = themes,

	-- background
	--
	-- window_background_opacity = 1.0,
	-- window_background_image = wezterm.config_dir .. "/images/bg1.jpg",
	window_background_image_hsb = {
		-- Darken the background image by reducing it to 1/3rd
		brightness = 0.3,

		-- You can adjust the hue by scaling its value.
		-- a multiplier of 1.0 leaves the value unchanged.
		hue = 1.0,

		-- You can adjust the saturation also.
		saturation = 1.0,
	},
	background = {
		--[[ {
			source = { File = wezterm.config_dir .. "/images/bg" .. 3 ..".jpg" },
		}, ]]
		{
			source = { Color = themes.background },
			height = "100%",
			width = "100%",
			opacity = 1.0,
			horizontal_align = "Center",
		},
	},

	-- scroll bar
	enable_scroll_bar = true,
	-- How many lines of scrollback you want to retain per tab
	scrollback_lines = 10000,

	-- status
	status_update_interval = 200,

	-- tab bar
	enable_tab_bar = true,
	hide_tab_bar_if_only_one_tab = false,
	use_fancy_tab_bar = false,
	tab_max_width = 25,
	show_tab_index_in_tab_bar = false,
	switch_to_last_active_tab_when_closing_tab = true,

	-- window
	window_padding = {
		left = 5,
		right = 10,
		top = 12,
		bottom = 7,
	},
	window_close_confirmation = "NeverPrompt",
	window_frame = {
		active_titlebar_bg = "#090909",
		font = wezterm.font(font_family.agave, { bold = true }),
		font_size = 9,
	},
	automatically_reload_config = true,
	inactive_pane_hsb = { saturation = 1.0, brightness = 1.0 },
	-- window_background_opacity = 0.9,

	-- keybindings
	disable_default_key_bindings = false,
	keys = keybindings,

	-- mousebindings
	mouse_bindings = {
		-- Ctrl-click will open the link under the mouse cursor
		{
			event = { Up = { streak = 1, button = "Left" } },
			mods = "CTRL",
			action = wezterm.action.OpenLinkAtMouseCursor,
		},
	},

	-- shells
	default_prog = shell,
	launch_menu = launch_menu,

	-- ssh
	ssh_domains = ssh_domains,

	-- wsl
	wsl_domains = {
		{
			name = "WSL:Ubuntu",
			distribution = "MacOS",
			username = "l0calh0st",
			default_cwd = "/home/kevin",
			default_prog = { "zsh" },
		},
	},
}
