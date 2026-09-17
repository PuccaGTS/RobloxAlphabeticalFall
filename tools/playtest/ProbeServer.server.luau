--!nocheck
--[[
	Зонд Play-проверки: кладётся в место только для tools/playtest/run.py.
	Пишет, что происходит с игроком, и завершает тест отчётом.
	Сценарий — модуль ZZ_Scenario рядом (tools/playtest/scenarios/*.luau).
]]
local StudioTestService = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lines = {}
local t0 = os.clock()
local function note(text)
	table.insert(lines, string.format("%6.2f %s", os.clock() - t0, text))
end
LogService.MessageOut:Connect(function(message, kind)
	if not message:find("не загрузилась") and not message:find("не сходится") then
		note(`LOG {kind.Name} {message}`)
	end
end)
local report = Instance.new("RemoteEvent")
report.Name = "ZZ_ProbeReport"
report.Parent = ReplicatedStorage
report.OnServerEvent:Connect(function(_, text)
	note("CLIENT " .. tostring(text))
end)

local finished = false
local function finish()
	if finished then
		return
	end
	finished = true
	StudioTestService:EndTest(table.concat(lines, "\n"))
end
task.delay(240, function()
	note("TIMEOUT")
	finish()
end)

local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
note("player joined " .. player.Name)
player.CharacterAdded:Connect(function()
	note("CHARACTER ADDED")
end)
local ok, err = pcall(require(script.Parent:WaitForChild("ZZ_Scenario")), player, note)
if not ok then
	note("SCENARIO FAIL " .. tostring(err))
end
finish()
