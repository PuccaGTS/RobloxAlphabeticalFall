--!nocheck
--[[
	Забег глазами бегущего ребёнка: снимки из-за спины через равные отрезки пути
	и один сбоку сверху.

	  python tools/render/run.py tools/render/TunnelCheck.server.luau build/render
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = ServerScriptService:WaitForChild("Server")
require(ReplicatedStorage.Shared.Net.RemoteDefs).init()
local TunnelService = require(Server.Services.TunnelService)
local TunnelRun = require(Server.Challenges.TunnelRun)
local TrackShape = require(ReplicatedStorage.Shared.Logic.TrackShape)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local fake = { UserId = 1, Name = "Smoke", DisplayName = "Smoke", Character = nil }

local LEVEL = 1
local SHOTS = 6

-- Какое препятствие обязательно должно попасть в забег (для крупного плана), или nil.
local FOCUS = "bridge"

local spec
for attempt = 0, 40 do
	spec = TunnelRun.Rebuild({ letters = { "a", "b", "v" }, difficulty = 3, seed = 4242 + attempt, checkpoint = 0, level = LEVEL })
	local found = FOCUS == nil
	for _, obstacle in spec.params.obstacles do
		found = found or obstacle.kind == FOCUS
	end
	if found then
		break
	end
end
local ok, err = pcall(TunnelService.spawn, fake, spec)
if not ok then
	print("FAIL " .. tostring(err))
end
local model = workspace.Tunnels:FindFirstChildWhichIsA("Model")
local guards = {}
local parts = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
		if d.Transparency >= 1 then
			table.insert(guards, d)
		end
	end
end
print(`INFO parts {parts}, length {spec.params.length}`)
local sampler = TrackShape.sampler(spec.params.track, spec.params.length)
local anyGuard = guards[1]
local index = math.floor((anyGuard.Position.X - Tunnel.PLOT_ORIGIN.X) / Tunnel.PLOT_SPACING + 0.5)
local base = CFrame.new(Tunnel.PLOT_ORIGIN + Vector3.new(index * Tunnel.PLOT_SPACING, 0, 0))

local garlands = 0
for _, d in model:GetChildren() do
	if d.Name:match("^Garland_%d+_Post_1$") then
		garlands += 1
	end
end
print(`INFO garlands {garlands}, gates {#spec.params.gates}`)

local function shotAt(name: string, z: number, back: number, height: number, ahead: number)
	local at = base * sampler.flat(math.clamp(z, 0, spec.params.length))
	local eye = (at * CFrame.new(0, height, back)).Position
	local target = (at * CFrame.new(0, 5, -ahead)).Position
	Render.shot(name, CFrame.lookAt(eye, target), 420, 260, 70, guards)
end

for shot = 1, SHOTS do
	shotAt(`tunnel_{shot}`, spec.params.length * (shot - 0.5) / SHOTS, 14, 9, 20)
end
for index, gate in spec.params.gates do
	if index <= 2 then
		shotAt(`tunnel_gate_{index}`, gate.z, 26, 7, 0)
	end
end
shotAt("tunnel_finish", spec.params.length - 6, 24, 7, 0)
local post = model:FindFirstChild("Garland_2_Post_1")
if post then
	local eye = post.Position
		+ Vector3.new(0, -2, 0)
		+ post.CFrame.LookVector * -22
		+ post.CFrame.RightVector * 13
	Render.shot(
		"tunnel_garland",
		CFrame.lookAt(eye, post.Position + post.CFrame.RightVector * 13 + Vector3.new(0, 1, 0)),
		420,
		260,
		60,
		guards
	)
end
local kinds = {}
for _, child in model:GetChildren() do
	if child:IsA("Model") and child.Name:match("^Scenery_") then
		local _, size = child:GetBoundingBox()
		local key = string.format("%dx%d", math.floor(size.X), math.floor(size.Y))
		kinds[key] = (kinds[key] or 0) + 1
	end
end
local line = {}
for key, count in kinds do
	table.insert(line, `{key}:{count}`)
end
print("INFO scenery sizes " .. table.concat(line, " "))
-- Вид на долину сверху сбоку: что стоит внизу по обе стороны трассы.
local low = base * sampler.flat(spec.params.length * 0.55)
Render.shot("tunnel_valley", CFrame.lookAt((low * CFrame.new(-70, 30, 40)).Position, (low * CFrame.new(-20, -30, -40)).Position), 480, 300, 65, guards)
for _, obstacle in spec.params.obstacles do
	if obstacle.kind == FOCUS then
		local at = base * sampler.flat(obstacle.z) * CFrame.new(Tunnel.laneOffset(obstacle.lane), 0, 0)
		Render.shot(`focus_{FOCUS}`, CFrame.lookAt((at * CFrame.new(9, 7, 8)).Position, (at * CFrame.new(0, 0, -7)).Position), 420, 280, 65, guards)
		Render.shot(`focus_{FOCUS}_run`, CFrame.lookAt((at * CFrame.new(0, 6, 12)).Position, (at * CFrame.new(0, 1, -10)).Position), 420, 280, 65, guards)
		break
	end
end
local mid = base * sampler.flat(spec.params.length * 0.3)
Render.shot(
	"tunnel_side",
	CFrame.lookAt((mid * CFrame.new(60, 45, 20)).Position, (mid * CFrame.new(0, 0, -30)).Position),
	420,
	260,
	60,
	guards
)
