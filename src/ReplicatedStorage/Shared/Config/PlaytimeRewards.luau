--!strict
-- Rewards reset each server session. Time starts when this session's profile is loaded.
-- The larger ninth tile unlocks at 75 minutes; the first eight unlock at 5..60 minutes.
export type Reward = {id: string, seconds: number, kind: string, amount: number, incomeSeconds: number?, itemId: string?, rarity: string?, bonusCoins: number?, bonusIncomeSeconds: number?}
local rewards: {Reward} = {
	{id="gift_1",seconds=5*60,kind="Coins",amount=500,incomeSeconds=60},
	{id="gift_2",seconds=10*60,kind="Item",amount=3,itemId="YarnBall"},
	{id="gift_3",seconds=15*60,kind="Coins",amount=2500,incomeSeconds=120},
	{id="gift_4",seconds=20*60,kind="Item",amount=2,itemId="Fish"},
	{id="gift_5",seconds=30*60,kind="Coins",amount=10000,incomeSeconds=240},
	{id="gift_6",seconds=40*60,kind="Item",amount=2,itemId="BaitCan"},
	{id="gift_7",seconds=50*60,kind="Cat",amount=1,rarity="Rare"},
	{id="gift_8",seconds=60*60,kind="Cat",amount=1,rarity="Epic"},
	{id="gift_9",seconds=75*60,kind="Cat",amount=1,rarity="Epic",bonusCoins=50000,bonusIncomeSeconds=600},
}
local byId: {[string]: Reward} = {}
for _, reward in rewards do byId[reward.id] = table.freeze(reward) end
local config = {
	Rewards=table.freeze(rewards), SessionReset=true, TickInterval=1, RequestCooldown=0.3,
	FinalRewardId="gift_9", MaxIdLength=24,
	Ui=table.freeze({Width=820,Height=650,Columns=4,PortraitColumns=2,TileHeight=204,FinalHeight=150,
		Gap=12,HeaderHeight=44,FooterHeight=42,IconSize=58,LockIconSize=20,TextSize=18,SmallTextSize=15,ClaimHeight=44,
		Breakpoint=560,DisplayTick=0.2,GlowThickness=3,FinalIconSize=90,GlowColor=Color3.fromRGB(255,216,78)}),
}
function config.Get(id: string): Reward? return byId[id] end
return table.freeze(config)
