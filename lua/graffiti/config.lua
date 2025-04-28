local M = {}

M.default_config = {
	server_executable = "graffiti-rs",
	server_log_file = vim.fn.stdpath("data") .. "/graffiti-server.log",
	client_log_file = vim.fn.stdpath("data") .. "/graffiti-client.log",
	host = "127.0.0.1",
	port = 7777,
	cursors = {
		hi1 = "#FFD700",
	},
}

M.config = {}

local function create_highlight_groups()
	-- Define a custom highlight group for the virtual cursor
	vim.cmd("highlight VirtualCursor guibg=" .. M.config.cursors.hi1)
end

function M.configure(opts)
	M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})
	create_highlight_groups()
end

return M
