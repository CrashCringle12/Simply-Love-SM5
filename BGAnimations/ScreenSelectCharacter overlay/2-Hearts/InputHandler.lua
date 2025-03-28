local t = ...

local InputHandler = function(event)

	----------------------------------------------------------------------------
	-- DEVELOPER & DEBUG STUFF

	-- quick hack to allow collision toggling for testing's sake
	if event.type == "InputEventType_FirstPress" and event.DeviceInput.button == "DeviceButton_left ctrl" then
		TSH.Collisions = not TSH.Collisions
		SM("Collisions toggled to " .. tostring(TSH.Collisions))
	end

	-- -- quick hack to get to the operator menu pressing escape
	-- if event.type == "InputEventType_FirstPress" and event.DeviceInput.button == "DeviceButton_escape" then
	-- 	local topscreen = SCREENMAN:GetTopScreen()
	-- 	topscreen:SetNextScreenName("ScreenOptionsService")
	-- 	topscreen:StartTransitioningScreen("SM_GoToNextScreen")
	-- 	return false
	-- end

	-- -- toggle audio on/off
	-- if event.type == "InputEventType_FirstPress" and event.DeviceInput.button == "DeviceButton_0" then
	-- 	t:GetChild("BGM"):queuecommand("Toggle")
	-- end


	----------------------------------------------------------------------------

	-- if any of these, don't attempt to handle input
	if not event.PlayerNumber or not event.button then
		return false
	end

	-- truncate "PlayerNumber_P1" into "P1" and "PlayerNumber_P2" into "P2"
	local pn = ToEnumShortString(event.PlayerNumber)

	if event.type ~= "InputEventType_Release" then

		TSH[pn].input[event.button]	= true

		-- handle player sprite movement
		if event.button == "Up" or event.button == "Down" or event.button == "Left" or event.button == "Right" then

			if event.type == "InputEventType_FirstPress" then
				TSH[pn].input.Active = event.button
			end

			-- attempt to tween character
			t:GetChild("Visuals"):GetChild("AFT"):GetChild(pn.."_Sprite"):playcommand("AttemptToTween", {dir=event.button})

			-- attempt to tween the map
			t:GetChild("Visuals"):GetChild("Sprite"):playcommand("AttemptToTween")

		end
	elseif event.type == "InputEventType_Release" then
		TSH[pn].input.Active = nil
		TSH[pn].input[event.button]	= false

		-- if a player has released a diretional arrow...
		if event.button == "Up" or event.button == "Down" or event.button == "Left" or event.button == "Right" then
			-- ...then attempt to redraw the character sprite in a neutral (standing) state
			t:GetChild("Visuals"):GetChild("AFT"):GetChild(pn.."_Sprite"):queuecommand("AnimationOff")
		end
	end

	-- Trace(print_r(event) .. "\n")
	-- SM("input button for "..pn.." is ".. tostring(TSH[pn].input.Active))

	return false
end

return InputHandler