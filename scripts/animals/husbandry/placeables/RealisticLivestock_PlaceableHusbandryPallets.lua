RealisticLivestock_PlaceableHusbandryPallets = {}


function RealisticLivestock_PlaceableHusbandryPallets.registerOverwrittenFunctions(placeable)
	SpecializationUtil.registerOverwrittenFunction(placeable, "updateInputAndOutput", PlaceableHusbandryPallets.updateInputAndOutput)
end

PlaceableHusbandryPallets.registerOverwrittenFunctions = Utils.appendedFunction(PlaceableHusbandryPallets.registerOverwrittenFunctions, RealisticLivestock_PlaceableHusbandryPallets.registerOverwrittenFunctions)


function RealisticLivestock_PlaceableHusbandryPallets:onHusbandryAnimalsUpdate(superFunc, clusters)
	-- Skip superFunc (no base game cluster-based litersPerHour calculation)
	-- But populate activeFillTypes for UI display on both server and client
	local spec = self.spec_husbandryPallets
	if spec ~= nil then
		spec.activeFillTypes = {}
		for _, animal in ipairs(clusters) do
			local subType = animal:getSubType()
			if subType ~= nil then
				local pallets = subType.output.pallets
				if pallets ~= nil and spec.litersPerHour[pallets.fillType] ~= nil then
					table.addElement(spec.activeFillTypes, pallets.fillType)
				end
			end
		end
	end
end

PlaceableHusbandryPallets.onHusbandryAnimalsUpdate = Utils.overwrittenFunction(PlaceableHusbandryPallets.onHusbandryAnimalsUpdate, RealisticLivestock_PlaceableHusbandryPallets.onHusbandryAnimalsUpdate)


function PlaceableHusbandryPallets:updateInputAndOutput(superFunc, animals)

    superFunc(self, animals)

    local spec = self.spec_husbandryPallets

    for fillType, _ in pairs(spec.litersPerHour) do
        spec.litersPerHour[fillType] = 0
    end

    spec.activeFillTypes = {}

    for _, animal in pairs(animals) do

        local subType = animal:getSubType()

        if subType ~= nil then

            local pallets = subType.output.pallets

            if pallets ~= nil then

                if spec.litersPerHour[pallets.fillType] ~= nil then
                    local output = animal:getOutput("pallets")
                    spec.litersPerHour[pallets.fillType] = spec.litersPerHour[pallets.fillType] + output
                    table.addElement(spec.activeFillTypes, pallets.fillType)
                    if output > 0 then
                        Log:trace("Pallets: subType='%s' fillType=%s output=%.4f litersPerHour=%.4f",
                            tostring(subType.name),
                            tostring(g_fillTypeManager:getFillTypeNameByIndex(pallets.fillType)),
                            output,
                            spec.litersPerHour[pallets.fillType])
                    end
                else
                    Log:debug("Pallets: fillType %s (index=%s) for subType '%s' not in building's litersPerHour - output dropped. Registered: %s",
                        tostring(g_fillTypeManager:getFillTypeNameByIndex(pallets.fillType)),
                        tostring(pallets.fillType),
                        tostring(subType.name),
                        tostring(table.concat(
                            (function() local keys = {} for k, _ in pairs(spec.litersPerHour) do table.insert(keys, tostring(g_fillTypeManager:getFillTypeNameByIndex(k) or k)) end return keys end)(),
                            ", ")))
                end

            end

        end

    end

end