
local function setupBackground()
    local entity = Entity("background")
    local skyplane = SkyPlaneComponent()
    skyplane.properties.plane.normal = Vector3(0, 0, 2000)
    skyplane.properties.materialName = "background/blue_01"
    skyplane.properties:touch()
    
    entity:addComponent(skyplane)
end

local function setupCamera()
    local entity = Entity(CAMERA_NAME)
    -- Camera
    local camera = OgreCameraComponent("camera")
    camera.properties.nearClipDistance = 5
    camera.offset = Vector3(0, 0, 30)
    camera.properties:touch()
    entity:addComponent(camera)
    -- Scene node
    local sceneNode = OgreSceneNodeComponent()
    sceneNode.transform.position.z = 30
    sceneNode.transform:touch()
    entity:addComponent(sceneNode)
    -- Light
    local light = OgreLightComponent()
    light:setRange(200)
    entity:addComponent(light)
    -- Viewport
    local viewportEntity = Entity()
    local viewportComponent = OgreViewportComponent(0)
    viewportComponent.properties.cameraEntity = entity
    viewportComponent.properties:touch()
    viewportEntity:addComponent(viewportComponent)
end

-- there must be some more robust way to script agents than having stuff all over the place.
function oxytoxyEffect(entityId, potency)
    Microbe(Entity(entityId)):damage(potency*15, "toxin")
end

local function setupCompounds()
    CompoundRegistry.loadFromXML("../definitions/compounds.xml")
end

--  This isn't a finished solution. Optimally the process class would be moved to CPP and loaded there entirely.
global_processMap = {}
local function setupProcesses()
    BioProcessRegistry.loadFromXML("../definitions/processes.xml")
    for processId in BioProcessRegistry.getList() do
        local inputCompounds = {}
        local outputCompounds = {}
        
        for recipyCompound in BioProcessRegistry.getInputCompounds(processId) do
            inputCompounds[recipyCompound.compoundId] = recipyCompound.amount
        end
        for recipyCompound in BioProcessRegistry.getOutputCompounds(processId) do
            outputCompounds[recipyCompound.compoundId] = recipyCompound.amount
        end
        
        global_processMap[BioProcessRegistry.getInternalName(processId)] = Process(
            BioProcessRegistry.getSpeedFactor(processId),
            BioProcessRegistry.getEnergyCost(processId),
            inputCompounds,
            outputCompounds
        )
    end
end

