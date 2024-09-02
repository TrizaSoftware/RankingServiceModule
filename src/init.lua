--[[
  ______  ____  _                ____              __   _                _____                 _         
 /_  __/ / __ \(_)___  ____ _   / __ \____ _____  / /__(_)___  ____ _   / ___/___  ______   __(_)_______ 
  / / (_) /_/ / /_  / / __ `/  / /_/ / __ `/ __ \/ //_/ / __ \/ __ `/   \__ \/ _ \/ ___/ | / / / ___/ _ \
 / / _ / _, _/ / / /_/ /_/ /  / _, _/ /_/ / / / / ,< / / / / / /_/ /   ___/ /  __/ /   | |/ / / /__/  __/
/_/ (_)_/ |_/_/ /___/\__,_/  /_/ |_|\__,_/_/ /_/_/|_/_/_/ /_/\__, /   /____/\___/_/    |___/_/\___/\___/ 
                                                            /____/                                                
                                                            
   Programmer(s): Jyrezo
   
   Copyright(c) The T:Riza Software 2020-2024
]]

local HttpService = game:GetService("HttpService")
local GroupService = game:GetService("GroupService")
local RankingUrl = "https://infra.triza.xyz/api/v2/ranking/%s"
local Depdendencies = script.Dependencies
local Promise = require(Depdendencies.Promise)

local function makeHttpRequest(url: string, data: { Method: string, Body: { [any]: any } })
	local FormattedData = {
		Url = url,
	}

	for property, value in data do
		if property ~= "Body" then
			FormattedData[property] = value
		else
			FormattedData[property] = HttpService:JSONEncode(value)
		end
	end

	return HttpService:RequestAsync(FormattedData)
end

local RankingService = {}
RankingService.__index = RankingService

function RankingService.new(key: string, groupId: number, organizationId: number)
	local self = setmetatable({}, RankingService)

	self._key = key
	self._groupId = groupId
	self._organizationId = organizationId
	self._token = nil
	self._thread = coroutine.create(function()
		while true do
			local _, decodedData = Promise.retryWithDelay(function()
				return Promise.new(function(resolve)
					local tokenRequest = makeHttpRequest(RankingUrl:format("authenticate"), {
						Method = "POST",
						Body = {
							key = self._key,
							organizationid = self._organizationId,
						},
						Headers = {
							["Content-Type"] = "application/json",
						},
					})
					local responseBodyDecoded = HttpService:JSONDecode(tokenRequest.Body)
					resolve(responseBodyDecoded)
				end)
			end, 20, 10):await()

			self._token = decodedData.data.token
			task.wait((decodedData.data.expires - os.time()) - 20)
		end
	end)

	coroutine.resume(self._thread)

	return self
end

function RankingService:SetRank(userId: number, rankId: number)
	assert(userId and rankId, "You Must Provide All Fields.")

	return Promise.new(function(resolve)
		local Request = makeHttpRequest(RankingUrl:format(`rankuser/{userId}`), {
			Body = {
				token = self._token,
				newrankid = rankId,
			},
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
		})
	
		local Body = HttpService:JSONDecode(Request.Body)
	
		resolve(Body.success, Body.message)
	end)
end

function RankingService:Promote(userId: number)
	local GroupInfo = GroupService:GetGroupInfoAsync(self._groupId)
	local Player = game.Players:GetPlayerByUserId(userId)
	local UserRank = Player:GetRankInGroup(self._groupId)

	local NewRank = nil

	for i, Rank in GroupInfo.Roles do
		if Rank.Rank == UserRank then
			if (i + 1) > #GroupInfo.Roles then
				error(`The rank index {i + 1} does not exist.`)
			end
			
			if GroupInfo.Roles[i + 1].Rank < 255 then
				NewRank = GroupInfo.Roles[i + 1]
			end
		end
	end

	assert(NewRank, "You can't set someone's rank to 255.")

	return Promise.new(function(resolve)
		local Request = makeHttpRequest(RankingUrl:format(`rankuser/{userId}`), {
			Body = {
				token = self._token,
				newrankid = NewRank.Rank,
			},
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
		})
	
		local Body = HttpService:JSONDecode(Request.Body)
	
		resolve(Body.success, Body.message, NewRank.Name)
	end)
