--!strict

--[[
	Teste dedicado de `./Pages.luau` (regra 01: teste na mesma tarefa da lógica que cobre).
	Cobre o comportamento GENÉRICO de paginação (a fábrica `New` + `GetCurrentPage`/`IsFinished`/
	`AdvanceToNextPageAsync`), isolado de `DataStore.luau`/`Store.luau` -- este módulo não conhece
	nenhum dos dois (ver o cabeçalho de `Pages.luau`, "MODELO"). O fluxo end-to-end via
	`ListVersionsAsync`/`ListKeysAsync` de verdade (o "uso a garantir" da task, exercitando
	`ProfileVersionQuery`) é coberto em `./DataStore.spec.luau`.

	`AdvanceToNextPageAsync` tem a tag `Yields` no dump -- todo teste que o chama roda dentro de
	`scheduler:Spawn(...)` seguido de `scheduler:StepOnce(0)`, mesmo padrão de
	`GlobalDataStore.spec.luau`/`AsyncCall.spec.luau`.

	Roda com `lune run src/services/behavior/Pages.spec.luau`.
]]

local process = require("@lune/process")
local Runtime = require("../../runtime")
local Services = require("../")
local PagesBehavior = require("./Pages")

type Dynamic = { [string]: unknown }

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- `AsyncCall.Yield` (chamado por `AdvanceToNextPageAsync`) resolve o Scheduler via `Context`, que
-- só é semeado por `Services.Bootstrap` -- `Services.Register()` sozinho NÃO basta (achado desta
-- tarefa: sem isto, `Context.GetScheduler()` erra dentro da coroutine spawnada, o erro nunca é
-- observado pelo teste, `IsFinished` nunca avança, e o `while true` do teste de paginação entra em
-- loop infinito, estourando memória -- corrigido chamando Bootstrap como o resto do território já
-- faz, ver `GlobalDataStore.spec.luau`).
Services.Register()
local scheduler = Runtime.Scheduler.new()
local game = Runtime.DataModel.new()
Services.Bootstrap({ scheduler = scheduler, dataModel = game })

-- Chama `body` dentro de uma thread gerida pelo Scheduler e avança exatamente um passo -- basta
-- para o único `AsyncCall.Yield` que `AdvanceToNextPageAsync` faz (`Wait(0)`).
local function runAsync(body: () -> ()): ()
	scheduler:Spawn(body)
	scheduler:StepOnce(0)
end

-- `New` não faz parte de `Types.Behavior` -- alcançado direto via `require("./Pages")`, mesmo
-- padrão que `./DataStore.luau` usa de verdade. `newRaw` devolve `Runtime.Instance` de verdade
-- (o tipo natural de `Pages.New`); `new` (abaixo) só rebate isso pra `Dynamic`, via `unknown`
-- (cast direto de `Instance` pra `Dynamic`/`unknown` -- unrelacionados -- não é permitido; o
-- mesmo padrão de dois passos já usado em `GlobalDataStore.spec.luau`, ex.:
-- `(Runtime.ClassRegistry.NewEngineInstance(...) :: unknown) :: Dynamic`).
local newRaw = PagesBehavior.New :: (className: string, items: { unknown }, pageSize: number, hasCursorProperty: boolean, resumeCursor: string?) -> Runtime.Instance

local function new(className: string, items: { unknown }, pageSize: number, hasCursorProperty: boolean, resumeCursor: string?): Dynamic
	local instance = newRaw(className, items, pageSize, hasCursorProperty, resumeCursor)
	return (instance :: unknown) :: Dynamic
end

