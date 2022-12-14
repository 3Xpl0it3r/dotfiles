local get_os_name = require("utils.get_os_name")

if get_os_name.get_os_name() == "Windows" then
	return { "pwsh.exe" }
else
	-- return {"/bin/zsh", "-c", "/usr/local/bin/zellij"}
	return { "/bin/zsh" }
end
