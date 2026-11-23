--!strict
-- Attribute names and State values carried by every cat Model. Shared by server and client.

export type CatState = "Wild" | "Carried" | "OnPillow" | "Returning"

return table.freeze({
	Attributes = table.freeze({
		CatId = "CatId", -- string, key into Config/Cats
		Rarity = "Rarity", -- string, key into Config/Rarities
		State = "State", -- CatState
		OwnerUserId = "OwnerUserId", -- number, WildOwnerUserId while wild
		UniqueId = "UniqueId", -- string GUID, stable identity for this cat instance
		SpawnArea = "SpawnArea", -- string DistrictName the cat spawned in (wild cats)
		CarrierUserId = "CarrierUserId", -- number while State == Carried: who is holding it (may differ from owner once stealing exists)
		PillowIndex = "PillowIndex", -- number while State == OnPillow
		Tamed = "Tamed", -- true once the taming timer finished
		TameDuration = "TameDuration", -- seconds; full taming time (for progress display)
		TameEndsAt = "TameEndsAt", -- workspace:GetServerTimeNow() when taming finishes; set only while on a pillow
		TameRemaining = "TameRemaining", -- seconds left while taming is paused (cat picked up)
		OriginalOwnerUserId = "OriginalOwnerUserId", -- number on owned cats: who first owned it (set when first placed)
		Mutation = "Mutation", -- string ("" = none); rolled on wild spawn, saved on owned cats (Config/Mutations)
		Tier = "Tier", -- "Normal" | "Mega" | "Giga" on owned cats (merging)
		Loyalty = "Loyalty", -- number on owned cats
		TimesReturned = "TimesReturned", -- number on owned cats
		PetAvailableAt = "PetAvailableAt", -- saved per-cat pet cooldown, Unix seconds
	}),
	States = table.freeze({
		Wild = "Wild" :: CatState,
		Carried = "Carried" :: CatState,
		OnPillow = "OnPillow" :: CatState,
		Returning = "Returning" :: CatState, -- stolen cat running home after being dropped
	}),
	WildOwnerUserId = 0,
})

