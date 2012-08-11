-- /script SendAddonMessage("LSDB","REQ;Regaro","GUILD")
-- /script SendAddonMessage("LSDB","VER;4","GUILD")
-- /script LibSharedDb_Data["LibSharedDb_Guild"]["Data"]["Regaro"]["Data"]["GCOM"]["Test"]="12345"
-- /script LibStub:GetLibrary("LibSharedDb"):SetData("LibSharedDb_Guild","GCOM","12345")
-- /script LibSharedDb_Data["LibSharedDb_Guild"]["Data"]["Neoran"]["Data"]={}
-- /script local l=LibStub:GetLibrary("LibSharedDbPrivate");l.Dbg:Debug(0,l.Db,l.AceDb.factionrealm);
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
Lib.LoadedCallbacks = {}

Lib.Const = {}
Lib.Const.SelfPlayerName = UnitName("player")
Lib.Const.SelfGuildName = nil
Lib.Const.ChatPrefix = "LSDB1"
Lib.Const.ConfigVersion = "LSDB1"
Lib.Const.VirtChanPrefix = "LibSharedDb_"
Lib.Const.GuildChanPrefix = Lib.Const.VirtChanPrefix .. "GUILD_"
Lib.Const.ExternToInternChan = {
}
Lib.Const.InternToExternChan = {}

Lib.Config = {}
Lib.Config.SendDataInterval = 15 -- Seconds
Lib.Config.CleanupInterval = 60
Lib.Config.MaxStartupDelay = 45
Lib.Config.TestInitReadyInterval = 1


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

function Lib.InitWhenReady(count)
	local InitNow = true

	local Tmp = GetGuildInfo("player")
	if Tmp == nil then
		InitNow = false
	end

	local ForceInit = false
	if count * Lib.Config.TestInitReadyInterval >= Lib.Config.MaxStartupDelay then
		ForceInit = true
	end

	if InitNow == true or ForceInit == true then
		print("LibSharedDb: Startup")
		Lib:Init()
	else
		Lib.Timer:ScheduleTimer(Lib.InitWhenReady,Lib.Config.TestInitReadyInterval,count + 1)
	end
end

function Lib:Init()
	self.Dbg:SearchDebugChatFrame()
	if self.Dbg:IsLogging() then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"SharedDb:Init")
	end

	-- Constants init
	self.Const.SelfGuildName = GetGuildInfo("player")
	if self.Const.SelfGuildName == nil then
		self.Const.SelfGuildName = ""
	end
	self.Const.ExternToInternChan["GUILD"] = self.Const.GuildChanPrefix .. self.Const.SelfGuildName
	for ext,int in pairs(self.Const.ExternToInternChan) do
		self.Const.InternToExternChan[int] = ext
	end

	-- Init
	self.Timer:ScheduleRepeatingTimer(self.AdvertiseVersionAndSendData,
		self.Config.SendDataInterval,self)
	self.Timer:ScheduleRepeatingTimer(self.Cleanup,
		self.Config.CleanupInterval,self)
	if LibSharedDb_Data == nil or LibSharedDb_Config == nil or
	  LibSharedDb_Config["Version"] ~= self.Const.ConfigVersion then
		LibSharedDb_Data = {}
		self.AceDb = LibStub:GetLibrary("AceDB-3.0"):New("LibSharedDb_Data", {})
		self:SetDb()
		LibSharedDb_Config = {}
		LibSharedDb_Config["Version"] = self.Const.ConfigVersion
	end
	for chan,data in pairs(self.Db) do
		data["Config"]["ResendRequested"] = false
		data["Config"]["SendingData"] = false
		data["Config"]["SessionShareOff"] = false
		if chan:find(self.Const.GuildChanPrefix,1,true) == 1 and
		  (self:InternToExternChan(chan) == chan or self.Const.GuildName == "") then
			if self.Dbg:IsLogging() then
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Share off for " .. chan)
			end
			data["Config"]["SessionShareOff"] = true
		end
		self:CreateUserEntry(chan,self.Const.SelfPlayerName)
	end
	self:Cleanup()
	self.Frame:RegisterEvent("CHAT_MSG_CHANNEL")
	self.Frame:RegisterEvent("CHAT_MSG_ADDON")
	local Tmp = self.LoadedCallbacks
	self.LoadedCallbacks = nil
	for func,param in pairs(Tmp) do
		func(param)
	end
