--!strict

--[[
	Ponto ÚNICO de acesso a `@lune/fs` para o estado "cloud" simulado (hoje: DataStoreService) --
	arquiteto-persistencia-cloud-2026-09-06.md, seções 2 ("por que @lune/fs mora em cli, não em
	services"), 3 ("layout em disco"), 9 ("auto-.gitignore") e 10 ("contrato entre territórios").

	NENHUM outro módulo do projeto (nem `src/services/**`, nem qualquer outro arquivo de
	`src/cli/**`) toca dentro de `.luaubench/` -- auditável por um grep de uma linha:
	`require("@lune/fs")` só aparece aqui dentro da feature de persistência (task-cli-029).
	`services` nunca ganha `@lune/fs`: o caminho de persistência é relativo ao `.project.json`
	resolvido por `ProjectFile.Locate`, informação que só `cli` tem -- por isso `cli` passa um
	PORT (este `Store`) para `services`, nunca um caminho cru (seção 2 do desenho).

	`CloudStore.Open(projectRoot, onFirstCreate)` devolve um `Store` estruturalmente compatível
	com `Services.CloudPersistence` ({ Load, Save }) -- SEM depender de `services` (a dependência
	só corre `cli -> services`, nunca o inverso; este módulo é a base que `services` vai consumir
	via injeção). `document` é sempre um NOME LÓGICO opaco ("datastore" hoje, "memorystore" numa
	leva futura), NUNCA um caminho -- só ESTE módulo decide como um nome vira caminho, e valida o
	nome ANTES de usá-lo como componente de caminho (nunca aceita "/", "\", "." -- bloqueia
	travessia de diretório por construção -- só letras/dígitos/"_"/"-" são aceitos -- nunca por
	lista negra de sequências perigosas tipo "..").

	Layout, ancorado em `projectRoot` (a pasta do `.project.json` RESOLVIDO por
	`ProjectFile.Locate` -- NUNCA `process.cwd()`, pra que "luaubench run caminho/pra/projeto" de
	qualquer diretório atinja sempre o mesmo arquivo):

		<projectRoot>/.luaubench/
		├── .gitignore              (conteúdo "*", escrito uma vez, na criação)
		└── cloud/
		    └── <document>.json

	`Open` NUNCA toca o disco (nem para checar se `.luaubench/` existe) -- o diretório só nasce na
	PRIMEIRA gravação bem-sucedida (`Save`); uma execução que só lê (`Load`) nunca cria pasta
	nenhuma no projeto do usuário. `onFirstCreate` dispara exatamente UMA VEZ por `Store` (a
	fronteira é o processo: cada `luaubench run` chama `Open` uma vez), e só quando `.luaubench/`
	de fato NÃO existia em disco antes desta gravação -- se o diretório já sobreviveu de uma
	execução anterior, a próxima execução nunca dispara `onFirstCreate` de novo.

	Escrita ATÔMICA (seção 6 do desenho, medição: custo extra irrelevante, 0 a 1.3ms):
	`fs.writeFile(tmp)` seguido de `fs.move(tmp, final, { overwrite = true })` -- nunca deixa um
	`<document>.json` truncado se o processo morrer no meio da gravação.

	`Load` NUNCA devolve `nil` para "existe mas está ilegível" -- perder estado do usuário em
	silêncio é proibido (regra 00, invariante 2; ver também regra 01, "nunca pcall silencioso").
	Só devolve `nil` quando nada nunca existiu nesse caminho (`fs.metadata(path).exists == false`).
	"Ilegível" cobre tanto uma falha real de I/O (permissão negada, etc.) quanto o caso
	determinístico e testável de "existe algo ali, mas não é um arquivo" (ex.: um diretório no
	lugar de `datastore.json`) -- ambos erram com uma mensagem limpa, NUNCA um stack trace cru do
	Lune/SO (mesmo protocolo de `ProjectFile.Read`: corta a mensagem bruta na primeira quebra de
	linha antes de propagar -- confirmado empiricamente nesta tarefa que uma falha de
	`@lune/fs` sob `pcall` devolve a mensagem real seguida de um `stack traceback:` de várias
	linhas apontando para dentro do binário do Lune).

	IDIOMA das mensagens de erro deste módulo: strings INLINE em inglês, não roteadas por
	`Messages.luau`, por dois motivos: (1) este território está restrito a `CloudStore.luau` +
	spec nesta tarefa (task-cli-029) -- `Messages.luau` é outro arquivo do mesmo território `cli`,
	tocado em paralelo por outro `coder-cli` nesta leva (regra 05: nunca dois agentes no mesmo
	arquivo); (2) a maioria é invariante INTERNA (nome de documento inválido é um bug de quem
	chama -- hoje só `services`, sempre com um nome literal fixo, nunca o script do usuário; falha
	de I/O do "cloud" ainda não tem um caminho de exibição final decidido). `task-cli-030`
	("fiação da persistência em cli" -- arquiteto-persistencia-cloud-2026-09-06.md, seção 11,
	linha "mensagens em Messages.luau") é quem decide como essas falhas aparecem formatadas pro
	usuário final; ver o relatório desta tarefa, "API faltante".

	Depende só de `@lune/fs`. Módulo folha dentro de `cli` (não importa `ProjectFile.luau` nem
	qualquer outro módulo do território -- mesmo princípio de `Messages.luau`: evita qualquer
	ciclo e mantém este módulo auditável sozinho).
]]

local fs = require("@lune/fs")

export type Store = {
	Load: (document: string) -> string?,
	Save: (document: string, contents: string) -> (),
}

local CloudStore = {}

-- Nome do subdiretório de estado do LuauBench e do seu ".gitignore" auto-gerado (seção 3 e 9 do
-- desenho) -- sempre relativos a `projectRoot`, nunca a `process.cwd()`.
local ROOT_DIR_NAME = ".luaubench"
local CLOUD_SUBDIR_NAME = "cloud"
local GITIGNORE_CONTENTS = "*"

-- Só letras, dígitos, "_" e "-" -- bloqueia "/", "\" e "." (portanto também "..") POR
-- CONSTRUÇÃO, nunca por lista negra de sequências perigosas (regra 00: nunca uma defesa que
-- depende de adivinhar todo padrão de ataque). O "+" exige pelo menos um caractere, então também
-- rejeita a string vazia.
local DOCUMENT_NAME_PATTERN = "^[%a%d_%-]+$"

-- Concatena `directory` + `name` com uma única barra entre os dois, mesmo que `directory` já
-- termine em "/" ou "\" -- mesma disciplina de `ProjectFile.luau` (função homônima local,
-- deliberadamente não compartilhada: este módulo não importa `ProjectFile`, ver cabeçalho).
local function joinPath(directory: string, name: string): string
	local normalized = directory
	if #normalized > 0 then
		local lastChar = string.sub(normalized, -1)
		if lastChar == "/" or lastChar == "\\" then
			normalized = string.sub(normalized, 1, -2)
		end
	end
	return `{normalized}/{name}`
