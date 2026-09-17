--!nocheck
-- Временный плагин стенда: только в месте с зондом запускает Play и отсылает отчёт.
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local StudioTestService = game:GetService("StudioTestService")
local ServerScriptService = game:GetService("ServerScriptService")

if not RunService:IsEdit() then
	return
end
task.wait(3)
local server = ServerScriptService:FindFirstChild("Server")
if not (server and server:FindFirstChild("ZZ_ProbeServer")) then
	return
end
local port = workspace:GetAttribute("ZZ_ProbePort")
local function post(text)
	pcall(function()
		HttpService:PostAsync(`http://127.0.0.1:{port}/`, text)
	end)
end
post("PLUGIN ready, starting play")
local ok, result = pcall(function()
	return StudioTestService:ExecutePlayModeAsync({})
end)
post((if ok then "RESULT\n" else "PLAY FAIL ") .. tostring(result))
post("DONE")
