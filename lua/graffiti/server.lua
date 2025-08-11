local Path = require("plenary.path")

local M = {}

M.server_job = nil
M.server_name = ""
M.server_version = ""
M.buffer = ""

M.default_state = {
	client_id = "",
	requests = {},
	cursors = {},
}

M.state = {
	client_id = "",

	---@class RequestBase
	---@field method string
	---@field params table
	---
	---@type table<string, Request>
	requests = {},

	---@class DocumentPosition
	---@field line number
	---@field column number
	---
	---@class DocumentLocation
	---@field uri string
	---@field pos DocumentPosition
	---
	--- key is client_id
	---@type table<string, DocumentLocation>
	cursors = {},
}

local config = require("graffiti.config").config

-- Create or get the namespace for the virtual cursor
local virtual_cursor_ns = vim.api.nvim_create_namespace("graffiti.virtual_cursor")

local function file_exists(uri)
	local path = Path:new(uri)
	return path:exists() and path:is_file()
end

local function get_relative_path(buf)
	local path = vim.api.nvim_buf_get_name(buf)
	local relative_path = vim.fn.fnamemodify(path, ":." .. vim.fn.getcwd())
	return relative_path:gsub("\\", "/")
end

local function clear_marks()
	vim.notify("clearing virtual cursors")

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		vim.notify("clearing " .. vim.inspect(buf))
		if vim.api.nvim_buf_is_loaded(buf) then
			vim.api.nvim_buf_clear_namespace(buf, virtual_cursor_ns, 0, -1)
		end
	end
end

-- Function to find a buffer that matches a given relative path
local function find_buf_by_relative_path(relative_path)
	-- Get the current working directory
	local cwd = vim.fn.getcwd()

	-- Iterate through all open buffers
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		-- Get the full path of the buffer
		local buf_path = vim.api.nvim_buf_get_name(buf)
		buf_path = vim.fn.fnamemodify(buf_path, ":p"):gsub("\\", "/")

		local full_path = vim.fn.fnamemodify(cwd .. "/" .. relative_path, ":p"):gsub("\\", "/")

		-- Check if the buffer path matches the relative path
		if buf_path == full_path then
			return buf -- Return the buffer number if a match is found
		end
	end

	return nil -- Return nil if no matching buffer is found
end

local function clear_namespace(ns_id)
	local buffers = vim.api.nvim_list_bufs()

	for _, buf in ipairs(buffers) do
		-- Clear any existing extmarks in the namespace
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	end
end

-- Function to write content to a file given a URI
local function write_content_to_file(uri, content)
	vim.notify("123 Writing content to file: " .. uri)
	-- Check if the buffer is open
	local bufnr = vim.fn.bufnr(uri, false)

	if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
		local new_lines = vim.split(content, "\n")

		-- If the buffer is open, set the content and write
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
	else
		vim.notify("126 Buffer is not open and loaded")
		-- If the buffer is not open, write directly to the file
		local file = io.open(uri, "w")
		if file then
			file:write(content)
			file:close()
		else
			vim.notify("Failed to open file: " .. uri, vim.log.levels.ERROR)
		end
	end
end

function M.reset_state()
	M.server_name = ""
	M.server_version = ""
	M.state = M.default_state
	M.buffer = ""
end

---@param mode "host" | "connect"
---@param fingerprint string?
function M.start_server(mode, fingerprint)
	vim.notify(vim.inspect(mode))
	vim.notify(vim.inspect(fingerprint))
	if mode == "connect" and (fingerprint == nil or fingerprint == "") then
		vim.ui.input({
			prompt = "enter fingerprint",
		}, function(input)
			fingerprint = input
		end)

		while fingerprint == nil do
			vim.wait(50)
		end
	end

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
	-- Add new data to buffer
	for _, line in ipairs(data) do
		if line ~= "" then
			M.buffer = M.buffer .. line .. "\n"
		end
	end

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
			if object.id then
				if not M.state.requests[object.id] then
					M.handle_request(object.id, object.method, object.params)
				else
					M.handle_response(object.id, object.result)
				end
			end

			if object.method then
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
	local version = vim.version()

	local message = {
		id = M.generate_id(),
		jsonrpc = "2.0",
		method = "initialize",
		params = {
			process_id = vim.fn.getpid(),
			editor_info = {
				name = vim.v.progname,
				version = version.major .. "." .. version.minor .. "." .. version.patch,
			},
			root_path = vim.fn.getcwd(),
		},
	}

	M.send_message(message, nil, true)
end

function M.document_location(buf, line, column)
	local uri = get_relative_path(buf)

	local message = {
		jsonrpc = "2.0",
		method = "document/location",
		params = {
			location = {
				uri = uri,
				pos = {
					line = line,
					column = column,
				},
			},
		},
	}

	M.send_message(message, nil, false)
end

function M.cwd_changed(id)
	local message = {
		id = id,
		jsonrpc = "2.0",
		method = "cwd_changed",
	}

	M.send_message(message, nil, false)
end

function M.move_cursor()
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()

	local cursor_pos = vim.api.nvim_win_get_cursor(win)

	local uri = get_relative_path(buf)
	local line = cursor_pos[1] - 1 -- line is 1-indexed in nvim
	local column = cursor_pos[2] -- column is 0-indexed in nvim

	local location = {
		uri = uri,
		pos = {
			line = line,
			column = column,
		},
	}

	M.state.cursors[M.state.client_id] = location

	local message = {
		jsonrpc = "2.0",
		method = "move_cursor",
		params = {
			location = location,
		},
	}

	M.send_message(message, nil, false)