end

-- Corta uma mensagem de erro bruta na primeira quebra de linha -- uma chamada de `@lune/fs` que
-- falha, sob `pcall`, devolve a mensagem real seguida de um `stack traceback:` de várias linhas
-- apontando para dentro do binário do Lune (confirmado empiricamente contra Lune 0.10.5 nesta
-- tarefa); propagar isso cru violaria a regra 04 ("nunca stack trace cru"). Mesmo protocolo do
-- `ioMessage` de `ProjectFile.Read`.
local function firstLineOf(rawMessage: string): string
	local newlineIndex = string.find(rawMessage, "\n", 1, true)
	if newlineIndex == nil then
		return rawMessage
	end
	return string.sub(rawMessage, 1, newlineIndex - 1)
end

-- Erra com uma mensagem estável (nunca devolve `false`/`nil` em silêncio) se `document` puder
-- virar um componente de caminho arbitrário. É uma invariante INTERNA -- hoje só `services` chama
-- `CloudStore`, sempre com um nome literal fixo tipo "datastore", nunca com algo vindo do script
-- do usuário -- por isso `error()` direto (mesmo protocolo de invariante interna quebrada de
-- `RunCommand.luau`, ex. linha 268) em vez de um `Diagnostic` de `Diagnostics.luau`.
local function validateDocumentName(document: string): ()
	if string.match(document, DOCUMENT_NAME_PATTERN) == nil then
		error(
			`CloudStore: invalid document name "{document}" -- expected only letters, digits, "_" or "-" `
				.. '(this is an internal logical name, never a path -- it must never contain "/", "\\", ".", or be empty).'
		)
	end
