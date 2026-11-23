--!strict
-- Server -> client on-screen messages (toasts and server-wide announcements).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Shared.Network)
local Notifications = require(ReplicatedStorage.Shared.Config.Notifications)

local NotificationService = {
	Priority = 10,
}

local notifyEvent: RemoteEvent

function NotificationService.Notify(player: Player, message: string, style: Notifications.Style?)
	notifyEvent:FireClient(player, message, style or "Info")
end

function NotificationService.NotifyLocalized(player: Player, key: string, params: {[string]: any}, style: Notifications.Style?)
	notifyEvent:FireClient(player, {key=key,params=params}, style or "Info")
end

function NotificationService.AnnounceLocalized(key: string, params: {[string]: any})
	notifyEvent:FireAllClients({key=key,params=params}, "Announcement")
end

-- `catId` / `mutation` add the cat's portrait to the banner (rare-cat announcements).
function NotificationService.Announce(message: string, catId: string?, mutation: string?)
	if catId then
		notifyEvent:FireAllClients(message, "Announcement", { catId = catId, mutation = mutation or "" })
	else
		notifyEvent:FireAllClients(message, "Announcement")
	end
end

-- Live-event announcement; the client shows that event's icon (Config/UIAssets.Events) on the banner.
function NotificationService.AnnounceEvent(message: string, eventName: string)
	notifyEvent:FireAllClients(message, "Announcement", { event = eventName })
end

function NotificationService:Init(): ()
	notifyEvent = Network.GetEvent("Notify")
end

return NotificationService