function setupSpecies()
    --[[
    This function should be the entry point for all initial-species generation
    For now, it can go through the XML and instantiate all the species, but later this 
    would be all procedural.

    Together with the mutate function, these would be the only ways species are created
    ]]
    SpeciesRegistry.loadFromXML("../definitions/microbes.xml")
    for _, name in ipairs(SpeciesRegistry.getSpeciesNames()) do
        speciesEntity = Entity(name)
        speciesComponent = SpeciesComponent(name)
        speciesEntity:addComponent(speciesComponent)
        -- print("made entity and component")
        local organelles = {}
        assert(pcall(function () SpeciesRegistry.getSize(name) end), "could not load species", name, "from XML")
        -- In this case the species is a default one loaded from xml
        -- print("loaded", name)
        local numOrganelles = SpeciesRegistry.getSize(name)
        -- print("# organelles = "..numOrganelles)
        for i = 0,(numOrganelles-1) do
            -- returns a property table
            local organelleData = SpeciesRegistry.getOrganelle(name, i)
            organelles[#organelles+1] = organelleData
        end
        -- for _, org in pairs(organelles) do print(org.name, org.q, org.r) end
        speciesComponent.organelles = organelles

        -- iterates over all compounds, and sets amounts and priorities
        for compoundID in CompoundRegistry.getCompoundList() do
            compound = CompoundRegistry.getCompoundInternalName(compoundID)
            amount = SpeciesRegistry.getCompoundAmount(name, compound)
            priority = SpeciesRegistry.getCompoundPriority(name, compound)
            speciesComponent.avgCompoundAmounts[compoundID] = amount
            speciesComponent.compoundPriorities[compoundID] = priority
        end
    end
end

-- speciesName decides the template to use, while individualName is used for referencing the instance
function microbeSpawnFunctionGeneric(pos, speciesName, aiControlled, individualName)
    local microbe = Microbe.createMicrobeEntity(individualName, aiControlled)
    if pos ~= nil then
        microbe.rigidBody:setDynamicProperties(
            pos, -- Position
            Quaternion(Radian(Degree(0)), Vector3(1, 0, 0)), -- Orientation
            Vector3(0, 0, 0), -- Linear velocity
            Vector3(0, 0, 0)  -- Angular velocity
        )
    end
    -- set organelles, starting compound amounts, all that
    -- TODO: 
    Entity(speciesName):getComponent(SpeciesComponent.TYPE_ID):template(microbe)
    microbe.microbe:updateSafeAngles()
    return microbe
end

local function addEmitter2Entity(entity, compound)
    local compoundEmitter = CompoundEmitterComponent()
    entity:addComponent(compoundEmitter)
    compoundEmitter.emissionRadius = 1
    compoundEmitter.maxInitialSpeed = 10
    compoundEmitter.minInitialSpeed = 2
    compoundEmitter.minEmissionAngle = Degree(0)
    compoundEmitter.maxEmissionAngle = Degree(360)
    compoundEmitter.particleLifeTime = 5000
    local timedEmitter = TimedCompoundEmitterComponent()
    timedEmitter.compoundId = CompoundRegistry.getCompoundId(compound)
    timedEmitter.particlesPerEmission = 1
    timedEmitter.potencyPerParticle = 2.0
    timedEmitter.emitInterval = 1000
    entity:addComponent(timedEmitter)
end

local function createSpawnSystem()
    local spawnSystem = SpawnSystem()
    SpeciesRegistry.loadFromXML("../definitions/microbes.xml")

    local spawnOxygenEmitter = function(pos)
        -- Setting up an emitter for oxygen
        local entity = Entity()
        -- Rigid body
        local rigidBody = RigidBodyComponent()
        rigidBody.properties.friction = 0.2
        rigidBody.properties.linearDamping = 0.8
        rigidBody.properties.shape = CylinderShape(
            CollisionShape.AXIS_X, 
            0.4,
            2.0
        )
        rigidBody:setDynamicProperties(
            pos,
            Quaternion(Radian(Degree(math.random()*360)), Vector3(0, 0, 1)),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0)
        )
        rigidBody.properties:touch()
        entity:addComponent(rigidBody)
        -- Scene node
        local sceneNode = OgreSceneNodeComponent()
        sceneNode.meshName = "molecule.mesh"
        entity:addComponent(sceneNode)
        -- Emitter oxygen
        addEmitter2Entity(entity, "oxygen")
        return entity
    end
    local spawnCO2Emitter = function(pos)
        -- Setting up an emitter for co2
        local entity = Entity()
        -- Rigid body
        local rigidBody = RigidBodyComponent()
        rigidBody.properties.friction = 0.2
        rigidBody.properties.linearDamping = 0.8
        rigidBody.properties.shape = CylinderShape(
            CollisionShape.AXIS_X, 
            0.4,
            2.0
        )
        rigidBody:setDynamicProperties(
            pos,
            Quaternion(Radian(Degree(math.random()*360)), Vector3(0, 0, 1)),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0)
        )
        rigidBody.properties:touch()
        entity:addComponent(rigidBody)
        -- Scene node
        local sceneNode = OgreSceneNodeComponent()
        sceneNode.meshName = "co2.mesh"
        sceneNode.transform.scale = Vector3(0.4, 0.4, 0.4)
        entity:addComponent(sceneNode)
        -- Emitter carbon dioxide
        addEmitter2Entity(entity, "co2")
        return entity
    end
    local spawnGlucoseEmitter = function(pos)
        -- Setting up an emitter for glucose
        local entity = Entity()
        -- Rigid body
        local rigidBody = RigidBodyComponent()
        rigidBody.properties.friction = 0.2
        rigidBody.properties.linearDamping = 0.8
        rigidBody.properties.shape = SphereShape(HEX_SIZE)
        rigidBody:setDynamicProperties(
            pos,
            Quaternion(Radian(Degree(math.random()*360)), Vector3(0, 0, 1)),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0)
        )
        rigidBody.properties:touch()
        entity:addComponent(rigidBody)
        -- Scene node
        local sceneNode = OgreSceneNodeComponent()
        sceneNode.meshName = "glucose.mesh"
        entity:addComponent(sceneNode)
        -- Emitter glucose
        addEmitter2Entity(entity, "glucose")
        return entity
    end
    local spawnAmmoniaEmitter = function(pos)
        -- Setting up an emitter for ammonia
        local entity = Entity()
        -- Rigid body
        local rigidBody = RigidBodyComponent()
        rigidBody.properties.friction = 0.2
        rigidBody.properties.linearDamping = 0.8
        rigidBody.properties.shape = SphereShape(HEX_SIZE)
        rigidBody:setDynamicProperties(
            pos,
            Quaternion(Radian(Degree(math.random()*360)), Vector3(0, 0, 1)),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0)
        )
        rigidBody.properties:touch()
        entity:addComponent(rigidBody)
        -- Scene node
        local sceneNode = OgreSceneNodeComponent()
        sceneNode.meshName = "hex.mesh"
        entity:addComponent(sceneNode)
        -- Emitter ammonia
        addEmitter2Entity(entity, "ammonia")
        return entity
    end

    local toxinOrganelleSpawnFunction = function(pos) 
        powerupEntity = Entity()
        psceneNode = OgreSceneNodeComponent()
        psceneNode.transform.position = pos
        psceneNode.transform.scale = Vector3(0.9, 0.9, 0.9)
        psceneNode.transform:touch()
        psceneNode.meshName = "AgentVacuole.mesh"
        powerupEntity:addComponent(psceneNode)
        
        local reactionHandler = CollisionComponent()
        reactionHandler:addCollisionGroup("powerup")
        powerupEntity:addComponent(reactionHandler)
       
        local rigidBody = RigidBodyComponent()
        rigidBody.properties.friction = 0.2
        rigidBody.properties.linearDamping = 0.8
        rigidBody.properties.shape = SphereShape(HEX_SIZE)
        rigidBody:setDynamicProperties(
            pos,
            Quaternion(Radian(Degree(math.random()*360)), Vector3(0, 0, 1)),
            Vector3(0, 0, 0),
            Vector3(0, 0, 0)
        )
        rigidBody.properties:touch()
        powerupEntity:addComponent(rigidBody)
        
        local powerupComponent = PowerupComponent()
        powerupComponent:setEffect(unlockToxin)
        powerupEntity:addComponent(powerupComponent)
        return powerupEntity
    end

    local microbeDefault = function(pos)
        return microbeSpawnFunctionGeneric(pos, "Default", true, nil)
    end

    local microbeTeeny = function(pos)
        return microbeSpawnFunctionGeneric(pos, "Teeny", true, nil)
    end

    local microbePlankton = function(pos)
        return microbeSpawnFunctionGeneric(pos, "Plankton", true, nil)
    end

    --Spawn one emitter on average once in every square of sidelength 10
    -- (square dekaunit?)
    spawnSystem:addSpawnType(spawnOxygenEmitter, 1/500, 30)
    spawnSystem:addSpawnType(spawnCO2Emitter, 1/500, 30)
    spawnSystem:addSpawnType(spawnGlucoseEmitter, 1/500, 30)
    spawnSystem:addSpawnType(spawnAmmoniaEmitter, 1/1250, 30)

    -- Microbe spawning needs to be handled by species/population
    spawnSystem:addSpawnType(microbeDefault, 1/12000, 40)
    spawnSystem:addSpawnType(microbeTeeny, 1/6000, 40)
    spawnSystem:addSpawnType(microbePlankton, 1/32000, 40)
    
    spawnSystem:addSpawnType(toxinOrganelleSpawnFunction, 1/17000, 30)
    return spawnSystem