end

-- ## Events ## --

function Lib:ADDON_LOADED(...)
	if (arg1 == "LibSharedDb") then
		self.Frame:UnregisterEvent("ADDON_LOADED")
		self.ADDON_LOADED = nil
		self.AceDb = LibStub:GetLibrary("AceDB-3.0"):New("LibSharedDb_Data", {})
		self:SetDb()
		self.InitWhenReady(0)
		-- self.Timer:ScheduleTimer(self.Init,self.Config.StartupDelay,self)
	end
end

function Lib:GUILD_ROSTER_UPDATE()
	if self.Dbg:IsLogging() then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"GUILD_ROSTER_UPDATE")
	end
	local GuildChan = self:ExternToInternChan("GUILD")
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
	for user,val in pairs(self.Db[GuildChan]["Data"]) do
		if GuildMember[user] ~= true then
			self.Db[GuildChan]["Data"][user] = nil
			if self.Dbg:IsLogging() then
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Removing data for user " .. user .. 
					" from channel " .. GuildChan)
			end
		end
	end
	self.Frame:UnregisterEvent("GUILD_ROSTER_UPDATE")
	self.Db[GuildChan]["Config"]["NextCleanup"] = time() + self.Config.CleanupInterval - 1
end

function Lib:CHAT_MSG_CHANNEL(message,sender,language,channelString,_,flags,_,channelNumber,channelName,_,counter,guid)
end

function Lib:CHAT_MSG_ADDON(prefix, message, channel, sender)
	local chan = self:ExternToInternChan(channel)
	if prefix ~= self.Const.ChatPrefix or
		sender == self.Const.SelfPlayerName or
		chan == nil then
		return
	end
	if self.Dbg:IsLogging() then
		self.Dbg:Debug(LOG_LEVEL.DATA,"CHAT_MSG_ADDON", chan, sender, message)
	end
	local Data = split(message,";",2,true)
	if Data[1] == "VER" then
		local Tmp = split(Data[2],";",2,true)
		if self:IsTwinkOf(chan,sender,Tmp[1]) == true and
		  self:NewerVersion(chan,Tmp[1],tonumber(Tmp[2])) == true then
			self:SendMessage("NORMAL",chan,"REQ;" .. Tmp[1])
			if self.Dbg:IsLogging() then
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Requested new data from " .. sender)
			end
		end
	elseif Data[1] == "REQ" and Data[2] == self:GetMyMain(chan) and
	  self.Db[chan]["Config"]["SendingData"] ~= true then
		if self.Dbg:IsLogging() then
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Data for channel " .. chan ..
				" requested by " .. sender)
		end
		self.Db[chan]["Config"]["ResendRequested"] = true
	elseif Data[1] == "STADTA" then
		local Tmp = split(Data[2],";",3,true)
		if self:IsTwinkOf(chan,sender,Tmp[1]) then
			self:StartNewData(chan,sender,tonumber(Tmp[2]))
			self:NewData(chan,sender,Tmp[3])
		else
			if self.Dbg:IsLogging() then
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Refused Data from " .. sender ..
					" for " .. Tmp[1] .. " because sender isn't listed as twink.")
			end
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
	  self.Db[chan]["Data"][sender]["Config"]["Version"] ~= version then
		if self.Dbg:IsLogging() then
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Found newer version " .. version .. 
				" for data from " .. sender .. " in chan " .. chan)
		end
		return true
	end
	return false
end

-- ## Cleanup functions ## --

function Lib:Cleanup()
	if self:ExistsChannelEntry(self:ExternToInternChan("GUILD")) then
		self:CleanupGuildChannel()
	end
end

function Lib:CleanupGuildChannel()
	self.Frame:RegisterEvent("GUILD_ROSTER_UPDATE")
	local GuildChan = self:ExternToInternChan("GUILD")
	local function CallGuildRosterIfRequired()
		if self.Db[GuildChan]["Config"]["NextCleanup"] == nil or
		   self.Db[GuildChan]["Config"]["NextCleanup"] <= time() then
			GuildRoster()
			self.Timer:ScheduleTimer(CallGuildRosterIfRequired,10)
		end
	end
	CallGuildRosterIfRequired()
end

-- ## Outgoing communication functions ## --

