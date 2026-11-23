--!strict
return table.freeze({
	PromptName = "ShopPrompt", PromptActionText = "Shop", PromptObjectText = "Cat supplies",
	PromptKey = Enum.KeyCode.E, PromptGamepadKey = Enum.KeyCode.ButtonX,
	OpenDistance = 12, PurchaseDistance = 14, SessionDuration = 120,
	OpenCooldown = 0.5, PurchaseCooldown = 0.25, InventoryRequestCooldown = 1,
	UseCooldown = 0.35, ClientUseCooldown = 0.2, MaxIdLength = 40,
	FishReadyInventoryKey = "__FishReady", FishReadyAttribute = "FishReady",
	SoftPawsReadyInventoryKey = "__SoftPawsReady", SoftPawsReadyAttribute = "SoftPawsReady",
	Categories = table.freeze({"Catching", "Stealing", "Defense"}),
	NetOwnedAttribute = "NetOwned", UiStateAttribute = "ShopOpen", CatchingAttribute = "IsCatching", CatchLockedAttribute = "CatchLocked",
	CatchGuiName = "CatchMinigame", GuiName = "CatShop", HotbarGuiName = "ItemHotbar",
	CloseKey = Enum.KeyCode.Q, CloseGamepadKey = Enum.KeyCode.ButtonB,
	HotbarKeys = table.freeze({Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five,Enum.KeyCode.Six}),
	ThrowDistance = 30, DefaultThrowDistance = 12, TargetVerticalTolerance = 12,
	MaxAimCoordinate = 100000,
	GroundProbeUp = 15, GroundProbeDown = 60, GraceSeconds = 3,
	ThrowOriginLift = 1, ThrowWallOffset = 0.5, DirectionEpsilon = 0.01, BaitPulseInterval = 0.5,
	EffectFolderName = "CatchingItemEffects", MarkerHeight = 0.35, MarkerSize = Vector3.new(1.5,1.5,1.5),
	YarnColor = Color3.fromRGB(250,120,173), BaitColor = Color3.fromRGB(247,186,87), CatnipColor = Color3.fromRGB(97,225,155),
	MarkerLabelDistance = 75, MarkerLabelOffset = Vector3.new(0,2,0), MarkerLabelSize = Vector2.new(220,36), MarkerTextSize = 16,
	WildEffects = table.freeze({
		FrozenUntilAttribute="ItemFrozenUntil", CalmUntilAttribute="ItemCalmUntil", BaitUntilAttribute="ItemBaitUntil",
		BaitStopDistance=3, BaitRetargetInterval=0.5, BaitStepDistance=8,
		BaitAngles=table.freeze({0,35,-35,70,-70}), MaxDuration=60, MaxRadius=100,
	}),
	Ui = table.freeze({
		DisplayOrder=30,HotbarDisplayOrder=8,PanelWidth=720,PanelHeight=530,PanelWidthScale=0.9,PanelHeightScale=0.78,
		MinPanelSize=Vector2.new(290,310),Corner=16,Padding=18,TitleHeight=42,TabHeight=42,RowHeight=160,Gap=10,
		HotbarButtonSize=68,HotbarGap=8,HotbarBottom=22,HotbarWidthScale=0.86,HotbarPageHeight=44,IconSize=38,TextSize=16,SmallTextSize=13,
		PurchaseWidth=112,PurchaseHeight=44,MobileColumns=3,MobileWidthBreakpoint=600,MobilePortraitBottom=190,MobileLandscapeBottom=105,
		MobileSlapTop=100,MobileSlapRight=90,
		-- Light palette matching the UI pack (cream panels, dark-purple text). These colours are also the
		-- role keys UiStyleController uses to pick a 9-slice skin (Background panel, Surface card, Accent button...).
		Background=Color3.fromRGB(255,243,224),Surface=Color3.fromRGB(255,250,240),
		Muted=Color3.fromRGB(128,98,120),Text=Color3.fromRGB(62,34,74),Accent=Color3.fromRGB(60,190,130),
		Coin=Color3.fromRGB(230,140,20),ShadeTransparency=0.32,StrokeTransparency=0.7,
		Danger=Color3.fromRGB(235,90,90),OnColor=Color3.fromRGB(255,255,255), -- text on coloured buttons/tabs
		PopupMaxHeight=300, -- top-level panels at most this tall (offset) use Frame_Popup, larger ones Frame_MainPanel
		IconHolderMax=64, -- nested icon holders this small become transparent instead of cards
	}),
	BellUi = table.freeze({
		GuiName="BellTracking",DisplayOrder=12,Top=78,Width=250,WidthScale=0.6,RowHeight=26,MaxPanelHeight=42,Padding=8,Gap=4,
		Color=Color3.fromRGB(255,215,109),FillTransparency=0.65,OutlineTransparency=0,
		MarkerSize=Vector2.new(180,40),MarkerOffset=Vector3.new(0,4,0),TextSize=15,ArrowSize=28,
		AnchorSize=Vector3.new(0.1,0.1,0.1),
		UpdateInterval=0.1,DirectionEpsilon=0.01,
	}),
})

