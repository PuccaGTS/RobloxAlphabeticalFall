--!nocheck
--[[
	Снимки экрана из настоящего Play. Сервер присылает кадр камеры, клиент
	ставит камеру и ждёт прорисовку, а снимает окно Studio уже стенд
	(tools/playtest/run.py, PrintWindow): из игры пиксели экрана не прочитать.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shot = ReplicatedStorage:WaitForChild("ZZ_Shot")
local camera = workspace.CurrentCamera

shot.OnClientEvent:Connect(function(name, cframe, fov)
	-- «release» ждёт предыдущий снимок; обработчику он не кадр. Раньше он выключал
	-- интерфейс и падал на пустом cframe — после первого снимка UI не возвращался.
	if typeof(cframe) ~= "CFrame" then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local hidden = {}
	-- Снимки ui_* — вместе с интерфейсом: проверяется сам экран, а не мир.
	local keepUI = string.sub(name, 1, 3) == "ui_"
	for _, screen in gui:GetChildren() do
		if not keepUI and screen:IsA("ScreenGui") and screen.Enabled then
			screen.Enabled = false
			table.insert(hidden, screen)
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cframe
	camera.FieldOfView = fov or 70
	pcall(function()
		Players.LocalPlayer:RequestStreamAroundAsync(cframe.Position, 5)
	end)
	task.wait(4)
	shot:FireServer(name, "ready")
	shot.OnClientEvent:Wait()
	for _, screen in hidden do
		screen.Enabled = true
	end
	camera.CameraType = Enum.CameraType.Custom
end)
