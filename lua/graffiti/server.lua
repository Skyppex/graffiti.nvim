local M = {}

M.server_job = nil
M.server_name = ""
M.server_version = ""
M.buffer = ""

M.default_state = {
	requests = {},
	cursors = {},
}

M.state = {
	---@class RequestBase
	---@field method string
	---@field params table
	---
	---@type table<string, Request>
	requests = {},

	---@class DocumentLocation
	---@field uri string
	---@field line number
	---@field column number
	---
	--- key is client_id
	---@type table<string, DocumentLocation>
	cursors = {},
}

local config = require("graffiti.config").config

function M.reset_state()
	M.server_name = ""
	M.server_version = ""
	M.state = M.default_state
	M.buffer = ""
end

---@param mode "host" | "connect"
---@param fingerprint string?
function M.start_server(mode, fingerprint)
	vim.notify("Starting server in " .. mode .. " mode")
	if M.server_job then
		vim.notify("Server is already running!")
		return
	end

	local cmd = {}

	if mode == "connect" then
		cmd = {
			config.server_executable,
			-- "-l",
			"--log-file",
			config.client_log_file,
			mode,
			fingerprint,
		}
	else
		cmd = {
			config.server_executable,
			-- "-l",
			"--log-file",
			config.server_log_file,
			mode,
		}
	end

	vim.notify(vim.inspect(cmd))

	M.server_job = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			M.parse_message(data)
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.notify("Server Error: " .. line, vim.log.levels.ERROR)
				end
			end
		end,
		on_exit = function()
			M.server_job = nil
			M.reset_state()
			vim.notify("Server stopped")
		end,
	})

	if M.server_job == 0 or M.server_job == -1 then
		vim.notify("Failed to start server")
		M.server_job = nil
	else
		vim.notify("Server started")
	end

	M.initialize()
end

function M.stop_server()
	if M.server_job then
		M.shutdown()
	else
		vim.notify("No server running!")
	end
end

function M.kill_server()
	if M.server_job then
		vim.fn.jobstop(M.server_job)
		M.server_job = nil
	else
		vim.notify("No server running!")
	end
end

function M.request_fingerprint()
	local message = {
		id = M.generate_id(),
		jsonrpc = "2.0",
		method = "request_fingerprint",
	}

	M.send_message(message, nil, true)
end

-- Using vim's built-in random
function M.generate_id()
	return tostring(vim.loop.hrtime()) -- nanosecond timestamp
end

