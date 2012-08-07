-- /script SendAddonMessage("LSDB","REQ;Regaro","GUILD")
-- /script SendAddonMessage("LSDB","VER;4","GUILD")
-- /script LibSharedDb_Data["LibSharedDb_Guild"]["Data"]["Regaro"]["Data"]["GCOM"]["Test"]="12345"
-- /script LibStub:GetLibrary("LibSharedDb"):SetData("LibSharedDb_Guild","GCOM","12345")
-- /script LibSharedDb_Data["LibSharedDb_Guild"]["Data"]["Neoran"]["Data"]={}
local Lib = LibStub:NewLibrary("LibSharedDbPrivate", 1)
local Ext = LibStub:NewLibrary("LibSharedDb", 1)

local LOG_LEVEL = LibDbg.LOG_LEVEL
Lib.Dbg = {} ; LibStub:GetLibrary("LibDbg"):Embed(Lib.Dbg)
Lib.Dbg.DebugLevel = LOG_LEVEL.DATA
Lib.Dbg.ChatPrefix = "LSDb"

Lib.Timer = {} ; LibStub:GetLibrary("AceTimer-3.0"):Embed(Lib.Timer)
Lib.Serializer = {} ; LibStub:GetLibrary("AceSerializer-3.0"):Embed(Lib.Serializer)
Lib.Frame = CreateFrame("Frame", "LibSharedDb")

Lib.Buffer = {}
Lib.ChangedDataHooks = {}

Lib.Const = {}
Lib.Const.SelfPlayerName = UnitName("player")
Lib.Const.ChatPrefix = "LSDB1"
Lib.Const.ConfigVersion = "LSDB1"
Lib.Const.VirtChanPrefix = "LibSharedDb_"
Lib.Const.GuildChan = Lib.Const.VirtChanPrefix .. "Guild"
Lib.Const.VirtChanTranslate = {
	GUILD = Lib.Const.GuildChan,
}

Lib.Config = {}
Lib.Config.SendDataInterval = 15 -- Seconds
Lib.Config.CleanupInterval = 60
Lib.Config.StartupDelay = 30

Ext.Const = {}
Ext.Const.GuildChan = Lib.Const.GuildChan

local function BasicInit()
	Lib.Frame:SetScript("OnEvent",
		function(_, event, ...) Lib[event](Lib, ...) end )
	Lib.Frame:RegisterEvent("ADDON_LOADED")
end

local function split(str,delim,max,plain)
	local ret = {}
	local cur = 1
	local i = 1
	local del_start,del_end = str:find(delim,cur,plain)
	while del_start ~= nil and (i < max or max <= 0) do
		table.insert(ret,str:sub(cur,del_start-1))
		cur = del_end + 1
		del_start,del_end = str:find(delim,cur,plain)
		i = i + 1
	end
	table.insert(ret,str:sub(cur))
	return ret
end

function Lib:Init()
	self.Dbg:Debug(LOG_LEVEL.NORMAL,"SharedDb:Init");
	self.Frame:RegisterEvent("CHAT_MSG_CHANNEL")
	self.Frame:RegisterEvent("CHAT_MSG_ADDON")
	self.Timer:ScheduleRepeatingTimer(self.AdvertiseVersionAndSendData,
		self.Config.SendDataInterval,self)
	self.Timer:ScheduleRepeatingTimer(self.Cleanup,
		self.Config.CleanupInterval,self)
	if LibSharedDb_Data == nil or LibSharedDb_Config == nil or
	  LibSharedDb_Config["Version"] ~= self.Const.ConfigVersion then
		LibSharedDb_Data = {}
		LibSharedDb_Config = {}
		LibSharedDb_Config["Version"] = self.Const.ConfigVersion
	end
	for chan,data in pairs(LibSharedDb_Data) do
		data["Config"]["ResendRequested"] = false
		data["Config"]["SendingData"] = false
		self:CreateUserEntry(chan,self.Const.SelfPlayerName)
	end
	self:Cleanup()
end

-- ## Events ## --

