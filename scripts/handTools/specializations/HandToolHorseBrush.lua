RL_HandToolHorseBrush = {}


-- Fix MP cleaning: RL's animal IDs can differ between server and client.
-- Set a stable "farmId uniqueId" on animal.id so MP clean events resolve correctly.

function RL_HandToolHorseBrush:getHusbandryAndClusterFromNode(superFunc, node)

    if node == nil or not entityExists(node) then return nil, nil end

	local husbandryId, animalId = getAnimalFromCollisionNode(node)

	if husbandryId ~= nil and husbandryId ~= 0 then

		local clusterHusbandry = g_currentMission.husbandrySystem:getClusterHusbandryById(husbandryId)

		if clusterHusbandry ~= nil then

			local placeable = clusterHusbandry:getPlaceable()
			local animal = clusterHusbandry:getClusterByAnimalId(animalId, husbandryId)

			if animal ~= nil and (g_currentMission.accessHandler:canFarmAccess(self.farmId, placeable) and (animal.changeDirt ~= nil and animal.getName ~= nil)) then
				-- Use stable ID so MP events resolve correctly on the server
				if animal.farmId ~= nil and animal.uniqueId ~= nil then
					animal.id = animal.farmId .. " " .. animal.uniqueId
				end
				return placeable, animal
			end

		end

	end

	return nil, nil

end

HandToolHorseBrush.getHusbandryAndClusterFromNode = Utils.overwrittenFunction(HandToolHorseBrush.getHusbandryAndClusterFromNode, RL_HandToolHorseBrush.getHusbandryAndClusterFromNode)