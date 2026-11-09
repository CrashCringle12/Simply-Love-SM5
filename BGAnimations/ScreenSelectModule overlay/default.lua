local provider = LoadActor("./Provider.lua")
-- Temporary display data for testing the module browser.
local testData = {
	Enabled = true,
	-- Set true to show only the dummy entries, without contacting GitHub.
	OnlyDummyModules = false,

	-- Add as many entries as needed to test scrolling and text layout.
	-- Install/uninstall controls only toggle an in-memory state for these entries.
	-- Dummies can also set Usage={Managers={"GAMESTATE", "NETWORK"}, UsesNetwork=true}.
	-- Hosts go in Info.RequiredHosts={"api.example.com"}.
	Modules = {
		{
			Id = "ArrowCloud",
			Info = {
				Name = "Arrow Cloud Integration",
				Description = "This is a Test Description of Arrow Cloud. Yinga Finga Binga apple sauce",
				Author = "Wafles",
				Version = "1.2",
				Updated = "2026-10-24"
			}
		},
		{
			Id = "LongDescription",
			Installed = true,
			Info = {
				Name = "Rainbow Brackets",
				Description = "What will we do with the drunken sailor? MUSTARDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD ok testeroni bagels APPLESSSSSSSSSSSS. i am the cringle man.",
				Author = "Ghost of Christmas",
				Version = "2.0-preview",
				Updated = "2026-10-24"
			}
		}
	},

	-- Keys are the real module IDs shown by the provider (usually filenames).
	-- Only the fields specified here override the displayed information.
	-- Downloads and installation paths are unchanged.
	Overrides = {
		["ITLRankingSort.lua"] = {
			Name = "ITL Ranking Sort",
			Description = "Test description for an existing module.",
			Author = "Crash Cringle",
			Version = "2.3",
			Updated = "2026-05-12"
		},
		["ScreenSwitcher.lua"] = {
			Name = "Screen Switcher",
			Description = "Test description for an existing module.",
			Author = "Test Author",
			Version = "1.2",
			Updated = "2026-10-24"
		}
	}
}
local modules = {}
local selected = 1
local operation
local screen
local frame
local busy = false
local confirming = false
local active = true
local status = ""
local installDirectory = THEME:GetCurrentThemeDirectory() .. "Modules/"
local margin = 24
local top = 92
local rowHeight = 47
local rowCount = 6
local leftWidth = math.floor(_screen.w * 0.35)
local rightX = margin + leftWidth + 20
local rightWidth = _screen.w - rightX - margin
local rows = {}
local input

local function Text(key)
	return THEME:GetString("ScreenSelectModule", key)
end

local function Info(module, key)
	local value = module and module.Info and module.Info[key]
	return type(value) == "string" and value ~= "" and value or Text("Unknown")
end

local function Installed(module)
	if module.PreviewOnly then return module.TestInstalled end
	return FILEMAN:DoesFileExist(installDirectory .. module.EntryPoint)
end

local function ApplyTestData(list)
	if not testData.Enabled then return end
	for _, module in ipairs(list) do
		local overrides = testData.Overrides and testData.Overrides[module.Id]
		if overrides then
			module.Info = module.Info or {}
			for field, value in pairs(overrides) do module.Info[field] = value end
		end
	end
	for index = #(testData.Modules or {}), 1, -1 do
		local module = testData.Modules[index]
		table.insert(list, 1, {
			Id=module.Id, Info=module.Info or {}, Usage=module.Usage,
			PreviewOnly=true, TestInstalled=module.Installed or false
		})
	end
end

local function SafePath(path)
	if type(path) ~= "string" or path == "" or path:find("[\\:%c]") or
		path:sub(1, 1) == "/" or path:find("//", 1, true) then return false end
	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." then return false end
	end
	return true
end

local function ErrorText(error, detail)
	return Text(error or "InvalidCatalog") .. (detail and (" (" .. detail .. ")") or "")
end