function Lib:ADDON_LOADED(...)
	if (arg1 == "LibSharedDb") then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"ADDON_LOADED", ...)
		self.Frame:UnregisterEvent("ADDON_LOADED")
		self.ADDON_LOADED = nil
		-- self:Init()
		self.Timer:ScheduleTimer(self.Init,self.Config.StartupDelay,self)
	end
end

function Lib:GUILD_ROSTER_UPDATE()
	self.Dbg:Debug(LOG_LEVEL.NORMAL,"GUILD_ROSTER_UPDATE")
	local GuildMember = {}
	for i = 0,1000 do
		local name = GetGuildRosterInfo(i)
		if name ~= nil then
			GuildMember[name] = true
		end
	end
	if GuildMember[self.Const.SelfPlayerName] ~= true then
		self.Dbg:Debug(LOG_LEVEL.ERROR,"GUILD_ROSTER_UPDATE, but GetGuildRosterInfo doesn't contain myself, skipping cleanup!")
		return
	end
	for user,val in pairs(LibSharedDb_Data[self.Const.GuildChan]["Data"]) do
		if GuildMember[user] ~= true then
			LibSharedDb_Data[self.Const.GuildChan]["Data"][user] = nil
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Removing data for user " .. user .. 
				" from channel " .. self.Const.GuildChan)
		end
	end
	self.Frame:UnregisterEvent("GUILD_ROSTER_UPDATE")
	LibSharedDb_Data[self.Const.GuildChan]["Config"]["NextCleanup"] = 
		time() + self.Config.CleanupInterval - 1
end

function Lib:CHAT_MSG_CHANNEL(message,sender,language,channelString,_,flags,_,channelNumber,channelName,_,counter,guid)
end

function Lib:CHAT_MSG_ADDON(prefix, message, channel, sender)
	local chan = self.Const.VirtChanTranslate[channel]
	if prefix ~= self.Const.ChatPrefix or
		sender == self.Const.SelfPlayerName or
		chan == nil then
		return
	end
	self.Dbg:Debug(LOG_LEVEL.DATA,"CHAT_MSG_ADDON", chan, sender, message)
	local Data = split(message,";",2,true)
	if Data[1] == "VER" then
		local Tmp = split(Data[2],";",2,true)
		if self:IsTwinkOf(chan,sender,Tmp[1]) == true and
		  self:NewerVersion(chan,Tmp[1],tonumber(Tmp[2])) == true then
			self:SendMessage("NORMAL",chan,"REQ;" .. Tmp[1])
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Requested new data from " .. sender)
		end
	elseif Data[1] == "REQ" and Data[2] == self:GetMyMain(chan) and
	  LibSharedDb_Data[chan]["Config"]["SendingData"] ~= true then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"Data for channel " .. chan ..
			" requested by " .. sender)
		LibSharedDb_Data[chan]["Config"]["ResendRequested"] = true
	elseif Data[1] == "STADTA" then
		local Tmp = split(Data[2],";",3,true)
		if self:IsTwinkOf(chan,sender,Tmp[1]) then
			self:StartNewData(chan,sender,tonumber(Tmp[2]))
			self:NewData(chan,sender,Tmp[3])
		else
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Refused Data from " .. sender ..
			  " for " .. Tmp[1] .. " because sender isn't listed as twink.")
		end
	elseif Data[1] == "DTA" then
		self:NewData(chan,sender,Data[2])
	elseif Data[1] == "ENDDTA" then
		self:EndNewData(chan,sender)
	end
end

-- ## General Functions ## --

function Lib:NewerVersion(chan,sender,version)
	if Ext:ExistsUserEntry(chan,sender) == false or
	  LibSharedDb_Data[chan]["Data"][sender]["Config"]["Version"] ~= version then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"Found newer version " .. version .. 
			" for data from " .. sender .. " in chan " .. chan)
		return true
	end
	return false
end

-- ## Cleanup functions ## --

function Lib:Cleanup()
	if self:ExistsChannelEntry(self.Const.GuildChan) then
		self:CleanupGuildChannel()
	end
