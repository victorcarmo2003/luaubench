--!strict

--[[
	Coleta e renderização de problemas de projeto (arquiteto-cli-2026-09-05.md, seção "Módulos" ->
	"Diagnostics.luau"). É o mecanismo que cumpre a regra 04 ("erro claro apontando o campo
	problemático, nunca stack trace cru do parser"): as tarefas seguintes (`JsonValue`,
	`ProjectFile`, `TreePlanner`, `TreeMaterializer`) acumulam `Diagnostic`s aqui em vez de
	`error()`ar no meio do parsing/plano -- ver Decisão 3 do desenho ("falha antes de mutar").

	`Code` é um identificador estável (ex.: "project/unknown-field") -- é o que permite ao teste
	de quem gera o diagnóstico asserir por código, sem casar o texto exato de `Message` (que pode
	mudar de redação sem quebrar teste nenhum).

	Depende só de `Messages.luau` (severidade/rótulo/formatação de linha) -- nenhuma string
	literal voltada ao usuário aparece neste arquivo por fora de `Messages`.
]]

local Messages = require("./Messages")
local stdio = require("@lune/stdio")

export type Severity = Messages.Severity

export type Diagnostic = {
	Severity: Severity,
	Code: string,
	Message: string,
	ProjectPath: string?,
	NodePath: string?,
	FilePath: string?,
	Field: string?,
}

export type Bag = {
	Add: (self: Bag, diagnostic: Diagnostic) -> (),
	All: (self: Bag) -> { Diagnostic },
	CountOf: (self: Bag, severity: Severity) -> number,
	HasErrors: (self: Bag) -> boolean,
}

local Diagnostics = {}

-- Cor por severidade, só para `Render` -- não é uma string voltada ao usuário (é uma chave de
-- API do próprio Lune, `stdio.Color`), por isso vive aqui e não em `Messages.luau`.
--
-- ACHADO DE TOOLING #1 (luau-lsp 1.69.0, isolado com repro mínimo antes de decidir -- regra 00:
-- não adivinhar comportamento de ferramenta externa): uma tabela `{ [Severity]: stdio.Color }`
-- indexada por `diagnostic.Severity` faz o analisador estático DEVOLVER `string` em vez de
-- `stdio.Color` (o literal de cada entrada é widened, e a união resultante -- "string | string |
-- ...", nove vezes -- não bate mais contra o tipo esperado por `stdio.color`). Confirmado com um
-- repro de ~10 linhas isolado da tabela real, sem nada de `cli` envolvido; indexar por `string`
-- literal (`counts["error"]`) OU por dot-access (`counts.error`) na tabela de contagem abaixo
-- reproduz a MESMA classe de erro. `lune run` executa corretamente (ver Diagnostics.spec.luau,
-- teste "Render com cor..." -- confirma o byte ANSI de verdade); é só a análise estática que
-- erra. Contornado com ramificação explícita em vez de tabela -- cada `return` devolve um
-- literal já no tipo de retorno declarado, sem passar por indexação de tabela nenhuma.
local function colorForSeverity(severity: Severity): stdio.Color
	if severity == "error" then
		return "red"
	elseif severity == "warning" then
		return "yellow"
	end
	return "cyan"
end

function Diagnostics.newBag(): Bag
	local items: { Diagnostic } = {}
	local counts: { [Severity]: number } = { error = 0, warning = 0, info = 0 }

	local self: Bag
	self = {
		Add = function(_self: Bag, diagnostic: Diagnostic)
			table.insert(items, diagnostic)
			counts[diagnostic.Severity] += 1
		end,

		-- Devolve uma CÓPIA -- quem chama não pode mutar o estado interno do Bag por fora de Add.
		All = function(_self: Bag): { Diagnostic }
			local copy: { Diagnostic } = table.create(#items)
			for _, diagnostic in items do
				table.insert(copy, diagnostic)
			end
			return copy
		end,

		CountOf = function(_self: Bag, severity: Severity): number
			return counts[severity]
		end,

		HasErrors = function(_self: Bag): boolean
			-- Mesmo achado de tooling do comentário de `colorForSeverity`: `counts.error`
			-- (dot-access) e `counts["error"]` (literal direto) confundem o analisador estático
			-- nesta versão do luau-lsp quando a chave do indexador é uma união de literais;
			-- indexar por uma VARIÁVEL já tipada `Severity` (como `CountOf`, acima, já fazia)
			-- analisa limpo -- confirmado com repro isolado antes de escrever isto.
			local errorSeverity: Severity = "error"
			return counts[errorSeverity] > 0
		end,
	}
	return self
end

-- Monta o sufixo de localização entre parênteses, só com os campos presentes no diagnóstico, na
-- ordem do mais específico (posição na árvore/campo) para o mais geral (arquivo/projeto de
-- origem). "" (string vazia) se nenhum campo de localização foi preenchido.
local function buildLocationSuffix(diagnostic: Diagnostic): string
	local segments: { string } = {}

	if diagnostic.NodePath ~= nil then
		table.insert(segments, Messages.LocationSegment(Messages.LocationLabel("node"), diagnostic.NodePath))
	end
	if diagnostic.Field ~= nil then
		table.insert(segments, Messages.LocationSegment(Messages.LocationLabel("field"), diagnostic.Field))
	end
	if diagnostic.FilePath ~= nil then
		table.insert(segments, Messages.LocationSegment(Messages.LocationLabel("file"), diagnostic.FilePath))
	end
	if diagnostic.ProjectPath ~= nil then
		table.insert(segments, Messages.LocationSegment(Messages.LocationLabel("project"), diagnostic.ProjectPath))
	end

	if #segments == 0 then
		return ""
	end
	return ` ({table.concat(segments, ", ")})`
end

-- ACHADO DE TOOLING #2 (luau-lsp 1.69.0, mesmo protocolo do #1 acima -- isolado com repro
-- mínimo, ~20 linhas, antes de decidir): dentro de uma MESMA função, uma segunda chamada a
-- `stdio.color(...)` faz o analisador perder a narrowing de literal do argumento da PRIMEIRA
-- chamada sempre que o argumento dela não é um literal cru (aqui, `colorForSeverity(severity)`)
-- -- confirmado que a ordem das duas chamadas não importa (falha em qualquer uma) e que DUAS
-- chamadas com literal cru nos dois argumentos, sem nenhuma função no meio, analisam limpo.
-- Contornado isolando cada chamada em sua PRÓPRIA função de uma linha só (`colorPrefix`/
-- `colorReset` abaixo) -- confirmado que isso elimina o erro. `lune run` sempre executou
-- corretamente (Diagnostics.spec.luau, teste "Render com cor..."); é só a análise estática que
-- errava antes deste contorno.
local function colorPrefix(severity: Severity): string
	return stdio.color(colorForSeverity(severity))
end

local function colorReset(): string
	return stdio.color("reset")
end

-- Produz UMA linha legível para o diagnóstico. `useColor = false` (ex.: saída redirecionada para
-- arquivo, `--no-color`, `NO_COLOR` setado) devolve a mesma linha sem nenhum código ANSI --
-- quem decide `useColor` é o chamador (init.luau/RunCommand, task futura), nunca este módulo.
function Diagnostics.Render(diagnostic: Diagnostic, useColor: boolean): string
	local label = Messages.SeverityLabel(diagnostic.Severity)
	local locationSuffix = buildLocationSuffix(diagnostic)
	local line = Messages.DiagnosticLine(label, diagnostic.Code, diagnostic.Message, locationSuffix)

	if not useColor then
		return line
	end

	return colorPrefix(diagnostic.Severity) .. line .. colorReset()
end

return Diagnostics
