LoadActor("./helpers.lua")

local template = {}
if type(ITL_BuildTemplateEntries) == "function" and type(ITL_BuildTemplateSource) == "function" then
	local ok, built = pcall(function()
		return ITL_BuildTemplateEntries(ITL_BuildTemplateSource())
	end)
	if ok and type(built) == "table" then
		template = built
	else
		template = {}
	end
end

local achievements = {}
for _, entry in ipairs(template) do
	achievements[#achievements+1] = {
		Name = entry.Name,
		Icon = entry.Icon,
		Desc = entry.Desc,
		Difficulty = entry.Difficulty,
		ID = entry.ID,
		IsITL = true,
		Condition = function(pn)
			local playerAchievement = type(ITL_FindAchievementById) == "function" and ITL_FindAchievementById(pn, entry.ID) or nil
			return playerAchievement and playerAchievement.Unlocked or false
		end,
		DynamicName = function(pn)
			local playerAchievement = type(ITL_FindAchievementById) == "function" and ITL_FindAchievementById(pn, entry.ID) or nil
			if playerAchievement and type(playerAchievement.Name) == "string" and playerAchievement.Name ~= "" then
				return playerAchievement.Name
			end
			return entry.Name
		end,
		DynamicDesc = function(pn)
			local playerAchievement = type(ITL_FindAchievementById) == "function" and ITL_FindAchievementById(pn, entry.ID) or nil
			if playerAchievement and type(playerAchievement.Desc) == "string" and playerAchievement.Desc ~= "" then
				return playerAchievement.Desc
			end
			return entry.Desc
		end,
		DynamicPercentEarned = function(pn)
			local playerAchievement = type(ITL_FindAchievementById) == "function" and ITL_FindAchievementById(pn, entry.ID) or nil
			if playerAchievement and playerAchievement.PercentEarned ~= nil then
				return tonumber(playerAchievement.PercentEarned) or 0
			end
			return entry.PercentEarned
		end
	}
end

return achievements
