local Phonographs = {}

RegisterNetEvent('phonograph:sync')
RegisterNetEvent('phonograph:start')
RegisterNetEvent('phonograph:play')
RegisterNetEvent('phonograph:stop')
RegisterNetEvent('phonograph:showControls')

local entityEnumerator = {
	__gc = function(enum)
		if enum.destructor and enum.handle then
			enum.destructor(enum.handle)
		end
		enum.destructor = nil
		enum.handle = nil
	end
}

function EnumerateEntities(firstFunc, nextFunc, endFunc)
	return coroutine.wrap(function()
		local iter, id = firstFunc()

		if not id or id == 0 then
			endFunc(iter)
			return
		end

		local enum = {handle = iter, destructor = endFunc}
		setmetatable(enum, entityEnumerator)

		local next = true
		repeat
			coroutine.yield(id)
			next, id = nextFunc(iter)
		until not next

		enum.destructor, enum.handle = nil, nil
		endFunc(iter)
	end)
end

function EnumerateObjects()
	return EnumerateEntities(FindFirstObject, FindNextObject, EndFindObject)
end

function IsPhonograph(object)
	return GetEntityModel(object) == GetHashKey('p_phonograph01x')
end

function GetClosestPhonograph()
	local pos = GetEntityCoords(PlayerPedId())

	local closestPhonograph = nil
	local closestDistance = nil

	for object in EnumerateObjects() do
		if IsPhonograph(object) then
			local phonoPos = GetEntityCoords(object)
			local distance = GetDistanceBetweenCoords(pos.x, pos.y, pos.z, phonoPos.x, phonoPos.y, phonoPos.z, true)

			if distance <= Config.MaxDistance and (not closestDistance or distance < closestDistance) then
				closestPhonograph = object
				closestDistance = distance
			end
		end
	end
	
	return ObjToNet(closestPhonograph)
end

