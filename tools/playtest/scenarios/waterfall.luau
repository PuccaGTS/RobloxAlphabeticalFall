--!nocheck
-- Водопад на горизонте: с точки появления, с края участков и вблизи.
return function(player, note)
	local Horizon = require(game:GetService("ReplicatedStorage").Shared.Config.Horizon)
	task.wait(12)
	local foot = Horizon.waterfallFrame()
	local fall = workspace.Hub.Horizon:FindFirstChild("Waterfall")
	note(`waterfall parts {fall and #fall:GetDescendants() or 0}`)
	_G.ZZ_Shot(player, "wf_spawn", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 25, -300)), 70)
	_G.ZZ_Shot(
		player,
		"wf_houses",
		CFrame.lookAt(Vector3.new(0, 12, -300), foot.Position + Vector3.new(0, 30, 0)),
		70
	)
	_G.ZZ_Shot(
		player,
		"wf_close",
		CFrame.lookAt((foot * CFrame.new(20, 25, -70)).Position, foot.Position + Vector3.new(0, 25, 0)),
		70
	)
end
