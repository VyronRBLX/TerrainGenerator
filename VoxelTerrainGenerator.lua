
--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

type MaterialSettings = {
	Color: Color3,
	Material: Enum.Material,
	CanCollide: boolean,
	CastShadow: boolean?,
	Transparency: number?,
}

type LayerNames = {
	SHORE: string,
	SURFACE: string,
	SUBSURFACE: string,
	DEEP: string,
	HIGHLAND: string,
	WATER: string,
}

type FoliageSettings = {
	ENABLED: boolean,
	TREE_CHANCE: number,
	TREE_SPACING_CELLS: number,
	TREE_MIN_TRUNK: number,
	TREE_MAX_TRUNK: number,
	FOREST_FREQUENCY: number,
	MAX_SLOPE_CELLS: number,
	TUFT_CHANCE: number,
	FLOWER_CHANCE: number,
	FLOWER_COLORS: { Color3 },
}

type Settings = {
	MAP_SIZE: number,
	BLOCK_SIZE: number,
	MIN_HEIGHT: number,
	MAX_HEIGHT: number,
	SEA_LEVEL: number,
	BASE_HEIGHT: number,
	NOISE_FREQUENCY: number,
	NOISE_AMPLITUDE: number,
	DETAIL_FREQUENCY: number,
	DETAIL_AMPLITUDE: number,
	EDGE_FALLOFF_START: number,
	EDGE_FALLOFF_AMPLITUDE: number,
	SAND_DEPTH_BLOCKS: number,
	DIRT_DEPTH_BLOCKS: number,
	ROCKY_HEIGHT: number,
	CHUNK_CELLS: number,
	WORKER_COUNT: number,
	COMMAND_COOLDOWN: number,
	LAYERS: LayerNames,
	FOLIAGE: FoliageSettings,
	MATERIALS: { [string]: MaterialSettings },
}

type HeightGrid = { { number } }

local SETTINGS: Settings = {
	MAP_SIZE = 240,
	BLOCK_SIZE = 4,

	MIN_HEIGHT = -12,
	MAX_HEIGHT = 44,
	SEA_LEVEL = 4,

	BASE_HEIGHT = 16,

	NOISE_FREQUENCY = 0.015,
	NOISE_AMPLITUDE = 32,

	DETAIL_FREQUENCY = 0.025,
	DETAIL_AMPLITUDE = 6,

	EDGE_FALLOFF_START = 0.78,
	EDGE_FALLOFF_AMPLITUDE = 10,

	SAND_DEPTH_BLOCKS = 2,
	DIRT_DEPTH_BLOCKS = 3,
	ROCKY_HEIGHT = 36,

	CHUNK_CELLS = 10,
	WORKER_COUNT = 8,
	COMMAND_COOLDOWN = 5,

	LAYERS = {
		SHORE = "Sand",
		SURFACE = "Grass",
		SUBSURFACE = "Dirt",
		DEEP = "Rock",
		HIGHLAND = "Rock",
		WATER = "Water",
	},

	FOLIAGE = {
		ENABLED = true,

		TREE_CHANCE = 0.04,
		TREE_SPACING_CELLS = 3,
		TREE_MIN_TRUNK = 3,
		TREE_MAX_TRUNK = 5,
		FOREST_FREQUENCY = 0.02,
		MAX_SLOPE_CELLS = 1,

		TUFT_CHANCE = 0.16,
		FLOWER_CHANCE = 0.025,
		FLOWER_COLORS = {
			Color3.fromRGB(214, 59, 59),
			Color3.fromRGB(240, 205, 66),
			Color3.fromRGB(240, 240, 240),
			Color3.fromRGB(150, 90, 200),
			Color3.fromRGB(235, 130, 190),
		},
	},

	MATERIALS = {
		Grass = { Color = Color3.fromRGB(83, 154, 65), Material = Enum.Material.SmoothPlastic, CanCollide = true },
		Dirt = { Color = Color3.fromRGB(120, 82, 52), Material = Enum.Material.SmoothPlastic, CanCollide = true },
		Sand = { Color = Color3.fromRGB(218, 198, 133), Material = Enum.Material.SmoothPlastic, CanCollide = true },
		Rock = { Color = Color3.fromRGB(105, 108, 113), Material = Enum.Material.SmoothPlastic, CanCollide = true },
		Water = { Color = Color3.fromRGB(71, 145, 205), Material = Enum.Material.SmoothPlastic, CanCollide = false },

		Wood = { Color = Color3.fromRGB(102, 77, 46), Material = Enum.Material.SmoothPlastic, CanCollide = true },
		Leaves = { Color = Color3.fromRGB(52, 122, 48), Material = Enum.Material.SmoothPlastic, CanCollide = true },
		Tuft = { Color = Color3.fromRGB(96, 170, 70), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false },
		Flower = { Color = Color3.fromRGB(214, 59, 59), Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false },
	},
}

