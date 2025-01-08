RegisterNetEvent(RESOURCE .. ':client:backupSound', function(coords)
    PlaySoundFromCoord(-1, 'Click', coords.x, coords.y, coords.z, 'DLC_HEIST_HACKING_SNAKE_SOUNDS', false, 2.5, false)
end)

---@param jobName string
---@return number
function GetJobPlayersCount(jobName)
    return lib.callback.await(RESOURCE .. ':server:jobPlayersCount', false, jobName)
end

---@param message string
---@param indexed_values table<number, string>
---@param named_values table<string, string>
---@return string
local function placeholders(message, indexed_values, named_values)
    message = message:gsub("{(%d+)}", function(n)
        n = tonumber(n)
        return (indexed_values[n] and indexed_values[n] ~= "") and tostring(indexed_values[n]) or "n/a"
    end)

    for key, val in pairs(named_values) do
        message = message:gsub('{' .. key .. '}', val)
    end

    return message
end

---@param coords vector3
---@return string
local function getPlace(coords)
    local streetName, crossingRoad = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local zoneName = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    local place = GetStreetNameFromHashKey(streetName) .. (crossingRoad ~= 0 and " | "..GetStreetNameFromHashKey(crossingRoad) .. ", " or ", ") .. zoneName
    return place
end

---@return boolean
local function isDead()
    if IsEntityDead(cache.ped) then
        return true
    end
    return false
end

---@param vehicles table
---@param zones table
---@return boolean
local function isInVehicleOrZone(vehicles, zones)
    return true
end

