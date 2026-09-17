--!nocheck
--[[
	Буквята дома: участок №1 с домом и шестью буквятами над двором.
	Клиентский PetController запускается прямо здесь — в Studio без Play
	Heartbeat идёт, и буквята встают на свои круги.

	  python tools/render/run.py tools/render/YardPetsCheck.server.luau build/render
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local Server = ServerScriptService:WaitForChild("Server")
require(ReplicatedStorage.Shared.Net.RemoteDefs).init()
local BaseService = require(Server.Services.BaseService)
local Base = require(ReplicatedStorage.Shared.Config.Base)

BaseService.build()
local levels = {}
for _, id in Base.ids() do
	levels[id] = Base.maxLevel(id)
end
BaseService.preview(1, levels, { flags = 11, mathFlags = 11, arch = true, spire = true, countSpire = true, letterRooms = {}, mathRooms = {}, stageFlags = {} })
workspace.Plots:SetAttribute("YardPets_1", "1:a,b,v,g,d,ye,yo,zh")

-- Буквята дома не рисуются дальше 220 студов от камеры: ставим камеру к участку.
workspace.CurrentCamera.CFrame = BaseService.plotCFrame(1) * CFrame.new(0, 20, -50)

local ok, err = pcall(function()
	local PetController = require(StarterPlayer.StarterPlayerScripts.Client.Controllers.PetController)
	PetController.init()
end)
if not ok then
	print("FAIL PetController " .. tostring(err))
end
local beats = 0
RunService.Heartbeat:Connect(function()
	beats += 1
end)
task.wait(2)
print(`INFO heartbeats {beats}`)
local pets = workspace:FindFirstChild("AlphabetFallPets")
print(`INFO pets folder {pets and #pets:GetChildren() or 0}`)

local plot = BaseService.plotCFrame(1)
local function look(from: Vector3, to: Vector3): CFrame
	return CFrame.lookAt((plot * CFrame.new(from)).Position, (plot * CFrame.new(to)).Position)
end
Render.shot("yard_pets", look(Vector3.new(0, 26, -52), Vector3.new(0, 8, 0)), 480, 320, 55)
