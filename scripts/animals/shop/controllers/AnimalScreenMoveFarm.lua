local Log = RmLogging.getLogger("RLRM")

AnimalScreenMoveFarm = {}

AnimalScreenMoveFarm.MOVE_ERROR_CODE_MAPPING = {
    [AnimalMoveEvent.MOVE_ERROR_SOURCE_OBJECT_DOES_NOT_EXIST] = { text = "rl_ui_moveErrorNotSupported" },
    [AnimalMoveEvent.MOVE_ERROR_TARGET_OBJECT_DOES_NOT_EXIST] = { text = "rl_ui_moveErrorNotSupported" },
    [AnimalMoveEvent.MOVE_ERROR_NO_PERMISSION] = { text = "rl_ui_moveErrorNoPermission" },
    [AnimalMoveEvent.MOVE_ERROR_ANIMAL_NOT_SUPPORTED] = { text = "rl_ui_moveErrorNotSupported" },
    [AnimalMoveEvent.MOVE_ERROR_NOT_ENOUGH_SPACE] = { text = "rl_ui_moveErrorNoSpace" },
}


function AnimalScreenMoveFarm.new(husbandry)
    local self = {}
    setmetatable(self, { __index = AnimalScreenMoveFarm })

    self.husbandry = husbandry
    self.targetItems = {}
    self.animalsChangedCallback = nil
    self.actionTypeCallback = nil
    self.errorCallback = nil

    return self
end