local delay = false
local function internalMenu(list)
    local main = false
    if delay then return end

    local playerData = ESX.GetPlayerData()
    if not playerData then return end

    local job = playerData.job
    if not job then return end

    local menu = Config.InternalMenus[job.name]
    if not menu or not menu.enabled then return end
    if not list then
        list = menu.options
        main = true
    end

    local options = {}
    for _, item in ipairs(list) do
        local ctx = item.context
        local option = {
            title = ctx.title or 'Unknown...',
            description = ctx.description or 'Unknown...',
            icon = ctx.icon or 'question',
            iconColor = ctx.iconColor or nil,
            iconAnimation = ctx.iconAnimation or nil,
            arrow = item.is_category,
            disabled = (ctx.minimal_grade > job.grade) or (ctx.disabled_while_dead and isDead()) or (ctx.vehicle_and_zone_check and not isInVehicleOrZone(menu.vehicle_hashes, menu.station_zones)),
            onSelect = function()
                if item.is_category and item.options and #item.options > 0 then
                    return internalMenu(item.options)
                end

                local nearbyPlayers = lib.getNearbyPlayers(cache.coords, 25.0, false)
                local result = {}
                for _, player in ipairs(nearbyPlayers) do
                    local serverId = GetPlayerServerId(player.id)
                    table.insert(result, serverId)
                end
                nearbyPlayers = result
                local nearbyOfficers = lib.callback.await(RESOURCE .. ':server:nearbyOfficers', false, job.name, nearbyPlayers)

                TriggerServerEvent(RESOURCE .. ':server:backupSound', cache.coords)

                local act = item.actions
                local variables = nil
                if act.variables and #act.variables > 0 then
                    variables = lib.inputDialog(ctx.title, act.variables)
                    if not variables then goto skip end
                end

                if act.report then
                    local rep = act.report
                    if rep.method and type(rep.method) == 'string' then
                        if rep.method == 'add' and rep.message then
                            local report = ('%s'):format(rep.message)
                            report = placeholders(report, variables or {}, {
                                ['jobName'] = job.label,
                                ['gradeName'] = job.grade_label,
                                ['name'] = ('%s %s'):format(playerData.firstName, playerData.lastName),
                                ['place'] = getPlace(cache.coords),
                                ['jobCount'] = ('%s'):format(GetJobPlayersCount(job.name)),
                                ['nearbyOfficers'] = #nearbyOfficers > 0 and table.concat(nearbyOfficers, ', ') or 'n/a'
                            })
                            consoleLog(2, ('Adding report: %s'):format(report))
                            TriggerServerEvent(RESOURCE .. ':server:addReport', report, rep.current_time or false)
                        elseif rep.method == 'copy' then
                            local report = lib.callback.await(RESOURCE .. ':server:getReport', false)
                            report = table.concat(report, '\n') or nil
                            consoleLog(2, ('Copy report to clipboard: %s'):format(report))
                            lib.setClipboard(report)
                        elseif rep.method == 'edit' then
                            local report = lib.callback.await(RESOURCE .. ':server:getReport', false)
                            local textarea = lib.inputDialog(ctx.title, {
                                { type = 'textarea', default = table.concat(report, '\n') or nil, min = 10, autosize = true }
                            }, { allowCancel = false })
                            consoleLog(2, ('Edited report to: %s'):format(textarea[1]))
                            TriggerServerEvent(RESOURCE .. ':server:setReport', textarea[1])
                        elseif rep.method == 'clear' then
                            consoleLog(2, 'Cleared report')
                            TriggerServerEvent(RESOURCE .. ':server:clearReport')
                        end
                    end
                end

                if act.dispatch then
                    delay = true
                    local dispatch = lib.table.deepclone(act.dispatch)
                    if dispatch.message then
                        dispatch.message = placeholders(dispatch.message, variables or {}, {
                            ['jobName'] = job.label,
                            ['gradeName'] = job.grade_label,
                            ['name'] = ('%s %s'):format(playerData.firstName, playerData.lastName),
                            ['place'] = getPlace(cache.coords),
                            ['jobCount'] = ('%s'):format(GetJobPlayersCount(job.name)),
                            ['nearbyOfficers'] = #nearbyOfficers > 0 and table.concat(nearbyOfficers, ', ') or 'n/a'
                        })
                    end

                    if dispatch.information then
                        dispatch.information = placeholders(dispatch.information, variables or {}, {
                            ['jobName'] = job.label,
                            ['gradeName'] = job.grade_label,
                            ['name'] = ('%s %s'):format(playerData.firstName, playerData.lastName),
                            ['place'] = getPlace(cache.coords),
                            ['jobCount'] = ('%s'):format(GetJobPlayersCount(job.name)),
                            ['nearbyOfficers'] = #nearbyOfficers > 0 and table.concat(nearbyOfficers, ', ') or 'n/a'
                        })
                    end

                    dispatch.job_name = job.name
                    dispatch.coords = cache.coords
                    dispatch.street = getPlace(cache.coords)
                    dispatch.name = ('%s %s'):format(playerData.firstName, playerData.lastName)

                    exports['ps-dispatch']:CustomAlert(dispatch)
                end

                if act.discord then
                    delay = true
                    local dc = lib.table.deepclone(act.discord)
                    if dc.webhook and (type(dc.webhook) == 'string' or type(dc.webhook) == 'table') and dc.params then
                        if dc.params.content then
                            dc.params.content = placeholders(dc.params.content, variables or {}, {
                                ['jobName'] = job.label,
                                ['gradeName'] = job.grade_label,
                                ['name'] = ('%s %s'):format(playerData.firstName, playerData.lastName),
                                ['place'] = getPlace(cache.coords),
                                ['jobCount'] = ('%s'):format(GetJobPlayersCount(job.name)),
                                ['nearbyOfficers'] = #nearbyOfficers > 0 and table.concat(nearbyOfficers, ', ') or 'n/a'
                            })
                        end

                        if dc.params.embeds and #dc.params.embeds > 0 then
                            for _, embed in ipairs(dc.params.embeds) do
                                if embed.description then
                                    embed.description = placeholders(embed.description, variables or {}, {
                                        ['jobName'] = job.label,
                                        ['gradeName'] = job.grade_label,
                                        ['name'] = ('%s %s'):format(playerData.firstName, playerData.lastName),
                                        ['place'] = getPlace(cache.coords),
                                        ['jobCount'] = ('%s'):format(GetJobPlayersCount(job.name)),
                                        ['nearbyOfficers'] = #nearbyOfficers > 0 and table.concat(nearbyOfficers, ', ') or 'n/a'
                                    })
                                end

                                if embed.fields and #embed.fields > 0 then
                                    for _, field in ipairs(embed.fields) do
                                        if field.value then
                                            field.value = placeholders(field.value, variables or {}, {
                                                ['jobName'] = job.label,
                                                ['gradeName'] = job.grade_label,
                                                ['name'] = ('%s %s'):format(playerData.firstName, playerData.lastName),
                                                ['place'] = getPlace(cache.coords),
                                                ['jobCount'] = ('%s'):format(GetJobPlayersCount(job.name)),
                                                ['nearbyOfficers'] = #nearbyOfficers > 0 and table.concat(nearbyOfficers, ', ') or 'n/a'
                                            })
                                        end
                                    end
                                end

                                if embed.image then
                                    embed.image = placeholders(embed.image, variables or {}, {})
                                    if embed.image == '' then embed.image = nil end
                                end
                            end
                        end
                        TriggerServerEvent(RESOURCE .. ':server:sendWebhook', dc.webhook, dc.params)
                    end
                end

                if act.runcode then
                    act.runcode(variables)
                end

                ::skip::
                if delay then Citizen.SetTimeout(menu.delay, function() delay = false end) end
            end
        }
        table.insert(options, option)
    end

    lib.registerContext({
        id = 'internal_job_menu',
        title = job.label,
        options = options,
        menu = not main and 'internal_job_menu' or nil,
        onBack = function ()
            return internalMenu()
        end
    })
    lib.showContext('internal_job_menu')
end
exports('openInternalJobMenu', internalMenu)

lib.addKeybind({
    name = 'internal_job_menu',
    description = 'Menu frakcyjne',
    defaultKey = 'SLASH',
    onPressed = function(_)
        internalMenu()
    end
})