test("Pages.New com buffer menor que pageSize: 1 única página, já IsFinished == true", function()
	local pages = new("DataStoreVersionPages", { "a", "b", "c" }, 10, false, nil)
	assert(pages.IsFinished == true, "buffer inteiro cabe na 1a página -- deveria já estar IsFinished")

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local page = getCurrentPage(pages)
	assert(#page == 3, `esperava 3 itens na página, achou {#page}`)
	assert(page[1] == "a" and page[2] == "b" and page[3] == "c", "itens da página deveriam bater com o buffer, na ordem")
end)

test("Pages.New com buffer vazio: IsFinished == true de imediato, GetCurrentPage devolve {}", function()
	local pages = new("DataStoreVersionPages", {}, 10, false, nil)
	assert(pages.IsFinished == true, "buffer vazio deveria já estar IsFinished")

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	assert(#getCurrentPage(pages) == 0, "página de um buffer vazio deveria ser {}")
end)

test("paginar ATÉ IsFinished == true via GetCurrentPage/AdvanceToNextPageAsync: os itens de TODAS as páginas juntos batem com o total", function()
	local items: { unknown } = {}
	for i = 1, 25 do
		items[i] = i
	end
	local pages = new("DataStoreVersionPages", items, 10, false, nil)

	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local advance = pages.AdvanceToNextPageAsync :: (self: Dynamic) -> ()

	local collected: { unknown } = {}
	local pageCount = 0
	while true do
		local page = getCurrentPage(pages)
		for _, item in page do
			table.insert(collected, item)
		end
		pageCount += 1

		if pages.IsFinished == true then
			break
		end
		runAsync(function()
			advance(pages)
		end)
	end

	assert(pageCount == 3, `25 itens com pageSize=10 deveria dar 3 páginas (10+10+5), deu {pageCount}`)
	assert(#collected == 25, `os itens de todas as páginas juntos deveriam somar 25, somaram {#collected}`)
	for i = 1, 25 do
		assert(collected[i] == i, `item {i} deveria ser {i}, era {tostring(collected[i])} -- ordem/paginação corrompida`)
	end
end)

test("AdvanceToNextPageAsync chamado quando IsFinished == true ERRA (nunca no-op silencioso)", function()
	local pages = new("DataStoreVersionPages", { 1, 2 }, 10, false, nil)
	assert(pages.IsFinished == true, "buffer inteiro cabe na 1a página")

	local advance = pages.AdvanceToNextPageAsync :: (self: Dynamic) -> ()
	local ok = true
	local err: unknown = nil
	runAsync(function()
		ok, err = pcall(function()
			advance(pages)
		end)
	end)

	assert(ok == false, "AdvanceToNextPageAsync sobre a última página deveria erro")
	assert(
		string.find(tostring(err), "already the last page", 1, true) ~= nil,
		`mensagem deveria citar que já é a última página, recebeu: {err}`
	)
end)

test("GetCurrentPage devolve uma CÓPIA -- mutar o retorno não corrompe uma chamada seguinte", function()
	local pages = new("DataStoreVersionPages", { "x", "y" }, 10, false, nil)
	local getCurrentPage = pages.GetCurrentPage :: (self: Dynamic) -> { unknown }

	local firstCall = getCurrentPage(pages)
	table.insert(firstCall, "injected")

	local secondCall = getCurrentPage(pages)
	assert(#secondCall == 2, "mutar o retorno de GetCurrentPage não deveria afetar uma chamada seguinte")
end)

test("hasCursorProperty == false (DataStoreVersionPages): Cursor NÃO é escrito -- ler erra como membro inexistente do schema", function()
	local pages = new("DataStoreVersionPages", { 1 }, 10, false, nil)
	local ok, err = pcall(function()
		return pages.Cursor
	end)
	assert(not ok, "DataStoreVersionPages não declara Cursor no schema -- lê-lo deveria erro, não devolver algo")
	assert(
		string.find(tostring(err), "not a valid member", 1, true) ~= nil,
		`deveria erro de membro inexistente (schema não declara Cursor para DataStoreVersionPages), recebeu: {err}`
	)
end)

test("hasCursorProperty == true (DataStoreKeyPages): Cursor reflete o índice de resumo, e vira '' quando IsFinished", function()
	local items: { unknown } = {}
	for i = 1, 15 do
		items[i] = i
	end
	local pages = new("DataStoreKeyPages", items, 10, true, nil)

	-- Lidos em locais FRESCOS, com anotação explícita (`boolean`/`string`, não o `unknown` cru de
	-- `Dynamic`) -- ler `pages.IsFinished`/`pages.Cursor` de novo, MAIS ADIANTE, e comparar
	-- direto com um literal DIFERENTE do 1o `assert` faria o luau-lsp estreitar a expressão
	-- `pages.IsFinished` pro literal já provado (`false`/`"11"`) e recusar a 2a comparação como
	-- sempre-falsa ("Type false cannot be compared with true") -- achado desta tarefa, mesmo
	-- `pages` sendo uma tabela MUTÁVEL de verdade (o estreitamento do analisador estático não
	-- acompanha a mutação real que `AdvanceToNextPageAsync` faz por baixo).
	local isFinishedBefore = pages.IsFinished :: boolean
	assert(isFinishedBefore == false, "15 itens com pageSize=10 NÃO deveria já estar finished")
	local cursorBefore = pages.Cursor :: string
	assert(cursorBefore == "11", `Cursor deveria apontar pro início da próxima página (índice 11), achou {tostring(cursorBefore)}`)

	local advance = pages.AdvanceToNextPageAsync :: (self: Dynamic) -> ()
	runAsync(function()
		advance(pages)
	end)

	local isFinishedAfter = pages.IsFinished :: boolean
	assert(isFinishedAfter == true, "depois de avançar a 2a página (5 itens restantes) deveria estar finished")
	local cursorAfter = pages.Cursor :: string
	assert(cursorAfter == "", `Cursor deveria virar string vazia quando IsFinished, achou {tostring(cursorAfter)}`)
end)

test("resumeCursor: Pages.New com um cursor de uma consulta anterior COMEÇA a partir dali", function()
	local items: { unknown } = {}
	for i = 1, 20 do
		items[i] = i
	end

	-- Simula uma 1a chamada de ListKeysAsync (pageSize=5) que já rendeu um Cursor "6" -- uma 2a
	-- chamada com esse cursor deveria RETOMAR do item 6, não recomeçar do 1.
	local resumed = new("DataStoreKeyPages", items, 5, true, "6")
	local getCurrentPage = resumed.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local page = getCurrentPage(resumed)
	assert(page[1] == 6, `retomar do cursor '6' deveria começar no item 6, começou em {tostring(page[1])}`)
end)

test("resumeCursor inválido/corrompido ('' ou string não numérica) começa do zero -- aproximação de boa-fé, nunca erro", function()
	local items: { unknown } = {}
	for i = 1, 5 do
		items[i] = i
	end

	local withEmptyCursor = new("DataStoreKeyPages", items, 10, true, "")
	local getCurrentPageA = withEmptyCursor.GetCurrentPage :: (self: Dynamic) -> { unknown }
	assert(getCurrentPageA(withEmptyCursor)[1] == 1, "cursor vazio deveria começar do item 1")

	local withGarbageCursor = new("DataStoreKeyPages", items, 10, true, "not-a-number")
	local getCurrentPageB = withGarbageCursor.GetCurrentPage :: (self: Dynamic) -> { unknown }
	assert(getCurrentPageB(withGarbageCursor)[1] == 1, "cursor não numérico deveria começar do item 1, sem erro")
end)

test("Pages.New com pageSize <= 0 erra -- engenharia interna: o CHAMADOR deve resolver o default antes", function()
	local ok, err = pcall(function()
		new("DataStoreVersionPages", { 1 }, 0, false, nil)
	end)
	assert(not ok, "Pages.New com pageSize == 0 deveria erro (engenharia interna)")
	assert(
		string.find(tostring(err), "pageSize", 1, true) ~= nil,
		`mensagem de engenharia interna deveria citar pageSize, recebeu: {err}`
	)
end)

test("duas instâncias de Pages.New(...) têm buffer/cursor INDEPENDENTES (InstanceState por instância, L2.0.2)", function()
	local pagesOne = new("DataStoreVersionPages", { "one-a", "one-b" }, 1, false, nil)
	local pagesTwo = new("DataStoreVersionPages", { "two-a", "two-b", "two-c" }, 1, false, nil)

	local getCurrentPageOne = pagesOne.GetCurrentPage :: (self: Dynamic) -> { unknown }
	local getCurrentPageTwo = pagesTwo.GetCurrentPage :: (self: Dynamic) -> { unknown }

	assert(getCurrentPageOne(pagesOne)[1] == "one-a", "pagesOne deveria ver seu PRÓPRIO buffer")
	assert(getCurrentPageTwo(pagesTwo)[1] == "two-a", "pagesTwo deveria ver seu PRÓPRIO buffer, sem interferência de pagesOne")
	assert(pagesOne.IsFinished == false, "pagesOne (2 itens, pageSize=1) NÃO deveria estar finished ainda")
	assert(pagesTwo.IsFinished == false, "pagesTwo (3 itens, pageSize=1) NÃO deveria estar finished ainda")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
