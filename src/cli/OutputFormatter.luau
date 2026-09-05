--!strict

--[[
	`Runtime.OutputRecord` -> stdout/stderr (arquiteto-cli-2026-09-05.md, Decisão 13, "Formato do
	output e idioma" -- LER A DECISÃO INTEIRA antes de mexer aqui). É o módulo que recebe TODO
	`print`/`warn`/`error` de TODO script do usuário (top-level ou requerido) durante um
	`luaubench run`, via `RunContext.OnOutput`/`ModuleLoaderOptions.OnOutput` (Decisão 5/11).

	ROTEAMENTO stdout/stderr: `print` -> `stdio.write` (stdout); `warn`/`error` -> `stdio.ewrite`
	(stderr). É o que permite `luaubench run > saida.txt` funcionar (só o que o script imprimiu de
	verdade vai pro arquivo) e o que os testes de integração deste território verificam via
	`process.exec` redirecionando os dois streams de um subprocesso real (RunCommand.spec.luau).

	COR: `stdio.color` (amarelo para `warn`, vermelho para `error`; `print` nunca ganha cor -- ver
	o exemplo verbatim da Decisão 13). O Lune 0.10.5 não expõe detecção de TTY, então quem decide
	`useColor` é sempre quem chama `OutputFormatter.new` (`RunCommand`, task-cli-006, combinando
	`--no-color` e a variável de ambiente `NO_COLOR`) -- este módulo nunca inspeciona
	`process.env`/TTY por conta própria.

	ACHADO DE TOOLING (mesma classe já documentada em `Diagnostics.luau`, "ACHADO DE TOOLING #2":
	luau-lsp 1.69.0 perde a narrowing de literal de uma SEGUNDA chamada a `stdio.color(...)`
	dentro da MESMA função quando o argumento não é um literal cru) -- contornado da MESMA forma:
	cada cor isolada na sua própria função de uma linha (`warnColorPrefix`/`errorColorPrefix`/
	`colorReset`, abaixo), nunca duas chamadas de `stdio.color` na mesma função.

	REATRIBUIÇÃO DE LINHA (Decisão 13, ponto mais delicado deste módulo): um erro que se originou
	dentro de um `ModuleScript` requerido chega aqui com `record.line == nil` e `record.message`
	ainda contendo o marcador cru `[string "<nome do módulo>"]:<linha>: <mensagem>` -- porque
	`Sandbox.splitErrorMessage` (runtime, privado, não reexportado) procura o marcador do SCRIPT
	QUE ESTÁ RODANDO (`options.scriptName`, sempre o Script de TOPO que originou a cadeia de
	`require` -- ver `ModuleLoader.luau`, "por que uma instância por Script"), não do módulo que de
	fato errou -- os dois nomes divergem, a busca falha, e `splitErrorMessage` devolve a mensagem
	crua sem cortar nada (`markerEnd == nil -> return firstLine, nil`, ver `Sandbox.luau`).
	`tryReattributeModuleError`, abaixo, faz uma SEGUNDA passada sobre esse padrão -- mas, ao
	contrário de `splitErrorMessage` (que TEM que casar `options.scriptName` exatamente），esta
	busca é por QUALQUER marcador `[string "..."]:<n>: ` na mensagem, em qualquer posição (não
	ancorada no início -- uma falha entregue via `coroutine.resume` no Lune pode vir prefixada por
	um rótulo de categoria do próprio Lune, ex.: `"runtime error: "`, mesmo achado documentado no
	cabeçalho de `Sandbox.luau`) -- se achar, é o nome do MÓDULO que errou, e a mensagem final cita
	ele (nome + linha) em vez do Script de topo, mas também cita `record.scriptName` (o Script que
	fez o `require`) como origem da cadeia. Isso é APRESENTAÇÃO -- vive em `cli` de propósito
	(Decisão 13: "runtime fica intocado"); nenhum dado novo é inventado, só reformatado.

	Quando `tryReattributeModuleError` NÃO encontra o padrão (caso comum -- erro de um Script de
	topo, já limpo por `Sandbox.splitErrorMessage`, com `record.line` já preenchido e a mensagem
	sem marcador nenhum), cai no formato normal (`Messages.OutputErrorLine`).

	`scriptName = instance:GetFullName()` (decidido por quem monta o `OutputRecord` -- `Sandbox`/
	`ModuleLoader`) inclui o `Name` da raiz (`DataModel` por default -- `Instance.GetFullName` não
	tem o conceito de omitir isso, `Instance.luau` não conhece `DataModel` por nome, regra 02).
	Este módulo remove o prefixo `"DataModel."` se vier (Decisão 13, "uma linha, comentada" -- ver
	`stripDataModelPrefix`) -- é apresentação, não runtime.

	Depende só de `Messages.luau` (toda string user-facing) e `@lune/stdio`. NUNCA `../runtime`
	além do tipo `OutputRecord`/`OutputLevel` (não instancia nada, não chama `Sandbox`).
]]

local Messages = require("./Messages")
local stdio = require("@lune/stdio")
local RuntimeModule = require("../runtime")

type OutputRecord = RuntimeModule.OutputRecord

export type Formatter = {
	Emit: (self: Formatter, record: OutputRecord) -> (),
	ErrorCount: (self: Formatter) -> number,
}

local OutputFormatter = {}

local DATAMODEL_PREFIX = "DataModel."

-- Decisão 13, "uma linha, comentada": `GetFullName()` inclui o `Name` da raiz -- se for
-- "DataModel" (o default de `Runtime.DataModel.new()`), remove o prefixo pra bater com a
-- nomenclatura do Output do Studio (`ServerScriptService.Main`, não `game.ServerScriptService.Main`).
-- Se o projeto renomeou a raiz (`dataModel.Name = "MeuJogo"`, caso não coberto por esta leva), o
-- prefixo simplesmente não casa e o nome sai como veio -- divergência aceitável, não um bug.
local function stripDataModelPrefix(name: string): string
	if string.sub(name, 1, #DATAMODEL_PREFIX) == DATAMODEL_PREFIX then
		return string.sub(name, #DATAMODEL_PREFIX + 1)
	end
	return name
end

-- Busca NÃO ANCORADA (ver cabeçalho: pode haver um rótulo de categoria do Lune antes do
-- marcador) por `[string "<nome>"]:<linha>: <resto>` em `message`. `string.match` devolve os
-- três grupos já capturados, ou três `nil` se o padrão não casar em lugar nenhum da string --
-- `moduleLine` é sempre parseável (o grupo é `%d+`), mas `tonumber` é honestamente tipado
-- `number?`, então o tipo de retorno aqui reflete isso.
local function tryReattributeModuleError(message: string): (string?, number?, string?)
	local moduleName, lineText, rest = string.match(message, '%[string "(.-)"%]:(%d+): (.*)$')
	if moduleName == nil or lineText == nil or rest == nil then
		return nil, nil, nil
	end
	return moduleName, tonumber(lineText), rest
end

-- Mesmo contorno de tooling documentado no cabeçalho -- ver `Diagnostics.luau`, "ACHADO DE
-- TOOLING #2".
local function warnColorPrefix(): string
	return stdio.color("yellow")
end

local function errorColorPrefix(): string
	return stdio.color("red")
end

local function colorReset(): string
	return stdio.color("reset")
end

-- Função pura (nenhum I/O) que decide a LINHA final e o STREAM de destino para um `OutputRecord`
-- -- fatorada fora de `Emit` de propósito: é o que permite `OutputFormatter.spec.luau` testar
-- reatribuição de módulo/cor/formatação sem precisar interceptar `stdio.write`/`ewrite` reais
-- (não há como capturar isso de dentro do mesmo processo Lune -- a verificação de stdout/stderr
-- de verdade, "por redirecionamento", é responsabilidade de um teste de processo real em
-- `RunCommand.spec.luau`, via `process.exec`). Não faz parte do tipo público `Formatter`
-- (que só declara `Emit`/`ErrorCount`, a superfície documentada pelo desenho) -- é uma função
-- adicional exportada pelo MÓDULO `OutputFormatter`, não um método de instância.
function OutputFormatter.FormatRecord(record: OutputRecord, useColor: boolean): (string, "stdout" | "stderr")
	-- Declarado com o tipo FINAL (`string`, nunca `string?`) explícito -- mesmo padrão já usado em
	-- `TreePlanner.luau` (`projectName`/`resolvedRootClassName`, em `TreePlanner.Plan`):
	-- reatribuir um valor não-nil a uma variável inferida como `T?` não muda o tipo ESTÁTICO da
	-- variável pro resto do escopo (só a narrowing de controle de fluxo DENTRO do próprio `if`
	-- faz isso) -- anotar o tipo na declaração é o jeito de garantir `string` puro daqui em diante.
	local scriptNameOrNil = record.scriptName
	local scriptName: string
	if scriptNameOrNil ~= nil then
		scriptName = scriptNameOrNil
	else
		scriptName = Messages.UnknownScriptName()
	end
	scriptName = stripDataModelPrefix(scriptName)

	if record.level == "print" then
		return Messages.OutputPrintLine(scriptName, record.message), "stdout"
	end

	if record.level == "warn" then
		local line = Messages.OutputWarnLine(scriptName, record.message)
		if useColor then
			line = warnColorPrefix() .. line .. colorReset()
		end
		return line, "stderr"
	end

	-- record.level == "error"
	local moduleName, moduleLine, moduleMessage = tryReattributeModuleError(record.message)
	local line: string
	if moduleName ~= nil and moduleMessage ~= nil then
		line = Messages.OutputErrorLineFromModule(stripDataModelPrefix(moduleName), moduleLine, moduleMessage, scriptName)
	else
		line = Messages.OutputErrorLine(scriptName, record.line, record.message)
	end
	if useColor then
		line = errorColorPrefix() .. line .. colorReset()
	end
	return line, "stderr"
end

-- API pública (Decisão 13). `useColor` fixado na criação -- decidido por quem monta o pipeline
-- (`RunCommand`), nunca recalculado por chamada de `Emit`.
function OutputFormatter.new(useColor: boolean): Formatter
	local errorCount = 0

	local self: Formatter
	self = {
		Emit = function(_self: Formatter, record: OutputRecord): ()
			if record.level == "error" then
				errorCount += 1
			end

			local line, stream = OutputFormatter.FormatRecord(record, useColor)
			if stream == "stdout" then
				stdio.write(line .. "\n")
			else
				stdio.ewrite(line .. "\n")
			end
		end,

		ErrorCount = function(_self: Formatter): number
			return errorCount
		end,
	}
	return self
end

return OutputFormatter
