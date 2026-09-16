--!nocheck
--[[
	Локации занятий. Правило, которое держат эти тесты: одно задание — одна
	локация, и локации не налезают друг на друга.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Venues = require(Shared.Config.Venues)
local Challenges = require(Shared.Config.Challenges)

-- Забеги живут в своём туннеле, поляна им не нужна.
local RUNS = { tunnel_run = true, obstacle_course = true, math_gates = true }

return function()
	describe("Config: локации занятий", function()
		it("у каждого занятия с площади своя поляна", function()
			for _, id in Challenges.ids() do
				if not RUNS[id] then
					expect(Venues.get(id)).to.be.ok()
				end
			end
		end)

		it(
			"поляна заведена только под существующее занятие",
			function()
				for _, id in Venues.ids() do
					expect(Challenges.get(id)).to.be.ok()
					expect(RUNS[id]).to.equal(nil)
				end
			end
		)

		it("у поляны есть название и свой цвет", function()
			local grounds = {}
			for _, venue in Venues.all do
				expect(#venue.title > 0).to.equal(true)
				expect(#venue.decor > 0).to.equal(true)
				local key = tostring(venue.ground)
				expect(grounds[key]).to.equal(nil)
				grounds[key] = true
			end
		end)

		--[[
			Соседние поляны не должны видеть друг друга: ребёнок на своей поляне
			видит только своё задание. Расстояние считается из порядка локаций,
			поэтому шестая встанет правильно сама.
		]]
		it("поляны стоят далеко друг от друга", function()
			for _, first in Venues.ids() do
				for _, second in Venues.ids() do
					if first ~= second then
						local gap = (Venues.center(first) - Venues.center(second)).Magnitude
						expect(gap > Venues.SIZE * 2).to.equal(true)
					end
				end
			end
		end)

		it("поляны не налезают на туннели забегов", function()
			local Tunnel = require(Shared.Config.Tunnel)
			for _, id in Venues.ids() do
				expect(Venues.center(id).X < Tunnel.PLOT_ORIGIN.X - 1000).to.equal(true)
			end
		end)

		--[[
			Ребёнок появляется на самой поляне, а не рядом с ней, и смотрит
			на своё задание: сцена разворачивается в центре.
		]]
		it("точка входа стоит на поляне и смотрит в центр", function()
			for _, id in Venues.ids() do
				local center = Venues.center(id)
				local entry = Venues.entry(id)
				local flat = Vector3.new(entry.Position.X - center.X, 0, entry.Position.Z - center.Z)

				expect(flat.Magnitude < Venues.SIZE / 2).to.equal(true)
				expect(entry.Position.Y > center.Y).to.equal(true)

				-- Взгляд направлен к центру: скалярное произведение отрицательное.
				local toCenter = (center - entry.Position).Unit
				expect(entry.LookVector:Dot(toCenter) > 0.9).to.equal(true)
			end
		end)

		it("сцена стоит в центре своей поляны", function()
			for _, id in Venues.ids() do
				local stage = Venues.stage(id)
				expect((stage.Position - Venues.center(id)).Magnitude < 0.001).to.equal(true)
			end
		end)
	end)
end
