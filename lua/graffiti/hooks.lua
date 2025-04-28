local server = require("graffiti.server")
local M = {}

local group = vim.api.nvim_create_augroup("Graffiti", { clear = true })

function M.create_hooks()
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = server.move_cursor,
	})

	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = server.move_cursor,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "TextYankPost" }, {
		group = group,
		callback = server.edit_document,
	})
end

function M.clear_hooks()
	vim.api.nvim_clear_autocmds({ group = group })
end

return M