function Lib:SendMessage(prio,target,content,callback,callbackparam)
	if target:find(self.Const.VirtChanPrefix,1,true) == 1 then
		local TargetChan = self:InternToExternChan(target)
		if TargetChan ~= nil and TargetChan:find(self.Const.VirtChanPrefix,1,true) ~= 1 then
			if self.Dbg:IsLogging() then
				self.Dbg:Debug(LOG_LEVEL.DATA,"SendMessage " .. prio .. "," .. TargetChan .. "(" ..
					target .. ")," .. content)
			end
			ChatThrottleLib:SendAddonMessage(prio,self.Const.ChatPrefix,content,
				TargetChan,nil,nil,callback,callbackparam)
		else
			error("Called SendMessage with invalid target " .. target .. " translated to " .. TargetChan)
		end
	else
		if self.Dbg:IsLogging() then
			self.Dbg:Debug(LOG_LEVEL.DATA,"SendMessage " .. prio .. "," .. target .. "," .. content)
		end
		ChatThrottleLib:SendChatMessage(prio,self.Const.ChatPrefix,content,"CHANNEL",
			nil,target,nil,callback,callbackparam)
	end
end

function Lib:AdvertiseVersionAndSendData()
	for chan,data in pairs(self.Db) do
		if data["Config"]["SessionShareOff"] ~= true then
		-- Potential Bugfix:
		--if data["Config"]["SessionShareOff"] ~= true and data["Data"][self:GetMyMain(chan)] ~= nil then
			local MainChar = self:GetMyMain(chan)
			if data["Config"]["SendingData"] ~= true and data["Config"]["ResendRequested"] ~= true then
				if data["Data"][MainChar] == nil then
					if self.Dbg:IsLogging() then
						self.Dbg:Debug(LOG_LEVEL.NORMAL,"Don't advertise Version because I don't have any data for " .. MainChar .. ".")
					end
					error("No own data for chan " .. chan)
				else
					assert(data["Data"][MainChar]["Config"]~=nil,"No Config for " .. MainChar .. "!")
					assert(data["Data"][MainChar]["Config"]["Version"]~=nil,"No Version for " .. MainChar .. "!")
					if self.Dbg:IsLogging() then
						self.Dbg:Debug(LOG_LEVEL.NORMAL,"Advertise Verison " .. 
							data["Data"][MainChar]["Config"]["Version"] ..
							" to channel " .. chan .. " for " .. MainChar)
					end
					self:SendMessage("NORMAL",chan,"VER;" .. MainChar .. ";" ..
						data["Data"][MainChar]["Config"]["Version"])
				end
			end
			if data["Config"]["ResendRequested"] == true then
				if data["Data"][MainChar] == nil then
					self.Dbg:Debug(LOG_LEVEL.ERROR,"ResendRequested, but I have no data for myself!")
				else
					self:SendData(chan,MainChar)
					self.Db[chan]["Config"]["ResendRequested"] = false
				end
			end
		end
	end
end

function Lib:SendData(chan,user)
	if self.Db[chan]["Config"]["SendingData"] == true then
		if self.Dbg:IsLogging() then
			self.Dbg:Debug(LOG_LEVEL.NORMAL,"Already sending data to channel " .. chan)
		end
		return
	end
	self.Db[chan]["Config"]["SendingData"] = true
	local Data = self.Serializer:Serialize(self.Db[chan]["Data"][user]["Data"])
	if self.Dbg:IsLogging() then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"Send to channel " .. chan .. " for user " .. user .. " data " .. Data)
	end
	local DataParts = {}
	local Version = self.Db[chan]["Data"][user]["Config"]["Version"]
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
	Lib.Db[chan]["Config"]["SendingData"] = false
	Lib.Dbg:Debug(LOG_LEVEL.NORMAL,"Data sent to chan " .. chan)
end

-- ## Incoming communication functions ## --