end

function Lib:CleanupGuildChannel()
	self.Frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	local function CallGuildRosterIfRequired()
		if LibSharedDb_Data[self.Const.GuildChan]["Config"]["NextCleanup"] == nil or
		   LibSharedDb_Data[self.Const.GuildChan]["Config"]["NextCleanup"] <= time() then
			GuildRoster()
			self.Timer:ScheduleTimer(CallGuildRosterIfRequired,10)
		end
	end
	CallGuildRosterIfRequired()
end

-- ## Outgoing communication functions ## --

function Lib:SendMessage(prio,target,content,callback,callbackparam)
	self.Dbg:Debug(LOG_LEVEL.DATA,"SendMessage " .. prio .. "," .. target .. "," .. content)
	if target:find(self.Const.VirtChanPrefix,1,true) == 1 then
		local TargetChan = nil
		if target == self.Const.GuildChan then
			TargetChan = "GUILD"
		end
		if TargetChan ~= nil then
			ChatThrottleLib:SendAddonMessage(prio,self.Const.ChatPrefix,content,
				TargetChan,nil,nil,callback,callbackparam)
		else
			error("Called SendMessage with invalid target " .. target)
		end
	else
		ChatThrottleLib:SendChatMessage(prio,self.Const.ChatPrefix,content,"CHANNEL",
			nil,target,nil,callback,callbackparam)
	end
end

function Lib:AdvertiseVersionAndSendData()
	for chan,data in pairs(LibSharedDb_Data) do
		assert(data~=nil)
		assert(data["Data"]~=nil)
		local MainChar = self:GetMyMain(chan)
		if data["Config"]["SendingData"] ~= true and data["Config"]["ResendRequested"] ~= true then
			if data["Data"][MainChar] == nil then
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Don't advertise Version because I don't have any data for " .. MainChar .. ".")
				error("No own data for chan " .. chan)
			else
				assert(data["Data"][MainChar]["Config"]~=nil,"No Config for " .. MainChar .. "!")
				assert(data["Data"][MainChar]["Config"]["Version"]~=nil,"No Version for " .. MainChar .. "!")
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Advertise Verison " .. 
					data["Data"][MainChar]["Config"]["Version"] ..
					" to channel " .. chan .. " for " .. MainChar)
				self:SendMessage("NORMAL",chan,"VER;" .. MainChar .. ";" ..
					data["Data"][MainChar]["Config"]["Version"])
			end
		end
		if data["Config"]["ResendRequested"] == true then
			if data["Data"][MainChar] == nil then
				self.Dbg:Debug(LOG_LEVEL.ERROR,"ResendRequested, but I have no data for myself!")
			else
				self:SendData(chan,MainChar)
				LibSharedDb_Data[chan]["Config"]["ResendRequested"] = false
			end
		end
	end
end

function Lib:SendData(chan,user)
	if LibSharedDb_Data[chan]["Config"]["SendingData"] == true then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"Already sending data to channel " .. chan)
		return
	end
	LibSharedDb_Data[chan]["Config"]["SendingData"] = true
	local Data = self.Serializer:Serialize(LibSharedDb_Data[chan]["Data"][user]["Data"])
	self.Dbg:Debug(LOG_LEVEL.NORMAL,"Send to channel " .. chan .. " for user " .. user .. " data " .. Data)
	local DataParts = {}
	local Version = LibSharedDb_Data[chan]["Data"][user]["Config"]["Version"]
	local Pos = 1
	local MAX_DATA_LEN = 245
	while Pos <= Data:len() do
		local Command = "DTA;"
		local CommandLen = 4
		if Pos == 1 then
			Command = "STADTA;" .. user .. ";" .. Version .. ";"
			CommandLen = Command:len()
		end
		table.insert(DataParts,Command .. Data:sub(Pos,Pos+MAX_DATA_LEN-1-CommandLen))
		Pos = Pos + MAX_DATA_LEN - CommandLen
	end
	for _,CurData in ipairs(DataParts) do
		self:SendMessage("BULK",chan,CurData)
	end
	self:SendMessage("BULK",chan,"ENDDTA",self.SentData,chan)
