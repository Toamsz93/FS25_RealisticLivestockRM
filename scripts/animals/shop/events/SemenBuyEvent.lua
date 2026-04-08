--[[
    SemenBuyEvent.lua

    Client sends purchase request to server. Server creates Vehicle dewar via
    VehicleLoadingData and charges money in the async callback. The Vehicle
    system automatically syncs the new dewar to all clients - no broadcast needed.
]]

local Log = RmLogging.getLogger("RLRM")
local modDirectory = g_currentModDirectory

SemenBuyEvent = {}

local SemenBuyEvent_mt = Class(SemenBuyEvent, Event)
InitEventClass(SemenBuyEvent, "SemenBuyEvent")


function SemenBuyEvent.emptyNew()

    local self = Event.new(SemenBuyEvent_mt)
    return self

end


function SemenBuyEvent.new(animal, quantity, price, farmId, position, rotation)

	local event = SemenBuyEvent.emptyNew()

	event.animal = animal
	event.quantity = quantity
	event.price = price
	event.farmId = farmId
	event.position = position
	event.rotation = rotation

	return event

end


function SemenBuyEvent:readStream(streamId, connection)

	self.animal = Animal.new()
	self.animal:readStream(streamId, connection)
	self.animal.success = streamReadFloat32(streamId)

	self.quantity = streamReadUInt16(streamId)
	self.price = streamReadFloat32(streamId)
	self.farmId = streamReadUInt8(streamId)

	local x = streamReadFloat32(streamId)
	local y = streamReadFloat32(streamId)
	local z = streamReadFloat32(streamId)

	local rx = streamReadFloat32(streamId)
	local ry = streamReadFloat32(streamId)
	local rz = streamReadFloat32(streamId)

	self.position = { x, y, z }
	self.rotation = { rx, ry, rz }

	Log:trace("SemenBuyEvent:readStream calling run()")
	self:run(connection)

end


function SemenBuyEvent:writeStream(streamId, connection)

	self.animal:writeStream(streamId, connection)
	streamWriteFloat32(streamId, self.animal.success or 0.65)

	streamWriteUInt16(streamId, self.quantity)
	streamWriteFloat32(streamId, self.price)
	streamWriteUInt8(streamId, self.farmId)

	streamWriteFloat32(streamId, self.position[1])
	streamWriteFloat32(streamId, self.position[2])
	streamWriteFloat32(streamId, self.position[3])

	streamWriteFloat32(streamId, self.rotation[1])
	streamWriteFloat32(streamId, self.rotation[2])
	streamWriteFloat32(streamId, self.rotation[3])

end


function SemenBuyEvent:run(connection)

	-- Server only - create the dewar Vehicle
	if g_server == nil then return end

	Log:info("SemenBuyEvent:run farmId=%d quantity=%d price=%.2f animalType=%s",
		self.farmId, self.quantity, self.price, tostring(self.animal.animalTypeIndex))

	local storeItem = g_storeManager:getItemByXMLFilename(modDirectory .. "objects/dewar/dewar.xml")
	if storeItem == nil then
		Log:error("SemenBuyEvent: could not find dewar store item")
		return
	end

	local data = VehicleLoadingData.new()
	data:setStoreItem(storeItem)
	data:setPropertyState(VehiclePropertyState.OWNED)
	data:setOwnerFarmId(self.farmId)
	data:setPosition(self.position[1], self.position[2], self.position[3])
	data:setRotation(self.rotation[1], self.rotation[2], self.rotation[3])

	Log:debug("SemenBuyEvent: VehicleLoadingData configured, starting async load")

	-- Store event data for callback access
	self.pendingAnimal = self.animal
	self.pendingQuantity = self.quantity
	self.pendingPrice = self.price
	self.pendingFarmId = self.farmId

	data:load(SemenBuyEvent.onDewarLoaded, self)

end


function SemenBuyEvent:onDewarLoaded(vehicles, loadingState)

	if loadingState ~= VehicleLoadingState.OK then
		Log:error("SemenBuyEvent: failed to create dewar vehicle, loadingState=%s", tostring(loadingState))
		return
	end

	local vehicle = vehicles[1]
	if vehicle == nil then
		Log:error("SemenBuyEvent: vehicle list is empty after successful load")
		return
	end

	-- Generate unique ID for this dewar
	local uniqueId = string.format("dw-%d-%d", math.random(100000, 999999), g_updateLoopIndex or 0)
	vehicle:setUniqueId(uniqueId)
	vehicle:setAnimal(self.pendingAnimal)
	vehicle:setStraws(self.pendingQuantity)

	-- Charge money only on successful creation
	g_currentMission:addMoney(self.pendingPrice, self.pendingFarmId, MoneyType.SEMEN_PURCHASE, true, true)

	Log:info("SemenBuyEvent: dewar created uniqueId=%s farmId=%d straws=%d",
		uniqueId, self.pendingFarmId, self.pendingQuantity)

end