function Lib:StartNewData(chan,sender,version)
	if self:NewerVersion(chan,sender,version) == false then
		if self.Dbg:IsLogging() then
			self.Dbg:Debug(LOG_LEVEL.DATA,"Skip data because already got version " .. version .. 
				" from " ..	sender .. " in channel " .. chan)
		end
		return
	end
	if self.Buffer[chan] == nil then
		self.Buffer[chan] = {}
	end
	self.Buffer[chan][sender] = {}
	self.Buffer[chan][sender]["Data"] = ""
	self.Buffer[chan][sender]["Version"] = version
	if self.Dbg:IsLogging() then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"Start new data for " .. sender .. " in channel " .. chan ..
			" with version " .. version)
	end
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
			self.Db[chan]["Data"][sender] = nil
		else
			if self.Dbg:IsLogging() then
				self.Dbg:Debug(LOG_LEVEL.NORMAL,"Refused to set owner of data to " ..
					data[self.Const.ConfigVersion]["Main"] .. " because this char doesn't have " ..
					sender .. " in Twink-List.")
			end
			return
		end
	end
	self:CreateUserEntry(chan,owner)
	self.Db[chan]["Data"][owner]["Data"] = data
	self.Db[chan]["Data"][owner]["Config"]["Version"] =
		self.Buffer[chan][sender]["Version"]
	if self.Dbg:IsLogging() then
		self.Dbg:Debug(LOG_LEVEL.NORMAL,"Got new version " .. 
			self.Db[chan]["Data"][owner]["Config"]["Version"] .. " from " .. sender ..
			" in channel " .. chan .. ": ",data)
	end
	self.Buffer[chan][sender] = nil
	self:CallChangedDataHooks(chan,owner)
end

-- ## Channelname translate functions ## --

function Lib:ExternToInternChan(chan)
	local Tmp = self.Const.ExternToInternChan[chan]
	if Tmp ~= nil then
		return Tmp
	end
	return chan
end

function Lib:InternToExternChan(chan)
	local Tmp = self.Const.InternToExternChan[chan]
	if Tmp ~= nil then
		return Tmp
	end
	return chan
end

-- ## Util functions ## --

function Lib:CallChangedDataHooks(chan,user)
	for func,param in pairs(self.ChangedDataHooks) do
		func(param,chan,user)
	end
end

function Lib:GetMyMain(chan)
	if self:ExistsUserEntry(chan,self.Const.SelfPlayerName) then
		return self.Db[chan]["Data"][self.Const.SelfPlayerName]["Data"][self.Const.ConfigVersion]["Main"]
	end
	return self.Const.SelfPlayerName
end

function Lib:IsTwinkOf(chan,twink,main)
	if twink == main or (self:ExistsUserEntry(chan,main) and
	  self.Db[chan]["Data"][main]["Data"][self.Const.ConfigVersion]["Twinks"][twink] == true) then
		return true
	end
	return false
end

function Lib:SetDb()
	local UsedDataType = "factionrealm"
	if self.AceDb[UsedDataType] == nil then
		self.AceDb[UsedDataType] = {}
	end
	self.Db = self.AceDb[UsedDataType]
end

function Lib:CreateChannelEntry(chan)
	if self:ExistsChannelEntry(chan) == true then
		return
	end
	self.Db[chan] = {}
	self.Db[chan]["Data"] = {}
	self.Db[chan]["Config"] = {}
end

function Lib:CreateUserEntry(chan,user)
	if self:ExistsUserEntry(chan,user) == true then
		return
	end
	self:CreateChannelEntry(chan)
	self.Db[chan]["Data"][user] = {}
	self.Db[chan]["Data"][user]["Data"] = {}
	self.Db[chan]["Data"][user]["Config"] = {}
	self.Db[chan]["Data"][user]["Config"]["Version"] = 0
	self.Db[chan]["Data"][user]["Data"][self.Const.ConfigVersion] = {}
	self.Db[chan]["Data"][user]["Data"][self.Const.ConfigVersion]["Twinks"]  = {}
	self.Db[chan]["Data"][user]["Data"][self.Const.ConfigVersion]["Main"] = user
end

function Lib:ExistsChannelEntry(chan)
	if self.Db[chan] ~= nil then
		return true
	end
	return false
end

function Lib:ExistsUserEntry(chan,user)
	if self:ExistsChannelEntry(chan) and
	  self.Db[chan]["Data"][user] ~= nil then
		return true
	end
	return false
end

function Lib:ExistsUserPrefixEntry(chan,user,prefix)
	if self:ExistsUserEntry(chan,user) and
	  self.Db[chan]["Data"][user]["Data"][prefix] ~= nil then
		return true
	end
	return false
end

-- ## Slash Command ## --

