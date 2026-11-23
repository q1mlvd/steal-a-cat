--!strict
-- Client input modes. Mobile-only UI (touch buttons, portrait hotbar) appears only in Touch mode; the
-- mode follows UserInputService.PreferredInput (fallback: last input type) and updates live.

export type Mode = "KeyboardMouse" | "Touch" | "Gamepad"

return table.freeze({
	Modes = table.freeze({
		KeyboardMouse = "KeyboardMouse" :: Mode,
		Touch = "Touch" :: Mode,
		Gamepad = "Gamepad" :: Mode,
	}),
	ModeAttribute = "InputMode", -- local mirror on the LocalPlayer (client only, for debugging)
	DebugModeAttribute = "DebugInputMode", -- Studio only: set on the LocalPlayer (client) to force a mode

	-- Key hints (keyboard / gamepad only)
	HintGuiName = "ControlsHint",
	HintDisplayOrder = 6,
	HintWidth = 340, -- room for Russian action labels
	HintLineHeight = 18,
	HintMargin = 10,
	HintSkinInset = 16, -- extra inset for the UI pack tooltip frame's border
	HintTextSize = 14,
	HintColor = Color3.fromRGB(62, 34, 74), -- dark text on the cream tooltip frame
	HintKeyColor = Color3.fromRGB(230, 120, 20),
	HintBackground = Color3.fromRGB(27, 29, 43),
	HintBackgroundTransparency = 0.1,
	GamepadPrefix = "Button", -- KeyCode.ButtonX -> "X"
})


