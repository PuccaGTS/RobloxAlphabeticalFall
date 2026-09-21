--!nocheck
--[[
	Временный плагин стенда (tools/playtest/run.py и tools/models/import.py).
	Ничего не делает в обычных местах: срабатывает, только если в месте есть
	метка стенда.

	  · ZZ_Mode = "play"   — запустить Play, вернуть отчёт зонда;
	  · ZZ_Mode = "import" — взять модели Creator Store по номерам и отдать
	    их описание в JSON: так модель попадает в файлы проекта, и игре не нужно
	    грузить её с сайта (InsertService берёт только модели владельца места).
]]
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local StudioTestService = game:GetService("StudioTestService")

if not RunService:IsEdit() then
	return
end
task.wait(3)
local mode = workspace:GetAttribute("ZZ_Mode")
local port = workspace:GetAttribute("ZZ_ProbePort")
if not mode or not port then
	return
end

local function post(text, path)
	local ok, err = pcall(function()
		HttpService:PostAsync(`http://127.0.0.1:{port}/{path or ""}`, text)
	end)
	if not ok then
		warn("ZZ post failed " .. tostring(err))
	end
end

if mode == "play" then
	post("PLUGIN ready, starting play")
	local ok, result = pcall(function()
		return StudioTestService:ExecutePlayModeAsync({})
	end)
	post((if ok then "RESULT\n" else "PLAY FAIL ") .. tostring(result))
	post("DONE")
	return
end

-- ===== Импорт моделей =====

local function vec(v)
	return { v.X, v.Y, v.Z }
end

local function explicit(value)
	local kind = typeof(value)
	if kind == "Vector3" then
		return { Vector3 = vec(value) }
	elseif kind == "CFrame" then
		local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
		return { CFrame = { position = vec(value.Position), orientation = { { r00, r01, r02 }, { r10, r11, r12 }, { r20, r21, r22 } } } }
	elseif kind == "Color3" then
		return { Color3 = { value.R, value.G, value.B } }
	elseif kind == "EnumItem" then
		return { Enum = value.Value }
	elseif kind == "boolean" then
		return { Bool = value }
	elseif kind == "number" then
		return { Float32 = value }
	elseif kind == "string" then
		return { String = value }
	elseif kind == "Vector2" then
		return { Vector2 = { value.X, value.Y } }
	end
	return nil
end

local CONTENT = { MeshId = true, TextureID = true, TextureId = true, Texture = true, ColorMap = true, NormalMap = true, RoughnessMap = true, MetalnessMap = true, SkyboxBk = true, SkyboxDn = true, SkyboxFt = true, SkyboxLf = true, SkyboxRt = true, SkyboxUp = true, SunTextureId = true, MoonTextureId = true }

local PROPS = {
	BasePart = { "Size", "CFrame", "Color", "Material", "Transparency", "Reflectance", "CanCollide", "CastShadow" },
	Part = { "Shape" },
	MeshPart = { "MeshId", "TextureID", "DoubleSided" },
	SpecialMesh = { "MeshType", "MeshId", "TextureId", "Scale", "Offset", "VertexColor" },
	BlockMesh = { "Scale", "Offset" },
	CylinderMesh = { "Scale", "Offset" },
	Decal = { "Texture", "Face", "Color3", "Transparency" },
	Texture = { "Texture", "Face", "Color3", "Transparency", "StudsPerTileU", "StudsPerTileV" },
	SurfaceAppearance = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap", "AlphaMode" },
	PointLight = { "Brightness", "Range", "Color", "Shadows" },
	SpotLight = { "Brightness", "Range", "Color", "Angle", "Face" },
	-- Небо: берётся ради id текстур, в игру его ставит WorldService, а не декор.
	Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId", "CelestialBodiesShown", "StarCount", "SunAngularSize" },
}

local SUPPORTED = {
	Model = true, Folder = true, Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true,
	MeshPart = true, SpecialMesh = true, BlockMesh = true, CylinderMesh = true, Decal = true, Texture = true,
	SurfaceAppearance = true, PointLight = true, SpotLight = true, Seat = true, VehicleSeat = true,
	Accessory = true, Tool = true, Sky = true,
}

-- Классы, которые пишутся другим классом: сиденье — просто деталь, аксессуар и инструмент — модель.
local WRITE_AS = { Seat = "Part", VehicleSeat = "Part", Accessory = "Model", Tool = "Model" }

local skipped = {}

local ContentProvider = game:GetService("ContentProvider")