SLASH_LIBSHAREDDB1 = "/libshareddb"
SLASH_LIBSHAREDDB2 = "/lsdb"

function Lib:HandleCommand(msg,editbox)
	local function _PrintHelp()
		print("LibSharedDb Help")
		print("Commands: /libshareddb or /lsdb")
		print("/lsdb setmain <chan> <main>")
		print("Sets the main-character for this character in channel chan.")
		print("/lsdb addtwink <chan> <twink>")
		print("Adds twink as twink for current character in channel chan.")
		print("/lsdb deltwink <chan> <twink>")
		print("Removes twink as twink for current character in channel chan.")
		print("TAKE CARE: setmain, addtwink and deltwink is case-sensetive concerning character names.")
		print("/lsdb showmain <chan>")
		print("Shows main character for channel chan.")
		print("/lsdb showtwinks <chan>")
		print("Shows twinks for channel chan.")
	end
	local tmp = msg:gsub("^%s*(.-)%s*$", "%1")
	tmp = tmp:gsub("(%s+)"," ")
	local cmd = split(msg," ",-1,true)
	cmd[1] = cmd[1]:lower()
	if cmd[1] == "setmain" and cmd[2] ~= nil and cmd[2] ~= "" then
		local chan = self:ExternToInternChan(cmd[2])
		if chan == nil then
			chan = cmd[2]
		end
		if cmd[3] == nil or cmd[3] == "" then
			cmd[3] = self.Const.SelfPlayerName
		end
		if Ext:SetMyMain(chan,cmd[3]) == true then
			print("Set Main for " .. self.Const.SelfPlayerName .. " to " .. cmd[3] .. ".")
		else
			print("Can't set Main. No channel " .. chan .. "?")
		end
	elseif (cmd[1] == "addtwink" or cmd[1] == "deltwink") and
	  cmd[3] ~= nil and cmd[2] ~= "" and cmd[3] ~= "" then
		local chan = self:ExternToInternChan(cmd[2])
		if chan == nil then
			chan = cmd[2]
		end
		local res = false
		if cmd[1] == "addtwink" then
			res = Ext:AddTwink(chan,cmd[3])
		elseif cmd[1] == "deltwink" then
			res = Ext:DelTwink(chan,cmd[3])
		else
			error("Neither addtwink nor deltwink oO")
		end
		if res == true then
			local text = cmd[3] .. " was "
			if cmd[1] == "addtwink" then
				text = text .. "added "
			else
				test = text .. "removed "
			end
			text = text .. "as twink from " .. self.Const.SelfPlayerName
			print(text)
		else
			print("Can't add or remove twink " .. cmd[3] .. ". Does channel " .. chan .. " exists?")
		end
	elseif (cmd[1] == "showmain" or cmd[1] == "showtwinks") and
	  cmd[2] ~= nil and cmd[2] ~= "" then
		local chan = self:ExternToInternChan(cmd[2])
		if chan == nil then
			chan = cmd[2]
		end
		if cmd[1] == "showmain" then
			print("My main is: " .. Ext:GetMain(chan,self.Const.SelfPlayerName))
		else
			local text = "My twinks are: "
			local twinks = Ext:GetTwinks(chan)
			if twinks ~= nil then
				for twink,val in pairs(twinks) do
					text = text .. twink .. ", "
				end
			end
			print(text)
		end
	else
		_PrintHelp()
	end
end

function Lib.SlashCommand(msg,editbox)
	Lib:HandleCommand(msg,editbox)
end

SlashCmdList["LIBSHAREDDB"] = Lib.SlashCommand