end

local function setupEmitter()
    -- Setting up a test emitter
    local entity = Entity("glucose-emitter")
    -- Rigid body
    local rigidBody = RigidBodyComponent()
    rigidBody.properties.friction = 0.2
    rigidBody.properties.linearDamping = 0.8
    rigidBody.properties.shape = CylinderShape(
        CollisionShape.AXIS_X, 
        0.4,
        2.0
    )
    rigidBody:setDynamicProperties(
        Vector3(10, 0, 0),
        Quaternion(Radian(Degree(0)), Vector3(1, 0, 0)),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0)
    )
    rigidBody.properties:touch()
    entity:addComponent(rigidBody)
    local reactionHandler = CollisionComponent()
    reactionHandler:addCollisionGroup("emitter")
    entity:addComponent(reactionHandler)
    -- Scene node
    local sceneNode = OgreSceneNodeComponent()
    sceneNode.meshName = "molecule.mesh"
    entity:addComponent(sceneNode)
    -- Emitter test
    local testEmitter = CompoundEmitterComponent()
    entity:addComponent(testEmitter)
    testEmitter.emissionRadius = 1
    testEmitter.maxInitialSpeed = 10
    testEmitter.minInitialSpeed = 2
    testEmitter.minEmissionAngle = Degree(0)
    testEmitter.maxEmissionAngle = Degree(360)
    testEmitter.particleLifeTime = 5000
    local timedEmitter = TimedCompoundEmitterComponent()
    timedEmitter.compoundId = CompoundRegistry.getCompoundId("glucose")
    timedEmitter.particlesPerEmission = 1
    timedEmitter.potencyPerParticle = 3.0
    timedEmitter.emitInterval = 1000
    entity:addComponent(timedEmitter)
end

function unlockToxin(entityId)
    if Engine:playerData():lockedMap():isLocked("Toxin") then
        showMessage("Toxin Unlocked!")
        Engine:playerData():lockedMap():unlock("Toxin")
        local guiSoundEntity = Entity("gui_sounds")
        guiSoundEntity:getComponent(SoundSourceComponent.TYPE_ID):playSound("microbe-pickup-organelle")
    end
    return true
