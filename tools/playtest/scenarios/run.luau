--!nocheck
--[[
	Забег мира букв глазами ребёнка: станция буквы и каждый аттракцион.
	ZZ_ONLY=7 — какой уровень пути (по умолчанию 7: там есть все аттракционы).

	Кроме снимков проверяет механику: станция открывается, когда встаёшь в круг;
	лава и валун возвращают к флажку.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	local level = tonumber(workspace:GetAttribute("ZZ_Only")) or 7
	ProfileService.update(player, function(p)
		p.levels = p.levels or {}
		p.levels.letters = level - 1
		p.runs = {}
	end)
	ChallengeService.startFor(player, "tunnel_run")
	task.wait(6)
	local model = workspace.Tunnels:FindFirstChild(`Tunnel_{player.UserId}`)
	if not model then
		note("NO TUNNEL")
		return
	end
	local root = player.Character.HumanoidRootPart
	note(`level {level} tunnel parts {#model:GetDescendants()}`)

	local function pivotOf(name)
		local found = model:FindFirstChild(name, true)
		if not found then
			return nil
		end
		return if found:IsA("Model") then found:GetPivot() else found.CFrame
	end

	-- Станция: вид от входа, потом шаг в круг.
	local letter = pivotOf("StationLetter_1")
	if letter then
		local look = letter.Position
		local eye = (letter * CFrame.new(0, 2, -22)).Position
		_G.ZZ_Shot(player, "run_station", CFrame.lookAt(eye, look), 70)
		local ring = pivotOf("StationRing_1")
		Teleport.to(
			player,
			CFrame.new(ring.Position + Vector3.new(0, 4, 0)) * letter.Rotation * CFrame.Angles(0, math.pi, 0)
		)
		task.wait(3.5)
		note(`station barrier after touch: {model:FindFirstChild("StationBarrier_1", true) ~= nil}`)
		_G.ZZ_Shot(player, "run_station_open", CFrame.lookAt(eye, look + Vector3.new(0, 6, 0)), 70)
	else
		note("NO STATION")
	end

	for _, child in model:GetChildren() do
		local index, id = string.match(child.Name, "^Attraction_(%d+)_(%a+)$")
		if not index then
			continue
		end
		local pole = pivotOf(`FlagPole_{index}`)
		local center, size = child:GetBoundingBox()
		if not pole then
			continue
		end
		-- Вид от флажка: чуть сверху и сзади, на середину аттракциона.
		local forward = (center.Position - pole.Position) * Vector3.new(1, 0, 1)
		local dir = forward.Unit
		-- С оси трассы: флажок стоит у бортика, и с него видна только стена.
		local axis = Vector3.new(center.Position.X, pole.Position.Y, center.Position.Z)
			- dir * ((center.Position - pole.Position) * Vector3.new(1, 0, 1)).Magnitude
		local eye = axis - dir * 8 + Vector3.new(0, 13, 0)
		Teleport.to(player, CFrame.new(pole.Position + Vector3.new(0, 1, 0) - dir * 6))
		task.wait(2)
		_G.ZZ_Shot(player, `run_{index}_{id}`, CFrame.lookAt(eye, center.Position), 70)
		note(`{id} #{index}: length {math.floor(size.Z)} center {center.Position}`)

		-- Механика: поставить в опасное место и посмотреть, вернёт ли к флажку.
		if id == "lava" or id == "boulders" or id == "spinner" or id == "hammers" then
			-- Сначала через флажок: он и есть точка возврата.
			local trigger = model:FindFirstChild(`FlagTrigger_{index}`)
			if trigger then
				Teleport.to(player, CFrame.new(trigger.Position))
			end
			task.wait(1.5)
			local danger = center.Position + Vector3.new(0, 4, 0)
			if id == "spinner" then
				danger = center.Position + dir * 7 + Vector3.new(0, 4, 0)
			elseif id == "lava" then
				-- Середина между колонками кочек — там лава.
				danger = Vector3.new(center.Position.X, center.Position.Y - size.Y / 2 + 4, center.Position.Z)
			end
			Teleport.to(player, CFrame.new(danger))
			local returned = false
			for _ = 1, 40 do
				task.wait(0.25)
				local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local home = if trigger then trigger.Position else pole.Position
				if r and (r.Position - home).Magnitude < 8 then
					returned = true
					break
				end
			end
			note(`   {id}: returned to flag = {returned}`)
		end
	end
	ChallengeService.abort(player)
end
