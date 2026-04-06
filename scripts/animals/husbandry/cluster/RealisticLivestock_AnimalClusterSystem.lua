RealisticLivestock_AnimalClusterSystem = {}
local AnimalClusterSystem_mt = Class(AnimalClusterSystem)

function RealisticLivestock_AnimalClusterSystem.new(superFunc, isServer, owner, customMt)

    local self = setmetatable({}, customMt or AnimalClusterSystem_mt)

    self.isServer = isServer
    self.owner = owner
    self.clusters = {}
    self.idToIndex = {}
    self.clustersToAdd = {}
    self.clustersToRemove = {}
    self.needsUpdate = false
    self.animals = {}
    self.currentAnimalId = 0

    return self

end

AnimalClusterSystem.new = Utils.overwrittenFunction(AnimalClusterSystem.new, RealisticLivestock_AnimalClusterSystem.new)

function RealisticLivestock_AnimalClusterSystem:delete()

    for _, animal in pairs(self.animals) do
        animal:delete()
    end

    self.animals = {}
    self.currentAnimalId = 0
end

AnimalClusterSystem.delete = Utils.appendedFunction(AnimalClusterSystem.delete, RealisticLivestock_AnimalClusterSystem.delete)

function RealisticLivestock_AnimalClusterSystem:getNextAnimalId()
    self.currentAnimalId = self.currentAnimalId + 1
    return self.currentAnimalId
end

AnimalClusterSystem.getNextAnimalId = RealisticLivestock_AnimalClusterSystem.getNextAnimalId

function RealisticLivestock_AnimalClusterSystem:getAnimals()
    return self.animals or {}
end

AnimalClusterSystem.getAnimals = RealisticLivestock_AnimalClusterSystem.getAnimals


