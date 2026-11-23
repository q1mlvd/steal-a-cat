--!strict
-- Rebirth: reset coins/bowl/cats/upgrades for a permanent income bonus, Sewers access and house styles.
-- Saved in PlayerData.rebirths (and PlayerData.houseStyle for the chosen style).

export type HouseStyle = { id: string, name: string, requiredRebirths: number, wallColor: Color3, floorColor: Color3 }

local styles: { HouseStyle } = {
	{ id = "Default", name = "Classic", requiredRebirths = 0, wallColor = Color3.fromRGB(235, 220, 200), floorColor = Color3.fromRGB(170, 130, 90) }, -- map colours
	{ id = "Mint", name = "Mint", requiredRebirths = 1, wallColor = Color3.fromRGB(170, 235, 205), floorColor = Color3.fromRGB(120, 160, 120) },
	{ id = "Sunset", name = "Sunset", requiredRebirths = 2, wallColor = Color3.fromRGB(255, 190, 150), floorColor = Color3.fromRGB(150, 90, 70) },
	{ id = "Royal", name = "Royal", requiredRebirths = 3, wallColor = Color3.fromRGB(150, 140, 230), floorColor = Color3.fromRGB(90, 70, 130) },
	{ id = "Galaxy", name = "Galaxy", requiredRebirths = 5, wallColor = Color3.fromRGB(45, 40, 80), floorColor = Color3.fromRGB(25, 20, 45) },
}
local styleById: { [string]: HouseStyle } = {}
for _, style in styles do
	styleById[style.id] = table.freeze(style)
end

local Rebirth = {
	Costs = table.freeze({ 1000000, 5000000, 25000000, 100000000, 400000000 }),
	CostGrowthAfterList = 4, -- each rebirth after the list costs 4x the previous one
	IncomeBonusPerRebirth = 0.5, -- +50% per rebirth, additive: multiplier = 1 + 0.5 x rebirths
	KeepCats = 1, -- cats kept (Monetization.KeepCatsWithPass with the Keep 3 Cats pass)
	-- Inventory kept through a rebirth (decision): player-permanent items and unattached Bell tokens.
	-- Consumables and armed Fish / Soft Paws flags are reset.
	KeepItems = table.freeze({ Net = true, GuardDog = true, Bell = true }),
	SewersRebirths = 1, -- see Config/Gates.Sewers
	HouseStyles = table.freeze(styles),
	DefaultStyle = "Default",
	LeaderstatName = "Rebirths",
	RequestCooldown = 1,
	SkipProductKey = "SkipRebirth",
	SkipIntentSaveTimeout = 15,
	MaxKeepIdLength = 80,
	Ui = table.freeze({Width=900,Height=710,Gap=12,OverviewHeight=172,ArrowSize=46,WarningHeight=32,RulesHeight=54,SmallTextSize=14,
		ProgressHeight=28,ButtonHeight=48,CatHeight=58,StylesHeight=48,HeaderTextSize=24,BodyTextSize=17,
		CompareBreakpoint=550,SideBySideMinWidth=260,UnlockDetailsHeight=70,
		PhoneOverviewHeight=120,PhoneArrowSize=28,PhoneGap=8,PhoneCardPadding=6,PhoneTitleSize=18,PhoneIncomeSize=20,PhoneUnlockSize=12,
		PhoneWarningHeight=32,PhoneCostHeight=24,PhoneProgressHeight=16,PhoneButtonHeight=44,
		CompactBodyHeight=280,CompactOverviewHeight=68,CompactArrowSize=20,CompactGap=4,CompactCardPadding=4,
		CompactTitleSize=16,CompactIncomeSize=18,CompactUnlockSize=12,CompactWarningHeight=30,CompactCostHeight=20,CompactProgressHeight=12,CompactButtonHeight=44,
		RobuxIconSize=24,SkipColor=Color3.fromRGB(160,94,220),ResetColor=Color3.fromRGB(231,78,88),CompareColor=Color3.fromRGB(255,216,84)}),
	-- House parts recoloured by the style (walls of both floors; floors).
	WallFolders = table.freeze({ "Walls", "SecondFloor" }),
	WallNames = table.freeze({ Back = true, Left = true, Right = true, FrontLeft = true, FrontRight = true, Lintel = true,
		Back2 = true, Left2 = true, Right2 = true, Front2 = true }),
	FloorNames = table.freeze({ Floor = true, Floor2Main = true, Floor2BackLeft = true, Floor2FrontLeft = true }),
}

function Rebirth.CostFor(rebirthsDone: number): number
	local costs = Rebirth.Costs
	if rebirthsDone < #costs then
		return costs[rebirthsDone + 1]
	end
	return costs[#costs] * Rebirth.CostGrowthAfterList ^ (rebirthsDone - #costs + 1)
end

function Rebirth.IncomeMultiplier(rebirths: number): number
	return 1 + Rebirth.IncomeBonusPerRebirth * math.max(0, rebirths)
end

function Rebirth.GetStyle(id: unknown): HouseStyle
	return (if type(id) == "string" then styleById[id] else nil) or styleById[Rebirth.DefaultStyle]
end

return table.freeze(Rebirth)

