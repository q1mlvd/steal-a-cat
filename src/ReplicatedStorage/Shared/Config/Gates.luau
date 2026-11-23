--!strict
-- Locked areas. Map parts in Workspace.Map.Gates carry GateIdAttribute and one of three tags:
--   BarrierTag - solid for everyone on the server; a qualified player's client turns it off locally
--   AreaTag    - volume a non-qualified player may not be inside (server pushes them to the nearest exit)
--   ExitTag    - where a pushed-out player is placed
-- The server check also stops clients that delete barriers on their side.

local Upgrades = require(script.Parent.Upgrades)

export type GateId = "Rooftops" | "Sewers" | "VIP"
export type GateDefinition = {
	requiredUpgrade: string?, -- Config/Upgrades id
	requiredLevel: number?,
	requiredRebirths: number?, -- PlayerData.rebirths
	requiredPass: string?, -- Config/Monetization pass key (server: MonetizationService.OwnsPass)
	hint: string,
	barrierTransparency: number, -- for players who can't pass yet (passing players never see it)
}

return table.freeze({
	FolderName = "Gates", -- under Workspace.Map
	GateIdAttribute = "GateId",
	BarrierTag = "GateBarrier",
	AreaTag = "GateArea",
	ExitTag = "GateExit",
	CollisionGroup = "GateBarrier", -- blocks players, not cats
	RebirthsAttribute = "Rebirths", -- player attribute mirror of PlayerData.rebirths
	CheckInterval = 0.5, -- seconds between server area checks
	NotifyCooldown = 3, -- seconds between hint notifications per player
	HintDuration = 4,
	ExitLift = 3, -- studs above the exit part's position
	HintMaxDistance = 45, -- studs; billboard hint visibility
	HintSize = UDim2.fromOffset(200, 40),
	HintOffset = Vector3.new(0, 2, 0),
	HintColor = Color3.fromRGB(255, 215, 109),
	Gates = table.freeze({
		Rooftops = table.freeze({
			requiredUpgrade = "Jump",
			requiredLevel = Upgrades.JumpGateLevel,
			hint = `Need Jump {Upgrades.JumpGateLevel}`,
			barrierTransparency = 1,
		} :: GateDefinition),
		Sewers = table.freeze({
			requiredRebirths = 1,
			hint = "Rebirth to unlock",
			barrierTransparency = 0.8,
		} :: GateDefinition),
		VIP = table.freeze({
			requiredPass = "VIP",
			hint = "VIP pass required",
			barrierTransparency = 0.7,
		} :: GateDefinition),
	}),
})

