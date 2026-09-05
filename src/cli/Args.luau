--!strict

--[[
	`argv -> Command` (arquiteto-cli-2026-09-05.md, seção "Módulos" -> "Args.luau"). Único
	módulo que interpreta `process.args` -- `main.luau`/`init.luau` só consomem o `Command`
	resultante, nunca leem um token de argv por conta própria.

	Duas camadas de reconhecimento:
	1. Flags globais (`--help`/`--version`) e o subcomando "run"/"version"/"help" bare -- têm
	   precedência sobre qualquer outra coisa, em qualquer posição do argv (é o que faz
	   `main.luau --help` funcionar sem precisar escrever `run` antes).
	2. O resto do argv (depois de consumido um eventual "run" explícito) é interpretado como
	   flags/posicional do comando "run" -- o único comando real desta leva (CLAUDE.md:
	   "luaubench run [caminho]").

	`--watch` é reconhecido e SEMPRE devolve `Kind = "error"` com o motivo técnico real (Decisão
	9 do desenho: Lune 0.10.5 não expõe observador de filesystem, regra 04 proíbe polling) --
	nunca cai no ramo de "flag desconhecida".

	Depende só de `Messages.luau` (toda string de erro vem de lá).
]]

local Messages = require("./Messages")

export type Command =
	{ Kind: "run", ProjectPath: string?, Timeout: number?, NoColor: boolean, Verbose: boolean }
	| { Kind: "version" }
	| { Kind: "help" }
	| { Kind: "error", Message: string }

local Args = {}

-- Interpreta o que sobrou do argv depois de um eventual "run" explícito ter sido consumido:
-- `--timeout <segundos>`, `--no-color`, `--verbose`, `--watch` (sempre erro com o motivo real),
-- um único argumento posicional (o caminho do projeto), e qualquer outra flag "--..." como
-- desconhecida.
local function parseRunArgs(rest: { string }): Command
	local projectPath: string? = nil
	local timeout: number? = nil
	local noColor = false
	local verbose = false

	local index = 1
	local count = #rest
	while index <= count do
		local token = rest[index]

		if token == "--timeout" then
			local value = rest[index + 1]
			if value == nil then
				return { Kind = "error", Message = Messages.MissingFlagValue("--timeout") }
			end
			local parsed = tonumber(value)
			if parsed == nil then
				return { Kind = "error", Message = Messages.InvalidFlagValue("--timeout", value) }
			end
			timeout = parsed
			index += 2
		elseif token == "--no-color" then
			noColor = true
			index += 1
		elseif token == "--verbose" then
			verbose = true
			index += 1
		elseif token == "--watch" then
			-- Decisão 9: reconhecida de propósito, nunca "flag desconhecida" -- o motivo é
			-- técnico e real (ausência de API no Lune fixado), não falta de prioridade.
			return { Kind = "error", Message = Messages.WatchNotSupported() }
		elseif string.sub(token, 1, 2) == "--" then
			return { Kind = "error", Message = Messages.UnknownFlag(token) }
		else
			if projectPath ~= nil then
				return { Kind = "error", Message = Messages.UnexpectedArgument(token) }
			end
			projectPath = token
			index += 1
		end
	end

	return { Kind = "run", ProjectPath = projectPath, Timeout = timeout, NoColor = noColor, Verbose = verbose }
end

function Args.Parse(argv: { string }): Command
	-- Passo 1: `--help`/`--version` têm prioridade em QUALQUER posição do argv -- é o que faz
	-- `lune run src/cli/main.luau --help` funcionar sem exigir o subcomando "run" antes (mesma
	-- forma testada no acceptance do board).
	for _, token in argv do
		if token == "--help" then
			return { Kind = "help" }
		end
		if token == "--version" then
			return { Kind = "version" }
		end
	end

	-- Passo 2: subcomando bare ("run"/"version"/"help") como primeiro token. Ausência de
	-- subcomando, OU um primeiro token que não é nenhum dos três, é tratada como o comando "run"
	-- implícito (hoje é o único comando de verdade -- CLAUDE.md: "luaubench run [caminho]") --
	-- o restante do argv (com ou sem o "run" explícito removido) vira flags/caminho de parseRunArgs.
	if argv[1] == "run" then
		return parseRunArgs(table.move(argv, 2, #argv, 1, {}))
	elseif argv[1] == "version" then
		return { Kind = "version" }
	elseif argv[1] == "help" then
		return { Kind = "help" }
	end

	return parseRunArgs(argv)
end

return Args
