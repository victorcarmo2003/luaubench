--!strict
-- ARQUIVO GERADO por tools/generate-services.luau — NÃO EDITAR À MÃO.
-- Roblox API Dump: MaximumADHD/Roblox-Client-Tracker @ 28360dea4b90b35dc3fe9f829baae64fb6c50e75
-- Versão Roblox: 0.737.0.7371584 | esquema do dump: Version 1
-- Regenerar: lune run tools/generate-services

-- Requires LITERAIS -- o `require` do Lune resolve estaticamente, não há require dinâmico
-- por string (Decisão 1 do desenho). `src/services/init.luau` é quem itera este mapa.

local Types = require("../Types")

local Index: { [string]: Types.GeneratedClass } = {
	["BasePlayerGui"] = require("./classes/BasePlayerGui") :: Types.GeneratedClass,
	["BaseScript"] = require("./classes/BaseScript") :: Types.GeneratedClass,
	["DataStore"] = require("./classes/DataStore") :: Types.GeneratedClass,
	["DataStoreGetOptions"] = require("./classes/DataStoreGetOptions") :: Types.GeneratedClass,
	["DataStoreIncrementOptions"] = require("./classes/DataStoreIncrementOptions") :: Types.GeneratedClass,
	["DataStoreInfo"] = require("./classes/DataStoreInfo") :: Types.GeneratedClass,
	["DataStoreKeyInfo"] = require("./classes/DataStoreKeyInfo") :: Types.GeneratedClass,
	["DataStoreKeyPages"] = require("./classes/DataStoreKeyPages") :: Types.GeneratedClass,
	["DataStoreListingPages"] = require("./classes/DataStoreListingPages") :: Types.GeneratedClass,
	["DataStoreObjectVersionInfo"] = require("./classes/DataStoreObjectVersionInfo") :: Types.GeneratedClass,
	["DataStoreOptions"] = require("./classes/DataStoreOptions") :: Types.GeneratedClass,
	["DataStorePages"] = require("./classes/DataStorePages") :: Types.GeneratedClass,
	["DataStoreService"] = require("./classes/DataStoreService") :: Types.GeneratedClass,
	["DataStoreSetOptions"] = require("./classes/DataStoreSetOptions") :: Types.GeneratedClass,
	["DataStoreVersionPages"] = require("./classes/DataStoreVersionPages") :: Types.GeneratedClass,
	["Folder"] = require("./classes/Folder") :: Types.GeneratedClass,
	["GlobalDataStore"] = require("./classes/GlobalDataStore") :: Types.GeneratedClass,
	["HttpService"] = require("./classes/HttpService") :: Types.GeneratedClass,
	["Instance"] = require("./classes/Instance") :: Types.GeneratedClass,
	["Lighting"] = require("./classes/Lighting") :: Types.GeneratedClass,
	["LocalScript"] = require("./classes/LocalScript") :: Types.GeneratedClass,
	["LuaSourceContainer"] = require("./classes/LuaSourceContainer") :: Types.GeneratedClass,
	["MessagingService"] = require("./classes/MessagingService") :: Types.GeneratedClass,
	["Model"] = require("./classes/Model") :: Types.GeneratedClass,
	["ModuleScript"] = require("./classes/ModuleScript") :: Types.GeneratedClass,
	["OrderedDataStore"] = require("./classes/OrderedDataStore") :: Types.GeneratedClass,
	["PVInstance"] = require("./classes/PVInstance") :: Types.GeneratedClass,
	["Pages"] = require("./classes/Pages") :: Types.GeneratedClass,
	["PhysicsService"] = require("./classes/PhysicsService") :: Types.GeneratedClass,
	["Players"] = require("./classes/Players") :: Types.GeneratedClass,
	["ReplicatedFirst"] = require("./classes/ReplicatedFirst") :: Types.GeneratedClass,
	["ReplicatedStorage"] = require("./classes/ReplicatedStorage") :: Types.GeneratedClass,
	["RunService"] = require("./classes/RunService") :: Types.GeneratedClass,
	["Script"] = require("./classes/Script") :: Types.GeneratedClass,
	["ServerScriptService"] = require("./classes/ServerScriptService") :: Types.GeneratedClass,
	["ServerStorage"] = require("./classes/ServerStorage") :: Types.GeneratedClass,
	["StarterCharacterScripts"] = require("./classes/StarterCharacterScripts") :: Types.GeneratedClass,
	["StarterGui"] = require("./classes/StarterGui") :: Types.GeneratedClass,
	["StarterPack"] = require("./classes/StarterPack") :: Types.GeneratedClass,
	["StarterPlayer"] = require("./classes/StarterPlayer") :: Types.GeneratedClass,
	["StarterPlayerScripts"] = require("./classes/StarterPlayerScripts") :: Types.GeneratedClass,
	["Workspace"] = require("./classes/Workspace") :: Types.GeneratedClass,
	["WorldRoot"] = require("./classes/WorldRoot") :: Types.GeneratedClass,
}

return Index
