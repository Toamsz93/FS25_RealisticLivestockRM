--[[
    DewarManager.lua

    Tracks all dewar vehicles by farm and animal type index.
    Network sync is handled by the Vehicle system (DewarData specialization)
    - no readStream/writeStream needed here.
]]

local Log = RmLogging.getLogger("RLRM")

DewarManager = {}

local DewarManager_mt = Class(DewarManager)


function DewarManager.new()

	local self = setmetatable({}, DewarManager_mt)

	self.farms = {}

	return self

end


function DewarManager:addDewar(farmId, dewar)

	if self.farms[farmId] == nil then self.farms[farmId] = {} end

	local farm = self.farms[farmId]
	local typeIndex = dewar.animal.typeIndex

	if farm[typeIndex] == nil then farm[typeIndex] = {} end

	table.insert(farm[typeIndex], dewar)

	Log:debug("DewarManager:addDewar farmId=%d typeIndex=%d uniqueId=%s count=%d",
		farmId, typeIndex, tostring(dewar:getUniqueId()), #farm[typeIndex])

end


function DewarManager:removeDewar(farmId, dewar)

	if dewar.animal == nil then return end

	local typeIndex = dewar.animal.typeIndex

	if self.farms[farmId] == nil or self.farms[farmId][typeIndex] == nil then return end

	local id = dewar:getUniqueId()

	for i, object in pairs(self.farms[farmId][typeIndex]) do

		if object:getUniqueId() == id then
			table.remove(self.farms[farmId][typeIndex], i)
			Log:debug("DewarManager:removeDewar farmId=%d typeIndex=%d uniqueId=%s", farmId, typeIndex, tostring(id))
			return
		end

	end

end


function DewarManager:getDewarsByFarm(farmId)

	return self.farms[farmId]

end


function DewarManager:hasAnyDewars()

	for _, farm in pairs(self.farms) do
		for _, dewars in pairs(farm) do
			if #dewars > 0 then return true end
		end
	end

	return false

end


g_dewarManager = DewarManager.new()
