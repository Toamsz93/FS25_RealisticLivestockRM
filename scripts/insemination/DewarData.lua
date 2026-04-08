--[[
    DewarData.lua

    Vehicle specialization for the dewar (semen container).
    Replaces the old PhysicsObject-based Dewar.lua with a proper Vehicle/pallet
    that gets engine-provided physics, network sync, pickup, and persistence for free.

    Requires parent type "pallet" (Pallet specialization).

    NOTE: Vehicle base already provides getUniqueId/setUniqueId (self.uniqueId).
    We use Vehicle's built-in uniqueId field directly -- no spec.uniqueId needed.
]]

local Log = RmLogging.getLogger("RLRM")

DewarData = {}

DewarData.SPEC_TABLE_NAME = "spec_FS25_RealisticLivestockRM.dewarData"
DewarData.CAPACITY = 1000
DewarData.PRICE_PER_STRAW = 0.85


function DewarData.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Pallet, specializations)
end


function DewarData.registerFunctions(vehicleType)
    -- getUniqueId/setUniqueId are on Vehicle base -- do NOT register here
    SpecializationUtil.registerFunction(vehicleType, "setAnimal", DewarData.setAnimal)
    SpecializationUtil.registerFunction(vehicleType, "getAnimal", DewarData.getAnimal)
    SpecializationUtil.registerFunction(vehicleType, "setStraws", DewarData.setStraws)
    SpecializationUtil.registerFunction(vehicleType, "changeStraws", DewarData.changeStraws)
end


function DewarData.registerOverwrittenFunctions(vehicleType)
    -- showInfo is on Vehicle base -- override, not register
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", DewarData.showInfo)
end


function DewarData.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", DewarData)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", DewarData)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", DewarData)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", DewarData)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", DewarData)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", DewarData)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", DewarData)
end


-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function DewarData:onLoad(savegame)
    local spec = self[DewarData.SPEC_TABLE_NAME]
    spec.animal = nil
    spec.straws = 0
    spec.texts = {}
    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.isRegistered = false

    -- Resolve 3D text parent nodes via component hierarchy
    -- i3d structure: component1 > dewarMesh > stickyNote_animal (child 0), stickyNote_straws (child 1)
    local componentNode = self.components[1].node
    local meshNode = getChildAt(componentNode, 0)
    if meshNode ~= nil and meshNode ~= 0 then
        spec.stickyNoteAnimal = getChildAt(meshNode, 0)
        spec.stickyNoteStraws = getChildAt(meshNode, 1)
    else
        spec.stickyNoteAnimal = nil
        spec.stickyNoteStraws = nil
        Log:warning("DewarData:onLoad could not resolve mesh node for 3D text")
    end

    -- Compatibility properties on the vehicle table for consumer access
    -- (self.uniqueId is managed by Vehicle base via setUniqueId/getUniqueId)
    self.isDewar = true
    self.animal = nil
    self.straws = 0

    -- Load from savegame if available
    if savegame ~= nil and savegame.xmlFile ~= nil then
        local key = savegame.key .. ".FS25_RealisticLivestockRM.dewarData"
        if savegame.xmlFile:hasProperty(key) then
            DewarData.loadDewarFromSavegame(self, savegame.xmlFile, key)
        end
    end

    Log:debug("DewarData:onLoad vehicle=%s uniqueId=%s straws=%d",
        tostring(self.rootNode), tostring(self:getUniqueId()), spec.straws)
end


function DewarData:onDelete()
    local spec = self[DewarData.SPEC_TABLE_NAME]

    if spec.isRegistered then
        g_dewarManager:removeDewar(self:getOwnerFarmId(), self)
        spec.isRegistered = false
    end

    -- Clean up 3D text overlays
    if spec.texts.straws ~= nil then
        RealisticLivestock.delete3DLinkedText(spec.texts.straws)
        spec.texts.straws = nil
    end
    if spec.texts.animal ~= nil then
        RealisticLivestock.delete3DLinkedText(spec.texts.animal)
        spec.texts.animal = nil
    end

    Log:info("DewarData:onDelete uniqueId=%s", tostring(self:getUniqueId()))
