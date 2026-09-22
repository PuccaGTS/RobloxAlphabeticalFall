--!nocheck
--[[
	Площадь, парк и кольцо участков: сверху целиком, с точки появления
	и с дорожки у домов.

	  python tools/render/run.py tools/render/WorldCheck.server.luau build/render
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = ServerScriptService:WaitForChild("Server")
require(ReplicatedStorage.Shared.Net.RemoteDefs).init()
local Base = require(ReplicatedStorage.Shared.Config.Base)

for _, name in { "WorldService", "BaseService", "ChestService" } do
	local ok, err = pcall(function()
		require(Server.Services[name]).start()
	end)
	if not ok then
		print(`FAIL {name}: {err}`)
	end
end
task.wait(1)

local ring = Base.RING_RADIUS
Render.shot(
	"world_top",
	CFrame.lookAt(Vector3.new(0, 900, 0.01), Vector3.zero),
	520,
	520,
	2 * math.deg(math.atan((ring + 40) / 900))
)
Render.shot("world_spawn", CFrame.lookAt(Vector3.new(0, 40, 90), Vector3.new(0, 0, -60)), 520, 320, 65)
Render.shot(
	"world_street",
	CFrame.lookAt(Vector3.new(ring - 70, 22, 30), Vector3.new(ring, 4, -40)),
	520,
	320,
	65
)

-- Крупные планы: по одному предмету каждого вида из новых.
local Decor = require(ReplicatedStorage.Shared.Config.Decor)
local counts = {}
for _, placement in Decor.placements do
	counts[placement.id] = (counts[placement.id] or 0) + 1
end
local line = {}
for id, count in counts do
	table.insert(line, `{id}={count}`)
end
table.sort(line)
print("INFO decor " .. table.concat(line, " "))
print(`INFO placements {#Decor.placements}`)

local seen = {}
for _, placement in Decor.placements do
	local id = placement.id
	if
		not seen[id]
		and table.find({
			"mushroom_house",
			"windmill",
			"abacus",
			"crayons",
			"picnic_table",
			"mushroom",
			"log",
			"hay_bales",
		}, id)
	then
		seen[id] = true
		local item = Decor.expect(id)
		local target = Vector3.new(placement.x, 1 + item.size.Y * 0.45, placement.z)
		local away = Vector3.new(placement.x, 0, placement.z).Unit
		local distance = math.max(item.size.X, item.size.Y) * 1.6 + 6
		local eye = target - away * distance + Vector3.new(0, item.size.Y * 0.5 + 2, 0)
		Render.shot(`park_{id}`, CFrame.lookAt(eye, target), 360, 240, 60)
	end
end