end

function Lib.SentData(chan)
	LibSharedDb_Data[chan]["Config"]["SendingData"] = false
	Lib.Dbg:Debug(LOG_LEVEL.NORMAL,"Data sent to chan " .. chan)
end

-- ## Incoming communication functions ## --

function Lib:StartNewData(chan,sender,version)
	if self:NewerVersion(chan,sender,version) == false then
		self.Dbg:Debug(LOG_LEVEL.DATA,"Skip data because already got version " .. version .. 
		" from " ..	sender .. " in channel " .. chan)
		return
	end
	if self.Buffer[chan] == nil then
		self.Buffer[chan] = {}
	end
	self.Buffer[chan][sender] = {}
	self.Buffer[chan][sender]["Data"] = ""
	self.Buffer[chan][sender]["Version"] = version
	self.Dbg:Debug(LOG_LEVEL.NORMAL,"Start new data for " .. sender .. " in channel " .. chan ..
		" with version " .. version)
end

function Lib:NewData(chan,sender,data)
	if self.Buffer[chan] == nil or self.Buffer[chan][sender] == nil then
		return
	end
	self.Buffer[chan][sender]["Data"] = self.Buffer[chan][sender]["Data"] .. data
end

function Lib:EndNewData(chan,sender)
	if self.Buffer[chan] == nil or self.Buffer[chan][sender] == nil then
		return
	end
	local result,data = self.Serializer:Deserialize(self.Buffer[chan][sender]["Data"])
	if result ~= true then
		self.Dbg:Debug(LOG_LEVEL.ERROR,"Can't deserialize string. Error: " .. data ..
		  " ; Data: ", self.Buffer[chan][sender])
		error("Can't deserialize string. Error: " .. data)
		return
	end
	local owner = sender
	if data[self.Const.ConfigVersion]["Main"] ~= sender then
		if self:IsTwinkOf(chan,sender,data[self.Const.ConfigVersion]["Main"]) == true then
			owner = data[self.Const.ConfigVersion]["Main"]
			LibSharedDb_Data[chan]["Data"][sender] = nil
		else
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Refused to set owner of data to " ..
				data[self.Const.ConfigVersion]["Main"] .. " because this char doesn't have " ..
				sender .. " in Twink-List.")
			return
		end
	end
	self:CreateUserEntry(chan,owner)
	LibSharedDb_Data[chan]["Data"][owner]["Data"] = data
	LibSharedDb_Data[chan]["Data"][owner]["Config"]["Version"] =
		self.Buffer[chan][sender]["Version"]
	self.Dbg:Debug(LOG_LEVEL.NORMAL,"Got new version " .. 
		LibSharedDb_Data[chan]["Data"][owner]["Config"]["Version"] .. " from " .. sender ..
		" in channel " .. chan .. ": ",data)
	self.Buffer[chan][sender] = nil
	self:CallChangedDataHooks(chan,owner)
end

-- ## Util functions ## --

function Lib:CallChangedDataHooks(chan,user)
	for func,param in pairs(self.ChangedDataHooks) do
		func(param,chan,user)
	end
end

function Lib:GetMyMain(chan)
	if self:ExistsUserEntry(chan,self.Const.SelfPlayerName) then
		return LibSharedDb_Data[chan]["Data"][self.Const.SelfPlayerName]["Data"][self.Const.ConfigVersion]["Main"]
	end
	return self.Const.SelfPlayerName
end

function Lib:IsTwinkOf(chan,twink,main)
	if twink == main or (self:ExistsUserEntry(chan,main) and
	  LibSharedDb_Data[chan]["Data"][main]["Data"][self.Const.ConfigVersion]["Twinks"][twink] == true) then
		return true
	end
	return false
end

function Lib:CreateChannelEntry(chan)
	if self:ExistsChannelEntry(chan) == true then
		return
	end
	LibSharedDb_Data[chan] = {}
	LibSharedDb_Data[chan]["Data"] = {}
	LibSharedDb_Data[chan]["Config"] = {}
