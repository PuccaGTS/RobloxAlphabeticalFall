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
