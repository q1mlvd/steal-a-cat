--!strict
-- UI asset pack (Desktop\Коты\UI, uploaded 2026-10-06). Every UI image id lives here; Shared/Util/UiSkin applies them.
-- 9-slice frames: SliceCenter from UI\slices.txt (source pixels); SliceScale shrinks the big source corners
-- to on-screen size (corner px on screen = corner x SliceScale).

export type Slice = { image: string, center: Rect, scale: number }

local function id(n: number): string
	return "rbxassetid://" .. n
end

local function slice(n: number, center: Rect, scale: number): Slice
	return table.freeze({ image = id(n), center = center, scale = scale })
end

local CARD = Rect.new(224, 224, 544, 800)
local BUTTON = Rect.new(120, 120, 648, 136)
local BAR = Rect.new(63, 63, 961, 65)
local SLOT = Rect.new(192, 192, 320, 320)

return table.freeze({
	Frames = table.freeze({
		MainPanel = slice(131291214282920, Rect.new(256, 256, 768, 512), 0.16),
		Header = slice(91171084850822, Rect.new(120, 120, 904, 136), 0.2),
		Popup = slice(70539653583176, Rect.new(192, 192, 576, 320), 0.16),
		Card = slice(79634949687765, CARD, 0.11),
		HotbarSlot = slice(98119080078100, SLOT, 0.14),
		HotbarSlotSelected = slice(107903893567724, SLOT, 0.14),
		Tooltip = slice(132293651246547, Rect.new(176, 176, 592, 208), 0.12),
		Toast = slice(78678298559271, Rect.new(120, 120, 904, 136), 0.2),
		Banner = slice(132803819279031, Rect.new(176, 176, 1360, 208), 0.3),
	}),
	-- Rarity-coloured card frames (Config/Rarities ids)
	Cards = table.freeze({
		Common = slice(107733012402334, CARD, 0.11),
		Uncommon = slice(132040926292466, CARD, 0.11),
		Rare = slice(110078486372108, CARD, 0.11),
		Epic = slice(71270453870420, CARD, 0.11),
		Legendary = slice(73552430963607, CARD, 0.11),
		Mythic = slice(124092370689968, CARD, 0.11),
		Secret = slice(84226314007355, CARD, 0.11),
	}),
	Buttons = table.freeze({
		Green = slice(113878252377346, BUTTON, 0.17),
		Blue = slice(134314194591233, BUTTON, 0.17),
		Red = slice(106696621764803, BUTTON, 0.17),
		Gold = slice(110126486332337, BUTTON, 0.17),
		Gray = slice(134908576495181, BUTTON, 0.17),
	}),
	Tabs = table.freeze({
		Normal = slice(93349594678480, Rect.new(120, 120, 392, 136), 0.17),
		Selected = slice(76429531778171, Rect.new(120, 120, 392, 136), 0.17),
	}),
	Bars = table.freeze({
		Background = slice(135518172248775, BAR, 0.12),
		Green = slice(94519198562701, BAR, 0.12),
		Pink = slice(74258116433450, BAR, 0.12),
		Gold = slice(133793748515307, BAR, 0.12),
	}),

	Icons = table.freeze({
		Admin = id(113973720621048), BellTracker = id(97218973372688), Coin = id(103817162019925),
		CoinStack = id(124407138258299), Daily = id(73389021495547), Hands = id(131909513031128),
		Heart = id(117050074235125), IncomePerSec = id(80097009481400), Index = id(82092271403090),
		Inventory = id(132797260070850), Jump = id(73950814414085), Lock = id(135945773447151),
		LoyalBadge = id(96359758102020), Luck = id(94683126160656), Magnet = id(106026288506666),
		Merge = id(130394852377875), Multiplier = id(71952167997886), Pet = id(103945183466341),
		Pillow = id(90843360335412), Premium = id(86645085743520), Quests = id(93219402029287),
		Rebirth = id(122177123623038), Settings = id(107480735548406), Shield = id(101762651373252),
		Shop = id(140600773642829), Slap = id(76918153184899), Speed = id(124687567504060),
		Tamed = id(106950527147543), Thief = id(99137310044655), Timer = id(110641987032741),
		UnstealableBadge = id(121685194882949), VIP = id(85597655828385), Warning = id(107002922694696),
	}),
	-- Rarity (Config/Rarities ids), mutation (Config/Mutations ids) and tier badges
	RarityBadges = table.freeze({
		Common = id(88263922663130), Uncommon = id(126287815037528), Rare = id(109259715257090),
		Epic = id(140518361094983), Legendary = id(119474033220279), Mythic = id(140196467866015),
		Secret = id(124374838192093),
	}),
	MutationBadges = table.freeze({
		Shiny = id(117226277595178), Rainbow = id(74715415634157), Diamond = id(96583494849507),
		Starry = id(78739597850542),
	}),
	TierBadges = table.freeze({ Mega = id(106665874692029), Giga = id(118625515063337) }),
	-- Live events (Config/Events schedule names) and seasons
	Events = table.freeze({
		Starfall = id(106859614596556), Rain = id(109374635001839), DogRaid = id(72073597176541),
		Halloween = id(76163852792858), Christmas = id(85727805199951),
	}),
	Controls = table.freeze({
		Close = id(91785091450736), Check = id(90034517242663), ArrowLeft = id(76667962291675),
		ArrowRight = id(88577397329560), Plus = id(136587333673277), Minus = id(71945827293449),
		SoundOn = id(130725191631835), SoundOff = id(80086962117320), Music = id(133560466480653),
		Graphics = id(133830089274885),
	}),
	Logo = id(118791957179721),
	LoadingBackground = id(86193610377468),

	-- Inner inset (pixels) the Panel / Popup skins add so content clears the frame art's border (cat ears on top)
	PanelInsets = table.freeze({
		Panel = table.freeze({ side = 16, top = 28, bottom = 14 }),
		Popup = table.freeze({ side = 12, top = 16, bottom = 12 }),
	}),

	-- HUD button id (HudButtonsController.Add) -> Icons key
	HudIcons = table.freeze({
		Daily = "Daily", Quests = "Quests", Rebirth = "Rebirth", Shop = "Shop", Collection = "Index",
		Inventory = "Inventory", Settings = "Settings", Robux = "Premium", Admin = "Admin",
	}),
	HudButtonSize = 64, -- square icon tiles
	HudHeightShare = 0.62, -- the HUD column may use this share of the screen height, then wraps into columns
	HudCenterY = 0.43, -- vertical centre of the HUD column (fraction of the screen)
	-- Shop page -> card colour (rarity card frames)
	CategoryCards = table.freeze({
		Catching = "Rare", Stealing = "Epic", Defense = "Uncommon", Upgrades = "Legendary", Robux = "Mythic",
	}),
	-- Upgrade id (Config/Upgrades) -> Icons key
	UpgradeIcons = table.freeze({
		Speed = "Speed", Jump = "Jump", Hands = "Hands", BowlMagnet = "Magnet", Pillows = "Pillow",
	}),
})