local function getMaterial(name: string): MaterialSettings
	local material = SETTINGS.MATERIALS[name]
	assert(material, ("no material set up for %q"):format(name))
	return material
end

-- Startup checks
for _, materialName in SETTINGS.LAYERS do
	getMaterial(materialName)
end
for _, materialName in { "Wood", "Leaves", "Tuft", "Flower" } do
	getMaterial(materialName)
end

local ROLE_ATTRIBUTE = "BlockTerrainGeneratorRole"
local role = script:GetAttribute(ROLE_ATTRIBUTE)
local actor = script:GetActor()

local BLOCK_SIZE = SETTINGS.BLOCK_SIZE
assert(SETTINGS.MAP_SIZE % BLOCK_SIZE == 0, "MAP_SIZE must be divisible by BLOCK_SIZE!")
assert((SETTINGS.MAX_HEIGHT - SETTINGS.MIN_HEIGHT) % BLOCK_SIZE == 0, "height bounds must line up with BLOCK_SIZE!")
assert((SETTINGS.SEA_LEVEL - SETTINGS.MIN_HEIGHT) % BLOCK_SIZE == 0, "SEA_LEVEL must line up with BLOCK_SIZE!")

local GRID_CELLS = SETTINGS.MAP_SIZE / BLOCK_SIZE
local CHUNK_CELLS = SETTINGS.CHUNK_CELLS
local CHUNKS_PER_AXIS = math.ceil(GRID_CELLS / CHUNK_CELLS)
local CHUNK_COUNT = CHUNKS_PER_AXIS * CHUNKS_PER_AXIS
local VERTICAL_CELLS = (SETTINGS.MAX_HEIGHT - SETTINGS.MIN_HEIGHT) / BLOCK_SIZE
local SEA_LEVEL_CELLS = (SETTINGS.SEA_LEVEL - SETTINGS.MIN_HEIGHT) / BLOCK_SIZE
local HALF_SIZE = SETTINGS.MAP_SIZE / 2

-- script makes the controller, controller makes workers
-- bit clunky but keeps everything in one script
if not actor then
	local controllerActor = Instance.new("Actor")
	controllerActor.Name = "BlockTerrainGenerationController"
	controllerActor.Parent = ServerScriptService

	local controllerScript = script:Clone()
	controllerScript.Name = "Controller"
	controllerScript:SetAttribute(ROLE_ATTRIBUTE, "Controller")
	controllerScript.Disabled = false
	controllerScript.Parent = controllerActor
	return
end

