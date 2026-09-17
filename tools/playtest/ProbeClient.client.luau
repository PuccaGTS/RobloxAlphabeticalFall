--!nocheck
-- Клиентская половина зонда: что видит ребёнок. Отчёт уходит серверному зонду.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local report = ReplicatedStorage:WaitForChild("ZZ_ProbeReport")
local player = Players.LocalPlayer
-- Сценарий зовёт радугу меткой в Workspace: у сервера до клиентского контроллера не дотянуться.
workspace:GetAttributeChangedSignal("ZZ_Rainbow"):Connect(function()
	local scripts = player:WaitForChild("PlayerScripts")
	require(scripts.Client.Controllers.LiveWorldController).rainbow(120)
end)
task.wait(6)
local gui = player:WaitForChild("PlayerGui")
local names = {}
for _, child in gui:GetChildren() do
	table.insert(names, child.Name)
end
report:FireServer("PlayerGui: " .. table.concat(names, ", "))
report:FireServer("DevTools attr = " .. tostring(player:GetAttribute("DevTools")))
-- Где кнопки в углу: панель разработчика и родительский режим.
task.wait(2)
for _, screen in gui:GetChildren() do
	if screen:IsA("ScreenGui") then
		for _, button in screen:GetDescendants() do
			if workspace:GetAttribute("ZZ_Buttons") and button:IsA("GuiButton") and button.AbsoluteSize.X > 0 and button.AbsolutePosition.X < 200 then
				local shown = button.Visible and screen.Enabled
				local cursor = button.Parent
				while shown and cursor and cursor ~= screen do
					if cursor:IsA("GuiObject") and not cursor.Visible then
						shown = false
					end
					cursor = cursor.Parent
				end
				local text = if button:IsA("TextButton") then button.Text else "img"
				report:FireServer(string.format("BUTTON %s.%s '%s' at %s size %s shown=%s order=%d", screen.Name, button.Name, text, tostring(button.AbsolutePosition), tostring(button.AbsoluteSize), tostring(shown), screen.DisplayOrder))
			end
		end
	end
end

task.delay(12, function()
	local loaded, empty, sample = 0, 0, ""
	for _, d in workspace:GetDescendants() do
		if d:IsA("MeshPart") then
			if d.MeshSize.Magnitude > 0 then
				loaded += 1
				if sample == "" then
					sample = d:GetFullName() .. " MeshSize " .. tostring(d.MeshSize) .. " Size " .. tostring(d.Size)
				end
			else
				empty += 1
			end
		end
	end
	report:FireServer(string.format("MESHES loaded=%d empty=%d sample=%s", loaded, empty, sample))
	local ContentProvider = game:GetService("ContentProvider")
	local statuses = {}
	local seen = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("SpecialMesh") and d.MeshType == Enum.MeshType.FileMesh and d.MeshId ~= "" and not seen[d.MeshId] then
			seen[d.MeshId] = true
			ContentProvider:PreloadAsync({ d })
			local status = ContentProvider:GetAssetFetchStatus(d.MeshId)
			statuses[status.Name] = (statuses[status.Name] or 0) + 1
		end
	end
	local parts = {}
	for name, count in statuses do
		table.insert(parts, name .. "=" .. count)
	end
	report:FireServer("FILEMESH fetch: " .. table.concat(parts, " "))
end)

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