--[[--
function Lib:RecalcMergedData(chan,user)
	for prefix,data in pairs(self.Db[chan]["Data"][user]["Data"]) do
		if self.MergedData[prefix] == nil then
			self.MergedData[prefix] = {}
		end
		if type(self.Db[chan]["Data"][user]["Data"][prefix]) == "table" then
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
	self.Db[chan]["Data"][user]["Data"][prefix] = {}
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

function Ext:JoinChannel(chan)
	Lib:CreateUserEntry(Lib:ExternToInternChan(chan),Lib.Const.SelfPlayerName)
end

function Ext:ExistsChannelEntry(chan)
	return Lib:ExistsChannelEntry(Lib:ExternToInternChan(chan))
end

function Ext:ExistsUserEntry(chan,user)
	return Lib:ExistsUserEntry(Lib:ExternToInternChan(chan),user)
end

function Ext:ExistsUserPrefixEntry(chan,user,prefix)
	return Lib:ExistsUserPrefixEntry(Lib:ExternToInternChan(chan),user,prefix)
end

function Ext:IncrementVersion(chan,user)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	Lib.Db[TranslatedChan]["Data"][user]["Config"]["Version"] =
		Lib.Db[TranslatedChan]["Data"][user]["Config"]["Version"] + 1
end

function Ext:SetData(chan,prefix,data)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	local Main = self:GetMain(TranslatedChan,nil)
	if self:ExistsUserEntry(TranslatedChan,Main) ~= true then
		return false
	end
	Lib.Db[TranslatedChan]["Data"][Main]["Data"][prefix] = data
	self:IncrementVersion(TranslatedChan,Main)
	Lib.Dbg:Debug(LOG_LEVEL.NORMAL,"New Data for user " .. Main .. " in chan " .. TranslatedChan .. " with prefix " .. prefix)
end

function Ext:CopyAndSetData(chan,prefix,data)
	self:SetData(chan,prefix,deepcopy(data))
end

function Ext:GetData(chan,user,prefix)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if Ext:ExistsUserPrefixEntry(TranslatedChan,user,prefix) == false then
		return nil
	end
	return Lib.Db[TranslatedChan]["Data"][self:GetMain(TranslatedChan,user)]["Data"][prefix]
end

function Ext:GetChanData(chan,prefix,includeSelf)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if not self:ExistsChannelEntry(TranslatedChan) then
		return nil
	end
	local main = self:GetMain(TranslatedChan,nil)
	local ret = {}
	for user,data in pairs(Lib.Db[TranslatedChan]["Data"]) do
		if (includeSelf == true or (user ~= main and user ~= Lib.Const.SelfPlayerName)) and
		  self:ExistsUserPrefixEntry(TranslatedChan,user,prefix) then
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

function Ext:SetLoadedCallback(func,param,dontCallWhenAlreadyLoaded)
	if Lib.LoadedCallbacks == nil then
		if dontCallWhenAlreadyLoaded ~= true then
			func(param)
		end
		return false
	end
	Lib.LoadedCallbacks[func] = param
	return true
end

function Ext:SetMyMain(chan,main)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if self:ExistsUserEntry(TranslatedChan,main) ~= true then
		return false
	end
	if main == nil then
		main = Lib.Const.SelfPlayerName
	end
	Lib.Db[TranslatedChan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Main"] = main
	--[[--
	for prefix,_ in pairs(Lib.Db[TranslatedChan]["Data"][Lib.Const.SelfPlayerName]["Data"]) do
		if prefix ~= Lib.Const.ConfigVersion then
			Lib.Db[TranslatedChan]["Data"][Lib.Const.SelfPlayerName]["Data"][prefix] = nil
		end
	end
	--]]--
	return true
end

function Ext:GetMain(chan,user)
	if user == nil then
		user = Lib.Const.SelfPlayerName
	end
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if self:ExistsUserPrefixEntry(TranslatedChan,user,Lib.Const.ConfigVersion) ~= true then
		return user
	end
	return Lib.Db[TranslatedChan]["Data"][user]["Data"][Lib.Const.ConfigVersion]["Main"]
end

function Ext:AddTwink(chan,twink)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if self:ExistsChannelEntry(TranslatedChan) ~= true then
		return false
	end
	Lib.Db[TranslatedChan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Twinks"][twink]  = true
	self:IncrementVersion(TranslatedChan,Lib.Const.SelfPlayerName)
	return true
end

function Ext:DelTwink(chan,twink)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if self:ExistsChannelEntry(TranslatedChan) ~= true then
		return false
	end
	Lib.Db[TranslatedChan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Twinks"][twink]  = nil
	self:IncrementVersion(TranslatedChan,Lib.Const.SelfPlayerName)
	return true
end

function Ext:GetTwinks(chan)
	local TranslatedChan = Lib:ExternToInternChan(chan)
	if self:ExistsChannelEntry(TranslatedChan) ~= true then
		return nil
	end
	return deepcopy(Lib.Db[TranslatedChan]["Data"][Lib.Const.SelfPlayerName]["Data"][Lib.Const.ConfigVersion]["Twinks"])
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