function AnimalScreenMoveFarm:initTargetItems()
    self.targetItems = {}
    local animals = self.husbandry:getClusters()

    if animals ~= nil then
        for _, animal in pairs(animals) do
            local item = AnimalItemStock.new(animal)
            table.insert(self.targetItems, item)
        end
    end

    RL_AnimalScreenBase.sortItems(self)

    Log:trace("AnimalScreenMoveFarm:initTargetItems: populated %d items", #self.targetItems)
end


function AnimalScreenMoveFarm:getTargetItems()
    return self.targetItems
end


function AnimalScreenMoveFarm:setAnimalsChangedCallback(callback, target)
    function self.animalsChangedCallback()
        callback(target)
    end
end


function AnimalScreenMoveFarm:setActionTypeCallback(callback, target)
    function self.actionTypeCallback(actionType, text)
        callback(target, actionType, text)
    end
end


function AnimalScreenMoveFarm:setErrorCallback(callback, target)
    function self.errorCallback(text)
        callback(target, text)
    end
end


--- Static: enumerate valid destinations for a move operation
---@param sourceHusbandry table The source husbandry (excluded from results)
---@param farmId number The farm ID to filter by
---@param animalSubTypeIndex number The animal subtype that must be supported
---@return table Array of destination entries
function AnimalScreenMoveFarm.getValidDestinations(sourceHusbandry, farmId, animalSubTypeIndex)
    Log:trace("getValidDestinations: farmId=%d subTypeIndex=%d", farmId, animalSubTypeIndex)

    local destinations = {}

    local subType = g_currentMission.animalSystem:getSubTypeByIndex(animalSubTypeIndex)
    if subType == nil then
        Log:warning("getValidDestinations: no subType for index %d", animalSubTypeIndex)
        return destinations
    end
    local animalTypeIndex = subType.typeIndex
    local animalType = g_currentMission.animalSystem:getTypeByIndex(animalTypeIndex)

    for _, placeable in ipairs(g_currentMission.placeableSystem.placeables) do
        if placeable:getOwnerFarmId() ~= farmId then
            -- skip: wrong farm
        elseif placeable.spec_husbandryAnimals ~= nil
               and placeable:getSupportsAnimalSubType(animalSubTypeIndex)
               and placeable ~= sourceHusbandry then
            -- Regular husbandry
            local currentCount = placeable:getNumOfAnimals()
            local maxCount = placeable:getMaxNumOfAnimals(animalType)
            local freeSlots = placeable:getNumOfFreeAnimalSlots(animalSubTypeIndex)

            local entry = {
                placeable = placeable,
                name = placeable:getName(),
                currentCount = currentCount,
                maxCount = maxCount,
                freeSlots = freeSlots,
                isEPP = false,
            }

            table.insert(destinations, entry)
            Log:trace("  husbandry: '%s' (%d/%d)", entry.name, currentCount, maxCount)

        elseif placeable.spec_extendedProductionPoint ~= nil then
            -- EPP (butcher) — methods live on the production point, not the placeable
            local eppSpec = placeable.spec_extendedProductionPoint
            local pp = eppSpec.productionPoint

            if pp ~= nil and pp.animalsTypeData ~= nil then
                local eppTypeData = pp.animalsTypeData[animalTypeIndex]

                if eppTypeData ~= nil and pp:getSupportsAnimalSubType(animalSubTypeIndex) then
                    local freeSlots = pp:getNumOfFreeAnimalSlots(animalSubTypeIndex)
                    local maxCount = eppTypeData.maxNumAnimals or 0
                    local currentCount = maxCount - freeSlots

                    local entry = {
                        placeable = pp,
                        name = placeable:getName(),
                        currentCount = currentCount,
                        maxCount = maxCount,
                        freeSlots = freeSlots,
                        isEPP = true,
                        minAge = eppTypeData.minimumAge,
                        maxAge = eppTypeData.maximumAge,
                    }

                    table.insert(destinations, entry)
                    Log:trace("  EPP: '%s' (%d/%d) ages %s-%s",
                        entry.name, currentCount, maxCount,
                        tostring(entry.minAge), tostring(entry.maxAge))
                end
            end
        end
    end

    Log:trace("getValidDestinations: found %d destinations", #destinations)
    return destinations
end


--- Static: validate animals against a destination, categorizing valid vs rejected
---@param animals table Array of Animal objects to validate
---@param destination table Destination entry from getValidDestinations
---@param animalTypeIndex number The animal type index
---@return table Validation result with valid, rejected arrays and destination
function AnimalScreenMoveFarm.buildMoveValidationResult(animals, destination, animalTypeIndex)
    Log:trace("buildMoveValidationResult: %d animals, dest='%s' typeIndex=%d",
        #animals, destination.name, animalTypeIndex)

    local result = { valid = {}, rejected = {}, destination = destination }

    local slotsUsed = 0
    local freeSlots = destination.freeSlots

    for _, animal in ipairs(animals) do
        local age = animal.age or 0
        local rejected = false

        -- Check EPP age constraints
        if destination.isEPP and destination.minAge ~= nil and destination.maxAge ~= nil then
            local minAge = destination.minAge
            local maxAge = destination.maxAge

            if age < minAge then
                table.insert(result.rejected, { animal = animal, reason = "AGE_TOO_YOUNG" })
                Log:trace("  rejected '%s': AGE_TOO_YOUNG (age=%d, min=%d)",
                    animal.name or animal.uniqueId or "?", age, minAge)
                rejected = true
            elseif age > maxAge then
                table.insert(result.rejected, { animal = animal, reason = "AGE_TOO_OLD" })
                Log:trace("  rejected '%s': AGE_TOO_OLD (age=%d, max=%d)",
                    animal.name or animal.uniqueId or "?", age, maxAge)
                rejected = true
            end
        end

        if not rejected then
            -- Check cumulative capacity
            if slotsUsed >= freeSlots then
                table.insert(result.rejected, { animal = animal, reason = "NO_CAPACITY" })
                Log:trace("  rejected '%s': NO_CAPACITY (used=%d, free=%d)",
                    animal.name or animal.uniqueId or "?", slotsUsed, freeSlots)
            else
                slotsUsed = slotsUsed + 1
                table.insert(result.valid, animal)
                Log:trace("  valid '%s' (slot %d/%d)",
                    animal.name or animal.uniqueId or "?", slotsUsed, freeSlots)
            end
        end
    end

    Log:trace("buildMoveValidationResult: %d valid, %d rejected", #result.valid, #result.rejected)
    return result
end


--- Execute single animal move
function AnimalScreenMoveFarm:applyMoveTarget(animalTypeIndex, animal, destination)
    Log:debug("applyMoveTarget: animal='%s' subType=%s dest='%s'",
        animal.name or animal.uniqueId or "?",
        tostring(animal.subTypeIndex),
        destination:getName())

    local ownerFarmId = self.husbandry:getOwnerFarmId()
    Log:trace("applyMoveTarget: validating (ownerFarmId=%d)", ownerFarmId)
    local errorCode = AnimalMoveEvent.validate(self.husbandry, destination, ownerFarmId, animal.subTypeIndex)

    if errorCode ~= nil then
        local mapping = AnimalScreenMoveFarm.MOVE_ERROR_CODE_MAPPING[errorCode]
        if mapping ~= nil and self.errorCallback ~= nil then
            self.errorCallback(g_i18n:getText(mapping.text))
        end
        Log:debug("applyMoveTarget: validation failed, errorCode=%d", errorCode)
        return false
    end

    Log:trace("applyMoveTarget: validation passed, dispatching event")
    self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_TARGET, g_i18n:getText("rl_ui_moveTab"))
    g_messageCenter:subscribe(AnimalMoveEvent, self.onAnimalMoved, self)

    Log:trace("applyMoveTarget: calling sendEvent")
    g_client:getServerConnection():sendEvent(AnimalMoveEvent.new(self.husbandry, destination, { animal }, "SOURCE"))
    Log:trace("applyMoveTarget: sendEvent returned")

    if self.husbandry.addRLMessage ~= nil then
        self.husbandry:addRLMessage("MOVED_ANIMALS_SOURCE_SINGLE", nil, { destination:getName() })
    end

    Log:debug("applyMoveTarget: complete for 1 animal to '%s'", destination:getName())
    return true
end


--- Execute bulk animal move
function AnimalScreenMoveFarm:applyMoveTargetBulk(animalTypeIndex, animals, destination)
    Log:debug("applyMoveTargetBulk: %d animals to '%s'", #animals, destination:getName())

    if #animals == 0 then
        Log:debug("applyMoveTargetBulk: no animals to move, skipping")
        return
    end

    self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_TARGET, g_i18n:getText("rl_ui_moveTab"))
    g_messageCenter:subscribe(AnimalMoveEvent, self.onAnimalMoved, self)

    Log:trace("applyMoveTargetBulk: calling sendEvent")
    g_client:getServerConnection():sendEvent(AnimalMoveEvent.new(self.husbandry, destination, animals, "SOURCE"))
    Log:trace("applyMoveTargetBulk: sendEvent returned")

    if self.husbandry.addRLMessage ~= nil then
        if #animals == 1 then
            self.husbandry:addRLMessage("MOVED_ANIMALS_SOURCE_SINGLE", nil, { destination:getName() })
        else
            self.husbandry:addRLMessage("MOVED_ANIMALS_SOURCE_MULTIPLE", nil, { #animals, destination:getName() })
        end
    end

    Log:debug("applyMoveTargetBulk: complete for %d animals to '%s'", #animals, destination:getName())
end


function AnimalScreenMoveFarm:onAnimalMoved(errorCode)
    Log:trace("onAnimalMoved: errorCode=%s", tostring(errorCode))

    if errorCode ~= AnimalMoveEvent.MOVE_SUCCESS then
        local mapping = AnimalScreenMoveFarm.MOVE_ERROR_CODE_MAPPING[errorCode]
        if mapping ~= nil and self.errorCallback ~= nil then
            self.errorCallback(g_i18n:getText(mapping.text))
        end
    end

    g_messageCenter:unsubscribe(AnimalMoveEvent, self)

    -- Dismiss the spinner overlay (nil text hides the MessageDialog)
    if self.actionTypeCallback ~= nil then
        self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_NONE, nil)
    end

    if self.animalsChangedCallback ~= nil then
        self.animalsChangedCallback()
    end
end
