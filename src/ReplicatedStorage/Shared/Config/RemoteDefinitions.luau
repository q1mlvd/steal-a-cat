--!strict
-- The single list of every RemoteEvent / RemoteFunction in the game.
-- Network.Setup() (server) creates exactly these; add new remotes here only.
-- Note each remote's direction and arguments so server handlers know what to validate.

export type Definitions = {
	Events: { string },
	Functions: { string },
}

local definitions: Definitions = {
	Events = {
		"Notify", -- server -> client (message: string, style: Notifications.Style, extra: {catId, mutation}? cat portrait | {event}? event icon, for announcements)
		"CatchStart", -- server -> client (params: CatchMinigame.Params)
		"CatchSubmit", -- client -> server (sessionId: string). The press moment is timed by the server.
		"CatchResult", -- server -> client (sessionId: string, success: boolean)
		"CoinsCollected", -- server -> client (amount: number, position: Vector3) for the collect effect
		"StealAlert", -- server -> client (active: boolean, thief: Player?, catName: string?) to the victim
		"BellTracking", -- server -> victim (active: boolean, uniqueId: string, cat: Model?, catName: string?, position: Vector3?)
		"CatLoyaltyReturned", -- server -> original owner (catName: string, timesReturned: number), celebration only
		"ShopOpen", -- server -> client (inventory snapshot), after a validated stall prompt
		"ShopPurchase", -- client -> server (itemId: string); price/distance/session are server checked
		"RobuxPurchaseRequest", -- client -> server (key: string) pass/product key from Config/Monetization; server validates, then prompts
		"MergeOpen", -- server -> client (groups: {{catId, tier, count, mutation}}) after a validated Merge Machine prompt
		"MergeRequest", -- client -> server (catId: string, tier: string); session/distance/ownership checked
		"RebirthOpenRequest", -- client -> server, no args; rate-limited; replies with RebirthOpen
		"RebirthOpen", -- server -> client (info: {rebirths, cost, coins, keepCount, cats, styles, style, blocked})
		"RebirthRequest", -- client -> server (keepIds: {string}); validated, one no-yield update
		"SetHouseStyle", -- client -> server (styleId: string); requires enough rebirths
		"AdminCommand", -- client -> server (command: string, arg1, arg2); admins only (Config/Admin, server check)
		"RetentionRequest", -- client -> server (kind: "Daily" | "Quests"); rate-limited; replies DailyInfo / QuestInfo
		"DailyInfo", -- server -> client ({streak, today, claimable, nextDay, pending, rewards})
		"DailyClaim", -- client -> server, no args
		"QuestInfo", -- server -> client ({{id, text, progress, target, claimed, reward}})
		"QuestClaim", -- client -> server (questId: string)
		"WelcomeBack", -- server -> client (coins: number, offlineSeconds: number)
		"SettingsUpdate", -- client -> server ({musicVolume?: number, sfxVolume?: number, lowGraphics?: boolean}); validated, saved
		"TutorialComplete", -- client -> server, no args (finished or skipped the onboarding tutorial)
		"UpgradePurchase", -- client -> server (upgradeId: string); uses the same stall session; levels mirror as player attributes
		"InventoryRequest", -- client -> server, no args; rate-limited initial snapshot
		"InventoryUpdate", -- server -> client ({inventory: {[string]: number}, fishReady: boolean, softPawsReady: boolean})
		"ItemUse", -- client -> server (itemId: string, optional throwTarget: Vector3)
		"Slap", -- client -> server, no args. Rate-limited by Config/Slap.Cooldown.
		"SlapHit", -- server -> client (velocity: Vector3) knockback for the slapped player
		"SlapEffect", -- server -> all clients (position: Vector3, hit: boolean)
		"HudState", -- server -> client (HudService.GetSnapshot result; badges/timers are server authoritative)
		"ExclusiveShopState", -- server -> client (offers, actual prices, recipient list and server luck snapshot)
		"IndexUpdated", -- server -> client (mutation discoveries, progress, milestone and bonus snapshot)
		"PlaytimeRewardState", -- server -> client (session rewards, server deadlines, claimed/ready states)
	},
	Functions = {
		"HudSnapshot", -- client -> server, no args; rate-limited HUD snapshot
		"HudHome", -- client -> server, no args; validates own plot/alive/no cat transit/cooldown, returns (ok, textKey, snapshot)
		"HudAutoCollect", -- client -> server (enabled: boolean); ownership checked, saves setting; (ok, textKey, snapshot)
		"HudShopSeen", -- client -> server, no args; records viewed catalog revision, returns HUD snapshot
		"HudMerge", -- client -> server, no args; previews own merge groups anywhere, grants action session only near own machine
		"ExclusiveShopSnapshot", -- client -> server, no args; rate-limited exclusive offers and eligible recipient snapshot
		"ExclusiveShopPurchase", -- client -> server (offerKey: string, recipientUserId?: number); validates offer/price and durable gift intent
		"GetIndex", -- client -> server, no args; rate-limited mutation discovery/milestone snapshot
		"ClaimIndexRewards", -- client -> server (tabId: string, threshold?: number); repeat-safe milestone claim
		"PlaytimeRewardsGet", -- client -> server, no args; loaded session playtime reward snapshot
		"PlaytimeRewardsClaim", -- client -> server (rewardId: string); validates monotonic time, capacity and session claim ledger
		"RebirthSkipRequest", -- client -> server (keepIds: {string}); validates and persists keep selection before native product prompt
	},
}

table.freeze(definitions.Events)
table.freeze(definitions.Functions)

return table.freeze(definitions)