function GetRandomPreset()
	local presets = {}

	for preset, info in pairs(Config.Presets) do
		table.insert(presets, preset)
	end

	return presets[math.random(#presets)]
end

function StartPhonograph(handle, url, volume, offset, filter)
	if url == 'random' then
		url = GetRandomPreset()
	end

	if not volume then
		volume = 100
	elseif volume > 100 then
		volume = 100
	elseif volume < 0 then
		volume = 0
	end

	if not offset then
		offset = '0'
	end

	TriggerServerEvent('phonograph:start', handle, url, volume, offset, filter)
end

function StartClosestPhonograph(url, volume, offset, filter)
	StartPhonograph(GetClosestPhonograph(), url, volume, offset, filter)
end

function PausePhonograph(handle)
	SendNUIMessage({
		type = 'pause',
		handle = handle
	})
end

function PauseClosestPhonograph()
	PausePhonograph(GetClosestPhonograph())
end

function StopPhonograph(handle)
	TriggerServerEvent('phonograph:stop', handle)
end

function StopClosestPhonograph()
	StopPhonograph(GetClosestPhonograph())
end

function StatusPhonograph(handle)
	local phonograph = Phonographs[handle]

	SendNUIMessage({
		type = 'status',
		handle = handle,
		startTime = phonograph and phonograph.startTime
	})
end

function StatusClosestPhonograph()
	StatusPhonograph(GetClosestPhonograph())
end

function GetActiveCamCoord()
	local cam = GetRenderingCam()
	return cam == -1 and GetGameplayCamCoord() or GetCamCoord(cam)
end

function SortByDistance(a, b)
	return a.distance < b.distance
end

function IsInSameRoom(entity1, entity2)
	local interior1 = GetInteriorFromEntity(entity2)
	local interior2 = GetInteriorFromEntity(entity2)

	if interior1 ~= interior2 then
		return false
	end

	local roomHash1 = GetRoomKeyFromEntity(entity1)
	local roomHash2 = GetRoomKeyFromEntity(entity2)

	if roomHash1 ~= roomHash2 then
		return false
	end

	return true
end

function ListPresets()
	local presets = {}

	for preset, info in pairs(Config.Presets) do
		table.insert(presets, preset)
	end

	if #presets == 0 then
		TriggerEvent('chat:addMessage', {
			color = {255, 255, 128},
			args = {'No presets available'}
		})
	else
		table.sort(presets)

		for _, preset in ipairs(presets) do
			TriggerEvent('chat:addMessage', {
				args = {preset, Config.Presets[preset].title}
			})
		end
	end
end

function UpdateUi(fullControls, anyUrl)
	local pos = GetEntityCoords(PlayerPedId())

	local activePhonographs = {}

	for handle, info in pairs(Phonographs) do
		if NetworkDoesNetworkIdExist(handle) then
			local object = NetToObj(handle)
			local phonoPos = GetEntityCoords(object)
			local distance = GetDistanceBetweenCoords(pos.x, pos.y, pos.z, phonoPos.x, phonoPos.y, phonoPos.z, true)

			if fullControls or distance <= Config.MaxDistance then
				table.insert(activePhonographs, {
					handle = handle,
					info = info,
					distance = distance
				})
			end
		else
			if fullControls or distance <= Config.MaxDistance then
				table.insert(activePhonographs, {
					handle = handle,
					info = info,
					distance = 0
				})
			end
		end
	end

	table.sort(activePhonographs, SortByDistance)

	local inactivePhonographs = {}

	for object in EnumerateObjects() do
		if NetworkGetEntityIsNetworked(object) then
			local handle = ObjToNet(object)

			if IsPhonograph(object) and not Phonographs[handle] then
				local phonoPos = GetEntityCoords(object)
				local distance = GetDistanceBetweenCoords(pos.x, pos.y, pos.z, phonoPos.x, phonoPos.y, phonoPos.z, true)

				if fullControls or distance <= Config.MaxDistance then
					table.insert(inactivePhonographs, {
						handle = handle,
						distance = distance
					})
				end
			end
		end
	end

	table.sort(inactivePhonographs, SortByDistance)

	SendNUIMessage({
		type = 'updateUi',
		activePhonographs = json.encode(activePhonographs),
		inactivePhonographs = json.encode(inactivePhonographs),
		presets = json.encode(Config.Presets),
		anyUrl = anyUrl
	})
end

RegisterCommand('phono', function(source, args, raw)
	if #args > 0 then
		local command = args[1]

		if command == 'play' then
			if #args > 1 then
				local url = args[2]
				local volume = tonumber(args[3])
				local offset = args[4]
				local filter = args[5] == '1'

				StartClosestPhonograph(url, volume, offset, filter)
			else
				PauseClosestPhonograph()
			end
		elseif command == 'pause' then
			PauseClosestPhonograph()
		elseif command == 'stop' then
			StopClosestPhonograph()
		elseif command == 'status' then
			StatusClosestPhonograph()
		elseif command == 'songs' then
			ListPresets()
		end
	else
		TriggerServerEvent('phonograph:showControls')
	end

end)

RegisterNUICallback('init', function(data, cb)
	TriggerServerEvent('phonograph:init', data.handle, data.url, data.title, data.volume, data.startTime)
	cb({})
end)

RegisterNUICallback('initError', function(data, cb)
	print('Error loading ' .. data.url)
	cb({})
end)

RegisterNUICallback('play', function(data, cb)
	StartPhonograph(data.handle, data.url, data.volume, data.offset, data.filter)
	cb({})
end)

RegisterNUICallback('pause', function(data, cb)
	TriggerServerEvent('phonograph:pause', data.handle, data.paused)
	cb({})
end)

RegisterNUICallback('stop', function(data, cb)
	StopPhonograph(data.handle)
	cb({})
end)

RegisterNUICallback('status', function(data, cb)
	local phonograph = Phonographs[data.handle]

	if phonograph then
		TriggerEvent('chat:addMessage', {
			args = {string.format('[%x] %s 🔊%d 🕒%s/%s %s', data.handle, phonograph.title, phonograph.volume, data.currentTime, data.duration, phonograph.paused and '⏸' or '▶️')}
		})
	else
		TriggerEvent('chat:addMessage', {
			args = {string.format('[%x] Not playing', data.handle)}
		})
	end

	cb({})
end)

RegisterNUICallback('closeUi', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

AddEventHandler('phonograph:sync', function(phonographs, fullControls, anyUrl)
	Phonographs = phonographs
	UpdateUi(fullControls, anyUrl)
end)

AddEventHandler('phonograph:start', function(handle, url, title, volume, offset, filter)
	SendNUIMessage({
		type = 'init',
		handle = handle,
		url = url,
		title = title,
		volume = volume,
		offset = offset,
		filter = filter
	})
end)

AddEventHandler('phonograph:play', function(handle)
	SendNUIMessage({
		type = 'play',
		handle = handle
	})
end)

AddEventHandler('phonograph:stop', function(handle)
	SendNUIMessage({
		type = 'stop',
		handle = handle
	})
end)

AddEventHandler('phonograph:showControls', function()
	SendNUIMessage({
		type = 'showUi'
	})
	SetNuiFocus(true, true)
end)

CreateThread(function()
	TriggerEvent('chat:addSuggestion', '/phono', 'Interact with phonographs. No arguments will open the phonograph control panel.', {
		{name = 'command', help = 'play|pause|stop|status|songs'},
		{name = 'url', help = 'URL or preset name of music to play. Use "random" to play a random preset.'},
		{name = 'volume', help = 'Volume to play the music at (0-100).'},
		{name = 'time', help = 'Time in seconds to start playing at.'}
	})
end)

CreateThread(function()
	while true do
		Wait(0)

		local pos = GetActiveCamCoord()

		for handle, info in pairs(Phonographs) do
			if NetworkDoesNetworkIdExist(handle) then
				local object = NetToObj(handle)
				local phonoPos = GetEntityCoords(object)
				local distance = GetDistanceBetweenCoords(pos.x, pos.y, pos.z, phonoPos.x, phonoPos.y, phonoPos.z, true)

				SendNUIMessage({
					type = 'update',
					handle = handle,
					url = info.url,
					volume = info.volume,
					startTime = info.startTime,
					paused = info.paused,
					distance = distance,
					sameRoom = IsInSameRoom(PlayerPedId(), object)
				})
			else
				SendNUIMessage({
					type = 'update',
					handle = handle,
					url = info.url,
					volume = 0,
					startTime = info.startTime,
					paused = info.paused,
					distance = 0,
					sameRoom = false
				})
			end
		end
	end
end)
