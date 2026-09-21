--!nocheck
-- Фото-зона: общий вид рамки и кадр «фотографа», когда ребёнок встал на метку.
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(10)
	local zone = workspace.Hub.Playground:FindFirstChild("Play_photo")
	local mark = zone and zone:FindFirstChild("PhotoMark")
	if not mark then
		note("NO PHOTO ZONE")
		return
	end
	local pose = mark:GetAttribute("Camera")
	_G.ZZ_Shot(player, "photo_zone", pose * CFrame.new(6, 3, 8), 70)
	Teleport.to(player, CFrame.new(mark.Position + Vector3.new(0, 3, 0)))
	task.wait(1.2)
	_G.ZZ_Shot(player, "photo_pose", pose, 55)
	local root = player.Character.HumanoidRootPart
	note(
		string.format(
			"root on mark: %.1f studs",
			((root.Position - mark.Position) * Vector3.new(1, 0, 1)).Magnitude
		)
	)
end
