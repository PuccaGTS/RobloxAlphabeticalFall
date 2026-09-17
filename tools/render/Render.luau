--!nocheck
--[[
	Снимок сцены лучами — без окна Studio и без скриншотов.

	run-in-roblox не умеет показывать картинку, а проверять арт из деталей
	на глаз надо. Этот модуль пускает луч из камеры в каждый пиксель, берёт цвет
	детали, притеняет по нормали и печатает строки в Output. tools/render/topng.py
	собирает из них PNG.

	Пример — tools/render/PlotCheck.server.luau.
]]
local Render = {}

local SUN = Vector3.new(-0.4, 1, -0.6).Unit
local SKY = Color3.fromRGB(170, 210, 245)

local function hex(color: Color3): string
	return string.format(
		"%02x%02x%02x",
		math.clamp(math.floor(color.R * 255), 0, 255),
		math.clamp(math.floor(color.G * 255), 0, 255),
		math.clamp(math.floor(color.B * 255), 0, 255)
	)
end

-- Кадр camera смотрит вдоль −Z. fov — по вертикали, в градусах.
function Render.shot(
	name: string,
	camera: CFrame,
	width: number,
	height: number,
	fov: number,
	ignore: { Instance }?
)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	local tanY = math.tan(math.rad(fov) / 2)
	local tanX = tanY * width / height
	print(`RENDER-BEGIN {name} {width} {height}`)
	for y = 0, height - 1 do
		local row = table.create(width)
		for x = 0, width - 1 do
			local u = ((x + 0.5) / width * 2 - 1) * tanX
			local v = (1 - (y + 0.5) / height * 2) * tanY
			local direction = camera:VectorToWorldSpace(Vector3.new(u, v, -1).Unit)
			local hit = workspace:Raycast(camera.Position, direction * 1000, params)
			if hit then
				local light = 0.5 + 0.5 * math.max(0, hit.Normal:Dot(SUN))
				local color = hit.Instance.Color
				if hit.Instance.Material == Enum.Material.Neon then
					light = 1.15
				end
				row[x + 1] = hex(Color3.new(color.R * light, color.G * light, color.B * light))
			else
				row[x + 1] = hex(SKY)
			end
		end
		print(`R{y} ` .. table.concat(row))
		if y % 20 == 0 then
			task.wait()
		end
	end
	print(`RENDER-END {name}`)
end

return Render
