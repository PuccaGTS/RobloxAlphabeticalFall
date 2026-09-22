--!nocheck
--[[
	Катания парка второй очереди: карусель, горка-спираль, воздушный шар.
	Снимки каждого, потом посадка — сервер смотрит, куда едет персонаж.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(8)
	local root = player.Character.HumanoidRootPart
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local park = workspace.Hub.Playground

	local function at(id)
		return Playground.position(Playground.expect(id))
	end

	-- Карусель: общий вид, потом посадка на круг — два оборота на лошадке.
	local carousel = at("carousel")
	_G.ZZ_Shot(
		player,
		"r2_carousel",
		CFrame.lookAt(carousel * 0.82 + Vector3.new(0, 9, 0), carousel + Vector3.new(0, 5, 0)),
		60
	)
	local pad = park.Play_carousel.BoardPad
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3, 0)))
	task.wait(3)
	local start = root.Position
	note(
		string.format(
			"carousel: sit=%s, root from centre %.1f",
			tostring(humanoid.Sit),
			((root.Position - carousel) * Vector3.new(1, 0, 1)).Magnitude
		)
	)
	_G.ZZ_Shot(
		player,
		"r2_carousel_ride",
		CFrame.lookAt(
			root.Position + Vector3.new(0, 6, 0) + (root.Position - carousel).Unit * 14,
			root.Position
		),
		60
	)
	task.wait(4)
	note(
		string.format(
			"carousel: moved %.1f studs in 4 s, sit=%s",
			(root.Position - start).Magnitude,
			tostring(humanoid.Sit)
		)
	)
	humanoid.Sit = false
	humanoid.Jump = true
	task.wait(2)

	-- Горка: вид сбоку, потом круг наверху — съехать и вылететь на траву.
	local slide = at("slide")
	_G.ZZ_Shot(
		player,
		"r2_slide",
		CFrame.lookAt(slide * 0.84 + Vector3.new(0, 10, 0), slide + Vector3.new(0, 9, 0)),
		60
	)
	local top = park.Play_slide.BoardPad
	Teleport.to(player, CFrame.new(top.Position + Vector3.new(0, 3, 0)))
	local deckY = top.Position.Y
	local waited = 0
	while root.Position.Y > deckY + 0.5 and waited < 8 do
		task.wait(0.1)
		waited += 0.1
	end
	local lowest, travelled, last = math.huge, 0, root.Position
	for step = 1, 32 do
		task.wait(0.2)
		lowest = math.min(lowest, root.Position.Y)
		travelled += (root.Position - last).Magnitude
		last = root.Position
		if step == 10 then
			_G.ZZ_Shot(
				player,
				"r2_slide_ride",
				CFrame.lookAt(root.Position + Vector3.new(12, 6, 12), root.Position),
				60
			)
		end
	end
	note(
		string.format(
			"slide: started after %.1f s, travelled %.0f studs, lowest root Y %.1f, landed %.1f from tower, sit=%s",
			waited,
			travelled,
			lowest,
			((root.Position - slide) * Vector3.new(1, 0, 1)).Magnitude,
			tostring(humanoid.Sit)
		)
	)

	-- Шар: снимок на земле, потом дождаться стоянки, сесть и подняться.
	local balloon = at("balloon")
	_G.ZZ_Shot(
		player,
		"r2_balloon",
		CFrame.lookAt(balloon * 0.8 + Vector3.new(0, 26, 0), balloon + Vector3.new(0, 12, 0)),
		60
	)
	local board = park.Play_balloon.BoardPad
	for _ = 1, 90 do
		local _, grounded = Rides.balloonAt(workspace:GetServerTimeNow() + 2, Vector3.xAxis)
		local _, groundedNow = Rides.balloonAt(workspace:GetServerTimeNow(), Vector3.xAxis)
		if grounded and groundedNow then
			break
		end
		task.wait(1)
	end
	Teleport.to(player, CFrame.new(board.Position + Vector3.new(0, 3, 0)))
	local highest = 0
	for step = 1, 40 do
		task.wait(1)
		highest = math.max(highest, root.Position.Y)
		if step == 30 then
			_G.ZZ_Shot(
				player,
				"r2_balloon_view",
				CFrame.lookAt(
					root.Position + Vector3.new(0, 4, 0) - root.CFrame.LookVector * 10,
					root.Position + root.CFrame.LookVector * 60 - Vector3.new(0, 40, 0)
				),
				70
			)
			_G.ZZ_Shot(player, "r2_balloon_sky", CFrame.lookAt(Vector3.new(0, 20, 30), root.Position), 60)
		end
	end
	note(
		string.format(
			"balloon: highest root Y %.1f (ground %.1f), sit=%s",
			highest,
			balloon.Y,
			tostring(humanoid.Sit)
		)
	)
end
