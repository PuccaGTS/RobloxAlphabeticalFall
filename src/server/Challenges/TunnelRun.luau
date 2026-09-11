--!nonstrict
--[[
	Испытание «Азбучный туннель» — основной режим. См. docs/14-TUNNEL-MODE.md.

	Ребёнок бежит по туннелю, перегороженному воротами. Над каждым проёмом буква,
	голос называет нужную. Пройти мимо выбора невозможно — в этом вся суть:
	буква не бонус на обочине, а единственный способ двигаться дальше.

	Ошибка не убивает и ничего не отнимает — она замедляет на секунду с небольшим,
	и за это время звучит подсказка. Это то же правило, что в «Буквопаде».

	Устройство забега общее с «Полосой препятствий» — см. RunCourse.
	Здесь только пропорции: ворота часто, препятствий между ними немного.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tunnel = require(Shared.Config.Tunnel)

local RunCourse = require(script.Parent.RunCourse)

return RunCourse.new("tunnel_run", Tunnel.PARAMS)
