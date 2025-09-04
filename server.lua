---@diagnostic disable: unused-function, inject-field
RegisterNetEvent(RESOURCE .. ':server:backupSound', function(coords)
    TriggerClientEvent('bcso_dispatch_addon:client:backupSound', -1, coords)
end)

function GetJobPlayersCount(jobName)
    local xPlayers = ESX.GetExtendedPlayers('job', jobName)
    return #xPlayers
end

---@diagnostic disable: undefined-field
lib.callback.register(RESOURCE .. ':server:jobPlayersCount', function(_, jobName)
    return GetJobPlayersCount(jobName)
end)

lib.callback.register(RESOURCE .. ':server:nearbyOfficers', function(_, jobName, nearbyPlayers)
    local result = {}
    local xPlayers = ESX.GetExtendedPlayers('job', jobName)
    for _, xPlayer in pairs(xPlayers) do
        if table.contains(nearbyPlayers, xPlayer.source) then
            table.insert(result, xPlayer.getName())
        end
    end
    return result
end)

local reports = {}
local function createReportForPlayer(xPlayer)
    local identifier = xPlayer.getIdentifier()
    if not reports[identifier] then
        local job = xPlayer.getJob()
        reports[identifier] = {
            name = xPlayer.name,
            job = job.name,
            report = {}
        }
    end
end

lib.callback.register(RESOURCE .. ':server:getReport', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    return reports[xPlayer.getIdentifier()]?.report or {}
end)

RegisterNetEvent(RESOURCE .. ':server:addReport', function(report, currentTime)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    createReportForPlayer(xPlayer)
    if currentTime and type(currentTime) == 'string' then
        local time = os.date(currentTime)
        report = ('[%s] %s'):format(time, report)
    end

    local identifier = xPlayer.getIdentifier()
    table.insert(reports[identifier].report, report)
end)

RegisterNetEvent(RESOURCE .. ':server:setReport', function(report)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local identifier = xPlayer.getIdentifier()
    reports[identifier] = nil
    createReportForPlayer(xPlayer)

    if not report or report == '' then return end
    table.insert(reports[identifier].report, report)
end)

RegisterNetEvent(RESOURCE .. ':server:clearReport', function()
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    local identifier = xPlayer.getIdentifier()
    reports[identifier] = nil
end)

local function validateImage(url)
    local result = promise:new()
    if not url:match("%.jpg$") and not url:match("%.jpeg$") and not url:match("%.png$") and not url:match("%.gif$") and not url:match("%.bmp$") then
        result:resolve(false)
    end

    PerformHttpRequest(url, function(statusCode, _, headers)
        if statusCode ~= 200 then
            result:resolve(false)
            collectgarbage("collect")
            return
        end

        local contentType = headers["content-type"]
        if contentType and contentType:find("image/") then
            result:resolve(true)
        else
            result:resolve(false)
        end
        collectgarbage("collect")
    end)

    return Citizen.Await(result)
end

---@param webhooks string | nil
---@param params table<string, any>
local function sendWebhook(webhooks, params)
    if type(webhooks) == 'table' then
        for index, url in ipairs(webhooks) do
            webhooks[index] = Config.Webhooks[url] or nil
        end
    elseif type(webhooks) == 'string' then
        webhooks = Config.Webhooks[webhooks] or nil
    else
        webhooks = nil
    end
    if not webhooks or not params then return end

    local payload = {
        username = params.username or nil,
        avatar_url = params.avatar_url or nil,
        tts = params.tts or false,
        allowed_mentions = {
            parse = { 'roles', 'users', 'everyone' }
        },
        content = nil,
        embeds = {}
    }
    if payload.username and #payload.username > 80 then payload.username = payload.username:sub(1, 77) .. '...' end

    local content = ''
    if params.mentions then
        local mentions = params.mentions
        if mentions.roles and #mentions.roles > 0 then
            content = content .. '||'
            for _, role in ipairs(mentions.roles) do
                if type(role) == 'string' then
                    content = content .. ('@%s'):format(role)
                elseif type(role) == 'number' then
                    content = content .. ('<@&%s>'):format(role)
                end
            end
            content = content .. '||\n'
        end

        if mentions.users and #mentions.users > 0 then
            content = content .. '||'
            for _, user in ipairs(mentions.users) do
                if type(user) == 'number' then
                    content = content .. ('<@%s>'):format(user)
                end
            end
            content = content .. '||\n'
        end
    end
    if #content > 2000 then content = content:sub(1, 1997) .. '...' end
    payload.content = content .. (params.content or '')

    if params.embeds and #params.embeds > 0 then
        for i = 1, 10, 1 do
            local embed = params.embeds[i]
            if embed then
                local object = {
                    color = embed.color or nil,
                    title = embed.title or nil,
                    description = embed.description or nil,
                    fields = embed.fields or {},
                    image = nil,
                    footer = embed.footer or nil,
                    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', os.time()),
                }
                if embed.image and type(embed.image) == 'string' and embed.image ~= "n/a" then
                    if validateImage(embed.image) then
                        object.image = {
                            url = embed.image
                        }
                    end
                end

                if object.title and #object.title > 256 then object.title = object.title:sub(1, 253) .. '...' end
                if object.description and #object.description > 4096 then
                    object.description = object.description:sub(1,
                        4093) .. '...'
                end

                while #object.fields > 25 do table.remove(object.fields) end
                for _, field in ipairs(object.fields) do
                    if field.name and #field.name > 256 then field.name = field.name:sub(1, 253) .. '...' end
                    if field.value and #field.value > 1024 then field.value = field.value:sub(1, 1021) .. '...' end
                end

                if object.footer and object.footer.text and #object.footer.text > 2048 then
                    object.footer.text = object
                        .footer.text:sub(1, 2045) .. '...'
                end

                table.insert(payload.embeds, object)
            end
        end
    end

    if type(webhooks) == 'table' then
        for _, webhook in pairs(webhooks) do
            if webhook ~= nil then
                Citizen.Wait(250)
                PerformHttpRequest(webhook, function(_, _, _, _) end, 'POST', json.encode(payload),
                    { ['Content-Type'] = 'application/json' })
            end
        end
    else
        PerformHttpRequest(webhooks, function(_, _, _, _) end, 'POST', json.encode(payload),
            { ['Content-Type'] = 'application/json' })
    end
