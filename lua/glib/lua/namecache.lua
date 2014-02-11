local self = {}
GLib.Lua.NameCache = GLib.MakeConstructor (self)

function self:ctor ()
	local state = {}
	state.NameCache = GLib.WeakKeyTable ()
	state.QueuedTables = GLib.WeakKeyTable ()
	
	state.QueueTables = {}
	state.QueueTableNames = {}
	state.QueueSeparators = {}
	
	self.GetState = function (self)
		return state
	end
	
	self.Thread = nil
	
	self:GetState ().NameCache [_G] = "_G"
	self:GetState ().NameCache [debug.getregistry ()] = "_R"
	
	self:Index (GLib, "GLib")
	self:Index (_G, "")
	self:Index (debug.getregistry (), "_R")
	
	hook.Add ("GLibSystemLoaded", "GLib.Lua.NameCache",
		function (systemName)
			print ("GLib.Lua.NameCache : Queued " .. systemName .. " for indexing.")
			self:Index (_G [systemName], systemName)
		end
	)
end

function self:GetFunctionName (func)
	return self:GetState ().NameCache [func]
end

function self:GetObjectName (object)
	return self:GetState ().NameCache [object]
end

function self:GetTableName (table)
	return self:GetState ().NameCache [table]
end

function self:IsIndexingThreadRunning ()
	if not self.Thread then return false end
	
	return not self.Thread:IsTerminated ()
end

function self:Index (table, tableName, dot)
	self:QueueIndex (table, tableName, dot)
	
	if not self:IsIndexingThreadRunning () then
		self:StartIndexingThread ()
	end
end

local tableNameBlacklist =
{
	["chatsounds.ac.words"] = true,
	["chatsounds.List"] = true,
	["chatsounds.SortedList"] = true,
	["chatsounds.SortedList2"] = true,
	["chatsounds.SortedListKeys"] = true,
	["GAuth.Groups"] = true,
	["GLib.Loader.PackFileManager.MergedPackFileSystem.Root"] = true,
	["GLib.Lua.FunctionCache"] = true,
	["GCompute.GlobalNamespace"] = true,
	["GCompute.IDE.Instance.DocumentManager"] = true,
	["GCompute.IDE.Instance.ViewManager"] = true,
	["GCompute.LanguageDetector.Extensions"] = true,
	["GCompute.Languages.Languages.GLua.EditorHelper.RootNamespace"] = true,
	["GCompute.TypeSystem"] = true,
	["pac.ActiveParts"] = true,
	["pace.example_outfits"] = true,
	["VFS.RealRoot"] = true,
	["VFS.Root"] = true
}

local numericTableNameBlacklist =
{
	["_R"] = true
}

function self:ProcessTable (table, tableName, dot)
	if tableNameBlacklist [tableName] then return end
	local numericBlacklisted = numericTableNameBlacklist [tableName]
	
	local state = self:GetState ()
	local nameCache = state.NameCache
	local queuedTables = state.QueuedTables
	
	for k, v in pairs (table) do
		GLib.CheckYield ()
		
		local keyType = type (k)
		local valueType = type (v)
		
		if not numericBlacklisted or
		   keyType ~= "number" then
			local memberName = nil
			
			if valueType == "function" or
			   valueType == "table" then
				if keyType == "string" and
				   not GLib.Lua.IsValidVariableName (k) then
					memberName = tableName .. " [" .. GLib.Lua.ToLuaString (k) .. "]"
				elseif keyType == "table" then
					-- ¯\_(ツ)_/¯
					memberName = tableName .. " [" .. GLib.Lua.ToCompactLuaString (k) .. "]"
				elseif keyType == "number" then
					memberName = tableName .. " [" .. GLib.Lua.ToLuaString (k) .. "]"
				else
					memberName = tableName ~= "" and (tableName .. dot .. tostring (k)) or tostring (k)
				end
				
				nameCache [v] = nameCache [v] or memberName
			end
			
			-- Recurse
			if valueType == "table" then
				if not queuedTables [v] then
					self:QueueIndex (v, memberName)
					
					-- Check if this is a GLib class
					if GLib.IsStaticTable (v) then
						self:QueueIndex (GLib.GetMetaTable (v), memberName, ":")
					end
				end
			end
		end
	end
end

function self:QueueIndex (table, tableName, dot)
	if type (table) ~= "table" then
		return
	end
	
	dot = dot or "."
	
	local state = self:GetState ()
	
	if state.QueuedTables [table] then return end
	
	state.QueuedTables [table] = true
	state.QueueTables [#state.QueueTables + 1] = table
	state.QueueTableNames [#state.QueueTableNames + 1] = tableName
	state.QueueSeparators [#state.QueueSeparators + 1] = dot
end

function self:StartIndexingThread ()
	if self.Thread and not self.Thread:IsTerminated () then
		return
	end
	
	print ("GLib.Lua.NameCache : Indexing thread started.")
	
	self.Thread = GLib.Threading.Thread ()
	self.Thread:Start (
		function ()
			GLib.Sleep (1000)
			
			local state = self:GetState ()
			
			while #state.QueueTables > 0 do
				GLib.CheckYield ()
				
				local t = state.QueueTables [1]
				local tableName = state.QueueTableNames [1]
				local separator = state.QueueSeparators [1]
				
				table.remove (state.QueueTables, 1)
				table.remove (state.QueueTableNames, 1)
				table.remove (state.QueueSeparators, 1)
				
				self:ProcessTable (t, tableName, separator)
			end
			
			print ("GLib.Lua.NameCache : Indexing took " .. GLib.FormatDuration (SysTime () - self.Thread:GetStartTime ()) .. ".")
		end
	)
end

GLib.Lua.NameCache = GLib.Lua.NameCache ()