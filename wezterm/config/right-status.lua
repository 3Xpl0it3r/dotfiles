local wezterm = require("wezterm")
local lume = require("utils.lume")
local default_color = require("themes.colors.tokyonight")
local M = {}

M.separator_char = " "

local icons = {
	host = "",
	dir = "",
	date = "",
	time = "",
	battery = "",
}

M.colors = {
    date = {
        fg = default_color.peach,
        bg = default_color.background,
    },
    battery = {
        fg = default_color.rosewater,
        bg = default_color.background,

    },
    host = {
        fg = default_color.ansi[5],
        bg = default_color.background,
    },
    workdir = {
        fg = default_color.ansi[6],
        bg = default_color.background,
    },
    separator = {
        fg = default_color.ansi[8],
        bg = default_color.background,
    },
}

M.cells = {} -- wezterm FormatItems (ref: https://wezfurlong.org/wezterm/config/lua/wezterm/format.html)

M.push = function(text, icon, fg, bg, separate)
	table.insert(M.cells, { Foreground = { Color = fg } })
	table.insert(M.cells, { Background = { Color = bg } })
	table.insert(M.cells, { Attribute = { Intensity = "Bold" } })
	table.insert(M.cells, { Text = icon .. " " .. text .. " " })

	if separate then
		table.insert(M.cells, { Foreground = { Color = M.colors.separator.fg } })
		table.insert(M.cells, { Background = { Color = M.colors.separator.bg } })
		table.insert(M.cells, { Text = M.separator_char })
	end

	table.insert(M.cells, "ResetAttributes")
end

M.strip_home_name = function(text)
	local username = os.getenv("USER")
	local os = require("utils.get_os_name").get_os_name()
	if os == "Mac" then
		return text:gsub("/Users/" .. username, "~")
	elseif os == "Linux" then
		return text:gsub("/home/" .. username, "~")
	end

	return text
end

M.set_work_dir = function(window, pane)
	local uri = pane:get_current_working_dir()

	if not uri then
		return
	end

	local cwd_uri = uri:sub(8)
	local slash = cwd_uri:find("/")

	if not slash then
		return
	end
	M.push(M.strip_home_name(cwd_uri), icons.dir, M.colors.workdir.fg, M.colors.workdir.bg, true)
end

M.set_hostname = function()
	local hostname = wezterm.hostname()

	M.push(hostname, icons.host, M.colors.host.fg, M.colors.host.bg, true)
end

M.set_date = function()
	local date = wezterm.strftime("%a %b %-d")
	local time = wezterm.strftime("%H:%M")

	M.push(date, icons.date, M.colors.date.fg, M.colors.date.bg, true)
	M.push(time, icons.time, M.colors.date.fg, M.colors.date.bg, true)
end

M.set_battery = function()
	-- ref: https://wezfurlong.org/wezterm/config/lua/wezterm/battery_info.html
	local discharging_icons = { "", "", "", "", "", "", "", "", "", "" }
	local charging_icons = { "", "", "", "", "", "", "", "", "", "" }

	local charge = ""
	local icon = ""

	for _, b in ipairs(wezterm.battery_info()) do
		local idx = lume.clamp(lume.round(b.state_of_charge * 10), 1, 10)
		charge = string.format("%.0f%%", b.state_of_charge * 100)

		if b.state == "Charging" then
			icon = charging_icons[idx]
		else
			icon = discharging_icons[idx]
		end
	end

	M.push(charge, icon, M.colors.battery.fg, M.colors.battery.bg, false)
end

M.setup = function()
	wezterm.on("format-window-title", function(tab, pane, tabs, panes, config)
		local zoomed = ""
		if tab.active_pane.is_zoomed then
			zoomed = "[Z] "
		end

		local index = ""
		if #tabs > 1 then
			index = string.format("[%d/%d] ", tab.tab_index + 1, #tabs)
		end

		local clean_title = M.strip_home_name(tab.active_pane.title)
		return zoomed .. index .. clean_title
	end)
	wezterm.on("update-right-status", function(window, pane)
		M.cells = {}
		M.set_hostname()
		M.set_work_dir(window, pane)
		M.set_date()
		M.set_battery()

		window:set_right_status(wezterm.format(M.cells))
	end)
end
return M
