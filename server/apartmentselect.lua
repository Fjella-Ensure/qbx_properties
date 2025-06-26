local config = require 'config.server'
local sharedConfig = require 'config.shared'
local logger = require '@qbx_core.modules.logger'

local function startRentThread(propertyId)
    CreateThread(function()
        while true do
            local property = MySQL.single.await('SELECT owner, price, rent_interval, property_name FROM properties WHERE id = ?', {propertyId})
            if not property or not property.owner then break end

            local player = exports.qbx_core:GetPlayerByCitizenId(property.owner) or exports.qbx_core:GetOfflinePlayer(property.owner)
            if not player then 
                print(string.format('%s does not exist anymore, consider checking property id %s', property.owner, propertyId)) 
                break 
            end

            if player.Offline then
                player.PlayerData.money.bank = player.PlayerData.money.bank - property.price
                if player.PlayerData.money.bank < 0 then break end
                exports.qbx_core:SaveOffline(player.PlayerData)
            else
                if not player.Functions.RemoveMoney('bank', property.price, string.format('Rent for %s', property.property_name)) then
                    exports.qbx_core:Notify(player.PlayerData.source, string.format('Not enough money to pay rent for %s', property.property_name), 'error')
                    break
                end
            end

            Wait(property.rent_interval * 3600000) 
        end

        MySQL.update('UPDATE properties SET owner = ? WHERE id = ?', {nil, propertyId})
    end)
end

