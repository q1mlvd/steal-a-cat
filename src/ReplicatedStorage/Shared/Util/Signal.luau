--!strict
-- Minimal pure-Luau signal for module-to-module events (same machine only; not networked).
-- Each listener runs in its own thread, so one listener erroring or yielding can't affect the others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local listeners: { [Connection]: (T...) -> () } = {}
	local signal = {}

	function signal.Connect(_self: Signal<T...>, callback: (T...) -> ()): Connection
		local connection = { Connected = true } :: any
		function connection.Disconnect(conn: Connection)
			conn.Connected = false
			listeners[conn] = nil
		end
		listeners[connection] = callback
		return connection :: Connection
	end

	function signal.Fire(_self: Signal<T...>, ...: T...)
		-- Iterate a snapshot so listeners may connect/disconnect while firing.
		for connection, callback in table.clone(listeners) do
			if connection.Connected then
				task.spawn(callback, ...)
			end
		end
	end

	function signal.DisconnectAll(_self: Signal<T...>)
		for connection in listeners do
			connection.Connected = false
		end
		table.clear(listeners)
	end

	return (signal :: any) :: Signal<T...>
end

return table.freeze(Signal)

