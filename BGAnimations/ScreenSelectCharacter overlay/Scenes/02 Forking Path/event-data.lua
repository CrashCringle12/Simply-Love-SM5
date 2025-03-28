-- 02 Forking Path

return {
	BGM = {
		file = "forest-of-forking-paths.ogg",
		length = 46.75
	},

	Events = {

		--exit map via bottom
		{
			Tiles = { 24, 25, 26, 27, 28, 29 },
			Trigger = "PlayerInteraction",
			Action = nil,
		},
	},
}