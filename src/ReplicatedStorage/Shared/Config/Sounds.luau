--!strict
-- Sound ids (SoundController). "" = placeholder (silent). Only Roblox-approved/free sounds may be used and
-- never copyrighted music. The rbxasset:// entries are sounds that ship with the Roblox client.
-- Fill the placeholders with approved Creator Store audio ids ("rbxassetid://<id>").

return table.freeze({
	Effects = table.freeze({
		CatchSuccess = table.freeze({ id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.6 }),
		CatchFail = table.freeze({ id = "", volume = 0.5 }), -- placeholder (swoosh.wav is not approved for this place)
		Slap = table.freeze({ id = "rbxasset://sounds/button.wav", volume = 0.9 }), -- placeholder thwack
		Purchase = table.freeze({ id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.5 }),
		Click = table.freeze({ id = "rbxasset://sounds/button.wav", volume = 0.35 }),
		StealAlarm = table.freeze({ id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.9 }), -- placeholder: replace with an alarm
		Homecoming = table.freeze({ id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.7 }),
	}),
	-- Meow on a successful catch, per rarity (placeholders).
	Meow = table.freeze({ Common = "", Uncommon = "", Rare = "", Epic = "", Legendary = "", Mythic = "", Secret = "" }),
	MeowVolume = 0.7,
	Purr = "", -- looped near your own seated cats (placeholder)
	PurrVolume = 0.3,
	PurrDistance = 14,
	Music = "", -- background music (placeholder; never copyrighted music)
	DefaultMusicVolume = 0.5,
	DefaultSfxVolume = 0.8,
})