end


-- ---------------------------------------------------------------------------
-- Savegame persistence
-- ---------------------------------------------------------------------------

function DewarData:loadDewarFromSavegame(xmlFile, key)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    local uniqueId = xmlFile:getString(key .. "#uniqueId")
    if uniqueId ~= nil then
        self:setUniqueId(uniqueId)
    end
    spec.straws = xmlFile:getInt(key .. "#straws") or 0

    local animalKey = key .. ".animal"
    if xmlFile:hasProperty(animalKey) then
        local animal = {}

        animal.country = xmlFile:getInt(animalKey .. "#country")
        animal.farmId = xmlFile:getString(animalKey .. "#farmId")
        animal.uniqueId = xmlFile:getString(animalKey .. "#uniqueId")
        animal.name = xmlFile:getString(animalKey .. "#name")
        animal.typeIndex = xmlFile:getInt(animalKey .. "#typeIndex")
        animal.subTypeIndex = xmlFile:getInt(animalKey .. "#subTypeIndex")
        animal.success = xmlFile:getFloat(animalKey .. "#success")

        animal.genetics = {
            ["metabolism"] = xmlFile:getFloat(animalKey .. ".genetics#metabolism"),
            ["fertility"] = xmlFile:getFloat(animalKey .. ".genetics#fertility"),
            ["health"] = xmlFile:getFloat(animalKey .. ".genetics#health"),
            ["quality"] = xmlFile:getFloat(animalKey .. ".genetics#quality"),
            ["productivity"] = xmlFile:getFloat(animalKey .. ".genetics#productivity")
        }

        -- Validate subtype consistency
        local animalSystem = g_currentMission.animalSystem
        local st = animalSystem:getSubTypeByIndex(animal.subTypeIndex)
        local resolvedTypeName = st and animalSystem.typeIndexToName[st.typeIndex] or "nil"
        local savedTypeName = animalSystem.typeIndexToName[animal.typeIndex] or "nil"
        Log:debug("DewarData load: saved typeIndex=%d subTypeIndex=%d -> resolved name=%s (type=%s)",
            animal.typeIndex, animal.subTypeIndex, st and st.name or "nil", resolvedTypeName)
        if st == nil then
            Log:warning("DewarData load: subTypeIndex=%d has no matching subtype - semen data may be from removed pack", animal.subTypeIndex)
        elseif st.typeIndex ~= animal.typeIndex then
            Log:warning("DewarData load: type mismatch! saved typeIndex=%d(%s) but subTypeIndex=%d resolves to typeIndex=%d(%s) - index may be stale",
                animal.typeIndex, savedTypeName, animal.subTypeIndex, st.typeIndex, resolvedTypeName)
        end

        spec.animal = animal
        DewarData.syncCompatProperties(self)
        DewarData.registerWithManager(self)
    end

    -- Mirror straws even if no animal
    self.straws = spec.straws

    Log:info("DewarData:loadDewarFromSavegame uniqueId=%s farmId=%d straws=%d animal=%s",
        tostring(self:getUniqueId()), self:getOwnerFarmId(), spec.straws,
        spec.animal and tostring(spec.animal.typeIndex) or "nil")

    DewarData.updateStrawVisuals(self)
    DewarData.updateAnimalVisuals(self)
end


function DewarData:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    local dewarUniqueId = self:getUniqueId()
    if dewarUniqueId ~= nil then
        xmlFile:setString(key .. "#uniqueId", dewarUniqueId)
    end
    xmlFile:setInt(key .. "#straws", spec.straws)

    if spec.animal ~= nil then
        local animalKey = key .. ".animal"
        local animal = spec.animal

        xmlFile:setInt(animalKey .. "#country", animal.country)
        xmlFile:setString(animalKey .. "#farmId", animal.farmId)
        xmlFile:setString(animalKey .. "#uniqueId", animal.uniqueId)
        xmlFile:setString(animalKey .. "#name", animal.name or "")
        xmlFile:setInt(animalKey .. "#typeIndex", animal.typeIndex)
        xmlFile:setInt(animalKey .. "#subTypeIndex", animal.subTypeIndex)
        xmlFile:setFloat(animalKey .. "#success", animal.success)

        for type, value in pairs(animal.genetics) do
            xmlFile:setFloat(animalKey .. ".genetics#" .. type, value)
        end
    end
