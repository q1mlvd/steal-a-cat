--!strict
-- Item art (Stage 17): imported meshes in ReplicatedStorage/ItemModels (one Model per item, pivot = bottom
-- centre, front = -Z). Functional parts (trap trigger, dog root, pillows, bowl) keep their names/attributes.

return table.freeze({
	ModelsFolder = "ItemModels",
	ArtName = "Art", -- name given to a cloned art Model inside its owner
	ArtWeldName = "ArtWeld", -- Weld from a functional root to its art (client animation edits its C0)

	-- Held in the right hand (offset from the hand's bottom, item pivot = its bottom centre)
	HandNames = table.freeze({ "RightHand", "Right Arm" }),
	Grips = table.freeze({
		Net = CFrame.new(0, -0.3, -0.15),
		Vacuum = CFrame.new(0, -0.95, -0.55),
		LaserPointer = CFrame.new(0, -0.45, -0.35),
	}),
	HeldName = "HeldItem",
	HeldItemAttribute = "ItemArtName", -- which item model is held (so one item never removes another)
	MarkerProbeLift = 1,
	MarkerGroundProbe = 12, -- dropped markers (Catnip at the player) sit on the ground below
	VacuumHoldSeconds = 1.2,

	-- Thrown / dropped markers
	MarkerModels = table.freeze({ ["Yarn Ball"] = "YarnBall", ["Bait Can"] = "BaitCan", Catnip = "Catnip" }),
	ThrowSeconds = 0.4,
	ThrowArcHeight = 4,

	-- Guard Dog / raid dogs: mesh on the (now invisible) Body root; raid dogs glow red instead of a recolour
	DogModel = "GuardDog",
	RaidGlowColor = Color3.fromRGB(255, 70, 60),
	RaidGlowRange = 8,
	DogTag = "Dog", -- CollectionService tag for client animation
	DogBobHeight = 0.18,
	DogCyclesPerStud = 0.35,

	-- Box trap mesh sits on the flat trigger part
	TrapModel = "BoxTrap",

	-- Bell on a belled cat (client-side): at the collar, below the head
	BellModel = "Bell",
	BellScale = 0.35,
	BellOffset = CFrame.new(0, -0.55, -0.15), -- from the cat's Head part
})

