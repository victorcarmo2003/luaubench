--!strict

--[[
	Teste da task-runtime-032 (TypeNameResolver: ponte injetada com o território novo de Value
	Types simulados). Cobre: `Resolve` devolve `nil` antes de qualquer `Set`; depois de `Set`,
	`Resolve` repassa o veredito do resolvedor instalado; `Resolve` devolve `nil` (não erro)
	quando o resolvedor instalado não reconhece o valor recebido -- a DIFERENÇA DELIBERADA do
	contrato de `UnknownClassResolver` documentada no cabeçalho de TypeNameResolver.luau; uma
	segunda chamada de `Set` sobrescreve a primeira sem erro.

	Roda com `lune run src/runtime/TypeNameResolver.spec.luau`.
]]

local process = require("@lune/process")
local TypeNameResolver = require("./TypeNameResolver")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

test("Resolve devolve nil quando nenhum resolvedor foi instalado", function()
	-- Módulo isolado por processo (estado global mutável, mesma invariante de
	-- UnknownClassResolver) -- este é o primeiro teste do arquivo, roda antes de qualquer Set.
	assert(TypeNameResolver.Resolve("qualquer coisa") == nil, "sem Set, Resolve deveria devolver nil sempre")
	assert(TypeNameResolver.Resolve(5) == nil, "sem Set, Resolve deveria devolver nil também para number")
	assert(TypeNameResolver.Resolve(nil) == nil, "sem Set, Resolve deveria devolver nil também para nil")
end)

test("depois de Set, Resolve repassa o veredito do resolvedor instalado", function()
	TypeNameResolver.Set(function(value: unknown): string?
		if value == "marcador-vector3" then
			return "Vector3"
		end
		return nil
	end)

	assert(TypeNameResolver.Resolve("marcador-vector3") == "Vector3", "Resolve deveria devolver o nome que o resolvedor instalado devolveu")
end)

test("Resolve devolve nil (nunca erro) quando o resolvedor instalado não reconhece o valor -- não confundir com 'nada instalado'", function()
	TypeNameResolver.Set(function(value: unknown): string?
		if value == "marcador-color3" then
			return "Color3"
		end
		return nil
	end)

	local ok, result = pcall(function()
		return TypeNameResolver.Resolve(42)
	end)
	assert(ok, "Resolve nunca deveria levantar erro, mesmo para um valor que o resolvedor não reconhece")
	assert(result == nil, "valor não reconhecido pelo resolvedor instalado deveria devolver nil, não um placeholder")
end)

test("uma segunda chamada de Set sobrescreve a primeira silenciosamente", function()
	TypeNameResolver.Set(function(_value: unknown): string?
		return "Primeiro"
	end)
	TypeNameResolver.Set(function(_value: unknown): string?
		return "Segundo"
	end)

	assert(TypeNameResolver.Resolve("qualquer coisa") == "Segundo", "a segunda instalação deveria vencer, sem erro")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