end


-- ---------------------------------------------------------------------------
-- Network serialization - full sync (client join)
-- ---------------------------------------------------------------------------

function DewarData:onWriteStream(streamId, connection)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    streamWriteUInt16(streamId, spec.straws)
    streamWriteBool(streamId, spec.animal ~= nil)

    if spec.animal ~= nil then
        local animal = spec.animal
        streamWriteUInt8(streamId, animal.country)
        streamWriteString(streamId, animal.farmId)
        streamWriteString(streamId, animal.uniqueId)
        streamWriteString(streamId, animal.name or "")
        streamWriteUInt8(streamId, animal.typeIndex)
        streamWriteUInt8(streamId, animal.subTypeIndex)
        streamWriteFloat32(streamId, animal.success)
        streamWriteFloat32(streamId, animal.genetics.metabolism)
        streamWriteFloat32(streamId, animal.genetics.fertility)
        streamWriteFloat32(streamId, animal.genetics.health)
        streamWriteFloat32(streamId, animal.genetics.quality)
        streamWriteFloat32(streamId, animal.genetics.productivity or -1)
    end

    Log:trace("DewarData:onWriteStream uniqueId=%s straws=%d hasAnimal=%s",
        tostring(self:getUniqueId()), spec.straws, tostring(spec.animal ~= nil))
end


function DewarData:onReadStream(streamId, connection)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    spec.straws = streamReadUInt16(streamId)

    local hasAnimal = streamReadBool(streamId)
    if hasAnimal then
        local animal = { genetics = {} }
        animal.country = streamReadUInt8(streamId)
        animal.farmId = streamReadString(streamId)
        animal.uniqueId = streamReadString(streamId)
        animal.name = streamReadString(streamId)
        animal.typeIndex = streamReadUInt8(streamId)
        animal.subTypeIndex = streamReadUInt8(streamId)
        animal.success = streamReadFloat32(streamId)
        animal.genetics.metabolism = streamReadFloat32(streamId)
        animal.genetics.fertility = streamReadFloat32(streamId)
        animal.genetics.health = streamReadFloat32(streamId)
        animal.genetics.quality = streamReadFloat32(streamId)
        animal.genetics.productivity = streamReadFloat32(streamId)
        if animal.genetics.productivity < 0 then animal.genetics.productivity = nil end

        spec.animal = animal
    end

    DewarData.syncCompatProperties(self)
    if spec.animal ~= nil then
        DewarData.registerWithManager(self)
    end

    DewarData.updateStrawVisuals(self)
    DewarData.updateAnimalVisuals(self)

    Log:info("DewarData:onReadStream uniqueId=%s straws=%d hasAnimal=%s",
        tostring(self:getUniqueId()), spec.straws, tostring(hasAnimal))
end


-- ---------------------------------------------------------------------------
-- Network serialization - update stream (mid-game dirty flag sync)
-- ---------------------------------------------------------------------------

function DewarData:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
            streamWriteUInt16(streamId, spec.straws)
            Log:trace("DewarData:onWriteUpdateStream straws=%d", spec.straws)
        end
    end
end


function DewarData:onReadUpdateStream(streamId, timestamp, connection)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    if connection:getIsServer() then
        if streamReadBool(streamId) then
            spec.straws = streamReadUInt16(streamId)
            self.straws = spec.straws
            DewarData.updateStrawVisuals(self)
            Log:trace("DewarData:onReadUpdateStream straws=%d", spec.straws)
        end
    end
end


-- ---------------------------------------------------------------------------
-- Public API (consumer-compatible names)
-- ---------------------------------------------------------------------------
-- NOTE: getUniqueId/setUniqueId are provided by Vehicle base class.
-- Consumers call dewar:getUniqueId() which returns self.uniqueId (Vehicle field).

