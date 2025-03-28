-- This will hopefully remain one of our few tables with global scope...
TSH = {

	-- set this here (for now?)
	ActiveMap = "03 Port Town",

	TileData = {},
	EventData = {},

	-- a (hackish) flag that can be toggled for the sake of map testing
	Collisions = true,

	-- a constant to be used to calculate animation and tween times
	-- (there is probably a better way to do this sort of thing?)
	SleepDuration = 0.125,

	-- initialize values for Player1
	P1 = {
		file = "Guy",
		pos = {
			r = nil,
			d = nil,
			z = nil
		},
		dir = "Left",
		input = {
			Active = nil,
			Up = false,
			Down = false,
			Left = false,
			Right = false,
			MenuRight = false,
			MenuLeft = false,
			Start = false,
			Select = false
		}
	},
	-- initialize values for Player2
	P2 = {
		file = "Girl",
		pos = {
			r = nil,
			d = nil,
			z = nil
		},
		dir = "Left",
		input = {
			Active = nil,
			Up = false,
			Down = false,
			Left = false,
			Right = false,
			MenuRight = false,
			MenuLeft = false,
			Start = false,
			Select = false
		}
	},

	Screen = {
		Width  = {
			Pixels = 853,
			Tiles = nil
		},
		Height = {
			Pixels = 480,
			Tiles = nil
		}
	}
}