if role == "Worker" then
	local controllerLink = actor:FindFirstChild("ControllerActor")
	if not controllerLink or not controllerLink:IsA("ObjectValue") then
		warn("worker has no controller reference")
		return
	end

	local controllerActor = controllerLink.Value
	if not controllerActor or not controllerActor:IsA("Actor") then
		warn("worker controller reference is invalid")
		return
	end

	actor:BindToMessageParallel("GenerateChunk", function(
		generationId: number,
		seed: number,
		chunkIndex: number,
		noiseOffsetX: number,
		noiseOffsetZ: number
	)
		local chunkX = (chunkIndex - 1) % CHUNKS_PER_AXIS
		local chunkZ = math.floor((chunkIndex - 1) / CHUNKS_PER_AXIS)
		local startX = chunkX * CHUNK_CELLS
		local startZ = chunkZ * CHUNK_CELLS
		local width = math.min(CHUNK_CELLS, GRID_CELLS - startX)
		local depth = math.min(CHUNK_CELLS, GRID_CELLS - startZ)
		local encodedHeights: { string } = table.create(width * depth)
		local index = 0

		for x = 0, width - 1 do
			for z = 0, depth - 1 do
				local worldX = -HALF_SIZE + (startX + x) * BLOCK_SIZE + BLOCK_SIZE * 0.5
				local worldZ = -HALF_SIZE + (startZ + z) * BLOCK_SIZE + BLOCK_SIZE * 0.5

				local broad = math.noise(
					(worldX + noiseOffsetX) * SETTINGS.NOISE_FREQUENCY,
					(worldZ + noiseOffsetZ) * SETTINGS.NOISE_FREQUENCY
				)
				local detail = math.noise(
					(worldX + noiseOffsetX) * SETTINGS.DETAIL_FREQUENCY + 37,
					(worldZ + noiseOffsetZ) * SETTINGS.DETAIL_FREQUENCY - 19
				)
				local edge = math.max(math.abs(worldX), math.abs(worldZ)) / HALF_SIZE
				local edgeFalloff = math.max(0, edge - SETTINGS.EDGE_FALLOFF_START) * SETTINGS.EDGE_FALLOFF_AMPLITUDE

				local height = SETTINGS.BASE_HEIGHT
					+ broad * SETTINGS.NOISE_AMPLITUDE
					+ detail * SETTINGS.DETAIL_AMPLITUDE
				- edgeFalloff

				height = math.clamp(height, SETTINGS.MIN_HEIGHT + BLOCK_SIZE, SETTINGS.MAX_HEIGHT - BLOCK_SIZE)
				height = math.floor(height / BLOCK_SIZE + 0.5) * BLOCK_SIZE

				local solidCells = math.clamp(math.floor((height - SETTINGS.MIN_HEIGHT) / BLOCK_SIZE), 1, VERTICAL_CELLS)
				index += 1

				-- store it as two bytes instead of one, just in case the height range gets bigger
				encodedHeights[index] = string.char(math.floor(solidCells / 256), solidCells % 256)
			end
		end

		task.synchronize()
		controllerActor:SendMessage("ChunkReady", generationId, seed, chunkIndex, table.concat(encodedHeights))
	end)

	controllerActor:SendMessage("WorkerReady")
	return
end

if role ~= "Controller" then
	return
end

local workerActors: { Actor } = {}
local readyWorkers = 0
local workersReady = false
local generationId = 0
local isGenerating = false
local completedChunks = 0
local chunkResults: { [number]: string } = {}
local lastSeed: number? = nil
local seedRandom = Random.new()
local lastCommandAt = -math.huge

local function getCellType(heights: HeightGrid, x: number, y: number, z: number): string?
	if x < 1 or x > GRID_CELLS or z < 1 or z > GRID_CELLS or y < 1 or y > VERTICAL_CELLS then
		return nil
	end

	local solidCells = heights[x][z]
	local surfaceHeight = SETTINGS.MIN_HEIGHT + solidCells * BLOCK_SIZE

	if y <= solidCells then
		local depth = solidCells - y
		if surfaceHeight <= SETTINGS.SEA_LEVEL + BLOCK_SIZE then
			return if depth <= SETTINGS.SAND_DEPTH_BLOCKS then SETTINGS.LAYERS.SHORE else SETTINGS.LAYERS.DEEP
		elseif surfaceHeight >= SETTINGS.ROCKY_HEIGHT then
			return SETTINGS.LAYERS.HIGHLAND
		elseif depth == 0 then
			return SETTINGS.LAYERS.SURFACE
		elseif depth <= SETTINGS.DIRT_DEPTH_BLOCKS then
			return SETTINGS.LAYERS.SUBSURFACE
		end
		return SETTINGS.LAYERS.DEEP
	elseif y <= SEA_LEVEL_CELLS then
		return SETTINGS.LAYERS.WATER
	end

	return nil
end

local function createWorkers()
	for workerIndex = 1, SETTINGS.WORKER_COUNT do
		local workerActor = Instance.new("Actor")
		workerActor.Name = "BlockTerrainWorker" .. workerIndex
		workerActor.Parent = ServerScriptService

		local controllerLink = Instance.new("ObjectValue")
		controllerLink.Name = "ControllerActor"
		controllerLink.Value = actor
		controllerLink.Parent = workerActor

		local workerScript = script:Clone()
		workerScript.Name = "Worker"
		workerScript:SetAttribute(ROLE_ATTRIBUTE, "Worker")
		workerScript.Disabled = false
		workerScript.Parent = workerActor

		workerActors[workerIndex] = workerActor
	end
