
local Lib = LibStub:NewLibrary("LibDbg", 1)

LibDbg = {}

LibDbg.DebugChatFrame = nil

LibDbg.LOG_LEVEL = {}
LibDbg.LOG_LEVEL.DATA = 50
LibDbg.LOG_LEVEL.INFO = 30
LibDbg.LOG_LEVEL.NORMAL = 20
LibDbg.LOG_LEVEL.ERROR = 10
LibDbg.LOG_LEVEL.NONE = 0

Lib.DebugLevel = LibDbg.LOG_LEVEL.NONE
Lib.ChatPrefix = "LibDbg"

local function BasicInit()
	local function _FindDebugChatFrame()
		for i=1, NUM_CHAT_WINDOWS do
			if GetChatWindowInfo(i):lower() == "debug" and tContains( { GetChatWindowMessages(i) } ,"ERRORS") then
				local PrintMessage = false
				if LibDbg.DebugChatFrame == nil then
					PrintMessage = true
				end
				LibDbg.DebugChatFrame = getglobal("ChatFrame"..i)
				if PrintMessage == true then
					Lib:Debug(LibDbg.LOG_LEVEL.NONE,"Found Debug ChatFrame: ChatFrame" .. i)
				end
				return
			end
		end
		if LibDbg.DebugChatFrame ~= nil then
			Lib:Debug(LibDbg.LOG_LEVEL.NONE,"Lost Debug ChatFrame.")
		end
		LibDbg.DebugChatFrame = nil
	end
	local function _OpenNewWindowHook(name)
		_FindDebugChatFrame()
	end
	local function _PopInWindowHook(frame,fallbackFrame)
		_FindDebugChatFrame()
	end
	local function _ToggleChatMessageGroupHook(checked,chatMsgType)
		_FindDebugChatFrame()
	end
	local function _OpenChatHook(text,chatFrame)
		_FindDebugChatFrame()
	end
	--hooksecurefunc("FCF_OpenNewWindow",_OpenNewWindowHook)
	--hooksecurefunc("FCF_PopInWindow",_PopInWindowHook)
	hooksecurefunc("ToggleChatMessageGroup",_ToggleChatMessageGroupHook)
	hooksecurefunc("ChatFrame_OpenChat",_OpenChatHook)
	_FindDebugChatFrame()
end

function Lib:ConvertToText(Data)
	if type(Data) == "table" then
		local OutText = "{ "
		for key,value in pairs(Data) do
			OutText = OutText .. self:ConvertToText(key) .. " = " .. self:ConvertToText(value) .. ", "
		end
		OutText = OutText .. " } "
		return OutText
	elseif type(Data) == "boolean" then
		if Data == true then
			return "true"
		else
			return "false"
		end
	elseif Data == nil then
		return "nil"
	else
		return Data
	end
end

function Lib:Debug(DebugLevel, ...)
	if self:IsLogging(DebugLevel) ~= true then
		return
	end

	local OutText = ""

	local FirstArg = true
	local NumArgs = select("#", ...)
	for i = 1, NumArgs do
		local Temp = self:ConvertToText(select(i, ...))
		if FirstArg == false then
			OutText = OutText .. " , "
		end
		FirstArg = false
		OutText = OutText .. Temp
	end

	LibDbg.DebugChatFrame:AddMessage("|cff00ff9a" .. self.ChatPrefix .. ":|r " .. OutText, 0.4588, 0.7843, 1)
end

function Lib:IsLogging(DebugLevel)
	return self.DebugLevel >= DebugLevel and LibDbg.DebugChatFrame ~= nil
end

function Lib:Embed(Target)
	local MixIns = {"ConvertToText","IsLogging","Debug","DebugLevel","ChatPrefix"}
	for _,name in pairs(MixIns) do
		Target[name] = self[name]
	end
end


BasicInit()
