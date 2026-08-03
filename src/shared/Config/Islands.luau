--!strict
--[[
	Острова. Полный список из 8 — docs/02-LEARNING.md § 2.
	Здесь описаны только те, чьи буквы уже заведены в Config/Letters (MVP).
]]

local Types = require(script.Parent.Parent.Types)
local Letters = require(script.Parent.Letters)

local Islands: { Types.Island } = {
	{
		index = 1,
		id = "singing_shore",
		title = "Поющий берег",
		letters = Letters.byIsland(1),
		challenges = { "letter_rain", "echo_letter", "syllable_bridge" },
		unlockPrevMasteryRatio = 0, -- первый остров открыт всегда
		bossId = "boss_shore",
		music = "mus_island1_shore",
		voIntro = "story_island1_intro",
	},
	{
		index = 2,
		id = "soft_hills",
		title = "Мягкие холмы",
		letters = Letters.byIsland(2),
		challenges = { "letter_rain", "echo_letter", "syllable_bridge" },
		unlockPrevMasteryRatio = 0.8,
		bossId = "boss_hills",
		music = "mus_island2_hills",
		voIntro = "story_island2_intro",
	},
	{
		index = 3,
		id = "knocking_valley",
		title = "Стучащая долина",
		letters = Letters.byIsland(3),
		challenges = { "letter_rain", "echo_letter", "syllable_bridge", "build_word" },
		unlockPrevMasteryRatio = 0.8,
		bossId = "boss_valley",
		music = "mus_island3_valley",
		voIntro = "story_island3_intro",
	},
}

local Module = {}

Module.all = Islands

function Module.get(index: number): Types.Island?
	for _, island in Islands do
		if island.index == index then
			return island
		end
	end
	return nil
end

function Module.expect(index: number): Types.Island
	local island = Module.get(index)
	assert(island, `Islands: нет острова с индексом {index}`)
	return island
end

function Module.count(): number
	return #Islands
end

--[[
	Открыт ли остров: нужно, чтобы >= unlockPrevMasteryRatio букв предыдущего острова
	имели статус «изученная» (2) или выше. Первый остров открыт всегда.
]]
function Module.isUnlocked(index: number, masteryOf: (letterId: string) -> number): boolean
	local island = Module.get(index)
	if not island then
		return false
	end
	if index <= 1 or island.unlockPrevMasteryRatio <= 0 then
		return true
	end

	local prev = Module.get(index - 1)
	if not prev or #prev.letters == 0 then
		return false
	end

	local learned = 0
	for _, letterId in prev.letters do
		if masteryOf(letterId) >= 2 then
			learned += 1
		end
	end

	return (learned / #prev.letters) >= island.unlockPrevMasteryRatio
end

return Module
