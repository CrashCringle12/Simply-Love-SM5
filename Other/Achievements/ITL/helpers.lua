ITL_ReadJsonFile = function(path)
	if type(path) ~= "string" or path == "" then return nil end
	if type(FILEMAN) ~= "table" or type(FILEMAN.DoesFileExist) ~= "function" then return nil end
	if type(RageFileUtil) ~= "table" or type(RageFileUtil.CreateRageFile) ~= "function" then return nil end
	if type(JsonDecode) ~= "function" then return nil end

	if not FILEMAN:DoesFileExist(path) then return nil end

	local f = RageFileUtil:CreateRageFile()
	local data = nil
	if f:Open(path, 1) then
		data = JsonDecode(f:Read())
		f:Close()
	end
	f:destroy()
	return data
end

ITL_JoinRequirements = function(requirements)
	if type(requirements) ~= "table" then return "" end

	local output = {}
	for _, requirement in pairs(requirements) do
		if type(requirement) == "table" and type(requirement.requirement) == "string" and requirement.requirement ~= "" then
			output[#output+1] = requirement.requirement
		end
	end

	return table.concat(output, "; ")
end

ITL_BuildTemplateEntries = function(data)
	if type(data) ~= "table" or type(data.data) ~= "table" then return {} end

	local entries = {}
	for _, category in pairs(data.data) do
		if type(category) == "table" and type(category.info) == "table" then
			local categoryTitle = (type(category.title) == "string" and category.title ~= "") and category.title or "ITL Achievement"
			local tiers = {}

			for tierIndex, tierData in pairs(category.info) do
				if type(tierData) == "table" then
					tiers[#tiers+1] = {index = tonumber(tierIndex) or 0, data = tierData}
				end
			end

			table.sort(tiers, function(a, b)
				return a.index < b.index
			end)

			for _, tier in ipairs(tiers) do
				local tierData = tier.data
				local id = tonumber(tierData.id)
				if not id then
					id = (tonumber(category.id) or 0) * 100 + tier.index
				end

				local requirementText = ITL_JoinRequirements(tierData.requirements)
				local unlockedTitle = type(tierData.titleUnlocked) == "string" and tierData.titleUnlocked or ""
				local name = unlockedTitle ~= "" and unlockedTitle or categoryTitle
				local desc = requirementText ~= "" and ("Requirements: " .. requirementText) or "Requirements unavailable"

				entries[#entries+1] = {
					ID = id,
					Name = name,
					Desc = desc,
					Difficulty = 1,
					Icon = "Trophy.png",
					PercentEarned = tonumber(tierData.percentEarned) or 0,
					Category = categoryTitle,
				}
			end
		end
	end

	table.sort(entries, function(a, b)
		return (a.ID or 0) < (b.ID or 0)
	end)

	return entries
end

ITL_FindAchievementById = function(pn, id)
	if not (SL and pn and SL[pn] and SL[pn].AchievementData and type(SL[pn].AchievementData.ITL) == "table") then
		return nil
	end

	for _, achievement in ipairs(SL[pn].AchievementData.ITL) do
		if type(achievement) == "table" and achievement.ID == id then
			return achievement
		end
	end

	return nil
end

ITL_BuildTemplateSource = function()
	local getSample = function()
		if type(THEME) ~= "table" or type(THEME.GetCurrentThemeDirectory) ~= "function" then
			return nil
		end
		local samplePath = THEME:GetCurrentThemeDirectory() .. "Other/Achievements/ITL/sample.json"
		return ITL_ReadJsonFile(samplePath)
	end

	-- During early theme boot this may not exist yet.
	if type(PROFILEMAN) ~= "table" or type(PROFILEMAN.GetProfileDir) ~= "function" then
		return getSample()
	end

	local profileSlots = {
		"ProfileSlot_Player1",
		"ProfileSlot_Player2"
	}

	for _, slot in ipairs(profileSlots) do
		local dir = PROFILEMAN:GetProfileDir(slot)
		if dir and #dir > 0 then
			local profileData = ITL_ReadJsonFile(dir .. "ITL-achievements.json")
			if profileData ~= nil then
				return profileData
			end
		end
	end

	return getSample()
end
