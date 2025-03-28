-- 01 Starting Town

return {
	BGM = {
		file = "Chloe.ogg",
		length = 105
	},
	Start = {
		P1 = {r=6, d=6, z=-1},
		P2 = {r=7, d=6, z=-2}
	},
	Events = {

		--exit map via top
		{
			Tiles = { 24, 25, 26, 27, 28, 29 },
			Trigger = "PlayersTouch",
			Action = function()

			end,
		},

		--mailboxes
		{
			Tiles = {},
			Trigger = "PlayerInteraction",
			Action = function()

			end,
		}
	},
}