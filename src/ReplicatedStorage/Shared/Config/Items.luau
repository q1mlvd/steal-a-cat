--!strict
-- One catalog for prices, inventory limits and future shop extensions.
export type ItemDefinition = {
	id: string, name: string, description: string, price: number,
	type: "consumable" | "permanent", maxStack: number, icon: string, hotbarSlot: number?,
	category: "Catching" | "Stealing" | "Defense", permanentScope: ("player" | "cat")?,
}

local effects = table.freeze({
	YarnBall = table.freeze({Duration = 3, TargetRadius = 15}),
	Fish = table.freeze({GreenZoneMultiplier = 1.5, MaximumGreenWidth = 0.8}),
	BaitCan = table.freeze({Radius = 40, Duration = 15}),
	Net = table.freeze({CatchDistance = 10}),
	LaserPointer = table.freeze({GraceSeconds = 3, CharacterLoadTimeout = 10}),
	Catnip = table.freeze({Radius = 30, Duration = 5}),
})

local list: {ItemDefinition} = {
	{id="YarnBall", name="Yarn Ball", description="Throw to stop the nearest wild cat for 3 seconds.", price=500, type="consumable", maxStack=99, icon="rbxassetid://107651976125689", hotbarSlot=1, category="Catching"},
	{id="Fish", name="Fish", description="Widen the green zone by 50% on your next catch attempt.", price=1000, type="consumable", maxStack=99, icon="rbxassetid://100733193003512", hotbarSlot=2, category="Catching"},
	{id="BaitCan", name="Bait Can", description="Place bait to attract wild cats within 40 studs for 15 seconds.", price=5000, type="consumable", maxStack=99, icon="rbxassetid://133003800755895", hotbarSlot=3, category="Catching"},
	{id="Net", name="Net", description="Permanent: catch wild cats from 10 studs away.", price=15000, type="permanent", maxStack=1, icon="rbxassetid://79732471631823", hotbarSlot=6, category="Catching", permanentScope="player"},
	{id="LaserPointer", name="Laser Pointer", description="Send a freshly caught cat walking home to a free pillow.", price=50000, type="consumable", maxStack=99, icon="rbxassetid://101642475455163", hotbarSlot=4, category="Catching"},
	{id="Catnip", name="Catnip", description="Wild cats within 30 studs stop fleeing for 5 seconds.", price=200000, type="consumable", maxStack=99, icon="rbxassetid://81844483743845", hotbarSlot=5, category="Catching"},
	{id="SoftPaws", name="Soft Paws", description="Your next successful steal sends no theft alert. Bells still track you.", price=10000, type="consumable", maxStack=99, icon="rbxassetid://118247081051670", hotbarSlot=1, category="Stealing"},
	{id="Bell", name="Bell", description="Permanently attach to a nearby owned cat. Track it if stolen, even after placement.", price=5000, type="permanent", permanentScope="cat", maxStack=99, icon="rbxassetid://86665454251537", hotbarSlot=1, category="Defense"},
	{id="GuardDog", name="Guard Dog", description="Permanent plot guard: patrols, chases thieves and makes them drop stolen cats.", price=100000, type="permanent", permanentScope="player", maxStack=1, icon="rbxassetid://101446803745891", hotbarSlot=6, category="Defense"},
	{id="BoxTrap", name="Box Trap", description="Place in your house. A thief carrying your cat gets stuck for 3 seconds.", price=25000, type="consumable", maxStack=99, icon="rbxassetid://100918671977623", hotbarSlot=2, category="Defense"},
	{id="BribeFood", name="Bribe Food", description="Reduce a nearby stolen cat you own by 30 loyalty toward its original owner.", price=20000, type="consumable", maxStack=99, icon="rbxassetid://106825077734840", hotbarSlot=2, category="Stealing"},
	{id="Vacuum", name="Vacuum", description="Scare a nearby thief into dropping stolen cats, which run home.", price=40000, type="consumable", maxStack=99, icon="rbxassetid://107227021764573", hotbarSlot=3, category="Defense"},
}
local byId: {[string]: ItemDefinition} = {}
for _, item in list do
	table.freeze(item)
	byId[item.id] = item
end
local Items = {
	List=table.freeze(list), Effects=effects,
	Hotbar=table.freeze({
		SlotCount=6, MinTouchSlot=44, TouchSlot=56, Gap=6, TabHeight=28, TouchTabHeight=44,
		Bottom=14, PortraitColumns=3, TouchSideReserve=112, PortraitControlHeight=132,
		MoreWidth=44, PickupSeconds=0.65, PickupSize=Vector2.new(72,44),
		SettingsAttribute="Setting_HotbarSlots", SettingsCooldown=0.2,
		InventoryCard=Vector2.new(112,130), InventoryHeight=530, InventoryWidth=560,
		AssignHeight=44, EmptyHeight=90,
	}),
}
function Items.Get(id: string): ItemDefinition?
	return byId[id]
end
return table.freeze(Items)


