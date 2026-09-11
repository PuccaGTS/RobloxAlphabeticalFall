--!nocheck
--[[
	Звуковые эффекты. Главный тест здесь не про данные, а про реальность:
	каждый звук ДЕЙСТВИТЕЛЬНО загружается движком.

	Это не паранойя. Звуки взяты из клиента Roblox (`rbxasset://sounds/…`),
	а их состав Roblox меняет без предупреждения: половина путей, которые
	перечислены на форумах, сегодня уже не существует. Молчащий эффект в игре
	для четырёхлетки заметить некому — ребёнок не пожалуется, он просто решит,
	что игра «не отвечает».
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sfx = require(ReplicatedStorage.Shared.Config.Sfx)

-- Эффекты, которые обязаны быть заведены: на них ссылается код.
local REQUIRED = {
	"correct",
	"miss",
	"reward",
	"purchase",
	"checkpoint",
	"fall",
	"finish",
	"tap",
}

return function()
	describe("Config: звуковые эффекты", function()
		it("заведены все эффекты, которые просит игра", function()
			for _, key in REQUIRED do
				if Sfx.get(key) == nil then
					error(`эффекта «{key}» нет в каталоге`)
				end
			end
		end)

		it(
			"каждый эффект — звук из клиента, а не с аккаунта",
			function()
				for key, effect in Sfx.effects do
					if string.sub(effect.id, 1, #"rbxasset://") ~= "rbxasset://" then
						error(
							`«{key}»: {effect.id} — это загружаемый ассет, а не звук движка`
						)
					end
				end
			end
		)

		--[[
			Эффект не имеет права перекрывать реплику: голос в этой игре главнее
			всего остального. Исключение одно — финиш, и он звучит там, где реплик нет.
		]]
		it("эффекты короткие", function()
			for key, effect in Sfx.effects do
				if effect.seconds > Sfx.MAX_SECONDS then
					error(
						`«{key}»: {effect.seconds} с — длиннее потолка {Sfx.MAX_SECONDS} с`
					)
				end
			end
		end)

		it("громкость в разумных пределах", function()
			for key, effect in Sfx.effects do
				expect(effect.volume > 0).to.equal(true)
				if effect.volume > 0.7 then
					error(
						`«{key}»: громкость {effect.volume} — эффект перекричит голос`
					)
				end
			end
		end)

		--[[
			Промах тише верного ответа. Правило не про звук, а про обучение:
			ошибка не должна звучать громче удачи (docs/02-LEARNING.md).
		]]
		it("промах звучит тише, чем верный ответ", function()
			expect(Sfx.get("miss").volume < Sfx.get("correct").volume).to.equal(true)
		end)

		it("каждый звук существует и загружается движком", function()
			for key, effect in Sfx.effects do
				local sound = Instance.new("Sound")
				sound.SoundId = effect.id
				sound.Parent = workspace

				local ok = pcall(function()
					ContentProvider:PreloadAsync({ sound })
				end)

				local length = sound.TimeLength
				local loaded = sound.IsLoaded
				sound:Destroy()

				if not ok or not loaded or length <= 0 then
					error(
						`«{key}»: звук {effect.id} не загрузился — движок его больше не знает`
					)
				end

				-- Длина в каталоге не для красоты: по ней тест на потолок и считает.
				if math.abs(length - effect.seconds) > 0.2 then
					error(
						`«{key}»: в каталоге {effect.seconds} с, а на деле {math.floor(
							length * 100
						) / 100} с`
					)
				end
			end
		end)
	end)
end
