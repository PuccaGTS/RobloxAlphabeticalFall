--!nocheck
--[[
	Домик на дереве: общий вид, проход по подвесному мостику пешком
	(зонд ведёт персонажа, как джойстик) и спуск на тарзанке — сервер
	смотрит, сидит ли ребёнок, куда его привезло и не застрял ли он.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(22) -- зонд клиента слушает метки ZZ_* только через ~20 с после входа
	local root = player.Character.HumanoidRootPart
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local spec = Rides.TREEHOUSE
	local zone = workspace.Hub.Playground:FindFirstChild("Play_treehouse")
	local origin = zone and zone:GetAttribute("Origin")
	if not origin then
		note("NO TREEHOUSE")
		return
	end
	local function at(v)
		return (origin * CFrame.new(v)).Position
	end
	local function settle()
		for _ = 1, 40 do
			if not root.Anchored then
				break
			end
			task.wait(0.1)
		end
		task.wait(0.5)
	end

	Teleport.to(player, CFrame.new(at(Vector3.new(0, 4, -30))))
	settle()
	_G.ZZ_Shot(player, "treehouse", CFrame.lookAt(at(Vector3.new(6, 16, -40)), at(Vector3.new(0, 10, 4))), 60)
	task.wait(4.5)
	_G.ZZ_Shot(
		player,
		"treehouse_house",
		CFrame.lookAt(
			at(spec.big + Vector3.new(-6, spec.deck + 6, -16)),
			at(spec.big + Vector3.new(0, spec.deck + 3, 0))
		),
		60
	)
	task.wait(4.5)

	-- Мостик: встать у проёма большой площадки и идти к малому дереву.
	local start = spec.big + Vector3.new(spec.bigDeck / 2 - 1, spec.deck + 3, 0)
	Teleport.to(player, CFrame.lookAt(at(start), at(start + Vector3.xAxis)))
	settle()
	local dir = (at(spec.small) - at(spec.big)).Unit
	workspace:SetAttribute("ZZ_Walk", string.format("%.3f,%.3f,1.6", dir.X, dir.Z))
	local lowest = root.Position.Y
	for _ = 1, 22 do
		task.wait(0.1)
		lowest = math.min(lowest, root.Position.Y)
	end
	local rel = origin:PointToObjectSpace(root.Position)
	note(
		string.format(
			"treehouse bridge: now at x=%.1f (small deck from %.1f), y=%.1f, lowest %.1f (deck %d)",
			rel.X,
			spec.small.X - spec.smallDeck / 2,
			rel.Y,
			origin:PointToObjectSpace(Vector3.new(0, lowest, 0)).Y + origin.Y - origin.Y,
			spec.deck
		)
	)

	-- Тарзанка: встать на круг и поехать.
	local pad = zone:FindFirstChild("BoardPad")
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3, 0)))
	settle()
	note(string.format("zip: sit=%s after stepping on pad", tostring(humanoid.Sit)))
	local view = CFrame.lookAt(at(Vector3.new(14, 12, -16)), at(Rides.zipPoint(0.45) - Vector3.new(0, 3, 0)))
	_G.ZZ_Shot(player, "treehouse_zip", view, 60)
	local ymin = math.huge
	for _ = 1, 60 do
		task.wait(0.1)
		ymin = math.min(ymin, root.Position.Y)
	end
	local landed = origin:PointToObjectSpace(root.Position)
	local sand = Rides.zipLanding()
	note(
		string.format(
			"zip: sit=%s, landed %.1f from sand centre (sand radius 4.5), height %.1f",
			tostring(humanoid.Sit),
			Vector2.new(landed.X - sand.X, landed.Z - sand.Z).Magnitude,
			landed.Y
		)
	)
end