end

function createStarterMicrobe(name, aiControlled)
    local microbe = microbeSpawnFunctionGeneric(nil,"Default",aiControlled, name)
    return microbe
end

local function setupPlayer()
    SpeciesRegistry.loadFromXML("../definitions/microbes.xml")
    microbe = createStarterMicrobe(PLAYER_NAME, false)
    microbe.collisionHandler:addCollisionGroup("powerupable")
    Engine:playerData():lockedMap():addLock("Toxin")
    Engine:playerData():setActiveCreature(microbe.entity.id, GameState.MICROBE)
    speciesEntity = Entity("defaultMicrobeSpecies")
    species = SpeciesComponent("defaultMicrobeSpecies")
    species.populationBonusFactor = 1.2
    speciesEntity:addComponent(species)
    microbe.microbe.speciesName = "defaultMicrobeSpecies"
end

local function setupSound()
    local ambientEntity = Entity("ambience")
    local soundSource = SoundSourceComponent()
    soundSource.ambientSoundSource = true
    soundSource.autoLoop = true
    soundSource.volumeMultiplier = 0.1
    ambientEntity:addComponent(soundSource)
    -- Sound
    soundSource:addSound("microbe-theme-1", "microbe-theme-1.ogg")
    soundSource:addSound("microbe-theme-3", "microbe-theme-3.ogg")
    soundSource:addSound("microbe-theme-4", "microbe-theme-4.ogg")
    soundSource:addSound("microbe-theme-5", "microbe-theme-5.ogg")
    soundSource:addSound("microbe-theme-6", "microbe-theme-6.ogg")   
    soundSource:addSound("microbe-theme-7", "microbe-theme-7.ogg")   
    local ambientEntity2 = Entity("ambience2")
    local soundSource = SoundSourceComponent()
     soundSource.volumeMultiplier = 0.4
    soundSource.ambientSoundSource = true
    ambientSound = soundSource:addSound("microbe-ambient", "soundeffects/microbe-ambience.ogg")
    soundSource.autoLoop = true
     ambientEntity2:addComponent(soundSource)
    -- Gui effects
    local guiSoundEntity = Entity("gui_sounds")
    soundSource = SoundSourceComponent()
    soundSource.ambientSoundSource = true
    soundSource.autoLoop = false
    soundSource.volumeMultiplier = 1.0
    guiSoundEntity:addComponent(soundSource)
    -- Sound
    soundSource:addSound("button-hover-click", "soundeffects/gui/button-hover-click.ogg")
    soundSource:addSound("microbe-pickup-organelle", "soundeffects/microbe-pickup-organelle.ogg")
    local listener = Entity("soundListener")
    local sceneNode = OgreSceneNodeComponent()
    listener:addComponent(sceneNode)
end

setupCompounds()
setupProcesses()

local function createMicrobeStage(name)
    return 
        Engine:createGameState(
        name,
        {
            MicrobeReplacementSystem(),
            SwitchGameStateSystem(),
            QuickSaveSystem(),
            -- Microbe specific
            MicrobeSystem(),
            MicrobeCameraSystem(),
            MicrobeAISystem(),
            MicrobeControlSystem(),
            HudSystem(),
            TimedLifeSystem(),
            CompoundMovementSystem(),
            CompoundAbsorberSystem(),
            PopulationSystem(),
            createSpawnSystem(),
            -- Physics
            RigidBodyInputSystem(),
            UpdatePhysicsSystem(),
            RigidBodyOutputSystem(),
            BulletToOgreSystem(),
            CollisionSystem(),
            -- Graphics
            OgreAddSceneNodeSystem(),
            OgreUpdateSceneNodeSystem(),
            OgreCameraSystem(),
            OgreLightSystem(),
            SkySystem(),
            TextOverlaySystem(),
            OgreViewportSystem(),
            OgreRemoveSceneNodeSystem(),
            RenderSystem(),
            -- Other
            SoundSourceSystem(),
            PowerupSystem(),
            CompoundEmitterSystem(), -- Keep this after any logic that might eject compounds such that any entites that are queued for destruction will be destroyed after emitting.
        },
        function()
            setupBackground()
            setupCamera()
            setupEmitter()
            setupSpecies()
            setupPlayer()
            setupSound()
        end,
        "MicrobeStage"
    )
end

GameState.MICROBE = createMicrobeStage("microbe")
GameState.MICROBE_ALTERNATE = createMicrobeStage("microbe_alternate")
--Engine:setCurrentGameState(GameState.MICROBE)