---@param message table
---@param headers? table<string, string> Used to add custom headers to the message. { "header": "value", ... }
function M.send_message(message, headers, log)
	if not M.server_job then
		vim.notify("No server running!")
		return
	end

	if message.id then
		M.state.requests[message.id] = {
			method = message.method,
			params = message.params,
		}
	end

	-- Convert message to JSON
	local json = vim.json.encode(message)

	-- Build headers
	local header_string = ""
	headers = headers or {}

	-- Always include content-type
	headers["content-type"] = "application/vscode-jsonrpc;charset=utf-8"

	-- Add each header
	for key, value in pairs(headers) do
		header_string = header_string .. string.format("%s: %s\r\n", key, value)
	end

	-- Always include content-length as the last header
	header_string = header_string .. string.format("%s: %s\r\n", "content-length", #json)

	-- Add the double newline separator
	header_string = header_string .. "\r\n"

	local message_string = header_string .. json

	if log then
		vim.notify("New Message: " .. message_string)
	end

	-- Send headers followed by content
	vim.fn.chansend(M.server_job, message_string)
end

function M.parse_message(data)
	vim.notify("Received data: " .. vim.inspect(data))

	-- Add new data to buffer
	for _, line in ipairs(data) do
		if line ~= "" then
			M.buffer = M.buffer .. line .. "\n"
		end
	end

	vim.notify("Buffer: " .. M.buffer)

	-- Try to parse a complete message
	while true do
		-- Look for headers end
		local headers_end = string.find(M.buffer, "\r\n\r\n")

		if not headers_end then
			return -- Need more data
		end

		-- Extract and parse headers
		local header_text = string.sub(M.buffer, 1, headers_end - 1)
		local headers = M.parse_headers(header_text)

		vim.notify("Headers: " .. vim.inspect(headers))

		-- Check for content-length
		local content_length = tonumber(headers["content-length"])

		if not content_length then
			-- Invalid message, clear buffer
			vim.notify("Invalid message: missing content-length header", vim.log.levels.ERROR)
			M.buffer = ""
			return
		end

		local message_end = headers_end + 4 + content_length

		-- Check if we have the full message
		if #M.buffer < message_end then
			return -- Need more data
		end

		-- Extract the JSON content
		local content = string.sub(M.buffer, headers_end + 4, message_end)

		-- Try to parse and handle the message
		local ok, object = pcall(vim.json.decode, content)

		if ok then
			-- You can use both headers and json here
			vim.notify("Client received message: " .. vim.inspect({
				headers = headers,
				content = object,
			}))

			if object.id then
				M.handle_response(object.id, object.result)
			end

			if object.method then
				vim.notify("Handling notification")
				M.handle_notification(object.method, object.params)
			end
		end

		-- Remove processed message from buffer
		M.buffer = string.sub(M.buffer, message_end + 1)
	end
end

function M.parse_headers(header_text)
	local headers = {}

	for line in header_text:gmatch("([^\r\n]+)") do
		local key, value = line:match("^%s*(%S+):%s*(.+)%s*$")
		if key then
			-- Store header keys in lowercase for consistency
			headers[key:lower()] = value
		end
	end

	return headers
end

function M.initialize()
	vim.notify("Initializing server")
	local version = vim.version()

	local message = {
		id = M.generate_id(),
		jsonrpc = "2.0",
		method = "initialize",
		params = {
			process_id = vim.fn.getpid(),
			client_info = {
				name = vim.v.progname,
				version = version.major .. "." .. version.minor .. "." .. version.patch,
			},
			root_path = vim.fn.getcwd(),
		},
	}

	M.send_message(message, nil, true)
end

function M.move_cursor()
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	local cursor_pos = vim.api.nvim_win_get_cursor(win)

	local line = cursor_pos[1] - 1 -- line is 1-indexed in nvim
	local column = cursor_pos[2] -- column is 0-indexed in nvim

	local message = {
		jsonrpc = "2.0",
		method = "move_cursor",
		params = {
			location = {
				uri = get_relative_path(buf),
				line = line,
				column = column,
			},
		},
	}

	M.send_message(message, nil, false)
end

function M.shutdown()
	vim.notify("Shutting down server")

	local message = {
		id = M.generate_id(),
		jsonrpc = "2.0",
		method = "shutdown",
	}

	M.send_message(message, nil, true)
end

function M.exit()
	vim.notify("Exiting server")

	local message = {
		jsonrpc = "2.0",
		method = "exit",
	}

	M.send_message(message, nil, true)
end

function M.handle_response(id, result)
	vim.notify("Handling response: " .. vim.inspect(id))

	if not M.state.requests[id] then
		vim.notify("Received response for unknown request: " .. vim.inspect(id), vim.log.levels.ERROR)
		return
	end

	local request = M.state.requests[id]

	vim.notify("Response for method: " .. request.method)

	if request.method == "initialize" then
		M.server_name = result.server_info.name
		M.server_version = result.server_info.version
		vim.notify("Server initialized: " .. M.server_name .. " " .. M.server_version)
		M.initialized()
		return
	end

	if request.method == "shutdown" then
		vim.notify("Server ready for shutdown")
		M.exit()
		require("graffiti.hooks").clear_hooks()
		return
	end

	if request.method == "fingerprint" then
		vim.notify("Fingerprint received")
		M.display_fingerprint(result.fingerprint)
		return
	end
end

function M.handle_notification(method, params)
	vim.notify("Handling response: " .. method)
	vim.notify("Params: " .. vim.inspect(params))

	if method == "fingerprint_generated" then
		M.display_fingerprint(params.fingerprint)
		return
	end

	if method == "cursor_moved" then
		M.handle_cursor_moved(params.client_id, params.location)
	end
end

function M.initialized()
	vim.notify("Initialized server")

	local message = {
		jsonrpc = "2.0",
		method = "initialized",
	}

	M.send_message(message, nil, true)
end

function M.display_fingerprint(fingerprint)
	-- Open a horizontal split and create a new buffer
	vim.cmd("split")

	-- Get the current buffer number
	local buf = vim.api.nvim_create_buf(false, true)

	-- Insert text into the buffer
	local lines = {
		fingerprint,
	}

	-- Set the lines in the buffer
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Set the current buffer to the newly created one
	vim.api.nvim_set_current_buf(buf)
end

---@param client_id string
---@param location DocumentLocation
function M.handle_cursor_moved(client_id, location)
	M.state.cursors[client_id] = location

	-- Define a custom highlight group for the virtual cursor
	vim.cmd("highlight VirtualCursor guibg=#FFD700") -- Gold background color

	-- Function to update the virtual cursor position with a background color
	local function update_virtual_cursor_with_bg(buf, line, col)
		-- Create or get the namespace for the virtual cursor
		local ns_id = vim.api.nvim_create_namespace("virtual_cursor_bg")

		-- Clear any existing extmarks in the namespace
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- get the line at the specified line number
		local current_line = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)

		local line_length = #current_line[1]

		-- clamp the column to the line length and account for an empty line
		col = math.min(col, line_length)

		vim.notify("Column: " .. col)

		-- Apply the highlight to the specified range
		vim.api.nvim_buf_add_highlight(buf, ns_id, "VirtualCursor", line, col, col + 1)

		-- Set a new extmark at the specified line and column with the highlight
		-- vim.api.nvim_buf_set_extmark(buf, ns_id, line, col, {
		-- 	hl_group = "VirtualCursor", -- Use the custom highlight group
		-- 	end_col = line_length > 0 and col + 1 or 0, -- Highlight a single character
		-- })
	end

	local buf = find_buf_by_relative_path(location.uri)

	-- Example usage: Update the virtual cursor
	update_virtual_cursor_with_bg(buf, location.line, location.column)
