local M = {}

--- @class GraffitiOpts
--- @field server_executable string | fun(): string
--- @field server_log_file string | fun(): string
--- @field client_log_file string | fun(): string
--- @field authorized_keys string | fun(): string
--- @field client_key string | fun(): string
--- @field cursors GraffitiCursorOpts[] | fun(): GraffitiCursorOpts[]
---
--- @class GraffitiCursorOpts
--- @field hi1 string | fun(): string

--- @type GraffitiOpts
M.default_config = {
	server_executable = "graffiti-rs",
	server_log_file = vim.fn.stdpath("data") .. "/graffiti-server.log",
	client_log_file = vim.fn.stdpath("data") .. "/graffiti-client.log",
	authorized_keys = "~/.graffiti/authorized_keys",
	client_key = "~/.graffiti/id_25519",
	cursors = {
		hi1 = "#FFD700",
	},
}

M.config = {}

local function create_highlight_groups()
	-- Define a custom highlight group for the virtual cursor
	vim.cmd("highlight VirtualCursor guibg=" .. M.resolve({ "cursors", "hi1" }))
end

function M.configure(opts)
	M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})
	create_highlight_groups()
end

--- resolves a config option, invoking function-type configs automatically
--- @param path string[] path to config option
--- @return unknown -- value is typed based on config option type
function M.resolve(path)
	local current = M.config

	for _, step in ipairs(path) do
		current = current[step]
	end

	if type(current) == "function" then
		current = current()
	end

	return current
end

return M
