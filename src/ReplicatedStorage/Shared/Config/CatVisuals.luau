--!strict
-- Client-side cat looks (Stage 17): procedural animation of the art meshes and optional effects.
-- Art cats (ServerStorage/CatModels) have Body (textured MeshPart) on Weld "BodyWeld" to HumanoidRootPart;
-- only the client moves that weld, so physics, hitboxes and prompts are untouched.

return table.freeze({
	BodyName = "Body",
	WeldName = "BodyWeld",
	FxAttribute = "CatFx", -- lights / particles baked into art models; disabled in Low graphics
	AnimateDistance = 90, -- studs from the camera; farther cats stay still
	MovingSpeed = 0.6, -- studs/s of the root before the walk cycle starts

	-- Walk: hop-like bob and a little side-to-side roll
	WalkBobHeight = 0.14,
	WalkCyclesPerStud = 0.32, -- bob cycles per stud travelled (faster cats bob faster)
	WalkRollDegrees = 4,

	-- Idle: breathing (rise and fall) and a slow body sway in place of a separate tail
	BreathHeight = 0.025,
	BreathSeconds = 2.6,
	IdleSwayDegrees = 2.5,
	IdleSwaySeconds = 4.5,

	-- Sitting on a pillow: squashed a little (set once when seated)
	SitSquash = 0.08, -- 8% shorter, 4% wider
	SitStates = table.freeze({ OnPillow = true }),

	-- UI portraits (Shared/Util/CatPortrait): rarity frame, Mega/Giga glow ring + badge, mutation tint overlay
	Portrait = table.freeze({
		BackgroundDarken = 0.6, -- rarity colour lerped this far toward the UI background
		Corner = 12,
		Stroke = 2,
		TierStroke = table.freeze({ Mega = 3, Giga = 4 }),
		TierColors = table.freeze({
			Mega = table.freeze({ Color3.fromRGB(255, 214, 90), Color3.fromRGB(255, 150, 40) }),
			Giga = table.freeze({ Color3.fromRGB(255, 90, 200), Color3.fromRGB(120, 110, 255), Color3.fromRGB(80, 230, 255) }),
		}),
		GlowTransparency = 0.55, -- inner glow (tier) behind the art
		BadgeHeightScale = 0.24,
		MutationTransparency = 0.72,
		Rainbow = table.freeze({ Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 80), Color3.fromRGB(80, 230, 120),
			Color3.fromRGB(80, 170, 255), Color3.fromRGB(200, 90, 255) }),
		MysteryText = "?",
		NoArtText = "\u{1F431}", -- cats without a portrait (seasonal)
	}),

	-- Cat index / collection (CatIndexService -> player attribute, CollectionController)
	Index = table.freeze({
		DiscoveredAttribute = "DiscoveredCats", -- comma-separated catIds (server-set player attribute)
		SweepInterval = 5, -- seconds between marking owned cats as discovered
		Columns = 5,
		CellHeight = 142,
	}),
})