end

function get_relative_path(buf)
	local path = vim.api.nvim_buf_get_name(buf)
	local relative_path = vim.fn.fnamemodify(path, ":." .. vim.fn.getcwd())
	return relative_path:gsub("\\", "/")
end

function get_buf_bytes(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

	local byte_array = {}

	for _, line in ipairs(lines) do
		for i = 1, #line do
			table.insert(byte_array, string.byte(line, i))
		end
	end

	return byte_array
end

-- Function to find a buffer that matches a given relative path
function find_buf_by_relative_path(relative_path)
	-- Get the current working directory
	local cwd = vim.fn.getcwd()

	-- Iterate through all open buffers
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		-- Get the full path of the buffer
		local buf_path = vim.api.nvim_buf_get_name(buf)
		buf_path = vim.fn.fnamemodify(buf_path, ":p"):gsub("\\", "/")

		local full_path = vim.fn.fnamemodify(cwd .. "/" .. relative_path, ":p"):gsub("\\", "/")

		vim.notify("Buf path" .. buf_path)
		vim.notify("Full path" .. full_path)

		-- Check if the buffer path matches the relative path
		if buf_path == full_path then
			vim.notify("FOUND MATCHING BUFFER")
			return buf -- Return the buffer number if a match is found
		end
	end

	vim.notify("NO MATCHING BUFFER")

	return nil -- Return nil if no matching buffer is found
end

return M
