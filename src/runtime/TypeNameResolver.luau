--!strict

--[[
	TypeNameResolver: ponte com o território novo de Value Types simulados (`Vector3`/`CFrame`/
	`Color3`/`Enum`/...), para o wrapper de `typeof` do Sandbox (Sandbox.luau,
	`resolveTypeName`). Desenho completo no documento de arquitetura de Value Types simulados,
	seção 3.4 "runtime", subitem (a)/(b) ("Decisão 4"). task-runtime-032.

	MESMO PRECEDENTE ESTRUTURAL de `UnknownClassResolver.luau` (task-runtime-030), copiado de
	propósito: `runtime` precisa de um fato que só outro território sabe responder (aqui,
	"qual é o nome de tipo Roblox deste userdata de value type?") e o recebe INJETADO, nunca
	descobrindo sozinho — `runtime` nunca lê o Roblox API Dump (regra 02) e este território
	nunca requer nada do território de Value Types simulados (invariante verificável por grep
	sobre o nome daquele território, ver desenho §2/§12).

	ESTADO GLOBAL MUTÁVEL, um ponteiro de função por processo — mesma invariante já documentada
	em `ClassRegistry.luau`/`Context.luau`/`UnknownClassResolver.luau`: um processo por execução
	do `luaubench run`, sem reset. `Set` SOBRESCREVE silenciosamente numa segunda chamada.

	DIFERENÇA DELIBERADA em relação a `UnknownClassResolver` (documentada aqui porque é fácil
	copiar o precedente sem perceber a diferença de contrato): `UnknownClassResolver.Resolve`,
	uma vez instalado, é TOTAL — sempre devolve um veredito não-nil para qualquer `className`.
	`TypeNameResolver.Resolve` é PARCIAL por desenho: `nil` significa tanto "nenhum resolvedor
	instalado" QUANTO "resolvedor instalado, mas `value` não é um value type reconhecido" (ex.:
	um `number`, uma `string`, uma tabela comum do script). As duas situações precisam produzir
	o MESMO resultado aqui — `nil` — porque o chamador (Sandbox.luau) reage à ambiguidade da
	MESMA forma nos dois casos: cai no `typeof` nativo do Luau (passo 5 da Decisão 4). Se este
	módulo tentasse diferenciar "não instalado" de "não reconhecido", o chamador não teria uso
	nenhum para essa distinção, e o contrato ficaria mais complicado sem ganhar nada.

	CONTRATO OBRIGATÓRIO do resolvedor instalado via `Set` (mesma disciplina de
	`UnknownClassResolver`):
	  - PURO: consulta de tabela/registro já resolvido, sem efeito colateral observável.
	  - NUNCA chama `error()`: propagaria como falha inesperada de LuauBench para dentro do
	    `typeof` do script do usuário, que no Roblox real jamais lança.
	  - Devolve `nil` para qualquer `value` que não seja um value type que ele reconheça —
	    nunca uma string vazia, nunca "unknown" como placeholder.

	Módulo folha: ZERO `require`. Não menciona value type nenhum por nome, nem API Dump, nem
	manifesto — esse vocabulário é do outro território (regra de idioma: `runtime` só fala a
	língua do motor Roblox).

	Depende de: nada. Usado por: `Sandbox.luau` (consulta via `Resolve`), `cli` (instala via
	`Set`, no composition root — `RunCommand`, ao lado de `Services.Bootstrap`/
	`UnknownClassResolver.Set`, ver desenho §3.4 "cli", subitem (d)). Reexportado por
	`init.luau`: só `Set` + o tipo `TypeNameResolver` — `Resolve` fica interno ao território
	(mesmo precedente de `UnknownClassResolver.Resolve`: `services`/`cli` não têm uso legítimo
	para consultá-lo de volta, só para instalar).
]]

export type TypeNameResolver = (value: unknown) -> string?

local TypeNameResolver = {}

-- Estado privado do módulo -- um processo por execução do LuauBench, sem função de reset (mesma
-- invariante de ClassRegistry/Context/UnknownClassResolver, ver cabeçalho acima).
local installed: TypeNameResolver? = nil

-- Chamado só pelo composition root (`cli/RunCommand.luau`) -- sobrescreve silenciosamente numa
-- segunda chamada (ver cabeçalho acima); não existe `TypeNameResolver.Reset`/`Unset`.
function TypeNameResolver.Set(resolver: TypeNameResolver): ()
	installed = resolver
end

-- `nil` <=> nenhum resolvedor instalado OU `value` não é um value type reconhecido pelo
-- resolvedor instalado (ver DIFERENÇA DELIBERADA no cabeçalho -- as duas situações são
-- indistinguíveis de propósito). NUNCA levanta erro.
function TypeNameResolver.Resolve(value: unknown): string?
	if installed == nil then
		return nil
	end
	return installed(value)
end

return TypeNameResolver
