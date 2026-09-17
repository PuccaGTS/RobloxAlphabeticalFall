--!nocheck
--[[
	Участок со всеми постройками на максимуме и всем заработанным учёбой —
	четыре снимка: сверху, от калитки, с двух задних углов.

	  python tools/render/run.py tools/render/PlotCheck.server.luau build/render
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = ServerScriptService:WaitForChild("Server")
require(ReplicatedStorage.Shared.Net.RemoteDefs).init()
local BaseService = require(Server.Services.BaseService)
local Base = require(ReplicatedStorage.Shared.Config.Base)

local ok, err = pcall(function()
	BaseService.build()
	local levels = {}
	for _, id in Base.ids() do
		levels[id] = Base.maxLevel(id)
	end
	local letters = { "a", "b", "v", "g", "d", "ye", "yo", "zh", "z", "i", "j", "k" }
	BaseService.preview(1, levels, {
		flags = 11,
		mathFlags = 11,
		arch = true,
		spire = true,
		countSpire = true,
		letterRooms = letters,
		mathRooms = {},
		stageFlags = { 1, 2, 3, 4 },
	})
end)
if not ok then
	print("FAIL " .. tostring(err))
end

local plot = BaseService.plotCFrame(1)
local ground = Instance.new("Part")
ground.Anchored = true
ground.Size = Vector3.new(400, 1, 400)
ground.CFrame = plot * CFrame.new(0, -0.5, 0)
ground.Color = Color3.fromRGB(120, 170, 110)
ground.Parent = workspace

local function look(from: Vector3, to: Vector3): CFrame
	return CFrame.lookAt((plot * CFrame.new(from)).Position, (plot * CFrame.new(to)).Position)
end

local only = nil -- "close" — только крупные планы наборов

if only ~= "close" then
	Render.shot("plot_top", look(Vector3.new(0, 110, 0.01), Vector3.new(0, 0, 0)), 360, 360, 36)
	Render.shot("plot_gate", look(Vector3.new(0, 28, -62), Vector3.new(0, 2, 2)), 480, 300, 55)
	Render.shot("plot_back_left", look(Vector3.new(-38, 18, 50), Vector3.new(-10, 2, 20)), 480, 300, 55)
	Render.shot("plot_back_right", look(Vector3.new(38, 16, 48), Vector3.new(14, 2, 22)), 480, 300, 55)
end
if only ~= "wide" then
	Render.shot("close_garden", look(Vector3.new(-8, 9, -16), Vector3.new(-23, 3, -1)), 400, 260, 60)
	Render.shot("close_playground", look(Vector3.new(-12, 10, 10), Vector3.new(-12, 2, 25)), 400, 260, 70)
	Render.shot("close_pets", look(Vector3.new(12, 7, 13), Vector3.new(14, 1.5, 25)), 400, 260, 70)
	Render.shot("close_transport", look(Vector3.new(9, 9, -12), Vector3.new(23, 4, -8)), 400, 260, 75)
	Render.shot("close_carousel", look(Vector3.new(-12, 6, -26), Vector3.new(-23, 3, -20)), 320, 220, 60)
end