end

function Lib:CreateUserEntry(chan,user)
	if self:ExistsUserEntry(chan,user) == true then
		return
	end
	self:CreateChannelEntry(chan)
	LibSharedDb_Data[chan]["Data"][user] = {}
	LibSharedDb_Data[chan]["Data"][user]["Data"] = {}
	LibSharedDb_Data[chan]["Data"][user]["Config"] = {}
	LibSharedDb_Data[chan]["Data"][user]["Config"]["Version"] = 0
	LibSharedDb_Data[chan]["Data"][user]["Data"][self.Const.ConfigVersion] = {}
	LibSharedDb_Data[chan]["Data"][user]["Data"][self.Const.ConfigVersion]["Twinks"]  = {}
	LibSharedDb_Data[chan]["Data"][user]["Data"][self.Const.ConfigVersion]["Main"] = self.Const.SelfPlayerName
end

function Lib:ExistsChannelEntry(chan)
	if LibSharedDb_Data[chan] ~= nil then
		return true
	end
	return false
end

function Lib:ExistsUserEntry(chan,user)
	if self:ExistsChannelEntry(chan) and
	  LibSharedDb_Data[chan]["Data"][user] ~= nil then
		return true
	end
	return false
end

function Lib:ExistsUserPrefixEntry(chan,user,prefix)
	if self:ExistsUserEntry(chan,user) and
	  LibSharedDb_Data[chan]["Data"][user]["Data"][prefix] ~= nil then
		return true
	end
	return false
end

--[[--
function Lib:RecalcMergedData(chan,user)
	for prefix,data in pairs(LibSharedDb_Data[chan]["Data"][user]["Data"]) do
		if self.MergedData[prefix] == nil then
			self.MergedData[prefix] = {}
		end
		if type(LibSharedDb_Data[chan]["Data"][user]["Data"][prefix]) == "table" then
			for key,val in pairs(data) do
			end
		end
	end
end

function Lib:CreateUserPrefixEntry(chan,user,prefix)
	self:CreateUserEntry(chan,user)
	if self:ExistsUserPrefixEntry(chan,user,prefix) == true then
		return
	end
	LibSharedDb_Data[chan]["Data"][user]["Data"][prefix] = {}
end
--]]--

local function deepcopy(object) -- http://lua-users.org/wiki/CopyTable
	local lookup_table = {}
	local function _copy(object)
		if type(object) ~= "table" then
			return object
		elseif lookup_table[object] then
			return lookup_table[object]
		end
		local new_table = {}
		lookup_table[object] = new_table
		for index, value in pairs(object) do
			new_table[_copy(index)] = _copy(value)
		end
		return new_table
	end
	return _copy(object)
end

function Ext:ExistsChannelEntry(chan)
	return Lib:ExistsChannelEntry(chan)
end

function Ext:ExistsUserEntry(chan,user)
	return Lib:ExistsUserEntry(chan,user)
end

function Ext:ExistsUserPrefixEntry(chan,user,prefix)
	return Lib:ExistsUserPrefixEntry(chan,user,prefix)
end

function Ext:IncrementVersion(chan,user)
	LibSharedDb_Data[chan]["Data"][user]["Config"]["Version"] =
		LibSharedDb_Data[chan]["Data"][user]["Config"]["Version"] + 1
end

function Ext:SetData(chan,prefix,data)
	local main = self:GetMain(chan,nil)
	if self:ExistsUserEntry(chan,main) ~= true then
		return false
	end
	LibSharedDb_Data[chan]["Data"][main]["Data"][prefix] = data
	self:IncrementVersion(chan,main)
	Lib.Dbg:Debug(LOG_LEVEL.NORMAL,"New Data for user " .. main .. " in chan " .. chan .. " with prefix " .. prefix)
end

function Ext:CopyAndSetData(chan,prefix,data)
	self:SetData(chan,prefix,deepcopy(data))
end

