local M = {}

M.server_job = nil
M.server_name = ""
M.server_version = ""
M.buffer = ""

---@class Request
---@field method string
---@field params table
---
---@type table<string, Request>
M.requests = {}

local config = require("graffiti.config").config

function M.reset_state()
	M.server_name = ""
	M.server_version = ""
	M.requests = {}
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

	vim.notify("12347890")

	local cmd = {
		config.server_executable,
		"--log-file",
		config.log_file,
		mode,
	}

	vim.notify("1234789012374890")

	if mode == "connect" then
		vim.notify("Connecting to server with fingerprint")
		vim.notify(vim.inspect(fingerprint))
		table.insert(cmd, fingerprint)
	end

	vim.notify(vim.inspect(cmd))

	M.server_job = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			M.parse_message(data)
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.notify("Sever Error: " .. line, vim.log.levels.ERROR)
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

	M.send_message(message)
end

-- Using vim's built-in random
function M.generate_id()
	return tostring(vim.loop.hrtime()) -- nanosecond timestamp
end

---@param message table
---@param headers? table<string, string> Used to add custom headers to the message. { "header": "value", ... }
function M.send_message(message, headers)
	if not M.server_job then
		vim.notify("No server running!")
		return
	end

	if message.id then
		M.requests[message.id] = {
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

	vim.notify("New Message: " .. message_string)

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

function M.handle_response(id, result)
	vim.notify("Handling response: " .. vim.inspect(id))

	if not M.requests[id] then
		vim.notify("Received response for unknown request: " .. vim.inspect(id), vim.log.levels.ERROR)
		return
	end

	local request = M.requests[id]

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
	end
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

	M.send_message(message)
end

function M.initialized()
	vim.notify("Initialized server")

	local message = {
		jsonrpc = "2.0",
		method = "initialized",
	}

	M.send_message(message)
end

function M.shutdown()
	vim.notify("Shutting down server")

	local message = {
		id = M.generate_id(),
		jsonrpc = "2.0",
		method = "shutdown",
	}

	M.send_message(message)
end

function M.exit()
	vim.notify("Exiting server")

	local message = {
		jsonrpc = "2.0",
		method = "exit",
	}

	M.send_message(message)
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

return M
