--!strict

--[[
	Lista de classes-alvo da primeira leva de `services` -- a ÚNICA entrada humana do gerador
	(tools/generate-services.luau). O FECHO de superclasses é calculado automaticamente pelo
	gerador andando `Superclass` no Roblox API Dump até "Instance" -- NÃO listar aqui WorldRoot/
	Model/PVInstance (puxados a partir de Workspace) nem BasePlayerGui (puxado a partir de
	StarterGui). Ver .claude/agents-memory/arquiteto-services-2026-09-05.md, "Decisão 1 -- Fecho
	transitivo automático" e "Decisão 5 -- Escopo da primeira leva".

	Lista exata da leva 1 (task-services-002), na ordem em que a tarefa do board a enumera:
	árvore básica do Rojo + Scripts + Workspace/Lighting + RunService/Players.
]]

local Coverage: { string } = {
	"Instance",

	-- Contêineres da árvore Rojo
	"ReplicatedStorage",
	"ServerStorage",
	"ServerScriptService",
	"ReplicatedFirst",
	"StarterPack",
	"Folder",

	-- GUI/Player containers
	"StarterGui",
	"StarterPlayer",
	"StarterPlayerScripts",
	"StarterCharacterScripts",

	-- Scripts
	"LuaSourceContainer",
	"BaseScript",
	"Script",
	"LocalScript",
	"ModuleScript",

	-- Mundo / Ambiente
	"Workspace",
	"Lighting",

	-- Comportamento real
	"RunService",
	"Players",
}

return Coverage
