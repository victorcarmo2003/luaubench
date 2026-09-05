--!strict

--[[
	Módulo folha: os filhos que o MOTOR simulado do LuauBench pré-cria dentro de uma instância de
	uma classe-pai específica -- dados puros mais dois acessores, SEM I/O, SEM `Context`, SEM
	`Runtime.ClassRegistry`. Ver .claude/agents-memory/arquiteto-cli-2026-09-05.md, seção "Revisão
	pós-implementação 2026-09-05 (task-cli-015) -- filho fixo do motor: adotar, não criar",
	subseções "Onde vive a lista fechada" e "Módulos" -> "src/services/EngineFixedChildren.luau".

	NÃO é a mesma lista que `src/cli/SyncRules.FIXED_CHILD_CLASS_NAMES` -- são dois FATOS
	DIFERENTES, com donos diferentes (tabela comparativa completa na seção "Onde vive a lista
	fechada" do desenho):
	- `SyncRules` responde "que `ClassName` o FORMATO ROJO infere para um nó chamado X sob um pai
	  de classe Y?" -- fonte: o código-fonte do Rojo. Dono: `cli`.
	- Este módulo responde "que filhos o MOTOR do LuauBench pré-cria dentro de uma instância da
	  classe Y, e com que `ClassName`?" -- fonte: `src/services/behavior/**`, o que `Initialize` de
	  fato cria. Dono: `services`.
	As duas JÁ divergem hoje, de propósito: `Workspace -> Terrain` está em `SyncRules` (o Rojo real
	infere isso) mas NÃO está aqui (`Covered = false` em `generated/Manifest.luau`, não existe
	`behavior/Workspace.luau` -- declarar `Terrain` aqui faria `cli` procurar, via
	`EngineFixedChildren.Is`, um filho que o motor nunca cria).

	DIVERGÊNCIA DE FIDELIDADE DECLARADA (regra 00: nunca silenciosa): no Roblox real, os filhos
	listados aqui são PROPRIEDADE DO MOTOR -- um script não consegue `Destroy()`/reparentar
	`StarterPlayerScripts` para fora de `StarterPlayer` (o motor recria/protege). No LuauBench, a
	instância que `behavior/StarterPlayer.luau` cria via `Runtime.ClassRegistry.NewEngineInstance`
	é uma `Runtime.Instance` simulada comum -- `Destroy()`/reparent funcionam normalmente, sem essa
	proteção. Aceito nesta fase (implementar a proteção exigiria um novo conceito em `runtime`, fora
	do desenho desta tarefa) -- não implementado silenciosamente como se fosse fiel.

	Consumidores (dentro do território `services`, único): `behavior/StarterPlayer.luau` (CRIA, via
	`EngineFixedChildren.Of`) e `init.luau` (RESPONDE à pergunta "isto é um filho fixo do motor?",
	via `EngineFixedChildren.Is`, reexportada como `Services.IsEngineFixedChild` -- a ÚNICA coisa que
	`cli` enxerga deste módulo; `Of` fica interno, `cli` não tem uso legítimo para a lista completa).
	Mesmo módulo alimentando os dois papéis: impossível `services` afirmar pré-criar algo que seu
	próprio `Initialize` não cria.
]]

export type EngineFixedChild = {
	Name: string,
	ClassName: string,
}

-- Ordem do array É a ordem de criação (espelha a ordem usual do Explorer do Studio) -- ver o
-- comentário de `behavior/StarterPlayer.luau` sobre por que essa ordem não é uma garantia formal
-- do Roblox real, mas é estável e sem efeito observável.
--
-- `Workspace`/`Terrain` NÃO entra: `Covered = false` no manifesto, não existe
-- `behavior/Workspace.luau` -- uma entrada aqui é uma AFIRMAÇÃO de que a instância existe de
-- verdade (ver cabeçalho acima).
local ENGINE_FIXED_CHILDREN: { [string]: { EngineFixedChild } } = {
	StarterPlayer = {
		{ Name = "StarterPlayerScripts", ClassName = "StarterPlayerScripts" },
		{ Name = "StarterCharacterScripts", ClassName = "StarterCharacterScripts" },
	},
}

local EngineFixedChildren = {}

-- Filhos fixos do motor para `parentClassName`, na ordem em que devem ser criados. Devolve `{}`
-- (nunca `nil`) para uma classe sem filhos fixos declarados -- quem consome (`behavior/**`, um
-- `for _, child in EngineFixedChildren.Of(...)`) não precisa de um `if ~= nil` prévio.
function EngineFixedChildren.Of(parentClassName: string): { EngineFixedChild }
	return ENGINE_FIXED_CHILDREN[parentClassName] or {}
end

-- `true` só quando o TRIO (pai, nome, classe) bate exatamente uma entrada declarada -- exigir Name
-- E ClassName juntos (não só ClassName) é o que mantém fiel o caso `"MyScripts": { "$className":
-- "StarterPlayerScripts" }` sob `StarterPlayer`: o predicado devolve `false`, e quem chama (`cli`,
-- via `Services.IsEngineFixedChild`) cai no caminho normal de criação, que erra
-- `Unable to create an Instance of type "StarterPlayerScripts"` -- exatamente o que o Roblox real
-- faria, sem nenhum caso especial escrito para isso.
function EngineFixedChildren.Is(parentClassName: string, name: string, className: string): boolean
	local children = ENGINE_FIXED_CHILDREN[parentClassName]
	if children == nil then
		return false
	end

	for _, child in children do
		if child.Name == name and child.ClassName == className then
			return true
		end
	end

	return false
end

return EngineFixedChildren
