--!strict
-- Collects connections, instances, threads, and cleanup functions so they can be released together.
-- Typical use: one Maid per player, Clean() on PlayerRemoving.

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: { _tasks: { any } }, Maid))

function Maid.new(): Maid
	return setmetatable({ _tasks = {} }, Maid)
end

-- Adds a task and returns it, so `local conn = maid:Add(signal:Connect(...))` works.
function Maid.Add<T>(self: Maid, item: T): T
	table.insert(self._tasks, item)
	return item
end

-- Releases tasks in reverse order of addition. The Maid stays usable afterwards.
function Maid.Clean(self: Maid): ()
	local tasks = self._tasks
	self._tasks = {}

	for index = #tasks, 1, -1 do
		local item = tasks[index]
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			item:Destroy()
		elseif kind == "thread" then
			if coroutine.status(item) ~= "dead" then
				pcall(task.cancel, item)
			end
		elseif kind == "function" then
			item()
		elseif kind == "table" then
			if type(item.Destroy) == "function" then
				item:Destroy()
			elseif type(item.Disconnect) == "function" then
				item:Disconnect()
			end
		end
	end
end

Maid.Destroy = Maid.Clean

return Maid