function RealisticLivestock_AnimalClusterSystem:loadFromXMLFile(_, xmlFile, key)

    Log:info("loadFromXMLFile: Loading animals from savegame (key=%s)", key)
    self.animals = {}
    local loadedCount, droppedCount, format = 0, 0, "unknown"


    xmlFile:iterate(key .. ".RLAnimal", function(_, legacyKey)
        format = "legacy-RL"
        local animal = Animal.loadFromXMLFile(xmlFile, legacyKey, self, true)
        if animal ~= nil then
            table.insert(self.animals, animal)
            loadedCount = loadedCount + 1
        else
            droppedCount = droppedCount + 1
            Log:warning("loadFromXMLFile: Legacy RL animal dropped (key=%s) - subtype not in registry", legacyKey)
        end

    end)


   xmlFile:iterate(key .. ".animal", function(_, animalKey)

        local numAnimals = xmlFile:getInt(animalKey .. "#numAnimals", 1)
        if numAnimals > 1 then
            Log:info("loadFromXMLFile: Vanilla cluster: numAnimals=%d from '%s'", numAnimals, animalKey)
        end
        format = numAnimals > 1 and "vanilla-cluster" or "current"

        for i = 1, numAnimals do

            local animal = Animal.loadFromXMLFile(xmlFile, animalKey, self)
            if animal ~= nil then
                table.insert(self.animals, animal)
                loadedCount = loadedCount + 1
            else
                droppedCount = droppedCount + 1
                Log:warning("loadFromXMLFile: Animal dropped (key=%s, i=%d) - subtype not in registry", animalKey, i)
            end

        end

    end)

    Log:info("loadFromXMLFile: Savegame load complete: %d animals loaded, %d dropped (missing subtype), format=%s", loadedCount, droppedCount, format)

    -- Migration pass for pre-v1.1.3 saves: seed typeIds counters and repair duplicates.
    -- Bridge animal types (RABBIT, QUAIL, etc.) got rawId=1 for every animal prior to v1.1.3,
    -- producing identical uniqueIds. This causes MP clients to collapse N animals into 1
    -- during readStream. Two steps:
    --   1. Seed typeIds counters past existing animals (prevents collision on next birth)
    --   2. Reassign all animals in any duplicate group (fixes existing collisions)
    -- TODO: RLRM-122 - remove this migration pass once affected saves have been migrated.
    if g_server ~= nil and #self.animals > 0 then

        -- Step 1: Seed typeIds counters for non-base types so future births/purchases
        -- start past existing IDs. Without this, a save with 1 pre-fix rabbit (no duplicate)
        -- would generate rawId=1 on the next birth, colliding with the existing animal.
        local ownerFarmId = self.owner ~= nil and self.owner.ownerFarmId or nil
        local farm = ownerFarmId ~= nil and g_farmManager.farmIdToFarm[ownerFarmId] or nil

        if farm ~= nil and farm.stats ~= nil then
            local animalSystem = g_currentMission.animalSystem
            local seededTypes = {}

            for _, animal in pairs(self.animals) do
                local typeIndex = animal.animalTypeIndex
                if typeIndex ~= AnimalType.COW and typeIndex ~= AnimalType.PIG
                    and typeIndex ~= AnimalType.SHEEP and typeIndex ~= AnimalType.HORSE
                    and typeIndex ~= AnimalType.CHICKEN then

                    local animalTypeObj = animalSystem:getTypeByIndex(typeIndex)
                    local typeName = animalTypeObj ~= nil and animalTypeObj.name or tostring(typeIndex)

                    if farm.stats.statistics.typeIds == nil then farm.stats.statistics.typeIds = {} end
                    farm.stats.statistics.typeIds[typeName] = (farm.stats.statistics.typeIds[typeName] or 0) + 1
                    seededTypes[typeName] = farm.stats.statistics.typeIds[typeName]
                end
            end

            for typeName, count in pairs(seededTypes) do
                Log:debug("Seeded typeIds counter: %s = %d", typeName, count)
            end
        end

        -- Step 2: Detect and fix duplicate (farmId, uniqueId, country) tuples.
        if #self.animals > 1 then
            local idCounts = {}
            for _, animal in pairs(self.animals) do
                if animal.uniqueId ~= nil and animal.farmId ~= nil and animal.birthday ~= nil then
                    local idKey = animal.farmId .. "_" .. animal.uniqueId .. "_" .. tostring(animal.birthday.country)
                    idCounts[idKey] = (idCounts[idKey] or 0) + 1
                end
            end

            local repairCount = 0
            for _, animal in pairs(self.animals) do
                if animal.uniqueId ~= nil and animal.farmId ~= nil and animal.birthday ~= nil then
                    local idKey = animal.farmId .. "_" .. animal.uniqueId .. "_" .. tostring(animal.birthday.country)
                    if idCounts[idKey] > 1 then
                        local oldId = animal.uniqueId
                        animal:setUniqueId()
                        Log:debug("Duplicate ID repair: %s -> %s (farmId=%s)", oldId, animal.uniqueId, animal.farmId)
                        repairCount = repairCount + 1
                    end
                end
            end

            if repairCount > 0 then
                Log:info("Repaired %d animal(s) with duplicate unique IDs", repairCount)
            end
        end
    end

    self:updateClusters()
    self.needsUpdate = false

    if self.owner ~= nil and self.owner.spec_husbandryFood ~= nil then SpecializationUtil.raiseEvent(self.owner, "onHusbandryAnimalsUpdate", self.animals) end

end


AnimalClusterSystem.loadFromXMLFile = Utils.overwrittenFunction(AnimalClusterSystem.loadFromXMLFile, RealisticLivestock_AnimalClusterSystem.loadFromXMLFile)


function RealisticLivestock_AnimalClusterSystem:saveToXMLFile(superFunc, xmlFile, key, usedModNames)

    local toRemove = {}
    for i, animal in pairs(self.animals) do
        if animal == nil or animal.isDead or animal.isSold or animal.numAnimals <= 0 then table.insert(toRemove, i) end
    end

    for i=#toRemove, 1, -1 do
        table.remove(self.animals, toRemove[i])
    end

    for i, animal in pairs(self.animals) do
        local animalKey = string.format("%s.animal(%d)", key, i - 1)
        animal:saveToXMLFile(xmlFile, animalKey)

    end

end

AnimalClusterSystem.saveToXMLFile = Utils.overwrittenFunction(AnimalClusterSystem.saveToXMLFile, RealisticLivestock_AnimalClusterSystem.saveToXMLFile)


