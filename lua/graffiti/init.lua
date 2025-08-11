local M = {}

function M.setup(opts)
	require("graffiti.config").configure(opts)

	vim.api.nvim_create_user_command("GraffitiHost", function()
		require("graffiti.server").start_server("host")
		require("graffiti.hooks").create_hooks()
	end, {})

	vim.api.nvim_create_user_command("GraffitiJoin", function(options)
		require("graffiti.server").start_server("connect", options.args)
		require("graffiti.hooks").create_hooks()
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("GraffitiStop", function()
		require("graffiti.server").stop_server()
		require("graffiti.hooks").clear_hooks()
	end, {})

	vim.api.nvim_create_user_command("GraffitiKill", function()
		require("graffiti.server").kill_server()
		require("graffiti.hooks").clear_hooks()
	end, {})

	vim.api.nvim_create_user_command("GraffitiShow", function()
		local server = require("graffiti.server")
		vim.notify("Server name: " .. server.server_name)
		vim.notify("Server version: " .. server.server_version)
		vim.notify("State: " .. vim.inspect(server.state))
	end, {})

	vim.api.nvim_create_user_command("GraffitiRequestFingerprint", function()
		require("graffiti.server").request_fingerprint()
	end, {})
end

return M