--[[
	MeshPart из файла у игры не оживает: чужой MeshId на MeshPart не грузится
	(на проверке MeshSize был нулевой у всех 72 деталей). Поэтому MeshPart
	пишется как Part со SpecialMesh: сетка та же, масштаб — Size / MeshSize,
	цвет и прозрачность прежние, текстура — TextureID или ColorMap поверхности.
]]
local function meshPartAsPart(instance)
	if instance.MeshSize.Magnitude == 0 then
		pcall(function()
			ContentProvider:PreloadAsync({ instance })
		end)
	end
	local meshSize = instance.MeshSize
	if meshSize.Magnitude == 0 then
		return nil
	end
	local texture = instance.TextureID
	local surface = instance:FindFirstChildWhichIsA("SurfaceAppearance")
	if texture == "" and surface then
		local ok, colorMap = pcall(function()
			return surface.ColorMap
		end)
		if ok and typeof(colorMap) == "string" then
			texture = colorMap
		end
	end
	local node = { Name = instance.Name, ClassName = "Part", Properties = {}, Children = {} }
	for _, name in { "Size", "CFrame", "Color", "Material", "Transparency", "Reflectance", "CanCollide", "CastShadow" } do
		node.Properties[name] = explicit(instance[name])
	end
	node.Properties.Anchored = { Bool = true }
	local mesh = {
		Name = "Mesh",
		ClassName = "SpecialMesh",
		Properties = {
			MeshType = { Enum = Enum.MeshType.FileMesh.Value },
			MeshId = { ContentId = instance.MeshId },
			Scale = explicit(instance.Size / meshSize),
		},
		Children = {},
	}
	if texture ~= "" then
		mesh.Properties.TextureId = { ContentId = texture }
	end
	table.insert(node.Children, mesh)
	return node
end

local function serialize(instance)
	if instance:IsA("MeshPart") then
		local node = meshPartAsPart(instance)
		if not node then
			skipped.MeshPartUnloaded = (skipped.MeshPartUnloaded or 0) + 1
		end
		return node
	end
	if not SUPPORTED[instance.ClassName] then
		skipped[instance.ClassName] = (skipped[instance.ClassName] or 0) + 1
		return nil
	end
	local node = { Name = instance.Name, ClassName = WRITE_AS[instance.ClassName] or instance.ClassName, Properties = {}, Children = {} }
	for class, names in PROPS do
		if instance:IsA(class) then
			for _, name in names do
				local ok, value = pcall(function()
					return instance[name]
				end)
				if ok and value ~= nil then
					if CONTENT[name] and typeof(value) == "string" then
						if value ~= "" then
							node.Properties[name] = { ContentId = value }
						end
					else
						local encoded = explicit(value)
						if encoded then
							node.Properties[name] = encoded
						end
					end
				end
			end
		end
	end
	if instance:IsA("BasePart") then
		node.Properties.Anchored = { Bool = true }
	end
	for _, child in instance:GetChildren() do
		local encoded = serialize(child)
		if encoded then
			table.insert(node.Children, encoded)
		end
	end
	return node
end

local ids = HttpService:JSONDecode(workspace:GetAttribute("ZZ_ImportIds") or "[]")
post(`PLUGIN import {#ids}`)
for _, entry in ids do
	local ok, result = pcall(function()
		return game:GetObjects(`rbxassetid://{entry.assetId}`)
	end)
	if not ok or not result or #result == 0 then
		post(`FAIL {entry.id} {entry.assetId}: {result}`)
		continue
	end
	skipped = {}
	local root = Instance.new("Model")
	root.Name = entry.id
	for _, object in result do
		object.Parent = root
	end
	--[[
		Цельные детали (UnionOperation) в файл не записать: их форма хранится
		в облаке. Разбираем их на исходные детали; вырезы (NegateOperation)
		выбрасываем — лучше чуть более грубая форма, чем дыра в модели.
	]]
	for _ = 1, 3 do
		local unions = {}
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("UnionOperation") then
				table.insert(unions, descendant)
			end
		end
		if #unions == 0 then
			break
		end
		for _, union in unions do
			local ok, parts = pcall(function()
				return plugin:Separate({ union })
			end)
			if not ok then
				warn("ZZ separate failed " .. tostring(parts))
			end
		end
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("NegateOperation") then
			descendant:Destroy()
		end
	end

	-- Скрипты не берём никогда: ни живые, ни выключенные.
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	local _, bounds = root:GetBoundingBox()
	local encoded = serialize(root)
	local skippedText = {}
	for class, count in skipped do
		table.insert(skippedText, `{class}×{count}`)
	end
	post(HttpService:JSONEncode({ id = entry.id, model = encoded, skipped = table.concat(skippedText, ", "), size = { bounds.X, bounds.Y, bounds.Z } }), "model")
	root:Destroy()
end
post("DONE")
