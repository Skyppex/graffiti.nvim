local M = {}

M.default_config = {
	server_executable = "graffiti-rs",
	server_log_file = vim.fn.stdpath("data") .. "/graffiti-server.log",
	client_log_file = vim.fn.stdpath("data") .. "/graffiti-client.log",
	host = "127.0.0.1",
	port = 7777,
}

M.config = {}

function M.configure(opts)
	M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})
end

return M
