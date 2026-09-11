--!nonstrict
--[[
	Испытание «Полоса препятствий». См. docs/19-OBSTACLES.md.

	Тот же забег, что и «Азбучный туннель», но пропорции перевёрнуты: препятствий
	много, ворот мало. Это режим для разнообразия — место, где ребёнок отдыхает
	от узнавания букв, оставаясь в той же игре и в том же мире.

	Обучающее правило от этого не меняется: звёздочки капают только за буквы
	на воротах. Паркур сам по себе не приносит ничего, иначе полоса стала бы
	способом «фармить» в обход учёбы.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Tunnel = require(Shared.Config.Tunnel)

local RunCourse = require(script.Parent.RunCourse)

return RunCourse.new("obstacle_course", Tunnel.COURSE_PARAMS)
