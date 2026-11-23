--!strict
-- Slap: knocks players back; a slapped carrier drops their cat(s).

return table.freeze({
	Key = Enum.KeyCode.F,
	GamepadKey = Enum.KeyCode.ButtonY,
	ButtonTitle = "Slap",
	Cooldown = 1.5, -- seconds
	CooldownTolerance = 0.1, -- server accepts slaps this much early (latency)
	Range = 7, -- studs
	FacingDot = 0.2, -- target must be roughly in front (dot of look vector and direction)
	KnockbackSpeed = 55,
	KnockbackUp = 22,
	KnockbackGrace = 1.5, -- seconds the speed check ignores a slapped player
	SoundId = "", -- placeholder: "rbxassetid://<id>"
})

