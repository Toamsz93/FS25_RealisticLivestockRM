RL_AnimalScreenDealerTrailer = {}

function RL_AnimalScreenDealerTrailer:initTargetItems(_)

    self.targetItems = {}
    local animals = self.trailer:getClusters()

    if animals ~= nil then
        for _, animal in pairs(animals) do
            local item = AnimalItemStock.new(animal)
            table.insert(self.targetItems, item)
        end
    end

    table.sort(self.targetItems, RL_AnimalScreenBase.sortAnimals)

end

AnimalScreenDealerTrailer.initTargetItems = Utils.overwrittenFunction(AnimalScreenDealerTrailer.initTargetItems, RL_AnimalScreenDealerTrailer.initTargetItems)


function RL_AnimalScreenDealerTrailer:initSourceItems(_)

    local animalSystem = g_currentMission.animalSystem
    local animalType = self.trailer:getCurrentAnimalType()

    if animalType == nil then

        local animalTypes = animalSystem:getTypes()
        self.sourceItems = {}

        for _, type in pairs(animalTypes) do

            local animalTypeIndex = type.typeIndex

            if not self.trailer:getSupportsAnimalType(animalTypeIndex) then continue end

            local animals = animalSystem:getSaleAnimalsByTypeIndex(animalTypeIndex)

            for _, animal in pairs(animals) do

                if self.sourceItems[animalTypeIndex] == nil then self.sourceItems[animalTypeIndex] = {} end

                local item = AnimalItemNew.new(animal)
                table.insert(self.sourceItems[animalTypeIndex], item)

            end

            if self.sourceItems[animalTypeIndex] ~= nil then table.sort(self.sourceItems[animalTypeIndex], RL_AnimalScreenBase.sortSaleAnimals) end

        end

        return

    end

    local animalTypeIndex = animalType.typeIndex
    local animals = animalSystem:getSaleAnimalsByTypeIndex(animalTypeIndex)
    
    self.sourceItems = { [animalTypeIndex] = {} }

    for _, animal in pairs(animals) do
        local item = AnimalItemNew.new(animal)
        table.insert(self.sourceItems[animalTypeIndex], item)
    end

    table.sort(self.sourceItems[animalTypeIndex], RL_AnimalScreenBase.sortSaleAnimals)

end

AnimalScreenDealerTrailer.initSourceItems = Utils.overwrittenFunction(AnimalScreenDealerTrailer.initSourceItems, RL_AnimalScreenDealerTrailer.initSourceItems)


function RL_AnimalScreenDealerTrailer:getSourceAnimalTypes()

    local currentAnimalType = self.trailer:getCurrentAnimalType()

	if currentAnimalType ~= nil then return { currentAnimalType } end

	local types = g_currentMission.animalSystem:getTypes()
	local sourceTypes = {}

	for _, type in ipairs(types) do
		if self.trailer:getSupportsAnimalType(type.typeIndex) and self.sourceItems[type.typeIndex] ~= nil then table.insert(sourceTypes, type) end
	end

	return sourceTypes

end

AnimalScreenDealerTrailer.getSourceAnimalTypes = Utils.overwrittenFunction(AnimalScreenDealerTrailer.getSourceAnimalTypes, RL_AnimalScreenDealerTrailer.getSourceAnimalTypes)


function RL_AnimalScreenDealerTrailer:getSourceMaxNumAnimals(_, _)

    return 1

end

AnimalScreenDealerTrailer.getSourceMaxNumAnimals = Utils.overwrittenFunction(AnimalScreenDealerTrailer.getSourceMaxNumAnimals, RL_AnimalScreenDealerTrailer.getSourceMaxNumAnimals)


function RL_AnimalScreenDealerTrailer:applySource(_, animalTypeIndex, animalIndex)

    self.sourceAnimals = nil

    local item = self.sourceItems[animalTypeIndex][animalIndex]
    local trailer = self.trailer
    local ownerFarmId = trailer:getOwnerFarmId()

    local price = -item:getPrice()

    local errorCode = AnimalBuyEvent.validate(trailer, item:getSubTypeIndex(), item:getAge(), 1, price, 0, ownerFarmId)

    if errorCode ~= nil then
		local error = AnimalScreenDealerFarm.BUY_ERROR_CODE_MAPPING[errorCode]
		self.errorCallback(g_i18n:getText(error.text))
		return false
	end

    local animal = item.animal or item.cluster

    self.sourceAnimals = { animal }

    self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_SOURCE, g_i18n:getText(AnimalScreenDealerFarm.L10N_SYMBOL.BUYING))
    g_messageCenter:subscribe(AnimalBuyEvent, self.onAnimalBought, self)
	g_client:getServerConnection():sendEvent(AnimalBuyEvent.new(trailer, self.sourceAnimals, price, 0))

    return true

end

AnimalScreenDealerTrailer.applySource = Utils.overwrittenFunction(AnimalScreenDealerTrailer.applySource, RL_AnimalScreenDealerTrailer.applySource)


