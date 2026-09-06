--!strict

--[[
	Teste da task-cli-029 (CloudStore.luau). Cobre o acceptance do board contra pastas de projeto
	geradas EM TEMPO DE TESTE sob `%TEMP%/luaubench-cloudstore-spec/<caso>` (mesma disciplina de
	`TreePlanner.spec.luau`, "cadeia de pastas reais... gerada em disco em tempo de teste, fora de
	`src/cli/fixtures/`" -- aqui TODO caso precisa de scratch, não só um): `Open` não toca o disco;
	primeira `Save` cria `.luaubench/`, `.luaubench/cloud/` e `.luaubench/.gitignore` (conteúdo
	"*"), disparando `onFirstCreate` exatamente uma vez (nem na 2ª `Save` da mesma execução, nem
	numa execução nova sobre um `.luaubench/` que já sobreviveu); `Load` de documento inexistente
	devolve `nil`; `Load` de um caminho que existe mas não é arquivo (diretório no lugar do
	documento -- substituto determinístico e portável para "arquivo ilegível", que dependeria de
	permissão de SO) ERRA sem stack trace cru; `Save` é atômica (sem sobrar `.tmp`, conteúdo
	íntegro mesmo após sobrescrita); `document` contendo "/", "\", ".." ou vazio é sempre recusado,
	nunca vira componente de caminho; o caminho fica ancorado em `projectRoot`, nunca em
	`process.cwd()`.

	Roda com `lune run src/cli/CloudStore.spec.luau`. Cada teste usa sua PRÓPRIA subpasta de
	scratch (nunca reaproveita estado entre casos) e a pasta-mãe inteira é apagada ao final (mesmo
	se algum teste falhar no meio -- ver o `pcall` ao redor da bateria de testes, perto do fim do
	arquivo).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local CloudStore = require("./CloudStore")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- Pasta-mãe de todo o spec, isolada de `src/cli/fixtures/` (aqueles são projetos Rojo estáticos
-- versionados; aqui cada teste PRECISA de um `.luaubench/` mutável do zero, então não faz sentido
-- versionar nada disso -- mesma disciplina de `TreePlanner.spec.luau`, teste de profundidade
-- máxima).
local tempRootValue = process.env.TEMP or process.env.TMP
assert(tempRootValue ~= nil, "TEMP/TMP precisa existir no ambiente pra este spec (CloudStore.spec.luau) criar pastas de projeto de teste")
local SCRATCH_ROOT = `{tempRootValue}/luaubench-cloudstore-spec`

-- Limpa resíduo de uma rodada anterior que talvez tenha abortado antes da limpeza final.
if fs.isDir(SCRATCH_ROOT) then
	fs.removeDir(SCRATCH_ROOT)
end
fs.writeDir(SCRATCH_ROOT)

-- Uma subpasta NOVA e VAZIA por caso de teste -- nenhum teste herda `.luaubench/` (nem qualquer
-- outro arquivo) de um teste anterior.
local function freshProjectRoot(caseName: string): string
	local path = `{SCRATCH_ROOT}/{caseName}`
	if fs.isDir(path) then
		fs.removeDir(path)
	end
	fs.writeDir(path)
	return path
end

--------------------------------------------------------------------------------------------------
-- Open nunca toca o disco
--------------------------------------------------------------------------------------------------

test("Open nao cria .luaubench/ nem dispara onFirstCreate -- so a primeira Save toca o disco", function()
	local root = freshProjectRoot("open-no-disk")
	local firstCreateCalls = 0

	local store = CloudStore.Open(root, function(_path: string)
		firstCreateCalls += 1
	end)

	assert(not fs.isDir(`{root}/.luaubench`), "Open nao deveria ter criado .luaubench/")
	assert(firstCreateCalls == 0, "onFirstCreate nao deveria disparar so por causa de Open")
	assert(store.Load ~= nil and store.Save ~= nil, "Open deveria devolver um Store com Load e Save")
end)

--------------------------------------------------------------------------------------------------
-- Primeira Save: cria a estrutura inteira e dispara onFirstCreate exatamente uma vez
--------------------------------------------------------------------------------------------------

test("primeira Save cria .luaubench/, cloud/ e .gitignore (conteudo '*'), dispara onFirstCreate UMA vez", function()
	local root = freshProjectRoot("first-save")
	local firstCreatePaths: { string } = {}

	local store = CloudStore.Open(root, function(path: string)
		table.insert(firstCreatePaths, path)
	end)

	store.Save("datastore", "{}")

	assert(fs.isDir(`{root}/.luaubench`), ".luaubench/ deveria existir apos a primeira Save")
	assert(fs.isDir(`{root}/.luaubench/cloud`), ".luaubench/cloud/ deveria existir apos a primeira Save")
	assert(fs.isFile(`{root}/.luaubench/.gitignore`), ".luaubench/.gitignore deveria existir apos a primeira Save")
	assert(fs.readFile(`{root}/.luaubench/.gitignore`) == "*", ".gitignore deveria conter exatamente '*'")

	assert(#firstCreatePaths == 1, `onFirstCreate deveria disparar exatamente 1 vez na primeira Save (disparou {#firstCreatePaths})`)
	assert(firstCreatePaths[1] == `{root}/.luaubench`, "onFirstCreate deveria receber o caminho de .luaubench/")

	-- Segunda Save na MESMA execucao: NAO dispara onFirstCreate de novo.
	store.Save("datastore", '{"x":1}')
	assert(#firstCreatePaths == 1, "onFirstCreate NAO deveria disparar de novo na segunda Save")
	assert(fs.readFile(`{root}/.luaubench/cloud/datastore.json`) == '{"x":1}', "segunda Save deveria ter sobrescrito o conteudo")
end)

test("uma NOVA execucao (novo Open) sobre um projeto que ja tem .luaubench/ NAO dispara onFirstCreate", function()
	local root = freshProjectRoot("second-run")

	local firstStore = CloudStore.Open(root, function() end)
	firstStore.Save("datastore", "{}")
	assert(fs.isDir(`{root}/.luaubench`), "pre-condicao: a primeira execucao deveria ter criado .luaubench/")

	local secondRunCalls = 0
	local secondStore = CloudStore.Open(root, function()
		secondRunCalls += 1
	end)
	secondStore.Save("datastore", '{"again":true}')

	assert(secondRunCalls == 0, "uma 2a execucao sobre um .luaubench/ que ja sobreviveu de uma execucao anterior nao deveria disparar onFirstCreate")
	assert(fs.readFile(`{root}/.luaubench/cloud/datastore.json`) == '{"again":true}', "a 2a execucao deveria ter conseguido sobrescrever o documento normalmente")
end)

--------------------------------------------------------------------------------------------------
-- Load: nil so quando nunca existiu; ERRA (nunca nil) quando existe mas nao e legivel como arquivo
--------------------------------------------------------------------------------------------------

test("Load de documento que nunca existiu devolve nil, sem criar nada em disco", function()
	local root = freshProjectRoot("load-missing")
	local store = CloudStore.Open(root, function() end)

	local contents = store.Load("datastore")

	assert(contents == nil, "Load de documento inexistente deveria devolver nil")
	assert(not fs.isDir(`{root}/.luaubench`), "Load nunca deveria criar .luaubench/ (so leitura, nunca grava)")
end)

test("Load ERRA (nunca nil) quando existe um DIRETORIO no lugar do documento -- substituto deterministico de 'arquivo ilegivel'", function()
	local root = freshProjectRoot("load-unreadable")
	-- Forca "datastore.json" a ser um DIRETORIO em vez de um arquivo -- caminho existe (algo real
	-- em disco), mas nao pode ser lido como documento. Mais deterministico e portavel do que
	-- tentar negar permissao de leitura de verdade (o atributo "read-only" do Windows NAO bloqueia
	-- leitura, so escrita -- confirmado empiricamente nesta tarefa).
	fs.writeDir(`{root}/.luaubench/cloud/datastore.json`)

	local store = CloudStore.Open(root, function() end)

	local ok, err = pcall(function()
		return store.Load("datastore")
	end)

	assert(not ok, "Load deveria ERRAR (nunca devolver nil) quando o caminho existe mas nao e um arquivo")
	local message = tostring(err)
	assert(string.find(message, "\n") == nil, `mensagem de erro nunca deveria conter stack trace cru (multi-linha). Mensagem: {message}`)
	assert(string.find(message, "datastore", 1, true) ~= nil, `mensagem deveria citar o documento "datastore". Mensagem: {message}`)
end)

--------------------------------------------------------------------------------------------------
-- Save atomica: nunca sobra .tmp, conteudo final sempre integro (inclusive apos sobrescrita)
--------------------------------------------------------------------------------------------------

test("Save e atomica: nao sobra arquivo .tmp e o conteudo final e integro, inclusive apos sobrescrita", function()
	local root = freshProjectRoot("atomic-save")
	local store = CloudStore.Open(root, function() end)

	local documentPath = `{root}/.luaubench/cloud/datastore.json`
	local tmpPath = `{documentPath}.tmp`

	local payload = string.rep("abc123", 2000) -- conteudo grande o bastante pra nao ser coincidencia
	store.Save("datastore", payload)

	assert(fs.readFile(documentPath) == payload, "conteudo final deveria ser identico ao que foi salvo")
	assert(not fs.isFile(tmpPath), "nao deveria sobrar arquivo .tmp apos a primeira Save bem-sucedida")

	-- Uma segunda Save (sobrescrita real) tambem nao deixa residuo, e o conteudo final e o NOVO.
	local overwritePayload = "overwritten-content"
	store.Save("datastore", overwritePayload)

	assert(fs.readFile(documentPath) == overwritePayload, "segunda Save deveria ter sobrescrito o conteudo por completo")
	assert(not fs.isFile(tmpPath), "nao deveria sobrar arquivo .tmp apos a segunda Save")
end)

--------------------------------------------------------------------------------------------------
-- Save se recupera de uma obstrucao transitoria em .luaubench/ (correcao de achado de revisao,
-- task-cli-029, 2026-09-06): "hasEnsuredDirectory" nao pode travar em `true` quando a criacao do
-- diretorio falha de verdade -- senao a PROXIMA Save no MESMO Store pula a tentativa de recriar o
-- diretorio e falha de novo com uma mensagem ainda mais confusa, mesmo depois da obstrucao sumir.
--------------------------------------------------------------------------------------------------

test("Save se recupera de uma obstrucao transitoria em .luaubench/ -- nao trava hasEnsuredDirectory em true numa falha real", function()
	local root = freshProjectRoot("transient-obstruction")

	-- Bloqueia ".luaubench" com um ARQUIVO (nao um diretorio) ANTES de qualquer Save -- reproduz
	-- exatamente o cenario do revisor: `fs.writeDir(".../.luaubench/cloud")` nao consegue criar um
	-- diretorio filho de um caminho que ja existe como arquivo.
	fs.writeFile(`{root}/.luaubench`, "isto deveria ser um diretorio, nao um arquivo")

	local store = CloudStore.Open(root, function() end)

	-- 1) Primeira Save falha (esperado) -- com uma mensagem CLARA apontando falha de criacao de
	-- diretorio, nunca um stack trace cru.
	local firstOk, firstErr = pcall(function()
		store.Save("datastore", "{}")
	end)
	assert(not firstOk, "Save deveria falhar enquanto .luaubench/ estiver obstruido por um arquivo")
	local firstMessage = tostring(firstErr)
	assert(string.find(firstMessage, "\n") == nil, `mensagem de erro nunca deveria conter stack trace cru (multi-linha). Mensagem: {firstMessage}`)
	assert(
		string.find(firstMessage, "could not create", 1, true) ~= nil,
		`mensagem da 1a falha deveria apontar falha de CRIACAO de diretorio, nao um erro generico de I/O de arquivo. Mensagem: {firstMessage}`
	)

	-- Remove o bloqueio -- a obstrucao era transitoria (ex.: algo tocando ".luaubench/" por fora do
	-- LuauBench durante a execucao).
	fs.removeFile(`{root}/.luaubench`)

	-- 2) Uma NOVA Save no MESMO Store (mesmo `hasEnsuredDirectory` capturado no closure) deveria
	-- tentar recriar o diretorio de novo -- nunca pular direto pra `fs.writeFile` dentro de um
	-- `cloudDir` que nunca chegou a existir (o que produziria "path specified not found", a
	-- mensagem confusa que o revisor reproduziu antes desta correcao).
	local secondOk, secondErr = pcall(function()
		store.Save("datastore", '{"recovered":true}')
	end)
	assert(secondOk, `Save deveria funcionar de novo apos a obstrucao ser removida, mas falhou: {tostring(secondErr)}`)

	assert(fs.isDir(`{root}/.luaubench`), ".luaubench/ deveria ter sido recriado como diretorio apos a recuperacao")
	assert(fs.isDir(`{root}/.luaubench/cloud`), ".luaubench/cloud/ deveria existir apos a recuperacao")
	assert(fs.isFile(`{root}/.luaubench/.gitignore`), ".gitignore deveria ter sido (re)criado apos a recuperacao")
	assert(
		fs.readFile(`{root}/.luaubench/cloud/datastore.json`) == '{"recovered":true}',
		"a Save apos a recuperacao deveria ter gravado o documento normalmente"
	)
end)

--------------------------------------------------------------------------------------------------
-- 'document' nunca vira componente de caminho arbitrario -- recusado, nunca aceito parcialmente
--------------------------------------------------------------------------------------------------

test("document contendo '../', barra, ou vazio e SEMPRE recusado -- nunca vira componente de caminho", function()
	local root = freshProjectRoot("document-validation")
	local store = CloudStore.Open(root, function() end)

	local maliciousNames = { "../evil", "../../evil", "sub/evil", "sub\\evil", "..", ".", "" }

	for _, badName in maliciousNames do
		local saveOk = pcall(function()
			store.Save(badName, "{}")
		end)
		assert(not saveOk, `Save deveria recusar o nome de documento "{badName}"`)

		local loadOk = pcall(function()
			return store.Load(badName)
		end)
		assert(not loadOk, `Load deveria recusar o nome de documento "{badName}"`)
	end

	-- Confirma que a recusa aconteceu ANTES de qualquer I/O -- nenhum arquivo/pasta "evil"
	-- escapou de ".luaubench/cloud/" para a raiz do projeto (nem sequer ".luaubench/" deveria ter
	-- sido criado, ja que TODAS as tentativas acima foram recusadas).
	assert(not fs.isDir(`{root}/.luaubench`), "nenhum nome malicioso deveria ter criado .luaubench/ (validacao acontece antes de tocar o disco)")
	assert(not fs.isFile(`{root}/evil`), "um nome de documento malicioso nunca deveria escapar para um arquivo fora de .luaubench/cloud/")
	assert(not fs.isDir(`{root}/sub`), "um nome de documento malicioso nunca deveria criar pasta fora de .luaubench/cloud/")

	-- Um nome valido continua funcionando normalmente (a validacao rejeita so o que e perigoso).
	local validOk = pcall(function()
		store.Save("datastore", "{}")
	end)
	assert(validOk, "um nome de documento valido ('datastore') nao deveria ser afetado pela validacao")
end)

--------------------------------------------------------------------------------------------------
-- Caminho ancorado em projectRoot, NUNCA em process.cwd()
--------------------------------------------------------------------------------------------------

test("caminho de persistencia fica ancorado em projectRoot, nunca em process.cwd()", function()
	local root = freshProjectRoot("anchored-not-cwd")
	-- `root` (dentro de %TEMP%) e deliberadamente um caminho BEM diferente de `process.cwd()`
	-- (a raiz do repo, de onde `lune run` roda este spec) -- se `CloudStore` usasse `process.cwd()`
	-- por engano em vez do `projectRoot` recebido, o arquivo apareceria no lugar errado.
	local cwdLuaubenchPath = `{process.cwd}.luaubench`
	local cwdAlreadyHadLuaubench = fs.isDir(cwdLuaubenchPath)

	local store = CloudStore.Open(root, function() end)
	store.Save("datastore", "{}")

	assert(fs.isFile(`{root}/.luaubench/cloud/datastore.json`), "o documento deveria ter sido gravado dentro de projectRoot")

	if not cwdAlreadyHadLuaubench then
		assert(not fs.isDir(cwdLuaubenchPath), "Save NUNCA deveria ter criado .luaubench/ em process.cwd() -- so em projectRoot")
	end
end)

--------------------------------------------------------------------------------------------------

-- Limpeza final -- `pcall` pra garantir que a bateria de testes acima (que já rodou e já
-- estampou os [PASS]/erro de asserção antes de chegar aqui) nunca deixe `SCRATCH_ROOT` pra trás,
-- mesmo que algo inesperado tenha deixado um arquivo com atributo especial pelo caminho.
pcall(function()
	fs.removeDir(SCRATCH_ROOT)
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
