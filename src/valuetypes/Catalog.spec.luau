--!strict

--[[
	Teste da task-valuetypes-002 (Catalog.luau -- lista fechada de todo global de valor do
	Roblox). Cobre: os 37 nomes esperados (23 originais + 14 da seção 0.8 do desenho), a flag
	`HasGlobalConstructor` correta nos quatro nomes do grupo "sem construtor original" (dois
	realmente sem, dois com), e a garantia de disjunção entre
	`SimulatedNames()`/`UnsimulatedGlobalNames()` pedida pelo acceptance da task
	("Catalog.UnsimulatedGlobalNames() não intersecta Catalog.SimulatedNames()").

	task-valuetypes-002-fix (achado ALTO de
	.claude/agents-memory/revisor-valuetypes-userdata-2026-09-05.md): `SharedTable` e `Content`
	estavam marcados `HasGlobalConstructor = false` por engano -- corrigido para `true` em
	Catalog.luau e neste spec. Fonte da correção, doc oficial da Roblox
	(create.roblox.com/docs/reference/engine/datatypes/SharedTable e .../Content):
	`SharedTable.new()`/`SharedTable.new(t: table)`; `Content.fromUri(uri)`,
	`Content.fromAssetId(id)`, `Content.fromObject(obj)`, `Content.none` -- todos chamáveis por um
	script comum. `Secret` (só chega via `HttpService:GetSecret(...)`) e `RaycastResult` (só
	devolvido por `WorldRoot:Raycast(...)`) continuam `HasGlobalConstructor = false` -- nenhum dos
	dois tem construtor/função estática chamável por script comum na doc oficial.

	ATUALIZAÇÃO (task-valuetypes-003, `Enum`): `Catalog.luau` teve a entrada `Enum` virada
	`Simulated = true` (cabeçalho do próprio arquivo já prescrevia isso: "task-valuetypes-003 em
	diante vão editar ESTE arquivo, virando Simulated = true nome a nome conforme cada
	types/*.luau for escrito"). Os testes abaixo que antes assumiam "TODAS as entradas têm
	Simulated = false" e "exatamente 35 nomes em UnsimulatedGlobalNames()" foram trocados por
	versões que checam SÓ o que esta tarefa muda (`Enum`) -- de propósito, para não ficarem
	acopladas (e frágeis/flaky) ao momento exato em que as tarefas IRMÃS paralelas desta mesma leva
	(`task-valuetypes-004`: Vector3/Vector2; `task-valuetypes-005`: Color3/UDim/UDim2 -- mesmo
	agente `coder-valuetypes`, mesmo arquivo `Catalog.luau`, rodando em paralelo) também viram
	`Simulated = true` suas próprias entradas. As invariantes ESTRUTURAIS (37 entradas, sem
	duplicata, disjunção Simulated/Unsimulated, `HasGlobalConstructor` dos grupos fixos) continuam
	tal como antes -- essas não mudam com o que as tarefas irmãs fazem.

	Roda com `lune run src/valuetypes/Catalog.spec.luau`.
]]

local process = require("@lune/process")
local fs = require("@lune/fs")
local Catalog = require("./Catalog")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local function toSet(names: { string }): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, name in names do
		set[name] = true
	end
	return set
end

-- Os 23 nomes originais de src/cli/UnsimulatedGlobals.luau (ver cabeçalho de Catalog.luau).
local ORIGINAL_23: { string } = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"DateTime",
	"Enum",
	"Faces",
	"Font",
	"NumberRange",
	"NumberSequence",
	"OverlapParams",
	"PhysicalProperties",
	"Random",
	"Ray",
	"RaycastParams",
	"Rect",
	"Region3",
	"TweenInfo",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector3",
}

-- Os 14 nomes novos da seção 0.8 do desenho, 12 com construtor global (SharedTable e Content
-- corrigidos em task-valuetypes-002-fix -- ver cabeçalho deste spec).
local NEW_WITH_CONSTRUCTOR_12: { string } = {
	"NumberSequenceKeypoint",
	"ColorSequenceKeypoint",
	"Vector3int16",
	"Vector2int16",
	"Region3int16",
	"PathWaypoint",
	"CatalogSearchParams",
	"FloatCurveKey",
	"RotationCurveKey",
	"Path2DControlPoint",
	"SharedTable",
	"Content",
}

-- Os 2 nomes novos SEM construtor global (confirmado contra a doc oficial -- ver cabeçalho).
local NEW_WITHOUT_CONSTRUCTOR_2: { string } = {
	"Secret",
	"RaycastResult",
}

test("Catalog.All() devolve exatamente 37 entradas (23 originais + 14 da seção 0.8)", function()
	local all = Catalog.All()
	assert(#all == 37, `esperava 37 entradas, recebeu {#all}`)
end)

test("Catalog.All() não tem nomes duplicados", function()
	local seen: { [string]: boolean } = {}
	for _, entry in Catalog.All() do
		assert(not seen[entry.Name], `nome duplicado no catálogo: {entry.Name}`)
		seen[entry.Name] = true
	end
end)

test("todos os 23 nomes originais estão presentes com HasGlobalConstructor = true", function()
	local byName: { [string]: Catalog.CatalogEntry } = {}
	for _, entry in Catalog.All() do
		byName[entry.Name] = entry
	end

	for _, name in ORIGINAL_23 do
		local entry = byName[name]
		assert(entry ~= nil, `nome original ausente do catálogo: {name}`)
		assert(entry.HasGlobalConstructor, `{name} deveria ter HasGlobalConstructor = true`)
	end
end)

test("os 12 nomes novos COM construtor global estão presentes e marcados corretamente", function()
	local byName: { [string]: Catalog.CatalogEntry } = {}
	for _, entry in Catalog.All() do
		byName[entry.Name] = entry
	end

	for _, name in NEW_WITH_CONSTRUCTOR_12 do
		local entry = byName[name]
		assert(entry ~= nil, `nome novo (com construtor) ausente do catálogo: {name}`)
		assert(entry.HasGlobalConstructor, `{name} deveria ter HasGlobalConstructor = true`)
	end
end)

test("os 2 nomes novos SEM construtor global estão presentes e marcados corretamente", function()
	local byName: { [string]: Catalog.CatalogEntry } = {}
	for _, entry in Catalog.All() do
		byName[entry.Name] = entry
	end

	for _, name in NEW_WITHOUT_CONSTRUCTOR_2 do
		local entry = byName[name]
		assert(entry ~= nil, `nome novo (sem construtor) ausente do catálogo: {name}`)
		assert(not entry.HasGlobalConstructor, `{name} deveria ter HasGlobalConstructor = false`)
	end
end)

-- Teste dedicado da task-valuetypes-002-fix (acceptance: "teste novo em Catalog.spec.luau
-- confirmando os 4 valores (2 true, 2 false) e citando a fonte (doc oficial) no comentário").
-- Fonte: create.roblox.com/docs/reference/engine/datatypes/SharedTable,
-- create.roblox.com/docs/reference/engine/datatypes/Content,
-- create.roblox.com/docs/reference/engine/datatypes/Secret,
-- create.roblox.com/docs/reference/engine/datatypes/RaycastResult (doc oficial da Roblox,
-- confirmada pelo revisor-valuetypes em .claude/agents-memory/revisor-valuetypes-userdata-2026-09-05.md).
test("HasGlobalConstructor dos 4 nomes do grupo original 'sem construtor' bate com a doc oficial", function()
	local byName: { [string]: Catalog.CatalogEntry } = {}
	for _, entry in Catalog.All() do
		byName[entry.Name] = entry
	end

	-- SharedTable.new() / SharedTable.new(t: table) -- chamável por script comum.
	assert(byName["SharedTable"].HasGlobalConstructor == true, "SharedTable deveria ter HasGlobalConstructor = true (SharedTable.new)")
	-- Content.fromUri(uri) / Content.fromAssetId(id) / Content.fromObject(obj) / Content.none.
	assert(byName["Content"].HasGlobalConstructor == true, "Content deveria ter HasGlobalConstructor = true (Content.fromUri/fromAssetId/fromObject/none)")
	-- Secret só chega via HttpService:GetSecret(...) -- sem construtor/função estática global.
	assert(byName["Secret"].HasGlobalConstructor == false, "Secret deveria ter HasGlobalConstructor = false (só via HttpService:GetSecret)")
	-- RaycastResult só é devolvido por WorldRoot:Raycast(...) -- sem construtor/função estática global.
	assert(byName["RaycastResult"].HasGlobalConstructor == false, "RaycastResult deveria ter HasGlobalConstructor = false (só via WorldRoot:Raycast)")
end)

test("Enum tem Simulated = true a partir desta tarefa (task-valuetypes-003, types/Enum.luau existe)", function()
	local byName: { [string]: Catalog.CatalogEntry } = {}
	for _, entry in Catalog.All() do
		byName[entry.Name] = entry
	end
	assert(byName["Enum"].Simulated == true, "Enum deveria ter Simulated = true (types/Enum.luau existe)")
	assert(byName["Enum"].HasGlobalConstructor == true, "Enum continua tendo HasGlobalConstructor = true")
end)

test("Catalog.SimulatedNames() contém 'Enum'", function()
	local set = toSet(Catalog.SimulatedNames())
	assert(set["Enum"], "SimulatedNames() deveria conter 'Enum'")
end)

test("Catalog.UnsimulatedGlobalNames() NÃO contém mais 'Enum' (virou Simulated = true)", function()
	local set = toSet(Catalog.UnsimulatedGlobalNames())
	assert(not set["Enum"], "UnsimulatedGlobalNames() não deveria mais conter 'Enum'")
end)

test("Catalog.UnsimulatedGlobalNames() nunca inclui um nome que está em SimulatedNames() (ex.: os outros 34 originais/novos-com-construtor, se ainda não simulados)", function()
	-- Versão fraca de propósito (não fixa uma contagem exata) -- ver nota no cabeçalho sobre as
	-- tarefas IRMÃS paralelas (-004/-005) também mexendo neste mesmo Catalog.luau. A garantia real
	-- (disjunção completa) já é coberta pelo teste dedicado mais abaixo.
	local simulated = toSet(Catalog.SimulatedNames())
	local unsimulated = toSet(Catalog.UnsimulatedGlobalNames())
	for _, name in ORIGINAL_23 do
		if name ~= "Enum" and not simulated[name] then
			assert(unsimulated[name], `{name} deveria estar em UnsimulatedGlobalNames() (ainda não simulado)`)
		end
	end
end)

test("Catalog.UnsimulatedGlobalNames() NUNCA contém os 2 nomes sem construtor global", function()
	local set = toSet(Catalog.UnsimulatedGlobalNames())
	for _, name in NEW_WITHOUT_CONSTRUCTOR_2 do
		assert(not set[name], `UnsimulatedGlobalNames() não deveria conter {name} (Roblox real não expõe como global)`)
	end
end)

test("Catalog.UnsimulatedGlobalNames() não intersecta Catalog.SimulatedNames() (acceptance da task)", function()
	local simulated = toSet(Catalog.SimulatedNames())
	local unsimulated = toSet(Catalog.UnsimulatedGlobalNames())

	for name in simulated do
		assert(not unsimulated[name], `{name} aparece nos dois grupos -- violação da disjunção exigida`)
	end
	for name in unsimulated do
		assert(not simulated[name], `{name} aparece nos dois grupos -- violação da disjunção exigida`)
	end
end)

test("Catalog.All() devolve uma cópia nova a cada chamada (mutar o resultado não afeta o catálogo interno)", function()
	local first = Catalog.All()
	table.insert(first, { Name = "Fantasma", Simulated = true, HasGlobalConstructor = true })
	assert(#first == 38, "sanity check: a cópia local deveria ter crescido pra 38")

	local second = Catalog.All()
	assert(#second == 37, `mutar a cópia anterior não deveria afetar chamadas seguintes, recebeu {#second}`)

	local found = false
	for _, entry in second do
		if entry.Name == "Fantasma" then
			found = true
		end
	end
	assert(not found, "\"Fantasma\" não deveria vazar para uma nova chamada de Catalog.All()")
end)

test("cada CatalogEntry devolvida está congelada (defesa em profundidade)", function()
	for _, entry in Catalog.All() do
		assert(table.isfrozen(entry), `entrada de {entry.Name} deveria estar congelada`)
	end
end)

-- Teste de coerência da task-valuetypes-005-fix: Catalog.luau é um arquivo efetivamente
-- COMPARTILHADO entre as tarefas paralelas da leva 40 (Enum/Vector3+Vector2/Color3+UDim+UDim2) --
-- só a entrada "Enum" tinha virado `Simulated = true` quando as outras 5 (Vector3/Vector2/Color3/
-- UDim/UDim2) já tinham `types/*.luau` implementado e aprovado. Este teste varre o diretório
-- `types/` de verdade (via `fs.readDir`, não uma lista à mão que poderia ficar desatualizada do
-- mesmo jeito que o drift original) e falha se QUALQUER `types/<Nome>.luau` existir sem a
-- respectiva entrada do Catalog em `Simulated = true` -- evita repetir esse drift no futuro
-- conforme `task-valuetypes-006` (CFrame) e as demais forem implementadas.
test("toda entrada com um types/*.luau real no território tem Simulated = true (evita drift entre coders paralelos)", function()
	local typesDir = process.cwd .. "src/valuetypes/types"
	local entries = fs.readDir(typesDir)

	local byName: { [string]: Catalog.CatalogEntry } = {}
	for _, entry in Catalog.All() do
		byName[entry.Name] = entry
	end

	local checkedCount = 0
	for _, fileName in entries do
		-- Só módulo de tipo propriamente dito: ignora "*.spec.luau" (teste) e qualquer arquivo que
		-- não seja um `.luau` 1:1 com o nome de uma entrada do catálogo (ex.: futuro helper interno
		-- do território que não corresponda a um datatype global).
		local isSpec = string.match(fileName, "%.spec%.luau$") ~= nil
		local typeName = if isSpec then nil else string.match(fileName, "^(.*)%.luau$")

		if typeName ~= nil then
			local entry = byName[typeName]
			assert(entry ~= nil, `types/{fileName} não corresponde a nenhuma entrada de Catalog (nome esperado "{typeName}")`)
			assert(
				entry.Simulated,
				`{typeName} tem types/{fileName} implementado mas Catalog.luau ainda diz Simulated = false -- drift entre coders paralelos`
			)
			checkedCount += 1
		end
	end

	-- Sanity check: garante que o teste examinou algo de verdade -- passaria vazio (falso
	-- positivo) se `fs.readDir` apontasse pra um diretório errado ou viesse vazio.
	assert(checkedCount > 0, "nenhum types/*.luau encontrado -- teste de coerência não verificou nada")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