function DewarData:getAnimal()
    return self[DewarData.SPEC_TABLE_NAME].animal
end


function DewarData:setAnimal(animal)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    -- Accept either a live Animal object or a raw table
    if animal.birthday ~= nil then
        -- Live Animal object - extract snapshot
        spec.animal = {
            ["country"] = animal.birthday.country,
            ["farmId"] = animal.farmId,
            ["uniqueId"] = animal.uniqueId,
            ["name"] = animal:getName(),
            ["typeIndex"] = animal.animalTypeIndex,
            ["subTypeIndex"] = animal.subTypeIndex,
            ["genetics"] = table.clone(animal.genetics, 3),
            ["success"] = animal.success
        }
    else
        -- Raw table (from network/migration) - store directly
        spec.animal = animal
    end

    DewarData.syncCompatProperties(self)
    DewarData.registerWithManager(self)
    DewarData.updateAnimalVisuals(self)

    Log:debug("DewarData:setAnimal uniqueId=%s animalType=%s animalId=%s",
        tostring(self:getUniqueId()), tostring(spec.animal.typeIndex),
        tostring(spec.animal.uniqueId))
end


function DewarData:setStraws(value)
    local spec = self[DewarData.SPEC_TABLE_NAME]
    spec.straws = value or 0
    self.straws = spec.straws

    if self.isServer then
        self:raiseDirtyFlags(spec.dirtyFlag)
        Log:debug("DewarData:setStraws value=%d dirtyFlag raised", spec.straws)
    end

    DewarData.updateStrawVisuals(self)
end


function DewarData:changeStraws(delta)
    local spec = self[DewarData.SPEC_TABLE_NAME]
    spec.straws = math.clamp(spec.straws + delta, 0, DewarData.CAPACITY)
    self.straws = spec.straws

    if spec.straws <= 0 then
        if g_server ~= nil then
            Log:info("DewarData:changeStraws auto-deleting empty dewar uniqueId=%s", tostring(self:getUniqueId()))
            self:delete()
        end
        return
    end

    if self.isServer then
        self:raiseDirtyFlags(spec.dirtyFlag)
    end

    DewarData.updateStrawVisuals(self)
end


function DewarData:showInfo(superFunc, box)
    local spec = self[DewarData.SPEC_TABLE_NAME]

    if spec.animal == nil then
        superFunc(self, box)
        return
    end

    local animal = spec.animal
    local animalSystem = g_currentMission.animalSystem
    local subType = animalSystem:getSubTypeByIndex(animal.subTypeIndex)

    box:addLine(g_i18n:getText("rl_ui_strawMultiple"), tostring(spec.straws))
    box:addLine(g_i18n:getText("rl_ui_averageSuccess"), string.format("%s%%", tostring(math.round(animal.success * 100))))
    box:addLine(g_i18n:getText("rl_ui_species"), animalSystem:getTypeByIndex(animal.typeIndex).groupTitle)
    box:addLine(g_i18n:getText("infohud_type"), g_fillTypeManager:getFillTypeTitleByIndex(subType.fillTypeIndex))
    box:addLine(g_i18n:getText("infohud_name"), animal.name)
    box:addLine(g_i18n:getText("rl_ui_earTag"), string.format("%s %s %s", RLConstants.AREA_CODES[animal.country].code, animal.farmId, animal.uniqueId))

    for type, value in pairs(animal.genetics) do
        local valueText

        if value >= 1.65 then
            valueText = "extremelyHigh"
        elseif value >= 1.4 then
            valueText = "veryHigh"
        elseif value >= 1.1 then
            valueText = "high"
        elseif value >= 0.9 then
            valueText = "average"
        elseif value >= 0.7 then
            valueText = "low"
        elseif value >= 0.35 then
            valueText = "veryLow"
        else
            valueText = "extremelyLow"
        end

        box:addLine(g_i18n:getText("rl_ui_" .. type), g_i18n:getText("rl_ui_genetics_" .. valueText))
    end
end


-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

function DewarData:syncCompatProperties()
    local spec = self[DewarData.SPEC_TABLE_NAME]
    self.animal = spec.animal
    self.straws = spec.straws
    -- self.uniqueId is managed by Vehicle base class
