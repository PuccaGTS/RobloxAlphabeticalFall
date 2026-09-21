--!nocheck
-- Клиентская половина зонда: что видит ребёнок. Отчёт уходит серверному зонду.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local report = ReplicatedStorage:WaitForChild("ZZ_ProbeReport")
local player = Players.LocalPlayer
-- Замер производительности по просьбе сценария perf: камера в точку, три секунды кадров, счётчики отрисовки.
local perf = if workspace:GetAttribute("ZZ_Perf") then ReplicatedStorage:WaitForChild("ZZ_Perf", 30) else nil
if perf then
	perf.OnClientInvoke = function(cframe, hideKind)
		-- hideKind: спрятать детали предметов этого вида (имя модели без номера) и мерить без них.
		if hideKind then
			for _, d in workspace:GetDescendants() do
				if d:IsA("Model") and (string.gsub(d.Name, "_%d+$", "") == hideKind or d.Name == hideKind) then
					for _, piece in d:GetDescendants() do
						if piece:IsA("BasePart") then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif hideKind == "HubBalls" and (d.Name == "Hub" or d.Name == "Venues") then
					for _, piece in d:GetDescendants() do
						if piece:IsA("Part") and piece.Shape == Enum.PartType.Ball then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif hideKind == "HubMeshes" and d.Name == "Hub" then
					for _, piece in d:GetDescendants() do
						if piece:IsA("BasePart") and (piece:FindFirstChildOfClass("SpecialMesh") or piece:IsA("MeshPart")) then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif (hideKind == "PlotBalls" or hideKind == "PlotCylinders" or hideKind == "PlotWedges") and d.Name == "Plots" then
					local shape = if hideKind == "PlotBalls" then Enum.PartType.Ball else Enum.PartType.Cylinder
					for _, piece in d:GetDescendants() do
						local match = if hideKind == "PlotWedges" then piece:IsA("WedgePart") else piece:IsA("Part") and piece.Shape == shape
						if match then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				elseif hideKind == "Plots" and d.Name == "Plots" then
					for _, piece in d:GetDescendants() do
						if piece:IsA("BasePart") then
							piece.LocalTransparencyModifier = 1
							piece:SetAttribute("ZZ_Hidden", true)
						end
					end
				end
			end
		end
		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cframe
		pcall(function()
			player:RequestStreamAroundAsync(cframe.Position, 5)
		end)
		task.wait(4)
		local RunService = game:GetService("RunService")
		local frames, total, worst = 0, 0, 0
		local connection = RunService.RenderStepped:Connect(function(dt)
			frames += 1
			total += dt
			worst = math.max(worst, dt)
		end)
		task.wait(3)
		connection:Disconnect()
		local Stats = game:GetService("Stats")
		local function stat(name)
			local ok, value = pcall(function()
				return Stats[name]
			end)
			return if ok then tostring(value) else "?"
		end
		local parts, near, shadows, lights, emitters, billboards, surfaces = 0, 0, 0, 0, 0, 0, 0
		local position = cframe.Position
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if (d.Position - position).Magnitude < 250 then
					near += 1
					if d.CastShadow and d.Transparency < 1 then
						shadows += 1
					end
				end
			elseif d:IsA("Light") and d.Enabled then
				lights += 1
			elseif d:IsA("ParticleEmitter") and d.Enabled then
				emitters += 1
			elseif d:IsA("BillboardGui") and d.Enabled then
				billboards += 1
			elseif d:IsA("SurfaceGui") and d.Enabled then
				surfaces += 1
			end
		end
		camera.CameraType = Enum.CameraType.Custom
		for _, d in workspace:GetDescendants() do
			if d:GetAttribute("ZZ_Hidden") then
				d.LocalTransparencyModifier = 0
				d:SetAttribute("ZZ_Hidden", nil)
			end
		end
		return string.format(
			"fps=%.0f worst=%.0fms parts=%d near250=%d nearShadow=%d lights=%d emitters=%d billboards=%d surfaceGuis=%d draw=%s tris=%s shadowDraw=%s mem=%s",
			frames / total, worst * 1000, parts, near, shadows, lights, emitters, billboards, surfaces,
			stat("SceneDrawcallCount"), stat("SceneTriangleCount"), stat("ShadowsDrawcallCount"),
			tostring(math.floor(Stats:GetTotalMemoryUsageMb()))
		)
	end
end

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

-- Звуки по просьбе сценария (метка ZZ_AudioReport): что играет, загрузилось ли, сколько длится.
workspace:GetAttributeChangedSignal("ZZ_AudioReport"):Connect(function()
	local lines = {}
	local SoundService = game:GetService("SoundService")
	for _, root in { SoundService, workspace } do
		for _, d in root:GetDescendants() do
			if d:IsA("Sound") and d.SoundId ~= "" and not d.SoundId:find("^rbxasset://") then
				table.insert(lines, string.format("%s[%s] loaded=%s len=%.0f playing=%s vol=%.2f", d.Name, d.SoundId:match("%d+") or "?", tostring(d.IsLoaded), d.TimeLength, tostring(d.IsPlaying), d.Volume))
			end
		end
	end
	report:FireServer("AUDIO " .. workspace:GetAttribute("ZZ_AudioReport") .. ": " .. table.concat(lines, " | "))
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
