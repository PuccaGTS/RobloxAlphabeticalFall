--!nocheck
-- Импортированные модели: стоят ли в мире и загрузились ли меши у клиента.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
return function(player, note)
	task.wait(4)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local decor = assets and assets:FindFirstChild("decor")
	note("assets decor: " .. (decor and #decor:GetChildren() or 0))
	local count = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("MeshPart") then
			count += 1
		end
	end
	note("server meshparts in workspace: " .. count)
	-- Встать рядом с первым мухомором, чтобы стриминг привёз его клиенту.
	for _, d in workspace:GetDescendants() do
		if d:IsA("MeshPart") and d.MeshId:find("4644067001") then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = CFrame.new(d.Position + Vector3.new(6, 4, 0))
				note("moved near mushroom at " .. tostring(d.Position))
			end
			break
		end
	end
	task.wait(30)
end
