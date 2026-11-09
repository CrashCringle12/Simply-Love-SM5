local api = "https://api.github.com/repos/Simply-Love/Simply-Love-Modules"
local provider = {}

local function NewOperation()
	local operation = { cancelled=false }
	function operation:Cancel()
		self.cancelled = true
		if self.request then self.request:Cancel() end
	end
	function operation:Request(url, accept, downloadFile, callback)
		self.request = NETWORK:HttpRequest{
			url=url,
			headers={ ["Accept"]=accept },
			downloadFile=downloadFile,
			connectTimeout=10,
			transferTimeout=60,
			onResponse=function(response)
				self.request = nil
				if self.cancelled then return end
				if response.error then
					callback(nil, "NetworkError", tostring(response.error))
				elseif response.statusCode ~= 200 then
					local message = response.statusCode == 403 or response.statusCode == 429
					callback(nil, message and "GitHubLimit" or "HttpError", tostring(response.statusCode))
				else
					callback(response)
				end
			end
		}
	end
	return operation
end

-- Read literal metadata without running the module or evaluating expressions.
local function ReadString(source, position)
	local quote = source:sub(position, position)
	if quote == '"' or quote == "'" then
		local parts = {}
		local escapes = { n="\n", r="\r", t="\t", ['"']='"', ["'"]="'", ["\\"]="\\" }
		position = position + 1
		while position <= #source do
			local character = source:sub(position, position)
			if character == quote then return table.concat(parts), position+1 end
			if character == "\\" then
				position = position + 1
				character = source:sub(position, position)
				character = escapes[character] or character
			end
			parts[#parts+1] = character
			position = position + 1
		end
	else
		local equals = source:sub(position):match("^%[(=*)%[")
		if equals then
			local first = position + #equals + 2
			local finish = source:find("]" .. equals .. "]", first, true)
			if finish then
				return source:sub(first, finish-1):gsub("^\r?\n", ""), finish+#equals+2
			end
		end
	end
end

local function ReadHosts(source, position)
	if source:sub(position, position) ~= "{" then return end
	local hosts = {}
	position = position + 1
	while position <= #source do
		local space = source:sub(position):match("^[%s,]+")
		if space then
			position = position + #space
		elseif source:sub(position, position) == "}" then
			return hosts, position+1
		elseif source:sub(position, position+1) == "--" then
			local comment, finish = ReadString(source, position+2)
			position = comment and finish or (source:find("\n", position, true) or #source)+1
		else
			local host, finish = ReadString(source, position)
			if not host then return end
			hosts[#hosts+1] = host
			position = finish
		end
	end
end

local function ReadModuleInfo(source)
	local info = {}
	local fields = { Name=true, Description=true, Author=true, Version=true, Updated=true, RequiredHosts=true }
	local _, position = source:find("%f[%w_]ModuleInfo%s*=%s*{")
	if position then
		position = position + 1
		while position <= #source do
			local rest = source:sub(position)
			local space = rest:match("^[%s,]+")
			if space then
				position = position + #space
			elseif rest:sub(1, 2) == "--" then
				local comment, finish = ReadString(source, position+2)
				position = comment and finish or (source:find("\n", position, true) or #source)+1
			else
				local field, offset = rest:match("^([%a_][%w_]*)%s*=%s*()")
				if not field then break end
				local value, finish = ReadString(source, position+offset-1)
				if not value and field == "RequiredHosts" then
					value, finish = ReadHosts(source, position+offset-1)
				end
				if not value then break end
				if fields[field] then info[field] = value end
				position = finish
			end
		end
	end
	-- Also accept assignments such as t.ModuleInfo.Name = "My Module".
	for field in pairs(fields) do
		if not info[field] then
			local _, finish = source:find("ModuleInfo%." .. field .. "%s*=%s*")
			if finish then
				info[field] = ReadString(source, finish+1)
				if not info[field] and field == "RequiredHosts" then
					info[field] = ReadHosts(source, finish+1)
				end
			end
		end
	end
	return info
end

-- This is a source summary, not a permission check or a complete Lua analysis.
local function ReadUsage(source)
	local managers = {}
	local position = 1
	while position <= #source do
		local character = source:sub(position, position)
		if source:sub(position, position+1) == "--" then
			local comment, finish = ReadString(source, position+2)
			position = comment and finish or (source:find("\n", position, true) or #source)+1
		elseif character == '"' or character == "'" or character == "[" then
			local value, finish = ReadString(source, position)
			position = value and finish or position+1
		else
			local first, finish, name = source:find("([%a_][%w_]*)", position)
			if first == position then
				if name:match("^[A-Z_]+$") and type(_G[name]) == "userdata" then managers[name] = true end
				position = finish + 1
			else
				position = position + 1
			end
		end
	end
	local names = {}
	for name in pairs(managers) do names[#names+1] = name end
	table.sort(names)
	return { Managers=names, UsesNetwork=managers.NETWORK == true }
end

function provider.List(callback)
	local operation = NewOperation()
	operation:Request(api .. "/git/trees/main?recursive=1", "application/vnd.github+json", nil,
		function(response, error, detail)
			if not response then callback(nil, error, detail); return end
			local success, tree = pcall(JsonDecode, response.body)
			if not success or type(tree) ~= "table" or type(tree.tree) ~= "table" or tree.truncated then
				callback(nil, "InvalidCatalog")
				return
			end
			local modules = {}
			for _, file in ipairs(tree.tree) do
				if file.type == "blob" and file.mode ~= "120000" and file.path:match("%.lua$") then
					local folder, name = file.path:match("^([^/]+)/([^/]+)$")
					if not file.path:find("/", 1, true) or
						(folder and (name == "default.lua" or name == folder .. ".lua")) then
						modules[#modules+1] = {
							Id=folder or file.path, EntryPoint=file.path, Source=file.sha, Files={}
						}
					end
				end
			end
			for _, module in ipairs(modules) do
				for _, file in ipairs(tree.tree) do
					if file.type == "blob" and file.mode ~= "120000" and
						(file.path == module.EntryPoint or file.path:sub(1, #module.Id+1) == module.Id .. "/") then
						module.Files[#module.Files+1] = { Path=file.path, Source=file.sha }
					end
				end
				-- Install the entry point last so an incomplete download stays inactive.
				table.sort(module.Files, function(a, b)
					if a.Path == module.EntryPoint then return false end
					if b.Path == module.EntryPoint then return true end
					return a.Path < b.Path
				end)
			end
			table.sort(modules, function(a, b) return a.Id:lower() < b.Id:lower() end)
			local index = 1
			local function ReadNext()
				local module = modules[index]
				if not module then callback(modules); return end
				operation:Request(api .. "/git/blobs/" .. module.Source, "application/vnd.github.raw+json", nil,
					function(source)
						module.Info = source and ReadModuleInfo(source.body) or {}
						module.Usage = source and ReadUsage(source.body) or nil
						index = index + 1
						ReadNext()
					end)
			end
			ReadNext()
		end)
	return operation
end

function provider.Download(module, onFile, callback)
	local operation = NewOperation()
	local index = 1
	local function DownloadNext()
		local file = module.Files[index]
		if not file then callback(true); return end
		local filename = "module-browser-" .. file.Source
		operation:Request(api .. "/git/blobs/" .. file.Source, "application/vnd.github.raw+json", filename,
			function(response, error, detail)
				if not response then callback(false, error, detail); return end
				-- Download files only exist during the response callback.
				if not onFile(file.Path, "/Downloads/" .. filename, index, #module.Files) then
					callback(false, "WriteError")
					return
				end
				index = index + 1
				DownloadNext()
			end)
	end
	DownloadNext()
	return operation
end

return provider