function RealisticLivestock_AnimalClusterSystem:readStream(_, streamId, connection)

    local numAnimals = streamReadUInt16(streamId)

    for i = 1, numAnimals do

        local animalTypeIndex = streamReadUInt8(streamId)
        local country = streamReadUInt8(streamId)
        local uniqueId = streamReadString(streamId)
        local farmId = streamReadString(streamId)

        local existingAnimal = false
        local found = RLAnimalUtil.find(self.animals, farmId, uniqueId, country)

        if found and found.animalTypeIndex == animalTypeIndex then
            found:readStream(streamId, connection)
            found.foundThisUpdate = true
            existingAnimal = true
        end

        if not existingAnimal then

            local animal = Animal.new()
            animal:readStream(streamId, connection)
            animal.foundThisUpdate = true
            self:addCluster(animal)

        end

    end

    for i = #self.animals, 1, -1 do

        local animal = self.animals[i]

        if not animal.foundThisUpdate then
            self:removeCluster(i)
        else
            animal.foundThisUpdate = false
        end

    end

    self:updateIdMapping()
	g_messageCenter:publish(AnimalClusterUpdateEvent, self.owner, self.animals)

end

AnimalClusterSystem.readStream = Utils.overwrittenFunction(AnimalClusterSystem.readStream, RealisticLivestock_AnimalClusterSystem.readStream)