end

local function makeSeed(): number
	local seed = seedRandom:NextInteger(1, 2147483647)
	if seed == lastSeed then
		seed = (seed % 2147483647) + 1
	end
	lastSeed = seed
	return seed
end

local function getChunkBounds(chunkIndex: number): (number, number, number, number)
	local chunkX = (chunkIndex - 1) % CHUNKS_PER_AXIS
	local chunkZ = math.floor((chunkIndex - 1) / CHUNKS_PER_AXIS)
	local startX = chunkX * CHUNK_CELLS
	local startZ = chunkZ * CHUNK_CELLS

	return startX, startZ,
		math.min(CHUNK_CELLS, GRID_CELLS - startX),
		math.min(CHUNK_CELLS, GRID_CELLS - startZ)
end

local function cellCenter(cell: number): number
	return -HALF_SIZE + (cell - 0.5) * BLOCK_SIZE
end

local function cellCenterY(cellY: number): number
	return SETTINGS.MIN_HEIGHT + (cellY - 0.5) * BLOCK_SIZE
end

local function createFoliagePart(
	parent: Instance,
	name: string,
	materialName: string,
	size: Vector3,
	cframe: CFrame,
	colorOverride: Color3?
)
	local material = getMaterial(materialName)

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Material = material.Material
	part.Color = colorOverride or material.Color
	part.CastShadow = material.CastShadow ~= false
	part.CanCollide = material.CanCollide
	part.CanTouch = false

	if not part.CanCollide then
		part.CanQuery = false
	end

	part.Parent = parent
end