end

function M.edit_document()
	vim.notify("Editing document")

	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local content = table.concat(lines, "\n")

	local message = {
		jsonrpc = "2.0",
		method = "document/edit",
		params = {
			mode = "full", -- "full" or "incremental"
			uri = get_relative_path(buf),
			content = content,
		},
	}

	M.send_message(message, nil, false)
end

function M.document_edited_full(client_id, uri, content)
	if not file_exists(uri) then
		return
	end

	vim.notify("Document edited full by: " .. vim.inspect(client_id))
	write_content_to_file(uri, content)
end

function M.shutdown()
	vim.notify("Shutting down server")

	-- Clear any existing extmarks in the namespace
	clear_namespace(virtual_cursor_ns)

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

function M.handle_request(id, method, params)
	vim.notify("Request for method: " .. method)
	if method == "document/location" then
		vim.notify("Document location request")

		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_get_current_win()

		local cursor_pos = vim.api.nvim_win_get_cursor(win)

		local line = cursor_pos[1] - 1 -- line is 1-indexed in nvim
		local column = cursor_pos[2] -- column is 0-indexed in nvim

		M.document_location(buf, line, column)
	end

	if method == "initial_file_uri" then
		vim.notify("Changing cwd: " .. params.cwd)
		vim.fn.chdir(params.cwd)

		vim.notify("Initial file is: " .. vim.inspect(params.initial_file_uri))
		if params.initial_file_uri then
			vim.notify("Opening initial file: " .. params.initial_file_uri)
			local file = params.initial_file_uri
			vim.cmd("edit! " .. file)
			-- local buf = vim.api.nvim_create_buf(true, false)
			-- vim.api.nvim_buf_set_name(buf, file)
			-- vim.api.nvim_set_current_buf(buf)
		end

		M.cwd_changed(id)
	end

	if method == "shutdown" then
		vim.notify("Server ready for shutdown")
		M.exit()
		clear_marks()
		require("graffiti.hooks").clear_hooks()
	end
end

function M.handle_response(id, result)
	if not M.state.requests[id] then
		vim.notify("Received response for unknown request: " .. vim.inspect(id), vim.log.levels.ERROR)
		return
	end

	local request = M.state.requests[id]

	if request.method == "initialize" then
		M.server_name = result.server_info.name
		M.server_version = result.server_info.version
		vim.notify("Server initialized: " .. M.server_name .. " " .. M.server_version)
		M.state.client_id = result.client_id
		M.initialized()
		return
	end

	if request.method == "shutdown" then
		vim.notify("Server ready for shutdown")
		M.exit()
		clear_marks()
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
	if method == "fingerprint_generated" then
		M.display_fingerprint(params.fingerprint)
		return
	end

	if method == "cursor_moved" then
		M.handle_cursor_moved(params.client_id, params.location)
	end

	if method == "document/edited" then
		if params.mode == "full" then
			M.document_edited_full(params.client_id, params.uri, params.content)
		elseif params.mode == "incremental" then
			vim.notify("Incremental edit not implemented yet", vim.log.Levels.WARN)
		else
			vim.notify("Unknown edit mode: " .. vim.inspect(params.mode), vim.log.Levels.ERROR)
		end
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
	if not file_exists(location.uri) then
		return
	end

	local old_location = M.state.cursors[client_id]
	M.state.cursors[client_id] = location

	if old_location and old_location.uri ~= location.uri then
		local buf = find_buf_by_relative_path(old_location.uri)

		if buf ~= nil then
			vim.api.nvim_buf_clear_namespace(buf, virtual_cursor_ns, 0, -1)
		end
	end

	-- Function to update the virtual cursor position with a background color
	local function update_virtual_cursor_with_bg(buf, line, col)
		-- Clear any existing extmarks in the namespace
		vim.api.nvim_buf_clear_namespace(buf, virtual_cursor_ns, 0, -1)

		-- get the line at the specified line number
		local current_line = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)

		local line_length = #current_line[1]

		if line_length == 0 then
			vim.api.nvim_buf_set_extmark(buf, virtual_cursor_ns, line, 0, {
				virt_text = { { " ", "VirtualCursor" } },
				virt_text_pos = "overlay",
			})

			return
		end

		-- clamp the column to the line length and account for an empty line
		col = math.min(col, line_length)

		-- Apply the highlight to the specified range
		vim.api.nvim_buf_add_highlight(buf, virtual_cursor_ns, "VirtualCursor", line, col, col + 1)

		-- Set a new extmark at the specified line and column with the highlight
		-- vim.api.nvim_buf_set_extmark(buf, ns_id, line, col, {
		-- 	hl_group = "VirtualCursor", -- Use the custom highlight group
		-- 	end_col = line_length > 0 and col + 1 or 0, -- Highlight a single character
		-- })
	end

	vim.notify(location.uri)
	local buf = find_buf_by_relative_path(location.uri)

	if buf then
		update_virtual_cursor_with_bg(buf, location.pos.line, location.pos.column)
	end
end

return M
