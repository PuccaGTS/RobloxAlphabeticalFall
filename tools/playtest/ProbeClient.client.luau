--!nocheck
-- Клиентская половина зонда: что видит ребёнок. Отчёт уходит серверному зонду.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local report = ReplicatedStorage:WaitForChild("ZZ_ProbeReport")
local player = Players.LocalPlayer
task.wait(6)
local gui = player:WaitForChild("PlayerGui")
local names = {}
for _, child in gui:GetChildren() do
	table.insert(names, child.Name)
end
report:FireServer("PlayerGui: " .. table.concat(names, ", "))
report:FireServer("DevTools attr = " .. tostring(player:GetAttribute("DevTools")))

-- Раз в секунду: что под ногами у персонажа на клиенте.
local lastLine = ""
while true do
	task.wait(1)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -60, 0), params)
		local venues = workspace:FindFirstChild("Venues")
		local line = string.format(
			"root %.0f,%.0f,%.0f anchored=%s below=%s venues=%s",
			root.Position.X, root.Position.Y, root.Position.Z, tostring(root.Anchored),
			hit and (hit.Instance:GetFullName() .. " @" .. string.format("%.1f", hit.Distance)) or "nothing",
			venues and tostring(#venues:GetDescendants()) or "none"
		)
		if line ~= lastLine then
			report:FireServer(line)
			lastLine = line
		end
	end
end