end


function DewarData:registerWithManager()
    local spec = self[DewarData.SPEC_TABLE_NAME]

    if spec.isRegistered then
        return
    end

    if spec.animal == nil then
        Log:debug("DewarData:registerWithManager skipped - no animal data yet")
        return
    end

    g_dewarManager:addDewar(self:getOwnerFarmId(), self)
    spec.isRegistered = true

    Log:debug("DewarData:registerWithManager farmId=%d typeIndex=%d uniqueId=%s",
        self:getOwnerFarmId(), spec.animal.typeIndex, tostring(self:getUniqueId()))
end


function DewarData:updateStrawVisuals()
    local spec = self[DewarData.SPEC_TABLE_NAME]
    local parent = spec.stickyNoteStraws

    if parent == nil or parent == 0 then return end

    RealisticLivestock.set3DTextRemoveSpaces(true)
    RealisticLivestock.setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    RealisticLivestock.setTextAlignment(RenderText.ALIGN_CENTER)
    RealisticLivestock.setTextColor(1, 0.1, 0.1, 1)
    RealisticLivestock.set3DTextWordsPerLine(1)
    RealisticLivestock.setTextLineHeightScale(0.75)
    RealisticLivestock.setTextFont(RealisticLivestock.FONTS.toms_handwritten)

    if spec.texts.straws ~= nil then RealisticLivestock.delete3DLinkedText(spec.texts.straws) end
    spec.texts.straws = RealisticLivestock.create3DLinkedText(parent, 0.003, 0.01, 0.003, 0, math.rad(-90), 0, 0.025, string.format("%s %s", spec.straws, spec.straws == 1 and "straw" or "straws"))

    RealisticLivestock.set3DTextRemoveSpaces(false)
    RealisticLivestock.setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    RealisticLivestock.setTextAlignment(RenderText.ALIGN_LEFT)
    RealisticLivestock.setTextColor(1, 1, 1, 1)
    RealisticLivestock.set3DTextWordsPerLine(0)
    RealisticLivestock.setTextLineHeightScale(1.1)
    RealisticLivestock.setTextFont()

    Log:trace("DewarData:updateStrawVisuals straws=%d", spec.straws)
end


function DewarData:updateAnimalVisuals()
    local spec = self[DewarData.SPEC_TABLE_NAME]

    if spec.animal == nil then return end

    local parent = spec.stickyNoteAnimal
    if parent == nil or parent == 0 then return end

    local country = RLConstants.AREA_CODES[spec.animal.country].code
    local farmId = spec.animal.farmId
    local uniqueId = spec.animal.uniqueId

    RealisticLivestock.set3DTextRemoveSpaces(true)
    RealisticLivestock.setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    RealisticLivestock.setTextAlignment(RenderText.ALIGN_CENTER)
    RealisticLivestock.setTextColor(1, 0.1, 0.1, 1)
    RealisticLivestock.set3DTextWordsPerLine(1)
    RealisticLivestock.setTextLineHeightScale(1.25)
    RealisticLivestock.setTextFont(RealisticLivestock.FONTS.toms_handwritten)

    if spec.texts.animal ~= nil then RealisticLivestock.delete3DLinkedText(spec.texts.animal) end
    spec.texts.animal = RealisticLivestock.create3DLinkedText(parent, -0.01, -0.002, 0.008, 0, math.rad(-170), 0, 0.02, string.format("%s %s %s", country, uniqueId, farmId))

    RealisticLivestock.set3DTextAutoScale(false)
    RealisticLivestock.set3DTextRemoveSpaces(false)
    RealisticLivestock.setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    RealisticLivestock.setTextAlignment(RenderText.ALIGN_LEFT)
    RealisticLivestock.setTextColor(1, 1, 1, 1)
    RealisticLivestock.set3DTextWordsPerLine(0)
    RealisticLivestock.setTextLineHeightScale(1.1)
    RealisticLivestock.setTextFont()

    Log:trace("DewarData:updateAnimalVisuals country=%s uniqueId=%s", country, uniqueId)
end
