local M = {}

function M.setup(opts)
	require("graffiti.config").configure(opts)

	vim.api.nvim_create_user_command("GraffitiHost", function()
		require("graffiti.server").start_server("host")
	end, {})

	vim.api.nvim_create_user_command("GraffitiShow", function()
		local state = require("graffiti.server")
		vim.notify("Server name: " .. state.server_name)
		vim.notify("Server version: " .. state.server_version)
	end, {})

	vim.api.nvim_create_user_command("GraffitiStop", function()
		require("graffiti.server").stop_server()
	end, {})

	vim.api.nvim_create_user_command("GraffitiKill", function()
		require("graffiti.server").kill_server()
	end, {})

	vim.api.nvim_create_user_command("GraffitiJoin", function()
		require("graffiti.server").start_server("connect")
	end)
end

return M
