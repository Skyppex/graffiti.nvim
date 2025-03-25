local server = require("graffiti.server")
local M = {}

local group = vim.api.nvim_create_augroup("Graffiti", { clear = true })

function M.create_hooks()
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = server.move_cursor,
	})
end

function M.clear_hooks()
	vim.api.nvim_clear_autocmds({ group = group })
end

return M
