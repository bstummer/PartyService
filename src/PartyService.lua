--[[

Tutorial & Documentation: vaschex.github.io/PartyService
Forum: 

Version of this module: 0.3.0-beta

Created by Vaschex

PartyService © 2021 by Vaschex is licensed under CC BY-NC 4.0. 
https://creativecommons.org/licenses/by-nc/4.0/

]]

local module = {}
module.Settings = {
	DefaultRank = "Members",
	RanksAddedByDefault = {},
	TeleportDataValidTime = 30,
	PlayerLostTime = 10,
	PollingCooldown = 3,
	SplitUpGroups = true,
	QueueExpiration = 300
}

---------------------------------------------------------------------

local TeleportService = game:GetService("TeleportService")
local SortedMap = game:GetService("MemoryStoreService"):GetSortedMap("PartyService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

module.Parties = {}
module.Queues = {}

type player = Player | number

local function fastAssert(v:any, errorMsg:string):()
	if not v then error(errorMsg, 3) end
	--click the 3rd light blue line under the error message to get to your error
	--devforum.roblox.com/t/49455
end

local function containsDuplicate(t:{[number]:any}):(boolean, number?)
	local hash = {}
	for i, v in next, t do
		if hash[v] == nil then
			hash[v] = true
		else
			return true, i
		end
	end
	return false
end

local function touserid(plr:player):number
	if type(plr) == "number" then return plr end
	return plr.UserId
end

local function deepCopy(t)
	local copy = {}
	for k, v in next, t do
		if type(v) == "table" then
			v = deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

--nested table to array
local function flattenTable(t)
	local result = {}
	for _, v in next, t do
		if type(v) == "table" then
			for _, v in next, flattenTable(v) do
				table.insert(result, v)
			end
		else
			table.insert(result, v)
		end
	end
	return result
end

local function deepLoop(t:any, callback:(i:any,v:any,t:any)->(),
	iterator:any):() --still a parameter
	iterator = iterator or pairs
	for i, v in iterator(t) do
		if type(v) == "table" then
			callback(i, v, t) --allows 3rd variable
			deepLoop(v, callback, iterator)
		else
			callback(i, v, t)
		end
	end
end

--[[local function reconcileTable(target, template)
	for k, v in pairs(template) do
		if type(k) == "string" then
			if target[k] == nil then
				if type(v) == "table" then
					target[k] = deepCopy(v)
				else
					target[k] = v
				end
			elseif type(target[k]) == "table" and type(v) == "table" then
				reconcileTable(target[k], v)
			end
		end
	end
end]]

--adds features to pcall
local function safeCall(func:()->(...any), retryTimes:number?, cooldown:number?):(...any)
	retryTimes = retryTimes or 0
	local i = 0
	local success = false
	while success == false do
		i += 1
		local args = {pcall(func)}
		success = args[1]
		if success == false then
			warn(args[2])
			if i > retryTimes then error("Call was thrown after "..i.." attempts due to error") end
			task.wait(cooldown)
		else
			table.remove(args, 1)
			return unpack(args)
		end
	end
end

local function getDataSize(data):number
	if type(data) == "string" then return #data end
	return #HttpService:JSONEncode(data)
end

--credits to XAXA for this function: devforum.roblox.com/t/292323/15
local function getTableType(t):string
	local isArray = true
	local isDictionary = true
	for k in next, t do
		if typeof(k) == "number" and k%1 == 0 and k > 0 then
			isDictionary = false
		else
			isArray = false
		end
	end
	if isArray then
		return "Array"
	elseif isDictionary then
		return "Dictionary"
	else
		return "Mixed"
	end
end

local util = {} --functions for managing queues

function util.Sub(key:string, subtrahend:number):string
	return string.format("%.6i", key - subtrahend)
end

function util.Add(key:string, addend:number):string
	return string.format("%.6i", key + addend)
end

--[[
Returns a sorted array of the keys, used for iterating in order:
for _, k in ipairs(util.GetKeys(t)) do
	local v = t[k]
end
]]
function util.GetKeys(queue:{[string]:any}):{[number]:string}
	local result = {}
	for k in next, queue do
		table.insert(result, k)
	end
	table.sort(result)
	return result
end

--returns the deep number of elements, not counting tables themselves
function util.GetN(t:any):number
	local result = 0
	deepLoop(t, function(_, v)
		if type(v) ~= "table" then
			result += 1
		end
	end)
	return result
end

--[[
- Removes the key and shifts down keys with same priority that are
  behind the key in queue
- If you want to remove multiple keys, it is important to pass 
  an array of the keys, not call the function multiple times
]]
function util.ShiftDownKeys(queue:{[string]:any}, key:string|{[number]:string}):()
	if type(key) == "table" then
		for _, currentKey in pairs(key) do
			local priority = string.sub(currentKey, 1, 2)
			local numberInQueue = string.sub(currentKey, -4)
			local shiftDown = {}
			for k in next, queue do
				if string.match(k, "^"..priority) and string.sub(k, -4) > numberInQueue then		
					table.insert(shiftDown, k)
				end
			end
			if #shiftDown > 0 then
				table.sort(shiftDown)
				for _, k in ipairs(shiftDown) do
					queue[util.Sub(k, 1)] = queue[k]
				end	
				queue[shiftDown[#shiftDown]] = nil
				--sub 1 from the shifted down keys
				for _, v in pairs(shiftDown) do
					local i = table.find(key, v)
					if i then
						key[i] = util.Sub(v, 1)
					end
				end
			else
				queue[currentKey] = nil
			end
		end
	else
		local priority = string.sub(key, 1, 2)
		local numberInQueue = string.sub(key, -4)
		local shiftDown = {}
		for k in next, queue do
			if string.match(k, "^"..priority) and string.sub(k, -4) > numberInQueue then		
				table.insert(shiftDown, k)
			end
		end
		if #shiftDown > 0 then
			table.sort(shiftDown)
			for _, k in ipairs(shiftDown) do
				queue[util.Sub(k, 1)] = queue[k]
			end	
			queue[shiftDown[#shiftDown]] = nil
		else
			queue[key] = nil
		end
	end
end

--[[
Player: Unique number
Group: Array of players that will be kept in the same match
Match: Returned array containing teamAmount arrays that contain teamSize players


]]

function util.MatchGreedy(queue:{[string]:any}, teamSize:number, teamAmount:number)
	local playersNeeded = teamSize * teamAmount
	if util.GetN(queue) >= playersNeeded then
		--local teams = table.create(teamAmount, {})
		local teams = {}
		for _ = 1, teamAmount do
			table.insert(teams, {})
		end
		local players = {} --players/groups to distribute
		local removedFromQueue = {} --keys

		--get the first playersNeeded players in the queue
		local plrCount:number, group:string = 0, nil
		for _, k in ipairs(util.GetKeys(queue)) do
			local v = queue[k]
			if type(v) == "table" then
				if plrCount + #v <= playersNeeded then
					plrCount += #v
					table.insert(players, v)
					table.insert(removedFromQueue, k)
					if plrCount == playersNeeded then break end
				elseif not group then
					group = k
				end
			else
				if plrCount < playersNeeded then
					plrCount += 1
					table.insert(players, v)
					table.insert(removedFromQueue, k)
				else
					break
				end
			end
		end
		if plrCount < playersNeeded then
			--a group didnt fit anymore but all in all there are enough players
			--therefore single players must be removed

			--check if the group would fit if they were removed
			local singlePlayers = 0
			for i, v in ipairs(players) do
				if type(v) == "number" then
					singlePlayers += 1
				end
			end
			if playersNeeded - singlePlayers + #queue[group] <= playersNeeded then
				local playersToRemove = #queue[group] - (playersNeeded - util.GetN(players))
				local playersRemoved = 0
				for i = #players, 1, -1 do --repeat loop?
					if type(players[i]) == "number" then
						table.remove(players, i)
						table.remove(removedFromQueue, i)
						playersRemoved += 1
						if playersRemoved == playersToRemove then break end
					end
				end
				table.insert(players, queue[group])
				table.insert(removedFromQueue, group)
			else
				return
			end
		end

		--distribute biggest groups first
		table.sort(players, function(a, b)
			if type(a) == "table" and type(b) == "table" then
				return #a > #b
			end
			return false
		end)
		for _, group in ipairs(players) do
			if type(group) == "table" then
				--get smallest team
				table.sort(teams, function(a, b)
					return #a < #b
				end)

				if #group + #teams[1] <= teamSize then
					table.move(group, 1, #group, #teams[1]+1, teams[1])
				else --split up group
					--in the future i'll check if the whole group
					--would fit if i moved the group in it to an 
					--other team
					if module.Settings.SplitUpGroups then
						for _, team in ipairs(teams) do
							if #group > 0 then
								repeat
									table.insert(team, group[1])
									table.remove(group, 1)
								until #team == teamSize or #group == 0
							else
								break
							end
						end
					else
						return
					end
				end
			end
		end
		for _, plr in pairs(players) do
			if type(plr) == "number" then
				table.sort(teams, function(a, b)
					return #a < #b
				end)
				if #teams[1] < teamSize then
					table.insert(teams[1], plr)
				else
					warn("Something unexpected happened:\nPlayers:",
						players, "\nTeams:", teams, "\nPlease report this.")
					return
				end
			end
		end
		util.ShiftDownKeys(queue, removedFromQueue)
		return teams
	end
end

function util.MatchPeriodic(queue, config)
	--[[
	
	
	]]

	local playersNeeded = config.TeamSize * config.TeamAmount
	if util.GetN(queue) >= playersNeeded then

	end
end

local messaging = {}
module.Messaging = messaging
messaging.PacketCache = {}
messaging.Connections = {}

--[[
Module that handles MessagingService calls

Packet switching:
Split data that is bigger than 1kB into packets
Keys of a table must be either strings or numbers
-> If a table contains both, string keys are removed
]]

function messaging:Publish(topic:string, message:any):()
	if getDataSize(message) > 975 then
		local packets = {}
		local dataId = math.random(100000, 999999)
		if type(message) ~= "string" then
			message = HttpService:JSONEncode(message)
		end
		local t = {}	
		--treat payload like it is escaped (-> double encoded)
		local len = math.floor(936-(#HttpService:JSONEncode(message)-#message)/(#message/936))
		while #message > len do
			table.insert(t, string.sub(message, 1, len))
			message = string.sub(message, len+1)
		end
		table.insert(t, message)		
		for i, v in ipairs(t) do
			table.insert(packets, {_A = #t, _I = dataId, _N = i, _P = v})
		end
		for _, v in pairs(packets) do
			task.spawn(function()
				safeCall(function()
					MessagingService:PublishAsync(topic, v)
				end, 1)
			end)
		end
	else
		task.spawn(function()
			safeCall(function()
				MessagingService:PublishAsync(topic, message)
			end, 1)
		end)
	end
end

function messaging:SubscribeAsync(topic:string, callback:(any,number)->()):()
	safeCall(function()
		messaging.Connections[topic] = MessagingService:SubscribeAsync(topic, function(message)
			if type(message.Data) == "table" and message.Data._I then
				local packet = message.Data
				local cache = messaging.PacketCache
				table.insert(cache, packet)
				local packetsWithId = {}
				for _, v in pairs(cache) do
					if v._I == packet._I then
						packetsWithId[v._N] = v
					end
				end
				local a = 0 --can't use #packetsWithId
				for _ in pairs(packetsWithId) do
					a += 1
				end
				if a == packet._A then
					local result = ""
					for _, v in ipairs(packetsWithId) do
						result = result..v._P
						table.remove(cache, table.find(cache, v))
					end
					local success, decoded = pcall(function()
						return HttpService:JSONDecode(result)
					end)
					if success then
						callback(decoded, message.Sent)
					else
						callback(result, message.Sent)
					end
				end
			else
				callback(message.Data, message.Sent)
			end
		end)
	end, 1)
end

function messaging:Unsubscribe(topic:string):()
	if messaging.Connections[topic] then
		messaging.Connections[topic]:Disconnect()
		messaging.Connections[topic] = nil
	else
		error("Server is not subscribed to topic \""..topic.."\"")
	end
end

--[[
GoodSignal by stravant
devforum.roblox.com/t/1387063
   
MIT License

Copyright (c) 2021 stravant

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Authors:
stravant - July 31st, 2021 - Created the file.   
]]

local Signal = {}
Signal.__index = Signal

do
	local freeRunnerThread
	local function acquireRunnerThreadAndCallEventHandler(fn, ...)
		local acquiredRunnerThread = freeRunnerThread
		freeRunnerThread = nil
		fn(...)
		freeRunnerThread = acquiredRunnerThread
	end

	local function runEventHandlerInFreeThread(...)
		acquireRunnerThreadAndCallEventHandler(...)
		while true do
			acquireRunnerThreadAndCallEventHandler(coroutine.yield())
		end
	end

	local Connection = {}
	Connection.__index = Connection

	function Connection.new(signal, fn):RBXScriptConnection
		return setmetatable({
			Connected = true,
			_signal = signal,
			_fn = fn,
			_next = false
		}, Connection)
	end

	function Connection:Disconnect()
		assert(self.Connected, "Can't disconnect a connection twice")
		self.Connected = false
		if self._signal._handlerListHead == self then
			self._signal._handlerListHead = self._next
		else
			local prev = self._signal._handlerListHead
			while prev and prev._next ~= self do
				prev = prev._next
			end
			if prev then
				prev._next = self._next
			end
		end
	end

	function Signal.new():RBXScriptSignal
		return setmetatable({_handlerListHead = false}, Signal)
	end

	function Signal:Connect(fn)
		local connection = Connection.new(self, fn)
		if self._handlerListHead then
			connection._next = self._handlerListHead
			self._handlerListHead = connection
		else
			self._handlerListHead = connection
		end
		return connection
	end

	function Signal:DisconnectAll()
		self._handlerListHead = false
	end

	function Signal:Fire(...)
		local item = self._handlerListHead
		while item do
			if item.Connected then
				if not freeRunnerThread then
					freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				end
				task.spawn(freeRunnerThread, item._fn, ...)
			end
			item = item._next
		end
	end

	function Signal:Wait()
		local waitingCoroutine = coroutine.running()
		local cn;
		cn = self:Connect(function(...)
			cn:Disconnect()
			task.spawn(waitingCoroutine, ...)
		end)
		return coroutine.yield()
	end
end

module.PlayerLoaded = Signal.new()
module.PartyAdded = Signal.new()
module.PartyRemoving = Signal.new()

fastAssert(module.Settings.DefaultRank ~= "Leader", "DefaultRank can't be leader")
if module.Settings.DefaultRank ~= "Members"
	and table.find(module.Settings.RanksAddedByDefault, module.Settings.DefaultRank) == nil then
	if module.Settings.DefaultRank == "Member" then
		error('DefaultRank "Member" gets never created - Did you mean "Members"?')
	else
		error("DefaultRank gets never created")
	end
end

local party = {}
party.__index = party
party.ClassName = "Party"

--[[type party = {
	Leader: number,
	Members: {[number]:number},
	PartyId: number,
	Created: number,
	AddRank: (rankName:string, players:{[number]:number}?) -> (),
	RemoveRank: (rankName:string) -> (),
	AddPlayer: (player:Player, rank:string?) -> (),
	RemovePlayer: (player:player) -> (),
	GetPlayers: (returnType:string) -> ({[number]:Player}|{[number]:number}),
	GetPlayersWithRank: (rank:string) -> ({[number]:Player}),
	GetRankOfPlayer: (player:player) -> (string),
	ChangePlayerRank: (player:player, newRank:string) -> (),
	Destroy: () -> ()
}]]

function module:CreateParty(leader:player, members:{player}|{[string]:{player}}?, ...)
	fastAssert(leader, "Argument 1 (leader) missing or nil")
	local id:number = ...

	leader = touserid(leader)

	--todo: check if plr is in other party
	if members then
		if typeof(members) == "table" then
			local t = getTableType(members)
			if t == "Dictionary" then
				local players = {} --to check for duplicates
				for rankName, rank in pairs(members) do
					for i, v in pairs(rank) do			
						rank[i] = touserid(v)
						table.insert(players, v)
					end
					if table.find(rank, leader) then 
						error("The leader can't be in rank "..rankName.." at the same time")
					end
				end
				if containsDuplicate(players) then error("A player can't be twice in a party") end
			elseif t == "Array" then
				for i, v in pairs(members) do
					members[i] = touserid(v)	
				end
				if table.find(members, leader) then 
					error("The leader can't be in rank "..module.Settings.DefaultRank.." at the same time")
				end
				if containsDuplicate(members) then error("A player can't be twice in a party") end
			elseif t == "Mixed" then
				error("Argument 2 (members) is a mixture of dictionary and array")
			else
				error("Argument 2 (members) is unknown table")
			end
		else
			error("Argument 2 (members) is not a table")
		end
	end

	local self = setmetatable({}, party)
	self.Leader = leader::number
	self.Members = {}
	self.PartyId = id or math.random(10000000, 99999999)
	self.Created = os.time()
	--self.Changed = Signal.new()
	--self.PlayerAdded = Signal.new()
	--self.PlayerRemoving = Signal.new()

	if members then
		for _, v in pairs(module.Settings.RanksAddedByDefault) do
			if members[v] then
				self[v] = members[v]
			else
				self[v] = {}
			end
		end

		local d = module.Settings.DefaultRank
		if getTableType(members) == "Array" then
			self[d] = members
		else --handle when DefaultRank is in dictionary
			if members[d] then
				self[d] = members[d]
			end
		end
	else
		for _, v in pairs(module.Settings.RanksAddedByDefault) do			
			self[v] = {}			
		end
	end

	module.Parties[self.PartyId] = self

	module.PartyAdded:Fire(self)

	return self
end

function party:AddRank(rankName:string, players:{[number]:number}?):()
	if self[rankName] then error("Rank "..rankName.." already exists in party") end
	self[rankName] = {}
	if players then
		for i, v in players do
			players[i] = touserid(v)
		end
		if table.find(players, self.Leader) then
			error("The leader can't be in rank "..rankName.." at the same time")
		end
		if containsDuplicate(players) then error("A player can't be twice in a rank") end

		for _, v in pairs(players) do
			if module:IsInParty(v, self) then
				self:ChangePlayerRank(v, rankName)
			else
				table.insert(self[rankName], v)
			end
		end
	end
	--self.Changed:Fire("AddRank", rankName, players)
end

function party:RemoveRank(rankName:string):()
	if rankName == "Leader" or rankName == "Members" then error("Rank "..rankName.." can't be removed") end
	for _, v in pairs(self[rankName]) do
		table.insert(self[module.Settings.DefaultRank], v)
	end
	self[rankName] = nil
	--self.Changed:Fire("RemoveRank", rankName)
end

function party:AddPlayer(plr:player, rank:string?):()
	fastAssert(plr, "Argument 1 (player) missing")
	if module:IsInParty(plr, self) then error("Player is already in party") end
	if self.Teleporting then error("Player can't be added, party is teleporting") end
	plr = touserid(plr)
	if rank then
		if self[rank] then
			if rank == "Leader" then
				table.insert(self[module.Settings.DefaultRank], self.Leader)
				self.Leader = plr
			else
				table.insert(self[rank], plr)
			end
		else
			error("Rank doesn't exist in party")
		end
	else
		table.insert(self[module.Settings.DefaultRank], plr)
	end
end

function party:GetPlayers(returnType:string?):{[number]:player}
	--Instance (default)
	--UserId
	local players = {}
	if returnType == "UserId" then
		table.insert(players, self.Leader)
		for _, v in pairs(self) do
			if typeof(v) == "table" then				
				for _, p in pairs(v) do			
					table.insert(players, p)
				end
			end
		end
		return players
	else
		local plr = Players:GetPlayerByUserId(self.Leader)
		if plr then table.insert(players, plr) end
		for _, v in pairs(self) do
			if typeof(v) == "table" then				
				for _, p in pairs(v) do
					local plr = Players:GetPlayerByUserId(p)
					if plr then table.insert(players, plr) end
				end
			end
		end
		return players
	end
end

function party:GetPlayersWithRank(rank:string):{[number]:Player}
	fastAssert(self[rank], "Rank doesn't exist in party")
	if typeof(self[rank]) == "table" then
		local players = {}
		for _, v in pairs(self[rank]) do
			local plr = Players:GetPlayerByUserId(v)
			if plr then table.insert(players, plr) end
		end
		return players
	elseif rank == "Leader" then
		local plr = Players:GetPlayerByUserId(self.Leader)
		if plr then return {plr} end
	else
		error("Rank "..rank.." doesn't exist in party")
	end
end

function party:GetRankOfPlayer(plr:player):string
	plr = touserid(plr)
	if self.Leader == plr then
		return "Leader"
	end
	for k, v in pairs(self) do
		if type(v) == "table" and table.find(v, plr) then
			return k
		end
	end
end

function party:RemovePlayer(plr:player):()
	plr = touserid(plr)
	if self.Leader == plr then
		local players = self:GetPlayers()
		if #players <= 1 then
			self:Destroy()
		else
			table.remove(players, table.find(players, plr))
			self:ChangePlayerRank(players[math.random(#players)], "Leader")
		end
	else
		for _, v in pairs(self) do
			if typeof(v) == "table" then				
				local plrIdx = table.find(v, plr)
				if plrIdx then table.remove(v, plrIdx) end
			end
		end
	end
end

function party:ChangePlayerRank(plr:player, newRank:string):()
	fastAssert(plr, "Argument 1 (player) missing or nil")
	fastAssert(self[newRank], "Argument 2 (rank) nil or not existing in party")
	plr = touserid(plr)

	--remove from old rank
	local rank = self:GetRankOfPlayer(plr)
	if rank == newRank then error("Player already has the rank "..newRank) end
	if typeof(self[rank]) == "table" then
		local idx = table.find(self[rank], plr)
		if idx then
			table.remove(self[rank], idx)
		end
	elseif rank == "Leader" then --choose new random leader			
		local players = self:GetPlayers("UserId")

		if #players == 1 then
			error("Rank of leader can't be changed because they're the only player in party")
		end

		table.remove(players, table.find(players, plr))
		local newLeader = players[math.random(#players)] --UserId

		local rank = self:GetRankOfPlayer(newLeader)
		local idx = table.find(self[rank], newLeader)
		if idx then
			table.remove(self[rank], idx)
		end

		self.Leader = newLeader
	end

	--add to new rank
	if typeof(self[newRank]) == "table" then
		table.insert(self[newRank], plr)
	elseif newRank == "Leader" then
		table.insert(self[module.Settings.DefaultRank], self.Leader)
		self.Leader = plr
	end
end

function party:Destroy():()
	module.PartyRemoving:Fire(self)
	--it isn't guaranteed that the user has enough time 
	--to handle the event
	module.Parties[self.PartyId] = nil
	table.clear(self)
	setmetatable(self, nil)
end

--[[local self = module:CreateParty(0) --doesn't work in do end apparently
export type Party = typeof(self)
self = self:Destroy()]]

function module:IsInParty(plr:player, party:party?):(boolean, any?)
	plr = touserid(plr)
	if party then
		if party.Leader == plr then return true, party end
		for _, v in pairs(party) do
			if typeof(v) == "table" and table.find(v, plr) then
				return true, party
			end
		end
		return false
	else
		for _, p in pairs(module.Parties) do
			if p.Leader == plr then return true, p end
			for _, v in pairs(p) do
				if typeof(v) == "table" and table.find(v, plr) then
					return true, p
				end
			end
		end
		return false
	end
end

function module:GetPartyFromPlayer(plr:player):(party, string)
	plr = touserid(plr)
	for _, p in pairs(module.Parties) do
		if p.Leader == plr then return p, "Leader" end
		for k, v in pairs(p) do
			if typeof(v) == "table" and table.find(v, plr) then
				return p, k
			end
		end
	end
end

function module:TeleportAsync(placeId:number, players:any,
	teleportOptions:TeleportOptions?):TeleportAsyncResult
	teleportOptions = teleportOptions or Instance.new("TeleportOptions")

	local playersToTeleport = {}
	local teleportData = teleportOptions:GetTeleportData() or {}
	teleportData.Parties = {}

	if typeof(players) == "table" then
		if players.PartyId then --single party
			for _, v in pairs(players:GetPlayers()) do
				table.insert(playersToTeleport, v)
				--v:SetAttribute("Teleporting", true)
			end

			teleportData.Parties[players.PartyId] = {
				Created = players.Created,
				Leader = players.Leader,
				PartyId = players.PartyId,
			}
			for k, v in pairs(players) do
				if typeof(v) == "table" then
					--copy so it can't be changed
					teleportData.Parties[players.PartyId][k] = {unpack(v)}
				end
			end
			players.Teleporting = true
		else --table with parties / players
			for _, v in pairs(players) do
				if v.PartyId then --party
					for _, p in pairs(v:GetPlayers()) do
						table.insert(playersToTeleport, p)
						--p:SetAttribute("Teleporting", true)
					end

					teleportData.Parties[v.PartyId] = {
						Created = v.Created,
						Leader = v.Leader,
						PartyId = v.PartyId,
					}
					for n, r in pairs(v) do
						if typeof(r) == "table" then
							teleportData.Parties[v.PartyId][n] = {unpack(r)}
						end
					end
					v.Teleporting = true
				else --player
					table.insert(playersToTeleport, v)
					--v:SetAttribute("Teleporting", true)

					--check if player is in a party, add to tpdata!
				end
			end
		end
	else --single player
		playersToTeleport = players
		--players:SetAttribute("Teleporting", true)
	end

	teleportData.Created = os.time()
	teleportOptions:SetTeleportData(teleportData)

	return safeCall(function()
		return TeleportService:TeleportAsync(placeId, playersToTeleport, teleportOptions)
	end, 1)
end

local queue = {}
queue.__index = queue
queue.ClassName = "Queue"

function module:GetQueue(config:{
	Name: string,
	TeamAmount: number?,
	TeamSize: number,
	MatchCallback: ({[number]:Player},any) -> (),
	GetPriority: nil | (Player) -> (number), --? doesn't work here apparently
	--SkillMatching: {

	--}?
	})

	--devforum.roblox.com/t/28027/9

	fastAssert(config, "Argument 1 (config) missing or nil")

	--confuses intellisense *insert annoyed face*
	if module.Queues[config.Name] then
		return module.Queues[config.Name]
	end

	config.TeamAmount = config.TeamAmount or 2

	local self = {}
	self.Config = config
	self.PlayerAdded = Signal.new()
	self.PlayerRemoved = Signal.new()

	task.spawn(function()
		messaging:SubscribeAsync(config.Name.."Match", function(players)
			local inGame = {}
			deepLoop(players, function(_, v)
				if type(v) == "number" then
					local plr = Players:GetPlayerByUserId(v)
					if plr then
						table.insert(inGame, plr)
					end
				end
			end)
			if #inGame > 0 then
				self.PlayerRemoved:Fire(players)
				config.MatchCallback(inGame, players)
			end
		end)
	end)

	module.Queues[config.Name] = self

	return setmetatable(self, queue)
end

function queue:AddAsync(players:Player|{Player|{Player}}):()
		--[[
		{
			UserId = Skill,
			{
				UserId = Skill,
				UserId = Skill,
			},
		}
		]]

	if typeof(players) ~= "table" then
		players = {players}
	end
	local config = self.Config

	if config.SkillMatching then

		--[[for k, v in pairs(players) do
			if type(v) == "table" then --group
				for p, s in pairs(v) do
					v[touserid(p)] = s
				end
			else --single player
				players[touserid(k)] = v
			end
		end

		local hash = {}	--check for duplicates
		deepLoop(players, function(k, v, t)
			if hash[k] == nil then
				hash[k] = true
			elseif type(v) == "number" then --check if it isnt table
				t[k] = nil
				warn("Prevented adding duplicate player to queue")
			end
		end)]]

		error("SkillMatching not supported yet")
	else

		local priorities = {} --{player index : priority}
		if config.GetPriority then
			for i, v in pairs(players) do
				if type(v) == "table" then --group
					local priority
					for _, p in pairs(v) do --take highest priority from players
						local currentPriority = 100 - (config.GetPriority(p) or 1)
						if not priority or currentPriority < priority then
							priority = currentPriority

							if priority < 1 or priority > 99 then
								error("Priority not in range between 1 and 99")
							end					
							priorities[i] = priority
						end
					end
				else --single player		
					--convert 1 to 99, 2 to 98, 3 to 97, etc.
					local priority = 100 - (config.GetPriority(v) or 1)

					if priority < 1 or priority > 99 then
						error("Priority not in range between 1 and 99")
					end
					priorities[i] = priority
				end
			end
		end

		local instances = flattenTable(players)

		--convert to userids
		for i, v in pairs(players) do
			if type(v) == "table" then --group
				for i, p in pairs(v) do
					v[i] = touserid(p)
				end
				if not module.Settings.SplitUpGroups
					and #v > self.Config.TeamSize then
					error("Group is bigger than TeamSize, enable SplitUpGroups")
				end
			else --single player
				players[i] = touserid(v)
			end
		end

		local hash = {}	--check for duplicates
		deepLoop(players, function(i, v, t)
			if hash[v] == nil then
				hash[v] = true
			else
				t[i] = nil
				warn("Prevented adding duplicate player to queue")
			end
		end)

		safeCall(function()
			SortedMap:UpdateAsync(config.Name, function(queue)
				queue = queue or {}
				print("Queue add before:", queue)
				if config.GetPriority then
					local addedPriorities = {}
					for i, v in pairs(players) do
						--for now don't check if plr is already in queue

						local priority = priorities[i]

						if not addedPriorities[priority] then
							--get other players with same priority
							local playersWithSamePriority = {}						
							for i, v in pairs(players) do
								if priorities[i] == priority then
									table.insert(playersWithSamePriority, v)
								end
							end

							local last = priority.."0000"
							for _, k in ipairs(util.GetKeys(queue)) do
								if string.match(k, "^"..string.format("%.2i", priority)) then
									last = k
								end
							end

							for _, v in ipairs(playersWithSamePriority) do
								last += 1 --converts to number if it isn't already
								queue[string.format("%.6i", last)] = v --padding
							end

							addedPriorities[priority] = true
						end
					end
					print("Queue add after:", queue)
					return queue
				else
					local last = 990000 --990001 is default key
					for _, k in ipairs(util.GetKeys(queue)) do
						if string.match(k, "^99") then
							last = k
						end
					end

					for _, v in ipairs(players) do
						--for now don't check if plr is already in queue

						last += 1 --converts to number if it isn't already
						queue[string.format("%.6i", last)] = v --padding
					end
					print("Queue add after:", queue)
					return queue
				end
			end, module.Settings.QueueExpiration)
		end, 1)

		self.PlayerAdded:Fire(instances)
	end
end

function queue:RemoveAsync(players:any):()
	local instances = {}

	if type(players) == "table" then
		for i, v in pairs(players) do
			if type(v) == "number" then
				local plr = Players:GetPlayerByUserId(v)
				if plr then
					table.insert(instances, plr)
				end
			else
				table.insert(instances, v)
				players[i] = touserid(v)
			end
		end
	else
		if type(players) == "number" then
			local plr = Players:GetPlayerByUserId(players)
			if plr then
				table.insert(instances, plr)
			end
		else
			table.insert(instances, players)
			players = touserid(players)
		end
	end

	safeCall(function()
		SortedMap:UpdateAsync(self.Config.Name, function(queue)
			print("Queue remove before:", queue)
			--if the queue didn't change, always return nil
			local changed = false
			if type(players) == "table" then
				for k, v in next, queue do
					if type(v) == "table" then --group
						for _, plr in next, players do
							local idx = table.find(v, plr)
							if idx then
								if #v == 1 then
									util.ShiftDownKeys(queue, k)
									changed = true
									break
								else
									table.remove(v, idx)
									changed = true
								end
							end
						end
					else --single plr
						local idx = table.find(players, v)
						if idx then
							util.ShiftDownKeys(queue, k)
							changed = true
						end
					end
				end
			else
				for k, v in next, queue do
					if type(v) == "table" then --group
						local idx = table.find(v, players)
						if idx then
							if #v == 1 then
								util.ShiftDownKeys(queue, k)
								changed = true
							else
								table.remove(v, idx)
								changed = true
							end
						end
					elseif v == players then --single plr
						util.ShiftDownKeys(queue, k)
						changed = true
					end
				end
			end
			if changed then
				print("Queue remove after:", queue)
				return queue
			end
			print("Queue remove after:", "No change")
			return nil
		end, module.Settings.QueueExpiration)
	end, 1)

	self.PlayerRemoved:Fire(instances)
end

function queue:Destroy(wipeQueue:boolean?):()
	if wipeQueue then --yields
		--[[local items, id = safeCall(function()
			return self.Queue:ReadAsync(100, false, 0)
		end, 1)
		safeCall(function()
			self.Queue:RemoveAsync(id)
		end, 1)
		if #items == 100 then
			repeat
				local items, id = safeCall(function()
					return self.Queue:ReadAsync(100, false, 0)
				end, 1)
				safeCall(function()
					self.Queue:RemoveAsync(id)
				end, 1)
			until #items < 100
		end]]
		safeCall(function()
			SortedMap:RemoveAsync(self.Config.Name)
		end, 1)
	end
	safeCall(function()
		--this could error when calling Destroy right after creation
		messaging:Unsubscribe(self.Config.Name.."Match")
	end, 1, 1)
	module.Queues[self.Config.Name] = nil
	table.clear(self)
	setmetatable(self, nil)
end

function module:IsInQueueAsync(plr:player, queueName:string?):(boolean, string?)
	plr = touserid(plr)

	return safeCall(function()
		if queueName then
			local queue = SortedMap:GetAsync(queueName)
			for k, v in next, queue do
				if type(v) == "table" then
					if table.find(v, plr) then
						return true
					end
				elseif v == plr then
					return true
				end
			end
			return false
		else
			--GetRangeAsync returns array instead of dictionary
			local queues = SortedMap:GetRangeAsync(Enum.SortDirection.Descending, 200)
			for _, queue in next, queues do
				for k, v in next, queue.value do
					if type(v) == "table" then
						if table.find(v, plr) then
							return true, queue.key
						end
					elseif v == plr then
						return true, queue.key
					end
				end
			end
			return false
		end
	end, 1)
end

--task scheduler
task.spawn(function()
	local adaptCooldown = true
	if module.Settings.PollingCooldown then
		adaptCooldown = false
	end
	
	while task.wait(module.Settings.PollingCooldown) do

		--queue polling
		if next(module.Queues) then
			for _, v in pairs(module.Queues) do	
				task.spawn(function()
					local config = v.Config
					local send

					safeCall(function()
						SortedMap:UpdateAsync(config.Name, function(queue)
							if queue then
								if config.SkillMatching then
									error("SkillMatching not supported yet")
								else
									local match = util.MatchGreedy(queue,
										config.TeamSize, config.TeamAmount)
									if match then
										send = match
										return queue
									else
										return nil
									end
								end
							else
								return nil --i dont want to risk a crash
							end
						end, module.Settings.QueueExpiration)
					end, 1)

					if send then
						messaging:Publish(config.Name.."Match", send)
					end
				end)
			end
		end

		--adapt PollingCooldown
		if adaptCooldown then
			error("Self-adapting PollingCooldown not available yet")
		end
	end
end)

--handle arriving players:
Players.PlayerAdded:Connect(function(plr)
	--[[if debounce then
		repeat task.wait() until debounce == false
	end
	debounce = true]]

	local data = plr:GetJoinData()
	local suc, err = pcall(function()
		if data.TeleportData and data.TeleportData.Parties and data.SourceGameId == game.GameId then

			local party, rank
			for _, p in pairs(data.TeleportData.Parties) do
				if p.Leader == plr.UserId then party = p; rank = "Leader" end
				for k, v in pairs(p) do
					if typeof(v) == "table" and table.find(v, plr.UserId) then
						party = p; rank = k
					end
				end
			end

			if party then
				if os.time() - data.TeleportData.Created < module.Settings.TeleportDataValidTime then
					if module.Parties[party.PartyId] then
						if rank ~= "Leader" then
							table.insert(module.Parties[party.PartyId][rank], plr.UserId)
							--module.Parties[party.PartyId]:AddPlayer(plr, rank)
						end
					else
						local newParty = module:CreateParty(party.Leader, nil, party.PartyId)

						if rank ~= "Leader" then
							table.insert(newParty[rank], plr.UserId)
							--newParty:AddPlayer(plr, rank)
						end

						task.spawn(function() 
							task.wait(module.Settings.PlayerLostTime)

							local players = {} --players that are in the server
							for _, v in pairs(party) do
								if typeof(v) == "table" then				
									for _, id in pairs(v) do
										local plr = Players:GetPlayerByUserId(id)
										if plr then
											table.insert(players, plr)
										else
											warn("Player "..id.." was lost during teleport")
											--maybe an event for this?
										end
									end
								end
							end
							local plr = Players:GetPlayerByUserId(party.Leader)
							if not plr then --leader got lost, choose new leader
								warn("Player "..party.Leader.." was lost during teleport")
								if #players > 0 then
									local newLeader = players[math.random(#players)]
									local rank = party:GetRankOfPlayer(newLeader)
									local idx = table.find(party[rank], newLeader.UserId)
									if idx then
										table.remove(party[rank], idx)
									end

									party.Leader = newLeader.UserId
								end
							end

						end)

					end
				else
					error("TeleportData was created "..os.time() - data.TeleportData.Created..
						" seconds ago, maximum is "..module.Settings.TeleportDataValidTime)
				end
			end
			data.TeleportData.Parties = nil
		end
	end)
	if not suc then
		warn("Failed loading player "..plr.Name..": "..err)
	end

	module.PlayerLoaded:Fire(plr, data.TeleportData)

	--debounce = false
end)

Players.PlayerRemoving:Connect(function(plr)
	local party = module:GetPartyFromPlayer(plr)
	if party then
		if party.Teleporting then
			party:Destroy()
		else
			party:RemovePlayer(plr)
		end
	end
end)

return module
