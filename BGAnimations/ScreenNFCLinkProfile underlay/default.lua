local POLL_INTERVAL_SECONDS = 0.25
local DEBUG_NFC_GROOVESTATS = true

local handledLinkedUIDs = {}
local lastPendingLinkUID = ""
local pendingLinkWasActive = false

local function DebugMessage(message)
	if not DEBUG_NFC_GROOVESTATS then return end
	Trace("[NFCLink] " .. tostring(message))
end

local function StatusMessage(message)
	if type(SCREENMAN) == "table" and type(SCREENMAN.SystemMessage) == "function" then
		SCREENMAN:SystemMessage("[NFCLink] " .. tostring(message))
	else
		SM("[NFCLink] " .. tostring(message))
	end
end

local function GetLinkScreen()
	local topScreen = SCREENMAN and SCREENMAN:GetTopScreen() or nil
	if not topScreen then return nil end
	if type(topScreen.HasPendingLink) ~= "function" then return nil end
	return topScreen
end

local function GetEditProfileID()
	if type(GAMESTATE.GetEditLocalProfileID) ~= "function" then return nil end
	local profileID = GAMESTATE:GetEditLocalProfileID()
	if type(profileID) ~= "string" or profileID == "" then return nil end
	return profileID
end

local function GetCurrentCardUID()
	if NFCMAN == nil then return "" end
	if type(NFCMAN.GetCardUID) ~= "function" then return "" end
	if type(NFCMAN.IsCardPresent) == "function" and not NFCMAN:IsCardPresent() then return "" end

	local uid = NFCMAN:GetCardUID()
	return type(uid) == "string" and uid or ""
end

local function HandleLinkedUID()
	local profileID = GetEditProfileID()
	if not profileID then return end

	local linkScreen = GetLinkScreen()
	if not linkScreen then return end

	if linkScreen:HasPendingLink() then
		local pendingUID = linkScreen:GetPendingCardUID()
		if type(pendingUID) ~= "string" or pendingUID == "" then
			pendingLinkWasActive = true
			return
		end

		pendingLinkWasActive = true
		lastPendingLinkUID = pendingUID

		local sourceProfileID = linkScreen:GetPendingSourceProfileID()
		local sourceProfileName = linkScreen:GetPendingSourceProfileName()
		if linkScreen:PendingLinkRequiresMove() then
			DebugMessage("Pending move from " .. tostring(sourceProfileName or sourceProfileID or "<unknown>") .. " to UID " .. pendingUID)
		else
			DebugMessage("Pending link for UID " .. pendingUID)
		end
		return
	end

	if not pendingLinkWasActive then return end

	local linkedUID = linkScreen:GetLinkedCardUID()
	if type(linkedUID) ~= "string" or linkedUID == "" then return end
	if handledLinkedUIDs[linkedUID] then
		pendingLinkWasActive = false
		lastPendingLinkUID = ""
		return
	end
	if linkedUID ~= lastPendingLinkUID then return end

	pendingLinkWasActive = false
	DebugMessage("Confirmed linked UID: " .. linkedUID)

	-- If local profile has no valid GrooveStats data yet, import from current card payload first.
	if UpdateGrooveStatsIniFromCardData(profileID) then
		DebugMessage("Imported GrooveStats payload from card into local profile ini")
	end

	local apiKey = GetGrooveStatsProfileApiKey(profileID)
	if apiKey == "" then
		DebugMessage("No valid profile ApiKey, skipping card write")
		handledLinkedUIDs[linkedUID] = true
		lastPendingLinkUID = ""
		return
	end

	local currentCardUID = GetCurrentCardUID()
	if currentCardUID == "" or currentCardUID ~= linkedUID then
		local status = "Linked, but the card was removed before GrooveStats data could be written"
		StatusMessage(status)
		DebugMessage("Cannot write payload; linked=" .. linkedUID .. " card=" .. (currentCardUID ~= "" and currentCardUID or "<none>"))
		handledLinkedUIDs[linkedUID] = true
		lastPendingLinkUID = ""
		return
	end

	if WriteGrooveStatsCardData(profileID) then
		DebugMessage("Wrote GrooveStats payload to linked card")
		handledLinkedUIDs[linkedUID] = true
		lastPendingLinkUID = ""
	else
		StatusMessage("Linked, but GrooveStats payload could not be written")
		DebugMessage("Failed to write GrooveStats payload to card")
		handledLinkedUIDs[linkedUID] = true
		lastPendingLinkUID = ""
	end
end

return Def.ActorFrame {
	OnCommand=function(self)
		self:queuecommand("Poll")
	end,
	PollCommand=function(self)
		HandleLinkedUID()
		self:sleep(POLL_INTERVAL_SECONDS):queuecommand("Poll")
	end,
}