local function generateFoliage(heights: HeightGrid, seed: number, parent: Instance)
	local foliage = SETTINGS.FOLIAGE
	if not foliage.ENABLED then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Foliage"
	folder.Parent = parent

	-- same seed = same trees, so it doesn't reshuffle every time
	local rng = Random.new(seed + 4242)
	local offsetRng = Random.new(seed)
	local forestX = offsetRng:NextNumber(-10000, 10000)
	local forestZ = offsetRng:NextNumber(-10000, 10000)

	-- keep track of occupied cells so leaves don't overlap everything
	local occupied: { [number]: boolean } = {}
	local trunkColumns: { [number]: boolean } = {}

	local function voxelKey(x: number, y: number, z: number): number
		return x + z * 4096 + y * 16777216
	end

	local function treeNearby(x: number, z: number): boolean
		local spacing = foliage.TREE_SPACING_CELLS

		for dx = -spacing, spacing do
			for dz = -spacing, spacing do
				if trunkColumns[(x + dx) + (z + dz) * 4096] then
					return true
				end
			end
		end

		return false
	end

	local function isFlatEnough(x: number, z: number): boolean
		local here = heights[x][z]

		for dx = -1, 1 do
			for dz = -1, 1 do
				if math.abs(heights[x + dx][z + dz] - here) > foliage.MAX_SLOPE_CELLS then
					return false
				end
			end
		end

		return true
	end

	-- leaves get made in horizontal strips, saves a ridiculous number of parts
	local function placeLeafLayer(
		cx: number,
		cz: number,
		y: number,
		radius: number,
		cornerChance: number,
		trunkTop: number,
		color: Color3
	)
		for dz = -radius, radius do
			local runStart: number? = nil

			-- one extra step at the end so the last strip gets made too
			for dx = -radius, radius + 1 do
				local include = false

				if dx <= radius then
					local cellX = cx + dx
					local cellZ = cz + dz
					include = true

					local isCorner = math.abs(dx) == radius and math.abs(dz) == radius

					if isCorner and (cornerChance <= 0 or rng:NextNumber() > cornerChance) then
						include = false
					elseif dx == 0 and dz == 0 and y <= trunkTop then
						include = false
					elseif cellX < 1 or cellX > GRID_CELLS or cellZ < 1 or cellZ > GRID_CELLS then
						include = false
					elseif occupied[voxelKey(cellX, y, cellZ)] then
						include = false
					elseif getCellType(heights, cellX, y, cellZ) ~= nil then
						include = false
					end
				end

				if include then
					occupied[voxelKey(cx + dx, y, cz + dz)] = true

					if not runStart then
						runStart = dx
					end
				elseif runStart then
					local firstCell = cx + runStart
					local lastCell = cx + dx - 1

					createFoliagePart(
						folder,
						"Leaves",
						"Leaves",
						Vector3.new((lastCell - firstCell + 1) * BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE),
						CFrame.new(cellCenter((firstCell + lastCell) / 2), cellCenterY(y), cellCenter(cz + dz)),
						color
					)

					runStart = nil
				end
			end
		end
	end

	local function placeTree(x: number, z: number)
		local ground = heights[x][z]
		local trunkHeight = rng:NextInteger(foliage.TREE_MIN_TRUNK, foliage.TREE_MAX_TRUNK)
		local trunkTop = ground + trunkHeight

		for y = ground + 1, trunkTop do
			occupied[voxelKey(x, y, z)] = true
		end

		trunkColumns[x + z * 4096] = true

		createFoliagePart(
			folder,
			"Trunk",
			"Wood",
			Vector3.new(BLOCK_SIZE, trunkHeight * BLOCK_SIZE, BLOCK_SIZE),
			CFrame.new(cellCenter(x), SETTINGS.MIN_HEIGHT + (ground + trunkHeight * 0.5) * BLOCK_SIZE, cellCenter(z))
		)

		-- tiny colour variation makes the canopy look a bit less copy pasted
		local leafColor = getMaterial("Leaves").Color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.14))

		placeLeafLayer(x, z, trunkTop - 1, 2, 0.5, trunkTop, leafColor)
		placeLeafLayer(x, z, trunkTop, 2, 0.5, trunkTop, leafColor)
		placeLeafLayer(x, z, trunkTop + 1, 1, 1, trunkTop, leafColor)
		placeLeafLayer(x, z, trunkTop + 2, 1, 0, trunkTop, leafColor)
	end

	local treeCount = 0
	for x = 3, GRID_CELLS - 2 do
		for z = 3, GRID_CELLS - 2 do
			local ground = heights[x][z]
			if getCellType(heights, x, ground, z) ~= SETTINGS.LAYERS.SURFACE then
				continue
			end

			-- noise handles the big forest patches, random chance fills them in
			local forestNoise = math.noise(
				(cellCenter(x) + forestX) * foliage.FOREST_FREQUENCY + 113,
				(cellCenter(z) + forestZ) * foliage.FOREST_FREQUENCY - 71
			)

			local density = math.clamp((forestNoise + 0.25) / 0.5, 0, 1)
			local chance = foliage.TREE_CHANCE * (0.15 + 1.85 * density)

			if rng:NextNumber() < chance and not treeNearby(x, z) and isFlatEnough(x, z) then
				placeTree(x, z)
				treeCount += 1

				if treeCount % 20 == 0 then
					RunService.PostSimulation:Wait()
				end
			end
		end
	end

	-- little plants go in after trees so they don't end up inside the trunks
	local flowerColors = foliage.FLOWER_COLORS
	local jitter = BLOCK_SIZE * 0.3

	for x = 1, GRID_CELLS do
		for z = 1, GRID_CELLS do
			local ground = heights[x][z]

			if getCellType(heights, x, ground, z) ~= SETTINGS.LAYERS.SURFACE then
				continue
			end
			if occupied[voxelKey(x, ground + 1, z)] then
				continue
			end

			local roll = rng:NextNumber()
			if roll >= foliage.FLOWER_CHANCE + foliage.TUFT_CHANCE then
				continue
			end

			local surfaceY = SETTINGS.MIN_HEIGHT + ground * BLOCK_SIZE
			local px = cellCenter(x) + rng:NextNumber(-jitter, jitter)
			local pz = cellCenter(z) + rng:NextNumber(-jitter, jitter)
			local yaw = rng:NextNumber(0, math.pi)

			if roll < foliage.FLOWER_CHANCE then
				local stemHeight = BLOCK_SIZE * 0.4
				local headSize = BLOCK_SIZE * 0.25

				createFoliagePart(
					folder,
					"FlowerStem",
					"Tuft",
					Vector3.new(BLOCK_SIZE * 0.08, stemHeight, BLOCK_SIZE * 0.08),
					CFrame.new(px, surfaceY + stemHeight * 0.5, pz)
				)

				createFoliagePart(
					folder,
					"FlowerHead",
					"Flower",
					Vector3.new(headSize, headSize, headSize),
					CFrame.new(px, surfaceY + stemHeight + headSize * 0.4, pz) * CFrame.Angles(0, yaw, 0),
					flowerColors[rng:NextInteger(1, #flowerColors)]
				)
			else
				local tuftHeight = BLOCK_SIZE * rng:NextNumber(0.3, 0.55)

				createFoliagePart(
					folder,
					"GrassTuft",
					"Tuft",
					Vector3.new(BLOCK_SIZE * 0.25, tuftHeight, BLOCK_SIZE * 0.25),
					CFrame.new(px, surfaceY + tuftHeight * 0.5, pz) * CFrame.Angles(0, yaw, 0)
				)
			end
		end

		if x % 10 == 0 then
			RunService.PostSimulation:Wait()
		end
	end
end

local function buildBlockTerrain(encodedChunks: { [number]: string }, seed: number)
	local heights: HeightGrid = table.create(GRID_CELLS)

	for x = 1, GRID_CELLS do
		heights[x] = table.create(GRID_CELLS, 1)
	end

	for chunkIndex = 1, CHUNK_COUNT do
		local encoded = encodedChunks[chunkIndex]
		local startX, startZ, width, depth = getChunkBounds(chunkIndex)

		if not encoded or #encoded ~= width * depth * 2 then
			error(("missing or invalid terrain chunk %d"):format(chunkIndex))
		end

		local byteIndex = 0
		for x = 0, width - 1 do
			for z = 0, depth - 1 do
				byteIndex += 2
				local highByte = string.byte(encoded, byteIndex - 1) or 0
				local lowByte = string.byte(encoded, byteIndex) or 1

				heights[startX + x + 1][startZ + z + 1] = highByte * 256 + lowByte
			end
		end
	end

	local previous = Workspace:FindFirstChild("GeneratedBlockTerrain")
	if previous then
		previous:Destroy()
	end

	local terrainFolder = Instance.new("Folder")
	terrainFolder.Name = "GeneratedBlockTerrain"
	terrainFolder.Parent = Workspace

	type Run = { Material: string, StartY: number, EndY: number }

	-- collect vertical runs first, then merge matching ones sideways into bigger parts
	local runsAt: { { { [string]: boolean } } } = {}
	local visited: { { { [string]: boolean } } } = {}
	local runInfo: { [string]: Run } = {}

	for x = 1, GRID_CELLS do
		runsAt[x] = {}
		visited[x] = {}

		for z = 1, GRID_CELLS do
			runsAt[x][z] = {}
			visited[x][z] = {}

			local y = 1
			while y <= VERTICAL_CELLS do
				local materialName = getCellType(heights, x, y, z)

				if not materialName then
					y += 1
					continue
				end

				local startY = y
				repeat
					y += 1
				until y > VERTICAL_CELLS or getCellType(heights, x, y, z) ~= materialName

				local endY = y - 1
				local key = string.format("%s:%d:%d", materialName, startY, endY)

				runsAt[x][z][key] = true
				runInfo[key] = { Material = materialName, StartY = startY, EndY = endY }
			end
		end
	end

	local ok, errorMessage = pcall(function()
		for x = 1, GRID_CELLS do
			for z = 1, GRID_CELLS do
				for key in runsAt[x][z] do
					if visited[x][z][key] then
						continue
					end

					-- try to make the rectangle bigger in Z first, then widen it in X
					local depth = 1
					while z + depth <= GRID_CELLS
						and runsAt[x][z + depth][key]
						and not visited[x][z + depth][key] do
						depth += 1
					end

					local width = 1
					while x + width <= GRID_CELLS do
						local rowMatches = true

						for runZ = z, z + depth - 1 do
							if not runsAt[x + width][runZ][key] or visited[x + width][runZ][key] then
								rowMatches = false
								break
							end
						end

						if not rowMatches then
							break
						end

						width += 1
					end

					for runX = x, x + width - 1 do
						for runZ = z, z + depth - 1 do
							visited[runX][runZ][key] = true
						end
					end

					local run = runInfo[key]
					local material = getMaterial(run.Material)
					local heightCells = run.EndY - run.StartY + 1

					local block = Instance.new("Part")
					block.Name = run.Material .. "Merged"
					block.Anchored = true
					block.Size = Vector3.new(width * BLOCK_SIZE, heightCells * BLOCK_SIZE, depth * BLOCK_SIZE)
					block.Position = Vector3.new(
						-HALF_SIZE + (x - 1 + width * 0.5) * BLOCK_SIZE,
						SETTINGS.MIN_HEIGHT + (run.StartY - 1 + heightCells * 0.5) * BLOCK_SIZE,
						-HALF_SIZE + (z - 1 + depth * 0.5) * BLOCK_SIZE
					)
					block.Material = material.Material
					block.Color = material.Color
					block.Transparency = material.Transparency or 0
					block.CastShadow = material.CastShadow ~= false
					block.CanCollide = material.CanCollide
					block.CanTouch = false
					block.Parent = terrainFolder
				end
			end

			RunService.PostSimulation:Wait()
		end

		-- keep foliage under this folder too, next generation can clear it all at once
		generateFoliage(heights, seed, terrainFolder)
	end)

	if not ok then
		terrainFolder:Destroy()
		error(errorMessage)
	end
end

actor:BindToMessage("WorkerReady", function()
	readyWorkers += 1
end)

actor:BindToMessage("ChunkReady", function(
	resultGenerationId: number,
	seed: number,
	chunkIndex: number,
	encoded: string
)
	-- ignore late replies if that generation already timed out
	if not isGenerating or resultGenerationId ~= generationId then
		return
	end
	if chunkResults[chunkIndex] then
		return
	end

	chunkResults[chunkIndex] = encoded
	completedChunks += 1

	if completedChunks < CHUNK_COUNT then
		return
	end

	local finishedGenerationId = generationId
	local resultsForBuild = chunkResults

	task.spawn(function()
		local ok, errorMessage = pcall(buildBlockTerrain, resultsForBuild, seed)

		if generationId == finishedGenerationId then
			isGenerating = false
			chunkResults = {}
		end

		if ok then
			print(("Generated %dx%d map with seed %d"):format(
				SETTINGS.MAP_SIZE,
				SETTINGS.MAP_SIZE,
				seed
				))
		else
			warn("Generation failed: " .. tostring(errorMessage))
		end
	end)
end)

local function startGeneration(seed: number)
	if isGenerating then
		return
	end

	generationId += 1
	local thisGeneration = generationId
	isGenerating = true
	completedChunks = 0
	chunkResults = {}

	local offsetRng = Random.new(seed)
	local noiseOffsetX = offsetRng:NextNumber(-10000, 10000)
	local noiseOffsetZ = offsetRng:NextNumber(-10000, 10000)

	print(("Generating %dx%d map with seed %d"):format(
		SETTINGS.MAP_SIZE,
		SETTINGS.MAP_SIZE,
		seed
		))

	for chunkIndex = 1, CHUNK_COUNT do
		local worker = workerActors[((chunkIndex - 1) % #workerActors) + 1]
		worker:SendMessage("GenerateChunk", thisGeneration, seed, chunkIndex, noiseOffsetX, noiseOffsetZ)
	end

	task.delay(120, function()
		if isGenerating and generationId == thisGeneration and completedChunks < CHUNK_COUNT then
			isGenerating = false
			chunkResults = {}
			warn("Timed out waiting on workers after 120s, keeping the old map")
		end
	end)
end

local function connectPlayer(player: Player)
	player.Chatted:Connect(function(message: string)
		local command = string.lower(string.match(message, "^%s*(.-)%s*$") or "")
		if command ~= "generate" then
			return
		end

		local now = os.clock()
		if not workersReady or isGenerating or now - lastCommandAt < SETTINGS.COMMAND_COOLDOWN then
			return
		end

		lastCommandAt = now
		startGeneration(makeSeed())
	end)
end

for _, player in Players:GetPlayers() do
	connectPlayer(player)
end

Players.PlayerAdded:Connect(connectPlayer)

createWorkers()

local readyDeadline = os.clock() + 5
while readyWorkers < #workerActors and os.clock() < readyDeadline do
	task.wait()
end

if readyWorkers < #workerActors then
	warn("Workers never reported ready, generation is disabled")
	return
end

workersReady = true
task.defer(function()
	startGeneration(makeSeed())
end)
