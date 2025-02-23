local M = {}

M.server_job = nil

local config = require("graffiti.config").config

function M.start_server()
	if M.server_job then
		vim.notify("Server is already running!")
		return
	end

	M.server_job = vim.fn.jobstart({
		config.server_executable,
		"--log-file",
		config.log_file,
	}, {
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.schedule(function()
						vim.notify("Graffiti: " .. line)
					end)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					vim.schedule(function()
						vim.notify("Graffiti Error: " .. line, vim.log.levels.ERROR)
					end)
				end
			end
		end,
		on_exit = function()
			M.server_job = nil
			vim.notify("Server stopped")
		end,
	})

	if M.server_job == 0 or M.server_job == -1 then
		vim.notify("Failed to start server")
		M.server_job = nil
	else
		vim.notify("Server started")
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

-- Using vim's built-in random
function M.generate_id()
	return tostring(vim.loop.hrtime()) -- nanosecond timestamp
end

function M.send_message(message, headers)
	if not M.server_job then
		vim.notify("No server running!")
		return
	end

	vim.notify("1")
	-- Convert message to JSON
	local json = vim.json.encode(message)

	vim.notify("2")
	-- Build headers
	local header_string = ""
	headers = headers or {}

	vim.notify("3")

	-- Always include content-type
	headers["content-type"] = "application/vscode-jsonrpc;charset=utf-8"

	vim.notify("4")
	-- Add each header
	for key, value in pairs(headers) do
		header_string = header_string .. string.format("%s: %s\r\n", key, value)
	end

	-- Always include content-length as the last header
	header_string = header_string .. string.format("%s: %s\r\n", "content-length", #json)

	vim.notify(header_string)
	vim.notify("5")

	-- Add the double newline separator
	header_string = header_string .. "\r\n"

	vim.notify("6")
	local message_string = header_string .. json

	vim.notify("7")
	vim.notify("New Message: " .. message_string)
	vim.notify("8")

	-- Send headers followed by content
	vim.fn.chansend(M.server_job, message_string)
	vim.notify("9")
end

function M.initialize()
	vim.notify("Initializing server")
	local version = vim.version()

	local message = {
		id = M.generate_id(),
		jsonrpc = "2.0",
		method = "initialize",
		params = {
			processId = vim.fn.getpid(),
			clientInfo = {
				name = vim.v.progname,
				version = version.major .. "." .. version.minor .. "." .. version.patch,
			},
			rootPath = vim.fn.getcwd(),
		},
	}

	-- You can add additional headers if needed
	local headers = {
		-- Example: "custom-header": "value"
	}

	vim.notify("Sending initialize message")
	M.send_message(message, headers)
end

return M
