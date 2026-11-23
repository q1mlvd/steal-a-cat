--!strict
-- House door lock.

return table.freeze({
	LockDuration = 60, -- seconds the door stays locked
	Cooldown = 180, -- seconds from locking until the owner can lock again
	PromptName = "LockPrompt",
	ActionText = "Lock door",
	LockedUntilAttribute = "DoorLockedUntil", -- on the plot Model (server time)
	CooldownUntilAttribute = "DoorCooldownUntil", -- on the plot Model (server time)
	PushOutInterval = 0.5, -- seconds between checks for intruders inside a locked house
	PushOutDistance = 8, -- studs outside the door where intruders are placed
	BarrierCollisionGroup = "DoorBarrier", -- blocks players, not cats
	LockedDoorColor = Color3.fromRGB(220, 60, 60),
	LockedDoorTransparency = 0.25,
})