end

RegisterNetEvent(RESOURCE .. ':server:sendWebhook', function(webhook, params)
    sendWebhook(webhook, params)
end)

AddEventHandler('playerDropped', function()
    local _source = source
    local xPlayer = ESX.GetPlayerFromId(_source)
    if not xPlayer then return end

    local identifier = xPlayer.getIdentifier()
    if reports[identifier] then
        local rep = reports[identifier]
        local dc = Config.InternalMenus?[rep.job]?.discord or nil
        if dc and dc.webhook and type(dc.webhook) == 'string' and dc.send_dropped_players_report and #rep.report > 0 then
            sendWebhook(dc.webhook, {
                embeds = {
                    {
                        color = 0x9C5C0E,
                        title = rep.name,
                        description = table.concat(rep.report, '\n')
                    }
                }
            })
        end
    end
end)

-- Dispatch connection
local translations = {
    ['street'] = 'Lokalizacja',
    ['heading'] = 'Kierunek',
    ['gender'] = 'Płeć',
    ['name'] = 'Imię i nazwisko',
    ['number'] = 'Numer telefonu',
    ['vehicle'] = 'Model',
    ['color'] = 'Kolor pojazdu',
    ['plate'] = 'Indeks pojazdu',
    ['class'] = 'Klasa pojazdu',
    ['doors'] = 'Drzwi pojazdu',
    ['weapon'] = 'Klasa broni',
    ['automaticGunfire'] = 'Ogień automatyczny'
}

AddEventHandler(RESOURCE .. ':server:centralNotify', function(data)
    if data.resource and data.resource == RESOURCE then return end

    local embed = {
        color = data.priority == 1 and 0xFF0000 or 0x0080FF,
        title = ('ID: #%s | %s: %s'):format(data.id, data.code, data.message),
        description = ('**Informacje:** %s'):format(data.information or 'n/a'),
        fields = {}
    }

    local loc = ""
    for _, fieldName in ipairs({ 'street', 'heading' }) do
        if data[fieldName] then
            if loc == "" then
                loc = ("__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            else
                loc = loc .. ("\n__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            end
        end
    end
    if loc ~= "" then
        table.insert(embed.fields, {
            name = 'Miejsce zgłoszenia',
            value = loc,
            inline = false
        })
    end

    local personal = ""
    for _, fieldName in ipairs({ 'gender', 'name', 'number' }) do
        if data[fieldName] then
            if personal == "" then
                personal = ("__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            else
                personal = personal .. ("\n__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            end
        end
    end
    if personal ~= "" then
        table.insert(embed.fields, {
            name = 'Dane osobowe',
            value = personal,
            inline = true
        })
    end

    local vehicle = ""
    for _, fieldName in ipairs({ 'vehicle', 'color', 'plate', 'class', 'doors' }) do
        if data[fieldName] then
            if fieldName == 'plate' then
                data[fieldName] = data[fieldName]:gsub(' ', '')
            end
            if vehicle == "" then
                vehicle = ("__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            else
                vehicle = vehicle .. ("\n__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            end
        end
    end
    if vehicle ~= "" then
        table.insert(embed.fields, {
            name = 'Dane pojazdu',
            value = vehicle,
            inline = true
        })
    end

    local weapon = ""
    for _, fieldName in ipairs({ 'weapon', 'automaticGunfire' }) do
        if data[fieldName] then
            if weapon == "" then
                weapon = ("__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            else
                weapon = weapon .. ("\n__%s__: `%s`"):format(translations[fieldName] or fieldName, data[fieldName])
            end
        end
    end
    if weapon ~= "" then
        table.insert(embed.fields, {
            name = 'Broń palna',
            value = weapon,
            inline = true
        })
    end

    for areaId, zone in pairs(AREAS) do
        if zone:contains(data.coords) then
            local jobs = Config.Areas[areaId].jobs
            for _, job in ipairs(jobs) do
                local dc = Config.InternalMenus?[job]?.discord or nil
                if table.contains(data.jobs, job) and dc and dc.central_webhook and type(dc.central_webhook) == 'string' and dc.send_all_dispatch_alerts then
                    sendWebhook(dc.central_webhook, {
                        embeds = { embed }
                    })
                end
            end
        end
    end
end)
