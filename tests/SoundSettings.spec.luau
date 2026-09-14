--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local SoundSettings = require(Shared.Logic.SoundSettings)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)

local function fresh()
	return ProfileTemplate.defaultSettings()
end

return function()
	describe("SoundSettings.setVolume", function()
		it(
			"умолчания стоят на ступенях и голос громче всех",
			function()
				local settings = fresh()
				for _, key in SoundSettings.KEYS do
					expect(SoundSettings.isStep(settings[key])).to.equal(true)
				end
				expect(settings.voice >= settings.music and settings.voice >= settings.sfx).to.equal(true)
			end
		)

		it("принимает только ступени и свои ключи", function()
			local settings = fresh()
			expect(SoundSettings.setVolume(settings, "music", 0.25)).to.equal(true)
			expect(settings.music).to.equal(0.25)

			for _, bad in { 0.3, -1, 2, "1", nil, 0 / 0 } do
				expect(SoundSettings.setVolume(settings, "music", bad)).to.equal(false)
			end
			expect(SoundSettings.setVolume(settings, "master", 1)).to.equal(false)
			expect(settings.music).to.equal(0.25)
		end)

		it("голос выключить нельзя", function()
			local settings = fresh()
			expect(SoundSettings.setVolume(settings, "voice", 0)).to.equal(false)
			expect(settings.voice).to.equal(1)
		end)

		it("тише голос — тише и музыка с эффектами", function()
			local settings = fresh()
			SoundSettings.setVolume(settings, "voice", 0.25)
			expect(settings.music).to.equal(0.25)
			expect(settings.sfx).to.equal(0.25)
		end)

		it("музыка громче голоса встаёт вровень с ним", function()
			local settings = fresh()
			SoundSettings.setVolume(settings, "voice", 0.5)
			SoundSettings.setVolume(settings, "music", 1)
			expect(settings.music).to.equal(0.5)
		end)

		it("музыку и эффекты можно выключить", function()
			local settings = fresh()
			expect(SoundSettings.setVolume(settings, "sfx", 0)).to.equal(true)
			expect(settings.sfx).to.equal(0)
		end)
	end)

	describe("SoundSettings.sanitize", function()
		it("старые умолчания и мусор приводит к ступеням", function()
			local settings = { music = 0.6, sfx = "громко", voice = 0, subtitles = "да" }
			SoundSettings.sanitize(settings, fresh())

			expect(settings.music).to.equal(0.25) -- 0.5, но не громче голоса 0.25
			expect(settings.voice).to.equal(SoundSettings.MIN_VOICE)
			expect(settings.sfx).to.equal(0.25)
			expect(settings.subtitles).to.equal(false)
		end)

		it(
			"прежние 0.6 и 0.7 при полном голосе — ближайшие ступени",
			function()
				local settings = { music = 0.6, sfx = 0.7, voice = 1, subtitles = true }
				SoundSettings.sanitize(settings, fresh())

				expect(settings.music).to.equal(0.5)
				expect(settings.sfx).to.equal(0.75)
				expect(settings.subtitles).to.equal(true)
			end
		)
	end)
end
