--!strict
-- Placing cats on pillows and taming. Tame time per rarity is Rarities.tameTime.

return table.freeze({
	PlacePromptName = "PlacePrompt",
	PlaceActionText = "Place cat",
	PickUpPromptName = "PickUpPrompt",
	PickUpActionText = "Pick up",
	OccupiedAttribute = "Occupied", -- true on a pillow part while a cat sits on it (display mirror)
	CollisionGroup = "Pillows", -- players stand on pillows; walking cats (Cats group) pass through them
	-- Thin stair rails (plot SecondFloor) share that group: returning cats otherwise hop onto the 0.5-stud
	-- rail at the top of the ramp and balance there. Players still collide; pathfinding still avoids them.
	CatPassThroughParts = table.freeze({ "RampRail", "RailInner", "RailFront" }),
	FreePillowsAttribute = "FreePillows", -- player attribute mirror (store UI: Cat Box needs a free pillow)
	LockedAttribute = "Locked", -- true on pillows above the plot owner's pillowCount (hidden, not usable)
	LockedTransparency = 1, -- locked pillows are hidden
	PaidDeliveryLift = 2, -- studs above the door sill for the shared fresh walking route
	WaitingNoticeDelay = 4, -- seconds after joining before the "cats waiting for a pillow" message
	ActionCooldown = 0.4, -- seconds between place / pick-up actions per player
	TameCheckInterval = 0.5, -- seconds between server checks for finished taming
})

