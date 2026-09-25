--!nocheck
--[[
	Три секрета на уровень и охота за ними: табличка портала «✨ 0 из 3»,
	три золотые буквы в забеге (касание — +15 ⭐ и «Секрет N из 3»), пад
	«Секреты» у портала ведёт на ранний уровень, где найдено не всё, и такой
	повтор не трогает сохранку текущего уровня.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local ProgressService = require(Services.ProgressService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(8)

	local started = {}
	ChallengeService.onStarted(function(p, spec)
		if p == player then
			table.insert(started, spec)
		end
	end)

	_G.ZZ_Shot(player, "hunt_portal", CFrame.lookAt(Vector3.new(-20, 12, 26), Vector3.new(-36, 8, -14)), 70)
	task.wait(4.5)

	ChallengeService.startFor(player, "tunnel_run")
	task.wait(6)
	local spec = started[#started]
	note(`run level={spec and spec.level} secrets={spec and #spec.params.secrets}`)

	local tiles = {}
	for _, d in workspace:GetDescendants() do
		if string.sub(d.Name, 1, 11) == "SecretTile_" and d:IsA("BasePart") then
			tiles[tonumber(string.sub(d.Name, 12))] = d
		end
	end
	local starsBefore = ProfileService.get(player).stars
	for index = 1, 3 do
		local tile = tiles[index]
		note(`tile {index}: {tile and tostring(tile.Position) or "нет"}`)
		if tile then
			if index == 1 then
				local root = player.Character.HumanoidRootPart
				root.Anchored = true
				root.CFrame = tile.CFrame * CFrame.new(0, 1, 16)
				task.wait(2)
				_G.ZZ_Shot(
					player,
					"hunt_secret",
					tile.CFrame * CFrame.new(3, 3, 14) * CFrame.Angles(-0.1, 0.15, 0),
					60
				)
				task.wait(4.5)
				root.Anchored = false
			end
			player.Character.HumanoidRootPart.CFrame = tile.CFrame
			task.wait(1.5)
		end
	end
	note(
		`found on level 1: {ProgressService.secretCounts(player)[1]} stars +{ProfileService.get(player).stars - starsBefore}`
	)
	_G.ZZ_Shot(player, "ui_hunt_toast", CFrame.lookAt(Vector3.new(0, 20, 40), Vector3.new(0, 0, 0)), 70)
	task.wait(4.5)

	-- Домой; пройдено два уровня, текущий третий со своей сохранкой.
	ChallengeService.abort(player)
	task.wait(2)
	ProfileService.update(player, function(p)
		p.levels.letters = 2
		p.runs.tunnel_run = {
			challengeId = "tunnel_run",
			seed = 777,
			letters = { "a", "b", "v" },
			difficulty = 2,
			level = 3,
			checkpoint = 1,
			savedAt = os.time(),
		}
	end)
	task.wait(1)
	_G.ZZ_Shot(player, "hunt_pad", CFrame.lookAt(Vector3.new(-30, 10, -8), Vector3.new(-45, 5, -24)), 70)
	task.wait(4.5)

	local pad = workspace.Hub.SecretsPad
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 4, 0)))
	task.wait(6)
	spec = started[#started]
	note(
		`hunt run: level={spec and spec.level} replay={spec and spec.params.replay} resumeFrom={spec and spec.params.resumeFrom}`
	)
	local saved = ProfileService.get(player).runs.tunnel_run
	note(`saved current run: level={saved and saved.level} checkpoint={saved and saved.checkpoint}`)
end
