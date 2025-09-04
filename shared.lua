RESOURCE = GetCurrentResourceName()
DEBUG = Config.Debug

---@param func function
local function functionName(func)
    local info = debug.getinfo(func, 'n')
    return info and info.name or 'unknown function'
end

local prefixes = {
    [1] = '[^2INFO^7]',
    [2] = '[^9DEBUG^7]',
    [3] = '[^6WARNING^7]',
    [4] = '[^8ERROR^7]'
}

---@param level number
---@param ... any
function consoleLog(level, ...)
    local args = {...}
    local formattedArgs = {}
    if type(level) ~= 'number' or level == 2 and not DEBUG then return end
    table.insert(formattedArgs, prefixes[level])
    for i = 1, #args do
        local arg = args[i]
        local argType = type(arg)
        local formattedArg
        if argType == 'table' then
            formattedArg = json.encode(arg)
        elseif argType == 'function' then
            formattedArg = functionName(arg)
        elseif argType == 'nil' then
            formattedArg = 'NULL'
        else formattedArg = tostring(arg) end
        table.insert(formattedArgs, formattedArg)
    end
    print(table.concat(formattedArgs, ' '))
end

table.contains = function(t, object)
    for _, v in pairs(t) do
        if v == object then
            return true
        end
    end
    return false
end

table.indexOf = function(t, object)
    for i, v in pairs(t) do
        if v == object then
            return i
        end
    end
    return nil
end

table.length = function(t)
    local length = 0
    for _ in pairs(t) do length = length + 1 end
    return length
end

AREAS = {}
Citizen.CreateThread(function()
    for areaId, data in pairs(Config.Areas) do
        local zone = lib.zones.poly({
            points = data.points,
            thickness = 1500.0,
            debug = DEBUG or false
        })
        AREAS[areaId] = zone
    end
end)

local function jurisdiction(coords, options, final)
    if not final then consoleLog(2, '-- NEW JURISDICTION CHECK --') end
    if not options then options = {} end
    local jobs_table, additional_jobs, currentArea_jobs, jobs_count, inside_any_area = {}, options.additional_jobs or {}, options.currentArea_jobs or {}, 0, false
    if options.use_areas == nil then options.use_areas = true end
    consoleLog(2, ('Get jobs, using jurisdiction: %s, final check: %s'):format(options.use_areas, final))

    if options.jobs and type(options.jobs) == 'table' then
        consoleLog(2, ('Adding job list: %s'):format(json.encode(options.jobs)))
        for _, jobName in ipairs(options.jobs) do
            if not table.contains(jobs_table, jobName) then
                table.insert(jobs_table, jobName)
            end
        end
    else
        if options.inside_job and options.job_name then
            consoleLog(2, ('Only inside job: %s'):format(options.job_name))
            return { options.job_name }
        else
            options.playersCount = options.playersCount or {}
            for areaId, zone in pairs(AREAS) do
                local data = Config.Areas[areaId]
                if (type(options.type) == 'table' and table.contains(options.type, data.type) or options.type == data.type) then
                    if (options.use_areas and zone:contains(coords)) or not options.use_areas then
                        inside_any_area = true
                        consoleLog(2, ('Checking zone: %s'):format(areaId))
                        for _, jobName in ipairs(data.jobs) do
                            if not table.contains(jobs_table, jobName) and not options.playersCount[jobName] then
                                local playersCount = GetJobPlayersCount(jobName)
                                consoleLog(2, ('[%s]: %s'):format(jobName, playersCount))
                                table.insert(additional_jobs, jobName)
                                table.insert(currentArea_jobs, jobName)
                                jobs_count = jobs_count + playersCount
                                if playersCount > 0 then
                                    table.insert(jobs_table, jobName)
                                else options.playersCount[jobName] = true end
                            end
                        end
                        for _, jobName in ipairs(data.additional_jobs) do
                            if not table.contains(additional_jobs, jobName) then
                                local playersCount = GetJobPlayersCount(jobName)
                                consoleLog(2, ('Additional [%s]: %s'):format(jobName, playersCount))
                                table.insert(additional_jobs, jobName)
                            end
                        end
                    end
                end
            end
        end

        if not final and inside_any_area and (#jobs_table == 0 or jobs_count < 2) then
            options.use_areas = false
            options.additional_jobs = additional_jobs
            options.currentArea_jobs = currentArea_jobs
            return jurisdiction(coords, options, true)
        end
    end

    if additional_jobs and #additional_jobs > 0 then
        for _, jobName in ipairs(additional_jobs) do
            if not table.contains(jobs_table, jobName) then
                table.insert(jobs_table, jobName)
            end
        end
    end

    if options.caller_job and options.job_name then
        consoleLog(2, ('Adding caller job: %s'):format(options.job_name))
        if not table.contains(jobs_table, options.job_name) then
            table.insert(jobs_table, options.job_name)
        end
    end

    consoleLog(2, ('Returning job list: %s, players in current area online jobs: %s (no additional): %s'):format(json.encode(jobs_table), json.encode(currentArea_jobs), jobs_count))
    return jobs_table, jobs_count
end
exports('Jurisdiction', jurisdiction)
