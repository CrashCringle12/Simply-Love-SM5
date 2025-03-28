EventHandler = function( NextTile, pn )

	for key, event in ipairs(TSH.EventData.Events) do
		for EventTile in ivalues(event.Tiles) do
			if EventTile == NextTile then


				if event.Trigger == "PlayerTouch" then
					SM("player touch")
					event.Action()

				elseif event.Trigger == "PlayersTouch" then

					local other = OtherPlayer(pn)
					for t in ivalues(event.Tiles) do
						if TSH[other].pos.d * TSH.Screen.Width.Tiles + TSH[other].pos.r == t then
							SM( "PlayersTouch" )
							event.Action()
							break
						end
					end



				elseif event.Trigger == "PlayerInteraction" then


				else
					-- error handling
					SM("Event Trigger: " .. event.Trigger .. " is invalid.")
					break
				end
			end
		end
	end

end