end

function RankingService:Demote(userId: number)
	local GroupInfo = GroupService:GetGroupInfoAsync(self._groupId)
	local Player = game.Players:GetPlayerByUserId(userId)
	local UserRank = Player:GetRankInGroup(self._groupId)

	local NewRank = nil

	for i, Rank in GroupInfo.Roles do
		if Rank.Rank == UserRank then
			if (i - 1) < #GroupInfo.Roles then
				error(`The rank index {i - 1} does not exist.`)
			end

			if GroupInfo.Roles[i - 1].Rank > 0 then
				NewRank = GroupInfo.Roles[i - 1]
			end
		end
	end

	assert(NewRank, "You can't set someone's rank to 0.")

	return Promise.new(function(resolve)
		local Request = makeHttpRequest(RankingUrl:format(`rankuser/{userId}`), {
			Body = {
				token = self._token,
				newrankid = NewRank.Rank,
			},
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
		})
	
		local Body = HttpService:JSONDecode(Request.Body)
	
		resolve(Body.success, Body.message, NewRank.Name)
	end)
end

function RankingService:BulkPromote(userIds: {})
	local GroupInfo = GroupService:GetGroupInfoAsync(self._groupId)
	local FormattedRanks = {}
	local FormattedRankNames = {}

	for _, userId in userIds do
		local Player = game.Players:GetPlayerByUserId(userId)

		local UserRank = Player:GetRankInGroup(self._groupId)

		local NewRank = nil

		for i, Rank in GroupInfo.Roles do
			if Rank.Rank == UserRank then
				if (i + 1) > #GroupInfo.Roles then
					error(`The rank index {i + 1} does not exist.`)
				end

				if GroupInfo.Roles[i + 1].Rank < 255 then
					NewRank = GroupInfo.Roles[i + 1]
				end
			end
		end

		if not NewRank then
			continue
		end

		FormattedRankNames[userId] = NewRank.Name

		table.insert(FormattedRanks, { userid = userId, newrankid = NewRank.Rank })
	end

	return Promise.new(function(resolve)
		local Request = makeHttpRequest(RankingUrl:format(`bulkrank`), {
			Body = {
				token = self._token,
				users = FormattedRanks,
			},
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
		})
	
		local Body = HttpService:JSONDecode(Request.Body)
	
		resolve(Body.success, Body.message, Body.data.successfullyRankedUsers or {}, FormattedRankNames)
	end)
end

function RankingService:BulkDemote(userIds: {})
	local GroupInfo = GroupService:GetGroupInfoAsync(self._groupId)
	local FormattedRanks = {}
	local FormattedRankNames = {}

	for _, userId in userIds do
		local Player = game.Players:GetPlayerByUserId(userId)

		local UserRank = Player:GetRankInGroup(self._groupId)

		local NewRank = nil

		for i, Rank in GroupInfo.Roles do
			if Rank.Rank == UserRank then
				if (i - 1) < #GroupInfo.Roles then
					error(`The rank index {i - 1} does not exist.`)
				end

				if GroupInfo.Roles[i - 1].Rank > 0 then
					NewRank = GroupInfo.Roles[i - 1]
				end
			end
		end

		if not NewRank then
			continue
		end

		FormattedRankNames[userId] = NewRank.Name

		table.insert(FormattedRanks, { userid = userId, newrankid = NewRank.Rank })
	end

	return Promise.new(function(resolve)
		local Request = makeHttpRequest(RankingUrl:format(`bulkrank`), {
			Body = {
				token = self._token,
				users = FormattedRanks,
			},
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
		})
	
		local Body = HttpService:JSONDecode(Request.Body)
	
		resolve(Body.success, Body.message, Body.data.successfullyRankedUsers or {}, FormattedRankNames)
	end)
end

return RankingService
