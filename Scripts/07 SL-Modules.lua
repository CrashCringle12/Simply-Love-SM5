function GetModuleEntries()
	local root = "/" .. THEME:GetCurrentThemeDirectory():gsub("^/+", "") .. "Modules/"
	local files = FILEMAN:GetDirListing(root)
	table.sort(files)
	local entries = {}
	for _, file in ipairs(files) do
		file = file:gsub("/$", "")
		local path = root .. file
		local entry, directory
		if (file:match("[^.]+$") or ""):lower() == "lua" then
			entry = path
		elseif FILEMAN:DoesFileExist(path .. "/default.lua") then
			entry, directory = path .. "/default.lua", path .. "/"
		elseif FILEMAN:DoesFileExist(path .. "/" .. file .. ".lua") then
			entry, directory = path .. "/" .. file .. ".lua", path .. "/"
		end
		if entry then entries[#entries+1] = { Name=file, Path=entry, Directory=directory } end
	end
	return entries
end