local function SetVersionText(actor, module, showLabel)
	local version = Text("Version") .. ": " .. Info(module, "Version")
	local updated = " · " .. (showLabel and (Text("Updated") .. ": ") or "") .. Info(module, "Updated")
	actor:settext(version .. updated)
	actor:ClearAttributes()
	actor:AddAttribute(version:utf8len(), { Length=updated:utf8len(), Diffuse=color("#999999") })
end

local function Refresh()
	if not active or not frame then return end
	local first = math.max(1, math.min(selected-2, #modules-rowCount+1))
	for row, actors in ipairs(rows) do
		local index = first + row - 1
		local module = modules[index]
		actors.frame:visible(module ~= nil)
		if module then
			actors.index = index
			actors.background:diffuse(index == selected and GetCurrentColor() or color("#20252B"))
			actors.background:diffusealpha(index == selected and 0.3 or 1)
			actors.marker:visible(index == selected)
			local name = module.Info and module.Info.Name
			actors.name:settext(name and name ~= "" and name or module.Id:gsub("%.lua$", ""))
			SetVersionText(actors.version, module, false)
			local installed = Installed(module)
			actors.action:diffuse(installed and color("#F05B65") or color("#5CD98A"))
			if installed then
				actors.firstBar:xy(0, 0):zoomto(3, 15):rotationz(45)
				actors.secondBar:xy(0, 0):zoomto(3, 15):rotationz(-45)
			else
				actors.firstBar:xy(-4, 2):zoomto(3, 7):rotationz(-45)
				actors.secondBar:xy(2, -1):zoomto(3, 14):rotationz(45)
			end
		end
	end
	local module = modules[selected]
	frame:GetChild("Details"):visible(module ~= nil)
	if module then
		local details = frame:GetChild("Details")
		details:GetChild("Name"):settext(Info(module, "Name"))
		details:GetChild("Filename"):settext(module.EntryPoint or module.Id)
		details:GetChild("Author"):settext(Text("Author") .. ": " .. Info(module, "Author"))
		SetVersionText(details:GetChild("Version"), module, true)
		details:GetChild("Description"):settext(Info(module, "Description"))
		local usage = module.Usage
		local managers = usage and usage.Managers
		details:GetChild("Managers"):settext(Text("DetectedManagers") .. ": " ..
			(managers and (#managers > 0 and table.concat(managers, ", ") or Text("NoneDetected")) or Text("Unknown")))
		local declared = module.Info and module.Info.RequiredHosts
		if type(declared) == "string" then declared = { declared } end
		local hosts = {}
		for _, host in ipairs(type(declared) == "table" and declared or {}) do
			if type(host) == "string" and host ~= "" then hosts[#hosts+1] = "! " .. host end
		end
		local network = #hosts > 0 or (usage and usage.UsesNetwork)
		local hostText = #hosts > 0 and table.concat(hosts, "\n") or
			(network and ("! " .. Text("HostsUndeclared")) or Text("NotDeclared"))
		details:GetChild("Hosts"):settext(Text("RequiredHosts") .. ":\n" .. hostText)
		details:GetChild("Hosts"):diffuse(network and color("#F4BE63") or color("#999999"))
		local installed = Installed(module)
		details:GetChild("Install"):settext(busy and Text("Downloading") or
			(confirming and Text(installed and "ConfirmUninstall" or "ConfirmInstall") or
			Text(installed and "Uninstall" or "Install")))
	end
	frame:GetChild("Count"):settext(#modules > 0 and (selected .. " / " .. #modules) or "")
	frame:GetChild("Status"):settext(status)
end

local function LoadCatalog()
	busy = true
	status = Text("Loading")
	Refresh()
	local function ReceiveCatalog(list, error, detail)
		if not active then return end
		operation = nil
		busy = false
		if not list then
			modules = {}
			status = ErrorText(error, detail)
		else
			modules = {}
			for _, module in ipairs(list) do
				local valid = type(module) == "table" and type(module.Id) == "string" and
					SafePath(module.EntryPoint) and module.EntryPoint:match("%.lua$") and
					type(module.Files) == "table" and #module.Files > 0
				local hasEntryPoint = false
				for _, file in ipairs(valid and module.Files or {}) do
					valid = valid and SafePath(file.Path)
					hasEntryPoint = hasEntryPoint or file.Path == module.EntryPoint
				end
				if valid and hasEntryPoint then modules[#modules+1] = module end
			end
			status = ""
		end
		ApplyTestData(modules)
		selected = 1
		if list and #modules == 0 then status = Text("Empty") end
		Refresh()
	end
	if testData.Enabled and testData.OnlyDummyModules then
		ReceiveCatalog({})
	else
		operation = provider.List(ReceiveCatalog)
	end
end

local function ChangeInstallation()
	local module = modules[selected]
	if not module or busy then return end
	local installed = Installed(module)
	if installed and not module.PreviewOnly then
		status = Text("UninstallUnavailable")
		Refresh()
		return
	end
	if not installed and not module.PreviewOnly then
		for _, file in ipairs(module.Files) do
			if FILEMAN:DoesFileExist(installDirectory .. file.Path) then
				status = Text("ExistingFiles")
				Refresh()
				return
			end
		end
	end
	if not confirming then
		confirming = true
		status = Text(installed and "UninstallNotice" or "InstallNotice")
		Refresh()
		return
	end
	confirming = false
	if module.PreviewOnly then
		module.TestInstalled = not installed
		status = Text(installed and "UninstalledNotice" or "InstalledNotice")
		Refresh()
		return
	end
	busy = true
	status = Text("Downloading")
	Refresh()
	local staged = {}
	operation = provider.Download(module, function(path, download, index, total)
		if not active or not SafePath(path) then return false end
		local staging = "Save/ModuleBrowser/" .. path .. ".download"
		if not FILEMAN:Copy(download, staging) then return false end
		staged[path] = staging
		status = Text("Downloading") .. " " .. index .. " / " .. total
		Refresh()
		return true
	end, function(success, error, detail)
		if not active then return end
		operation = nil
		if success then
			-- Copy supporting files first. The loader cannot see a partial module.
			for _, file in ipairs(module.Files) do
				if file.Path ~= module.EntryPoint then
					success = staged[file.Path] and FILEMAN:Copy(staged[file.Path], installDirectory .. file.Path)
					if not success then break end
				end
			end
			if success then
				success = staged[module.EntryPoint] and
					FILEMAN:Copy(staged[module.EntryPoint], installDirectory .. module.EntryPoint)
			end
		end
		busy = false
		status = success and Text("InstalledNotice") or ErrorText(error or "WriteError", detail)
		Refresh()
	end)
end

input = function(event)
	if not active or SCREENMAN:GetTopScreen() ~= screen or screen:IsTransitioning() then return false end
	local button = event.GameButton
	local firstPress = event.type == "InputEventType_FirstPress"
	if not firstPress and event.type ~= "InputEventType_Repeat" then return false end
	if firstPress and not busy and event.DeviceInput and
		event.DeviceInput.button == "DeviceButton_left mouse button" then
		local x, y = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
		for _, actors in ipairs(rows) do
			if actors.frame:GetVisible() then
				local rowX, rowY = actors.frame:GetX(), actors.frame:GetY()
				if x >= rowX and x <= rowX+leftWidth and y >= rowY and y <= rowY+rowHeight-3 then
					if selected ~= actors.index then confirming = false end
					selected = actors.index
					status = ""
					if x >= rowX+leftWidth-28 then ChangeInstallation() else confirming = false end
					Refresh()
					return true
				end
			end
		end
	end
	if button == "Back" and firstPress then
		if confirming then
			confirming = false
			status = ""
			Refresh()
		else
			screen:RemoveInputCallback(input)
			screen:StartTransitioningScreen("SM_GoToPrevScreen")
		end
	elseif not busy then
		if (button == "MenuUp" or button == "Up") and #modules > 0 then
			selected = (selected-2) % #modules + 1
			confirming = false
			status = ""
			Refresh()
		elseif (button == "MenuDown" or button == "Down") and #modules > 0 then
			selected = selected % #modules + 1
			confirming = false
			status = ""
			Refresh()
		elseif button == "Start" and firstPress then
			if #modules == 0 then LoadCatalog() else ChangeInstallation() end
		end
	end
	return true
end

local af = Def.ActorFrame{
	InitCommand=function(self) frame = self end,
	OnCommand=function(self)
		screen = SCREENMAN:GetTopScreen()
		screen:AddInputCallback(input)
		self:queuecommand("LoadCatalog")
	end,
	LoadCatalogCommand=function(self) LoadCatalog() end,
	OffCommand=function(self)
		active = false
		if operation then operation:Cancel() end
		if screen then screen:RemoveInputCallback(input) end
	end
}

af[#af+1] = Def.Quad{
	InitCommand=function(self)
		self:xy(_screen.cx, 243):zoomto(_screen.w-margin*2, 322)
		self:diffuse(DarkUI() and color("#10151B") or color("#17212B"))
	end
}

for row = 1, rowCount do
	local actors = {}
	rows[row] = actors
	af[#af+1] = Def.ActorFrame{
		InitCommand=function(self) actors.frame = self; self:xy(margin+4, top+(row-1)*rowHeight) end,
		Def.Quad{
			InitCommand=function(self)
				actors.background = self
				self:halign(0):valign(0):zoomto(leftWidth, rowHeight-3)
			end
		},
		Def.Quad{
			InitCommand=function(self)
				actors.marker = self
				self:halign(0):valign(0):zoomto(3, rowHeight-3):diffuse(GetCurrentColor())
			end
		},
		Def.BitmapText{
			Font="Common Normal",
			InitCommand=function(self)
				actors.name = self
				self:xy(10, 11):halign(0):zoom(0.85):maxwidth((leftWidth-42)/0.85)
			end
		},
		Def.BitmapText{
			Font="Common Normal",
			InitCommand=function(self)
				actors.version = self
				self:xy(10, 30):halign(0):zoom(0.6):maxwidth((leftWidth-20)/0.6)
			end
		},
		Def.ActorFrame{
			InitCommand=function(self) actors.action = self; self:xy(leftWidth-14, 13) end,
			Def.Quad{ InitCommand=function(self) actors.firstBar = self end },
			Def.Quad{ InitCommand=function(self) actors.secondBar = self end }
		}
	}
end

local details = Def.ActorFrame{
	Name="Details",
	InitCommand=function(self) self:xy(rightX, top) end
}
local fields = {
	{ "Name", 10, 1 }, { "Filename", 35, 0.65 },
	{ "Author", 64, 0.75 }, { "Version", 84, 0.75 },
	{ "Description", 124, 0.8 }, { "Managers", 208, 0.65 }, { "Hosts", 244, 0.65 },
	{ "Install", 290, 0.85 }
}
for _, field in ipairs(fields) do
	details[#details+1] = Def.BitmapText{
		Name=field[1],
		Font="Common Normal",
		InitCommand=function(self)
			self:y(field[2]):halign(0):valign(0):zoom(field[3])
			if field[1] == "Description" then
				self:_wrapwidthpixels(rightWidth):maxheight(72/field[3])
			elseif field[1] == "Managers" or field[1] == "Hosts" then
				self:_wrapwidthpixels(rightWidth):maxheight((field[1] == "Managers" and 28 or 36)/field[3])
			else
				self:maxwidth(rightWidth/field[3])
			end
			if field[1] == "Install" then self:diffuse(GetCurrentColor()) end
		end
	}
end
af[#af+1] = details
af[#af+1] = Def.BitmapText{
	Name="Count", Font="Common Normal",
	InitCommand=function(self) self:xy(margin+leftWidth/2, 391):zoom(0.65) end
}
af[#af+1] = Def.BitmapText{
	Name="Status", Font="Common Normal",
	InitCommand=function(self)
		self:xy(_screen.cx, 422):zoom(0.7):_wrapwidthpixels(_screen.w-margin*2):maxheight(35/0.7)
	end
}
af[#af+1] = Def.BitmapText{
	Font="Common Normal",
	InitCommand=function(self)
		self:xy(_screen.cx, 462):zoom(0.65):maxwidth((_screen.w-margin*2)/0.65):settext(Text("HelpText"))
	end
}

return af