function RealisticLivestock_AnimalClusterSystem:writeStream(_, streamId, connection)

    streamWriteUInt16(streamId, #self.animals)

    for _, animal in pairs(self.animals) do

        streamWriteUInt8(streamId, animal.animalTypeIndex)
        streamWriteUInt8(streamId, animal.birthday.country)
        streamWriteString(streamId, animal.uniqueId)
        streamWriteString(streamId, animal.farmId)

        local success = animal:writeStream(streamId, connection)

    end

end

AnimalClusterSystem.writeStream = Utils.overwrittenFunction(AnimalClusterSystem.writeStream, RealisticLivestock_AnimalClusterSystem.writeStream)


function RealisticLivestock_AnimalClusterSystem:getClusters(superFunc)
    return self.animals or {}
end

AnimalClusterSystem.getClusters = Utils.overwrittenFunction(AnimalClusterSystem.getClusters, RealisticLivestock_AnimalClusterSystem.getClusters)

function RealisticLivestock_AnimalClusterSystem:getCluster(superFunc, index)
    return self.animals[index] or nil
end

AnimalClusterSystem.getCluster = Utils.overwrittenFunction(AnimalClusterSystem.getCluster, RealisticLivestock_AnimalClusterSystem.getCluster)


function RealisticLivestock_AnimalClusterSystem:getClusterById(superFunc, id)
    local index = self.idToIndex[id]

    if id == nil or self.animals == nil then return end

    if string.contains(id, "-") then

        for _, animal in pairs(self.animals) do
            if animal.id == id then return animal end
        end

    end


    for _, animal in pairs(self.animals) do
        if RLAnimalUtil.toKey(animal.farmId, animal.uniqueId, animal.birthday.country) == id then return animal end
    end

    if index == nil or self.animals == nil or self.animals[index] == nil then return nil end

    return self.animals[index]
end

AnimalClusterSystem.getClusterById = Utils.overwrittenFunction(AnimalClusterSystem.getClusterById, RealisticLivestock_AnimalClusterSystem.getClusterById)



function RealisticLivestock_AnimalClusterSystem:addCluster(superFunc, animal)

    if animal.uniqueId == nil or animal.uniqueId == "1-1" or animal.uniqueId == "0-0" then return end
    animal:setClusterSystem(self)
    table.insert(self.animals, animal)

    self:updateIdMapping()

end

AnimalClusterSystem.addCluster = Utils.overwrittenFunction(AnimalClusterSystem.addCluster, RealisticLivestock_AnimalClusterSystem.addCluster)


function RealisticLivestock_AnimalClusterSystem:removeCluster(_, animalIndex)

    if self.animals[animalIndex] ~= nil then
        local animal = self.animals[animalIndex]

        local spec = self.owner.spec_husbandryAnimals

        if animal.idFull ~= nil and animal.idFull ~= "1-1" and spec ~= nil then

            local sep = string.find(animal.idFull, "-")
            local husbandry = tonumber(string.sub(animal.idFull, 1, sep - 1))
            local animalId = tonumber(string.sub(animal.idFull, sep + 1))

            if husbandry ~= 0 and animalId ~= 0 then

                removeHusbandryAnimal(husbandry, animalId)

                local clusterHusbandry = spec.clusterHusbandry
                local count = clusterHusbandry.husbandryIdsToVisualAnimalCount[husbandry]
                if count ~= nil then
                    clusterHusbandry.husbandryIdsToVisualAnimalCount[husbandry] = math.max(count - 1, 0)
                    clusterHusbandry.visualAnimalCount = math.max(clusterHusbandry.visualAnimalCount - 1, 0)
                else
                    Log:warning("removeCluster: visual count missing for husbandryId=%s idFull=%s", tostring(husbandry), tostring(animal.idFull))
                end

                for husbandryIndex, animalIds in pairs(clusterHusbandry.animalIdToCluster) do

                    if clusterHusbandry.husbandryIds[husbandryIndex] == husbandry then

                        animalIds[animalId] = nil
                        break

                    end

                end

            end

        end

        table.remove(self.animals, animalIndex)
        animal:setClusterSystem(nil)
    else
        for i, animal in pairs(self.animals) do
            if RLAnimalUtil.toKey(animal.farmId, animal.uniqueId, animal.birthday.country) == animalIndex then

                local spec = self.owner.spec_husbandryAnimals

                if animal.idFull ~= nil and animal.idFull ~= "1-1" and spec ~= nil then

                    local sep = string.find(animal.idFull, "-")
                    local husbandry = tonumber(string.sub(animal.idFull, 1, sep - 1))
                    local animalId = tonumber(string.sub(animal.idFull, sep + 1))

                    if husbandry ~= 0 and animalId ~= 0 then

                        removeHusbandryAnimal(husbandry, animalId)

                        local clusterHusbandry = spec.clusterHusbandry
                        local count = clusterHusbandry.husbandryIdsToVisualAnimalCount[husbandry]
                        if count ~= nil then
                            clusterHusbandry.husbandryIdsToVisualAnimalCount[husbandry] = math.max(count - 1, 0)
                            clusterHusbandry.visualAnimalCount = math.max(clusterHusbandry.visualAnimalCount - 1, 0)
                        else
                            Log:warning("removeCluster: visual count missing for husbandryId=%s idFull=%s", tostring(husbandry), tostring(animal.idFull))
                        end

                        for husbandryIndex, animalIds in pairs(clusterHusbandry.animalIdToCluster) do
                            if clusterHusbandry.husbandryIds[husbandryIndex] == husbandry then
                                animalIds[animalId] = nil
                                break
                            end
                        end

                    end

                end

                table.remove(self.animals, i)
                animal:setClusterSystem(nil)
                break
            end
        end
    end

    self:updateIdMapping()

end

AnimalClusterSystem.removeCluster = Utils.overwrittenFunction(AnimalClusterSystem.removeCluster, RealisticLivestock_AnimalClusterSystem.removeCluster)


function RealisticLivestock_AnimalClusterSystem:updateClusters(superFunc)

    local isDirty = false
    local removedClusterIndices = {}

    for animalsToAdd, pending in pairs(self.clustersToAdd) do
        if not pending then continue end

        if animalsToAdd.isIndividual ~= nil then
            self:addCluster(animalsToAdd)
            isDirty = true
            continue
        end

        if animalsToAdd.numAnimals ~= nil then
            local subType = g_currentMission.animalSystem:getSubTypeByIndex(animalsToAdd.subTypeIndex)
            if subType == nil then
                Log:warning("addAnimals: subTypeIndex=%d has no matching subtype - will crash", animalsToAdd.subTypeIndex)
            else
                Log:debug("addAnimals: subTypeIndex=%d -> subType=%s gender=%s breed=%s",
                    animalsToAdd.subTypeIndex, subType.name, subType.gender or "?", subType.breed or "?")
            end
            for i=1, animalsToAdd.numAnimals do
                local animal = Animal.new({
                    age = animalsToAdd.age,
                    health = animalsToAdd.health,
                    monthsSinceLastBirth = animalsToAdd.monthsSinceLastBirth,
                    gender = subType.gender,
                    subTypeIndex = animalsToAdd.subTypeIndex,
                    reproduction = animalsToAdd.reproduction,
                    isParent = animalsToAdd.isParent,
                    isPregnant = animalsToAdd.isPregnant,
                    isLactating = animalsToAdd.isLactating,
                    clusterSystem = self,
                    uniqueId = animalsToAdd.uniqueId,
                    motherId = animalsToAdd.motherId,
                    fatherId = animalsToAdd.fatherId,
                    name = animalsToAdd.name,
                    dirt = animalsToAdd.dirt,
                    fitness = animalsToAdd.fitness,
                    riding = animalsToAdd.riding,
                    farmId = animalsToAdd.farmId,
                    weight = animalsToAdd.weight,
                    genetics = animalsToAdd.genetics,
                    impregnatedBy = animalsToAdd.impregnatedBy,
                    variation = animalsToAdd.variation,
                    children = animalsToAdd.children,
                    monitor = animalsToAdd.monitor
                })
                self:addCluster(animal)
                isDirty = true
            end

            continue
        end

        for _, animalToAdd in pairs(animalsToAdd) do

            if animalToAdd.isIndividual then
                self:addCluster(animalToAdd)
                isDirty = true

            else
                local subType = g_currentMission.animalSystem:getSubTypeByIndex(animalToAdd.subTypeIndex)
                if subType == nil then
                    Log:warning("addAnimals: subTypeIndex=%d has no matching subtype - will crash", animalToAdd.subTypeIndex)
                else
                    Log:debug("addAnimals: subTypeIndex=%d -> subType=%s gender=%s breed=%s",
                        animalToAdd.subTypeIndex, subType.name, subType.gender or "?", subType.breed or "?")
                end
                for i=1, animalToAdd.numAnimals do
                    local animal = Animal.new({
                        age = animalToAdd.age,
                        health = animalToAdd.health,
                        monthsSinceLastBirth = animalToAdd.monthsSinceLastBirth,
                        gender = subType.gender,
                        subTypeIndex = animalToAdd.subTypeIndex,
                        reproduction = animalToAdd.reproduction,
                        isParent = animalToAdd.isParent,
                        isPregnant = animalToAdd.isPregnant,
                        isLactating = animalToAdd.isLactating,
                        clusterSystem = self,
                        uniqueId = animalToAdd.uniqueId,
                        motherId = animalToAdd.motherId,
                        fatherId = animalToAdd.fatherId,
                        name = animalToAdd.name,
                        dirt = animalToAdd.dirt,
                        fitness = animalToAdd.fitness,
                        riding = animalToAdd.riding,
                        farmId = animalToAdd.farmId,
                        weight = animalToAdd.weight,
                        genetics = animalToAdd.genetics,
                        impregnatedBy = animalToAdd.impregnatedBy,
                        variation = animalToAdd.variation,
                        children = animalToAdd.children,
                        monitor = animalToAdd.monitor
                    })
                    self:addCluster(animal)
                    isDirty = true
                end
            end

        end

    end


    for animalIndex, animal in pairs(self.animals) do
        if animal.isDirty then
            isDirty = true
            animal.isDirty = false
        end

        if self.clustersToRemove[animal] ~= nil or (animal.beingRidden ~= nil and animal.beingRidden) or animal:getNumAnimals() == 0 or animal.uniqueId == "1-1" or animal.uniqueId == "0-0" then table.insert(removedClusterIndices, animalIndex) end
    end


    for i = #removedClusterIndices, 1, -1 do
        isDirty = true
        local animalIndexToRemove = removedClusterIndices[i]

        self:removeCluster(animalIndexToRemove)
    end

    self.clustersToAdd = {}
    self.clustersToRemove = {}

    self:updateIdMapping()
    if self.owner.spec_husbandryAnimals ~= nil then self.owner.spec_husbandryAnimals:updateVisualAnimals() end


end

AnimalClusterSystem.updateClusters = Utils.overwrittenFunction(AnimalClusterSystem.updateClusters, RealisticLivestock_AnimalClusterSystem.updateClusters)


function RealisticLivestock_AnimalClusterSystem:updateIdMapping(superFunc)
    self.idToIndex = {}

    for index, animal in pairs(self.animals) do
        if index == nil then continue end
        self.idToIndex[RLAnimalUtil.toShortKey(animal.farmId, animal.uniqueId)] = index
    end
        
    if self.owner.updatedClusters ~= nil then self.owner:updatedClusters(self.owner, self.animals) end

    if g_server ~= nil then g_server:broadcastEvent(AnimalClusterUpdateEvent.new(self.owner, self.animals)) end
    g_messageCenter:publish(AnimalClusterUpdateEvent, self.owner, self.animals)
    
end

AnimalClusterSystem.updateIdMapping = Utils.overwrittenFunction(AnimalClusterSystem.updateIdMapping, RealisticLivestock_AnimalClusterSystem.updateIdMapping)