function Ext:GetData(chan,user,prefix)
	if Ext:ExistsUserPrefixEntry(chan,user,prefix) == false then
		return nil
	end
	return LibSharedDb_Data[chan]["Data"][self:GetMain(chan,user)]["Data"][prefix]
end

function Ext:GetChanData(chan,prefix,includeSelf)
	if not self:ExistsChannelEntry(chan) then
		return nil
	end
	local main = self:GetMain(chan,nil)
	local ret = {}
	for user,data in pairs(LibSharedDb_Data[chan]["Data"]) do
		if (includeSelf == true or (user ~= main and user ~= Lib.Const.SelfPlayerName)) and
		  self:ExistsUserPrefixEntry(chan,user,prefix) then
			ret[user] = data["Data"][prefix]
		end
	end
	return ret
end

function Ext:CopyAndGetData(chan,user,prefix)
	return deepcopy(self:GetData(chan,user,prefix))
end

function Ext:CopyAndGetChanData(chan,prefix,includeSelf)
	return deepcopy(self:GetChanData(chan,prefix,includeSelf))
end

function Ext:SetChangedDataHook(func,param)
	Lib.ChangedDataHooks[func] = param
end

function Ext:SetMyMain(chan,main)
	if self:ExistsChannelEntry(chan) ~= true then
		return false
	end
	if main == nil then
		main = Lib.Const.SelfPlayerName
	end
	LibSharedDb_Data[chan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Main"] = main
	--[[--
	for prefix,_ in pairs(LibSharedDb_Data[chan]["Data"][Lib.Const.SelfPlayerName]["Data"]) do
		if prefix ~= Lib.Const.ConfigVersion then
			LibSharedDb_Data[chan]["Data"][Lib.Const.SelfPlayerName]["Data"][prefix] = nil
		end
	end
	--]]--
	return true
end

function Ext:GetMain(chan,user)
	if self:ExistsChannelEntry(chan) ~= true then
		return nil
	end
	if user == nil then
		user = Lib.Const.SelfPlayerName
	end
	return LibSharedDb_Data[chan]["Data"][user]["Data"][Lib.Const.ConfigVersion]["Main"]
end

function Ext:AddTwink(chan,twink)
	if self:ExistsChannelEntry(chan) ~= true then
		return false
	end
	LibSharedDb_Data[chan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Twinks"][twink]  = true
	self:IncrementVersion(chan,Lib.Const.SelfPlayerName)
	return true
end

function Ext:DelTwink(chan,twink)
	if self:ExistsChannelEntry(chan) ~= true then
		return false
	end
	LibSharedDb_Data[chan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Twinks"][twink]  = nil
	self:IncrementVersion(chan,Lib.Const.SelfPlayerName)
	return true
end

function Ext:GetTwinks(chan)
	if self:ExistsChannelEntry(chan) ~= true then
		return nil
	end
	return deepcopy(LibSharedDb_Data[chan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Twinks"])
end

function Ext:DeepCompare(t1,t2,ignoreMetaTable) -- http://snippets.luacode.org/snippets/Deep_Comparison_of_Two_Values_3
	local ty1 = type(t1)
	local ty2 = type(t2)
	if ty1 ~= ty2 then
		return false
	end
	-- non-table types can be directly compared
	if ty1 ~= 'table' and ty2 ~= 'table' then
		return t1 == t2
	end
	-- as well as tables which have the metamethod __eq
	local mt = getmetatable(t1)
	if not ignoreMetaTable and mt and mt.__eq then return t1 == t2 end
	for k1,v1 in pairs(t1) do
		local v2 = t2[k1]
		if v2 == nil or not self:DeepCompare(v1,v2) then
			return false
		end
	end
	for k2,v2 in pairs(t2) do
		local v1 = t1[k2]
		--if v1 == nil or not self:DeepCompare(v1,v2) then
		-- v1==nil should be enough, if v1~=nil, value should be compared in for k1,v1 in pairs(t1)
		if v1 == nil then
			return false
		end
	end
	return true
end


BasicInit()