function RL_AnimalScreenDealerTrailer:applyTarget(_, _, animalIndex)

    self.targetAnimals = nil

    local item = self.targetItems[animalIndex]
    local trailer = self.trailer
    local ownerFarmId = trailer:getOwnerFarmId()

    local price = item:getPrice()

    local errorCode = AnimalSellEvent.validate(trailer, item:getSubTypeIndex(), item:getAge(), 1, price, 0, ownerFarmId)

    if errorCode ~= nil then
		local error = AnimalScreenDealerFarm.SELL_ERROR_CODE_MAPPING[errorCode]
		self.errorCallback(g_i18n:getText(error.text))
		return false
	end

    local animal = item.animal or item.cluster

    self.targetAnimals = { animal }

    self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_TARGET, g_i18n:getText(AnimalScreenDealerFarm.L10N_SYMBOL.SELLING))
    g_messageCenter:subscribe(AnimalSellEvent, self.onAnimalSold, self)
	g_client:getServerConnection():sendEvent(AnimalSellEvent.new(trailer, self.targetAnimals, price, 0))

    return true

end

AnimalScreenDealerTrailer.applyTarget = Utils.overwrittenFunction(AnimalScreenDealerTrailer.applyTarget, RL_AnimalScreenDealerTrailer.applyTarget)


function RL_AnimalScreenDealerTrailer:onAnimalBought(errorCode)

    if errorCode == AnimalBuyEvent.BUY_SUCCESS and self.sourceAnimals ~= nil then

        for _, animal in pairs(self.sourceAnimals) do g_currentMission.animalSystem:removeSaleAnimal(animal.animalTypeIndex, animal.birthday.country, animal.farmId, animal.uniqueId) end

    end

end

AnimalScreenDealerTrailer.onAnimalBought = Utils.prependedFunction(AnimalScreenDealerTrailer.onAnimalBought, RL_AnimalScreenDealerTrailer.onAnimalBought)


function RL_AnimalScreenDealerTrailer:getSourcePrice(_, animalTypeIndex, animalIndex, _)

    if self.sourceItems[animalTypeIndex] ~= nil then

        local item = self.sourceItems[animalTypeIndex][animalIndex]

        if item ~= nil then

	        local price = item:getPrice()
	        return true, price, 0, price

        end

    end

    return false, 0, 0, 0

end

AnimalScreenDealerTrailer.getSourcePrice = Utils.overwrittenFunction(AnimalScreenDealerTrailer.getSourcePrice, RL_AnimalScreenDealerTrailer.getSourcePrice)


function AnimalScreenDealerTrailer:applySourceBulk(animalTypeIndex, items)

    self.sourceAnimals = {}

    local trailer = self.trailer
    local ownerFarmId = trailer:getOwnerFarmId()

    local sourceItems = self.sourceItems[animalTypeIndex]
    local totalPrice = 0
    local totalBoughtAnimals = 0

    for _, item in pairs(items) do

        if sourceItems[item] ~= nil then

            local sourceItem = sourceItems[item]
            local animal = sourceItem.animal
            local price = -sourceItem:getPrice()

            local errorCode = AnimalBuyEvent.validate(trailer, animal.subTypeIndex, animal.age, 1, price, 0, ownerFarmId)

            if errorCode ~= nil then continue end
    
            totalBoughtAnimals = totalBoughtAnimals + 1
            totalPrice = totalPrice + price

            table.insert(self.sourceAnimals, animal)

        end

    end

    self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_SOURCE, g_i18n:getText(AnimalScreenDealerFarm.L10N_SYMBOL.BUYING))
    g_messageCenter:subscribe(AnimalBuyEvent, self.onAnimalBought, self)
    g_client:getServerConnection():sendEvent(AnimalBuyEvent.new(trailer, self.sourceAnimals, totalPrice, 0))

end


function AnimalScreenDealerTrailer:applyTargetBulk(animalTypeIndex, items)

    self.targetAnimals = {}

    local trailer = self.trailer
    local ownerFarmId = trailer:getOwnerFarmId()

    local targetItems = self.targetItems
    local totalPrice = 0
    local totalSoldAnimals = 0

    for _, item in pairs(items) do

        if targetItems[item] ~= nil then

            local targetItem = targetItems[item]
            local animal = targetItem.animal or targetItem.cluster
            local price = targetItem:getPrice()

            local errorCode = AnimalSellEvent.validate(trailer, targetItem:getClusterId(), 1, price, 0)

            if errorCode ~= nil then continue end
    
            totalSoldAnimals = totalSoldAnimals + 1
            totalPrice = totalPrice + price

            table.insert(self.targetAnimals, animal)

        end

    end

    self.actionTypeCallback(AnimalScreenBase.ACTION_TYPE_SOURCE, g_i18n:getText(AnimalScreenDealerFarm.L10N_SYMBOL.SELLING))
    g_messageCenter:subscribe(AnimalSellEvent, self.onAnimalSold, self)
	g_client:getServerConnection():sendEvent(AnimalSellEvent.new(trailer, self.targetAnimals, totalPrice, 0))

end