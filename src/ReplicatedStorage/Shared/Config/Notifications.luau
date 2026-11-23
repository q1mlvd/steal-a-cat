--!strict
-- On-screen notification styles.

export type Style = "Info" | "Success" | "Error" | "Announcement" | "Alert" | "Homecoming"

export type StyleConfig = {
	color: Color3,
	duration: number, -- seconds on screen
	banner: boolean?, -- big centred banner instead of a toast
}

local styles: { [Style]: StyleConfig } = {
	Info = { color = Color3.fromRGB(255, 255, 255), duration = 2.5 },
	Success = { color = Color3.fromRGB(120, 255, 140), duration = 2.5 },
	Error = { color = Color3.fromRGB(255, 110, 110), duration = 2.5 },
	Announcement = { color = Color3.fromRGB(255, 215, 80), duration = 5, banner = true },
	Alert = { color = Color3.fromRGB(255, 70, 70), duration = 4, banner = true }, -- urgent, e.g. your cat is being stolen
	Homecoming = { color = Color3.fromRGB(120, 255, 200), duration = 4, banner = true }, -- a stolen cat is back home (confetti)
}
for _, style in styles do
	table.freeze(style)
end

local Notifications = {
	Styles = table.freeze(styles),
	FadeTime = 0.25,
	MaxToasts = 3,
}

function Notifications.IsStyle(value: unknown): boolean
	return type(value) == "string" and styles[value :: Style] ~= nil
end

return table.freeze(Notifications)

