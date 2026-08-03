--!nocheck
--[[
	Запуск юнит-тестов. Используется только с test.project.json, в прод-сборку не попадает.

	  rojo build test.project.json -o build/test.rbxl
	  run-in-roblox --place build/test.rbxl --script tools/TestRunner.server.luau
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local devPackages = ReplicatedStorage:FindFirstChild("DevPackages")
if not devPackages then
	warn("[Tests] нет DevPackages — выполни `wally install`")
	return
end

local TestEZ = require(devPackages:WaitForChild("TestEZ"))

TestEZ.TestBootstrap:run({ ReplicatedStorage:WaitForChild("Tests") })