RegisterNetEvent('qbx_properties:server:apartmentSelect', function(apartmentIndex)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not sharedConfig.apartmentOptions[apartmentIndex] then return end

    local hasApartment = MySQL.single.await('SELECT * FROM properties WHERE owner = ?', {player.PlayerData.citizenid})
    if hasApartment then return end

    local interior = sharedConfig.apartmentOptions[apartmentIndex].interior
    local interactData = {
        {
            type = 'logout',
            coords = sharedConfig.interiors[interior].logout
        },
        {
            type = 'clothing',
            coords = sharedConfig.interiors[interior].clothing
        },
        {
            type = 'exit',
            coords = sharedConfig.interiors[interior].exit
        }
    }
    local stashData = {
        {
            coords = sharedConfig.interiors[interior].stash,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC')
    local apartmentNumber = result?.id or 0

    ::again::

    apartmentNumber += 1
    local numberExists = MySQL.single.await('SELECT * FROM properties WHERE property_name = ?', {string.format('%s %s', sharedConfig.apartmentOptions[apartmentIndex].label, apartmentNumber)})
    if numberExists then goto again end

    local id = MySQL.insert.await('INSERT INTO `properties` (`coords`, `property_name`, `owner`, `interior`, `interact_options`, `stash_options`) VALUES (?, ?, ?, ?, ?, ?)', {
        json.encode(sharedConfig.apartmentOptions[apartmentIndex].enter),
        string.format('%s %s', sharedConfig.apartmentOptions[apartmentIndex].label, apartmentNumber),
        player.PlayerData.citizenid,
        interior,
        json.encode(interactData),
        json.encode(stashData),
    })

    logger.log({
        source = playerSource,
        event = 'qbx_properties:server:apartmentSelect',
        message = locale('logs.apartment_selected', player.PlayerData.citizenid, sharedConfig.apartmentOptions[apartmentIndex].label, apartmentNumber),
        webhook = config.discordWebhook
    })

    TriggerClientEvent('qbx_properties:client:addProperty', -1, sharedConfig.apartmentOptions[apartmentIndex].enter)
    EnterProperty(playerSource, id, true)
    Wait(200)
    TriggerClientEvent('qb-clothes:client:CreateFirstCharacter', playerSource)
end)

RegisterNetEvent('qbx_properties:server:rentApartmentForNewPlayer', function(apartmentIndex)
    local playerSource = source 
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not sharedConfig.apartmentOptions[apartmentIndex] then return end
    
    local apartment = sharedConfig.apartmentOptions[apartmentIndex]
    if not apartment.rentable or not sharedConfig.rentalConfig.enabled then return end

    local existingRental = MySQL.single.await('SELECT * FROM properties WHERE owner = ? AND rent_interval IS NOT NULL', {player.PlayerData.citizenid})
    if existingRental then
        exports.qbx_core:Notify(playerSource, locale('notify.rental_already_exists'), 'error')
        return
    end

    if player.PlayerData.money.bank < apartment.rentPrice then
        exports.qbx_core:Notify(playerSource, string.format(locale('notify.insufficient_funds_rental'), apartment.rentPrice), 'error')
        return
    end

    local interior = apartment.interior
    local interactData = {
        {
            type = 'logout',
            coords = sharedConfig.interiors[interior].logout
        },
        {
            type = 'clothing',
            coords = sharedConfig.interiors[interior].clothing
        },
        {
            type = 'exit',
            coords = sharedConfig.interiors[interior].exit
        }
    }
    local stashData = {
        {
            coords = sharedConfig.interiors[interior].stash,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC')
    local apartmentNumber = result?.id or 0

    ::again::

    apartmentNumber += 1
    local numberExists = MySQL.single.await('SELECT * FROM properties WHERE property_name = ?', {string.format('%s %s', apartment.label, apartmentNumber)})
    if numberExists then goto again end

    if not player.Functions.RemoveMoney('bank', apartment.rentPrice, string.format('First rent payment for %s', apartment.label)) then
        exports.qbx_core:Notify(playerSource, locale('notify.rental_payment_failed'), 'error')
        return
    end

    local id = MySQL.insert.await('INSERT INTO `properties` (`coords`, `property_name`, `owner`, `interior`, `interact_options`, `stash_options`, `price`, `rent_interval`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        json.encode(apartment.enter),
        string.format('%s %s', apartment.label, apartmentNumber),
        player.PlayerData.citizenid,
        interior,
        json.encode(interactData),
        json.encode(stashData),
        apartment.rentPrice,
        apartment.rentInterval,
    })

    startRentThread(id)

    logger.log({
        source = playerSource,
        event = 'qbx_properties:server:rentApartmentForNewPlayer',
        message = string.format(locale('logs.new_player_rental'), player.PlayerData.citizenid, apartment.label, apartmentNumber, apartment.rentPrice),
        webhook = config.discordWebhook
    })

    exports.qbx_core:Notify(playerSource, string.format(locale('notify.rental_success'), apartment.label, apartmentNumber, apartment.rentPrice), 'success')
    TriggerClientEvent('qbx_properties:client:addProperty', -1, apartment.enter)
    EnterProperty(playerSource, id, true)
    Wait(200)
    TriggerClientEvent('qb-clothes:client:CreateFirstCharacter', playerSource)
end)

local startingApartment = require '@qbx_core.config.client'.characters.startingApartment

if not startingApartment then return end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local playerSource = source 
    local player = exports.qbx_core:GetPlayer(playerSource)
    local hasApartment = MySQL.single.await('SELECT * FROM properties WHERE owner = ?', {player.PlayerData.citizenid})
    if not hasApartment then
        TriggerClientEvent('apartments:client:setupSpawnUI', playerSource)
    end
end)

lib.addCommand('createrental', {
    help = 'Create a rental property for a player (Admin only)',
    params = {
        {
            name = 'player',
            type = 'number',
            help = 'Player ID',
            optional = false
        },
        {
            name = 'apartment',
            type = 'number',
            help = 'Apartment index (1-6)',
            optional = false
        }
    },
    restricted = 'admin'
}, function(source, args)
    local playerSource = args.player
    local apartmentIndex = args.apartment
    
    if not playerSource or not apartmentIndex then
        exports.qbx_core:Notify(source, 'Usage: /createrental [player_id] [apartment_index]', 'error')
        return
    end
    
    if apartmentIndex < 1 or apartmentIndex > #sharedConfig.apartmentOptions then
        exports.qbx_core:Notify(source, 'Invalid apartment index. Use 1-6.', 'error')
        return
    end
    
    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then
        exports.qbx_core:Notify(source, 'Player not found.', 'error')
        return
    end
    
    local apartment = sharedConfig.apartmentOptions[apartmentIndex]
    if not apartment.rentable then
        exports.qbx_core:Notify(source, 'This apartment is not rentable.', 'error')
        return
    end
    
    local hasProperty = MySQL.single.await('SELECT * FROM properties WHERE owner = ?', {player.PlayerData.citizenid})
    if hasProperty then
        exports.qbx_core:Notify(source, 'Player already has a property.', 'error')
        return
    end
    
    if player.PlayerData.money.bank < apartment.rentPrice then
        exports.qbx_core:Notify(source, string.format('Player needs $%s in bank account.', apartment.rentPrice), 'error')
        return
    end
    
    local interior = apartment.interior
    local interactData = {
        {
            type = 'logout',
            coords = sharedConfig.interiors[interior].logout
        },
        {
            type = 'clothing',
            coords = sharedConfig.interiors[interior].clothing
        },
        {
            type = 'exit',
            coords = sharedConfig.interiors[interior].exit
        }
    }
    local stashData = {
        {
            coords = sharedConfig.interiors[interior].stash,
            slots = config.apartmentStash.slots,
            maxWeight = config.apartmentStash.maxWeight,
        }
    }

    local result = MySQL.single.await('SELECT id FROM properties ORDER BY id DESC')
    local apartmentNumber = result?.id or 0

    ::again::

    apartmentNumber += 1
    local numberExists = MySQL.single.await('SELECT * FROM properties WHERE property_name = ?', {string.format('%s %s', apartment.label, apartmentNumber)})
    if numberExists then goto again end

    if not player.Functions.RemoveMoney('bank', apartment.rentPrice, string.format('First rent payment for %s', apartment.label)) then
        exports.qbx_core:Notify(source, 'Failed to process rent payment.', 'error')
        return
    end

    local id = MySQL.insert.await('INSERT INTO `properties` (`coords`, `property_name`, `owner`, `interior`, `interact_options`, `stash_options`, `price`, `rent_interval`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        json.encode(apartment.enter),
        string.format('%s %s', apartment.label, apartmentNumber),
        player.PlayerData.citizenid,
        interior,
        json.encode(interactData),
        json.encode(stashData),
        apartment.rentPrice,
        apartment.rentInterval,
    })

    startRentThread(id)

    exports.qbx_core:Notify(source, string.format('Created rental property %s %s for player %s', apartment.label, apartmentNumber, player.PlayerData.name), 'success')
    exports.qbx_core:Notify(playerSource, string.format('Admin created rental property %s %s for you. Rent: $%s/week', apartment.label, apartmentNumber, apartment.rentPrice), 'success')
    
    logger.log({
        source = source,
        event = 'qbx_properties:admin:createRental',
        message = string.format('Admin created rental property %s %s for player %s', apartment.label, apartmentNumber, player.PlayerData.citizenid),
        webhook = config.discordWebhook
    })
end)