end

-- `CloudStore.Open` (assinatura pública abaixo) constrói os três caminhos fixos e o estado de
-- "já tratei a criação do diretório nesta execução" ANTES de devolver o `Store` -- closures
-- capturam esse estado; nenhum dado sai do escopo de uma chamada de `Open` (duas chamadas de
-- `Open` -- ex.: dois testes distintos, ou dois processos `luaubench run` -- nunca compartilham o
-- flag `hasEnsuredDirectory`).
function CloudStore.Open(projectRoot: string, onFirstCreate: (path: string) -> ()): Store
	local rootDir = joinPath(projectRoot, ROOT_DIR_NAME)
	local cloudDir = joinPath(rootDir, CLOUD_SUBDIR_NAME)
	local gitignorePath = joinPath(rootDir, ".gitignore")

	-- `true` assim que este `Store` já garantiu o diretório com SUCESSO pelo menos uma vez -- nunca
	-- setada "otimisticamente" antes do resultado de `fs.writeDir` (ver `ensureDirectoryExists`
	-- abaixo). Existe para deixar EXPLÍCITA a garantia "onFirstCreate dispara no máximo uma vez por
	-- execução", em vez de depender implicitamente de reconsultar `fs.isDir` toda vez (que também
	-- chegaria no resultado certo, já que uma 2ª verificação veria o diretório já criado -- mas a
	-- garantia fica menos óbvia pra quem lê).
	local hasEnsuredDirectory = false

	local function ensureDirectoryExists(): ()
		if hasEnsuredDirectory then
			return
		end

		local didExistBefore = fs.isDir(rootDir)

		-- `fs.writeDir` cria TODOS os diretórios pais que faltarem numa só chamada (aqui,
		-- potencialmente `.luaubench/` E `.luaubench/cloud/` juntos) -- confirmado empiricamente
		-- nesta tarefa (Lune 0.10.5) que chamar `fs.writeDir` num diretório que JÁ existe também
		-- não lança (idempotente na prática), embora o typedef empacotado
		-- (`~/.lune/.typedefs/0.10.5/fs.luau`) documente "An error will be thrown... `path`
		-- already points to an existing file or directory" -- a doc está desatualizada em relação
		-- ao binário 0.10.5 real. `didExistBefore`, medido ANTES desta chamada, é quem decide
		-- `onFirstCreate` -- nunca uma suposição sobre `writeDir` lançar ou não.
		local writeDirOk, writeDirError = pcall(function()
			fs.writeDir(cloudDir)
		end)
		if not writeDirOk then
			error(`CloudStore: could not create "{cloudDir}": {firstLineOf(tostring(writeDirError))}`)
		end

		-- Só marca a garantia como cumprida DEPOIS de confirmar que `fs.writeDir` resolveu com
		-- sucesso -- nunca "otimisticamente" antes do `pcall` acima. Setar antes travaria a flag em
		-- `true` pro resto do PROCESSO mesmo quando a criação falha de verdade (ex.: obstrução
		-- transitória em `.luaubench/`), fazendo toda `Save` seguinte pular esta função inteira (o
		-- `if hasEnsuredDirectory then return end` do topo) e falhar de novo com uma mensagem AINDA
		-- menos clara ("path specified not found" ao tentar escrever dentro de um `cloudDir` que
		-- nunca chegou a existir, em vez de "could not create directory") -- mesmo depois da
		-- obstrução ter sumido. Achado de revisão, task-cli-029, correção pontual 2026-09-06 (ver
		-- CloudStore.spec.luau, "Save se recupera de uma obstrução transitória").
		hasEnsuredDirectory = true

		if not didExistBefore then
			local gitignoreOk, gitignoreError = pcall(function()
				fs.writeFile(gitignorePath, GITIGNORE_CONTENTS)
			end)
			if not gitignoreOk then
				error(`CloudStore: could not write "{gitignorePath}": {firstLineOf(tostring(gitignoreError))}`)
			end

			onFirstCreate(rootDir)
		end
	end

	local function documentPath(document: string): string
		validateDocumentName(document)
		return joinPath(cloudDir, `{document}.json`)
	end

	local function load(document: string): string?
		local path = documentPath(document)

		-- `fs.metadata` nunca lança pra "caminho não existe" (devolve `{ exists = false }`) --
		-- confirmado empiricamente nesta tarefa. Só lança se o PRÓPRIO ato de checar falhar
		-- (ex.: sem permissão pra sequer fazer `stat` no caminho) -- esse caso também conta como
		-- "ilegível" (nunca `nil` em silêncio).
		local metaOk, metaOrError = pcall(function()
			return fs.metadata(path)
		end)
		if not metaOk then
			error(`CloudStore: could not read cloud document "{document}" at "{path}": {firstLineOf(tostring(metaOrError))}`)
		end
		local meta = metaOrError :: fs.Metadata

		if not meta.exists then
			-- Único caso em que `Load` devolve `nil`: nada nunca existiu neste caminho.
			return nil
		end

		if meta.kind ~= "file" then
			-- Existe ALGO neste caminho (diretório, ou -- fora do nosso controle -- um symlink),
			-- mas não é um arquivo legível como documento -- "ilegível" no sentido do contrato
			-- (nunca `nil` em silêncio quando há algo ali). Caso determinístico e testável (ao
			-- contrário de simular permissão negada de verdade, que depende do SO) --
			-- ver CloudStore.spec.luau, cria um diretório no lugar do arquivo.
			error(`CloudStore: could not read cloud document "{document}" at "{path}": expected a file, found a {meta.kind}.`)
		end

		local readOk, contentsOrError = pcall(function(): unknown
			return fs.readFile(path)
		end)
		if not readOk then
			error(`CloudStore: could not read cloud document "{document}" at "{path}": {firstLineOf(tostring(contentsOrError))}`)
		end

		-- `fs.readFile` devolve `string` de verdade (assinatura real: `(path: string): string`)
		-- -- o `unknown` acima só existe pra passar pelo protocolo de `pcall` sem `any` (mesmo
		-- idioma de `ProjectFile.Read`); a narrowing aqui é trivial porque `readOk == true` já
		-- garante que veio de `fs.readFile`.
		return contentsOrError :: string
	end

	local function save(document: string, contents: string): ()
		-- `documentPath` valida `document` ANTES de qualquer coisa tocar o disco -- um nome
		-- inválido nunca deveria ter o efeito colateral de criar `.luaubench/` mesmo que a
		-- gravação em si não aconteça (a chamada inteira é recusada, não parcialmente aplicada).
		local finalPath = documentPath(document)
		ensureDirectoryExists()

		local tmpPath = finalPath .. ".tmp"

		local writeOk, writeError = pcall(function()
			fs.writeFile(tmpPath, contents)
		end)
		if not writeOk then
			error(`CloudStore: could not write cloud document "{document}" at "{tmpPath}": {firstLineOf(tostring(writeError))}`)
		end

		local moveOk, moveError = pcall(function()
			fs.move(tmpPath, finalPath, { overwrite = true })
		end)
		if not moveOk then
			-- Melhor esforço pra não deixar o ".tmp" pra trás -- NUNCA deixa uma falha de limpeza
			-- mascarar o erro real de `move` (por isso este `pcall` extra descarta o resultado).
			pcall(function()
				fs.removeFile(tmpPath)
			end)
			error(`CloudStore: could not save cloud document "{document}" to "{finalPath}": {firstLineOf(tostring(moveError))}`)
		end
	end

	return {
		Load = load,
		Save = save,
	}
end

return CloudStore
