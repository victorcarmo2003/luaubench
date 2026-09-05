--!strict

--[[
	Fábrica ÚNICA de userdata imutável dos value types simulados (task-valuetypes-002). Desenho
	completo em .claude/agents-memory/arquiteto-valuetypes-2026-09-05.md, seção 3.1 ("Userdata.luau
	-- fábrica única de userdata imutável"). Fatos empíricos usados aqui vêm da seção 0.3 do mesmo
	documento, reproduzidos de novo nesta tarefa com `lune run` sobre scripts descartáveis de
	scratchpad (newproxy(true): type()=="userdata", setmetatable/pairs erram nativamente,
	__metatable trava getmetatable(), __eq só dispara quando os dois lados são userdata).

	ESTE É O ÚNICO LUGAR DO PROJETO ONDE `newproxy(true)` É CHAMADO PARA UM VALUE TYPE (regra 00 --
	duas fábricas seria a divergência silenciosa que a regra proíbe; mesmo argumento que
	`Sandbox.buildEnvironment` já registra para a whitelist de globais, e mesmo precedente literal
	de `runtime/Instance.luau:Instance.NewBase`, que também usa `newproxy(true)` para o MESMO fim
	-- fazer um objeto ser userdata de verdade em vez de tabela fingindo ser userdata -- só que para
	Instance, não para value type. `Userdata.luau` e `Instance.NewBase` são desenhos IRMÃOS,
	território separado por decisão do arquiteto (grafo acíclico, seção 2 do desenho), nunca o
	mesmo módulo).

	## As quatro invariantes da fábrica (obrigatórias, nenhum tipo individual pode afrouxar)

	1. `__metatable` SEMPRE travado com uma string fixa -- `getmetatable(v)` nunca devolve a
	   metatable real (nossos closures/estado ficam inalcançáveis do script). Mesma string já usada
	   por `runtime/Instance.luau` para o mesmo propósito ("The metatable is locked") -- P4 (seção 9
	   do desenho) não confirmou o texto exato que o Roblox usa, mas reusar a MESMA string do resto
	   do projeto é a escolha mais segura disponível: pelo menos consistente internamente, e as duas
	   pendências se revisitam juntas se P4 for pesquisada.
	2. `__newindex` SEMPRE erra -- todo value type é imutável, sem exceção NESTA leva.
	   `RaycastParams`/`OverlapParams` (leva 2) são mutáveis de verdade no Roblox real e vão
	   precisar de um `Descriptor.SetProperty` opcional que AINDA NÃO EXISTE -- decisão já registrada
	   pelo arquiteto (seção 3.1, "Invariantes que a fábrica garante"), não uma omissão desta tarefa.
	3. Estado por instância mora numa side-table module-local com `__mode = "k"` (`stateOf`,
	   abaixo) -- nunca em upvalue exposta ao sandbox, nunca alcançável por fora deste módulo.
	   Chave fraca: quando o script solta a última referência ao proxy, o GC coleta o proxy E o
	   estado junto, sem exigir um `Destroy()` explícito (spec cobre com `collectgarbage` antes/
	   depois de 100k valores soltos).
	4. `__eq` só delega para `descriptor.Equals` quando OS DOIS LADOS são userdata NOSSO (têm
	   entrada em `stateOf`) e do MESMO `TypeName` -- comparação com userdata alheio (outro tipo
	   nosso, ou um `newproxy` cru de fora deste módulo) devolve `false` SEM erro. Verificado
	   empiricamente na sessão do arquiteto (seção 0.3) e reconfirmado aqui.

	## Por que newproxy(true) em vez de tabela com metatable compartilhada

	Medido pelo arquiteto (seção 0.4): newproxy é ~11x mais caro que tabela (3.2 µs vs 0.28 µs por
	operação em 200k iterações). Decisão consciente (seção 4 do desenho, "Decisão 2"): o caso de uso
	central do projeto (serializer de data manager, ProfileStore e afins) faz `type(v) == "table"`
	para decidir se desce recursivamente um valor -- um value type representado como TABELA seria
	confundido com um dicionário comum e corrompido silenciosamente ao serializar. `type()` devolver
	"userdata" (não "table") é a fidelidade que compra exatamente essa proteção.

	## Como a fábrica evita realocar uma metatable por operação

	Cada `newproxy(true)` cria uma metatable NOVA (não hà como reaproveitar uma única metatable
	compartilhada para userdata -- mesma observação já registrada em `Instance.NewBase`). O que É
	compartilhado entre todas as instâncias do MESMO tipo são as FUNÇÕES fechadas (`sharedIndex`,
	`sharedNewIndex`, `sharedEq`, `sharedTostring`, e os wrappers de operador) -- construídas UMA vez
	por chamada de `Define`, e só REFERENCIADAS (não recriadas) em cada nova metatable dentro da
	`Factory` devolvida. O custo por instância fica em: 1 `newproxy(true)` + 1 tabela de metatable
	pequena (até 10 campos) + 1 entrada na side-table -- nunca uma closure nova por instância.

	## Limitação conhecida: despacho cruzado em Add/Sub entre tipos diferentes

	`__add`/`__sub` são instalados em TODA instância que os suporta. Se um script somar/subtrair
	dois value types DIFERENTES onde só um dos dois define o operador (ex.: um tipo sem aritmética
	MENOS um tipo que a tem), o Luau despacha pelo operando que TEM o metamétodo, mas preserva a
	ORDEM original dos operandos ao chamar -- então o wrapper aqui pode acabar invocando
	`descriptor.Sub` com os operandos LOGICAMENTE invertidos (calculando "b - a" para uma chamada de
	script que escreveu "a - b"). Como `descriptor.Sub`/`descriptor.Add` sempre validam o
	`bTypeName` recebido e nenhum tipo desta leva aceita um `bTypeName` alheio ao seu próprio, o
	resultado nesse caminho é SEMPRE um erro coerente ("attempt to perform arithmetic..."), nunca um
	valor numericamente errado -- só a mensagem de erro pode descrever a operação na ordem trocada.
	Nenhum tipo da leva 1 (Vector3/Vector2/CFrame/Color3/UDim/UDim2) de fato aciona este caminho
	(todos só somam/subtraem consigo mesmos), documentado aqui como divergência declarada (regra 00)
	para o caso hipotético de um tipo futuro cruzar esse caminho.

	Depende de: nada (módulo-folha, junto com Float32.luau). Usado por: todo `types/*.luau`.
]]

export type Fields = { unknown }

export type Descriptor = {
	-- Nome que `typeof()` deve devolver: "Vector3", "CFrame", "EnumItem", ...
	TypeName: string,
	-- Métodos de instância (`v:Dot(o)`). Tabela COMPARTILHADA e CONGELADA por tipo -- `Define`
	-- ERRA se receber uma tabela não congelada (mesma disciplina de
	-- `runtime/Instance.luau:SetClassMethods`, que faz a mesma checagem pelo mesmo motivo: a
	-- tabela é compartilhada por TODAS as instâncias do tipo e não pode ser mutável depois).
	Methods: { [string]: unknown },
	-- Propriedades calculadas/lidas (`v.X`, `v.Magnitude`). Recebe os Fields crus da instância
	-- sendo indexada (não um valor fixo por tipo) e devolve (valor, achou?) -- `false` em achou
	-- sinaliza "não é um membro válido", e é a FÁBRICA (não o tipo individual) que formata o erro
	-- "X is not a valid member of Y", pra manter a mensagem consistente entre todos os tipos.
	GetProperty: (fields: Fields, key: string) -> (unknown, boolean),
	-- `tostring(v)`. Delega pra `Float32.Format` internamente (não é responsabilidade deste
	-- módulo saber disso -- cada `types/*.luau` decide seu próprio formato).
	Format: (fields: Fields) -> string,
	-- Metamétodos aritméticos OPCIONAIS. `nil` = operador não suportado pelo tipo -- a fábrica
	-- simplesmente NÃO instala o metamétodo correspondente, e o erro nativo que o Luau levanta
	-- sozinho ("attempt to perform arithmetic on X and Y") já é o comportamento certo (ex.:
	-- Color3 não tem NENHUM operador aritmético, confirmado por pesquisa -- `math_operations: []`
	-- na doc oficial).
	--
	-- Add/Sub recebem os DOIS lados já desembrulhados como `Fields` (a fábrica garante isso antes
	-- de chamar -- ver `buildFieldsBinaryOp` abaixo) mais o `TypeName` do lado direito, pra que o
	-- tipo decida se aceita ou rejeita a combinação (ex.: só `Vector3 + Vector3`).
	Add: ((a: Fields, b: Fields, bTypeName: string) -> unknown)?,
	Sub: ((a: Fields, b: Fields, bTypeName: string) -> unknown)?,
	-- Mul/Div/IDiv recebem os operandos CRUS (não desembrulhados) porque, ao contrário de
	-- Add/Sub, aceitam legitimamente um lado que NÃO é um value type nosso (`Vector3 * number`).
	-- A fábrica instala a função do descritor DIRETO como metamétodo, sem wrapper -- quem decide
	-- o que fazer com cada operando (inclusive chamar `Userdata.Unwrap` sobre o lado que É um
	-- value type) é o próprio `types/*.luau`.
	Mul: ((a: unknown, b: unknown) -> unknown)?,
	Div: ((a: unknown, b: unknown) -> unknown)?,
	IDiv: ((a: unknown, b: unknown) -> unknown)?,
	-- Unário `-v`. Só tem UM operando -- sempre `Fields` do próprio tipo.
	Unm: ((a: Fields) -> unknown)?,
	-- Igualdade componente a componente. Só é chamado pela fábrica quando AMBOS os lados já
	-- foram confirmados como userdata NOSSO do MESMO `TypeName` -- invariante 4, ver cabeçalho.
	Equals: (a: Fields, b: Fields) -> boolean,
}

export type Factory = (fields: Fields) -> unknown

local Userdata = {}

-- Invariante 1 (ver cabeçalho): string fixa devolvida por `getmetatable(v)` em TODO value type
-- desta fábrica. Mesma string já usada em `runtime/Instance.luau` (`Instance.NewBase`) pro mesmo
-- fim -- P4 (seção 9 do desenho) não confirmou o texto exato do Roblox real, mas reusar a MESMA
-- string do resto do projeto é a escolha mais segura disponível.
local LOCKED_METATABLE_MESSAGE = "The metatable is locked"

-- Tipo NOMINAL opaco usado só como chave de `stateOf`, abaixo -- em runtime o valor real É
-- SEMPRE um `newproxy(true)` (userdata), nunca uma tabela de fato. Mesmo padrão de cast em duas
-- etapas via `unknown` já usado em `runtime/Instance.luau` para `internals: { [Instance]: Internal
-- }` (lookup por `internals[value :: Instance]` mesmo quando `value` pode não ser uma Instance de
-- verdade -- o cast é uma ASSERÇÃO pro type-checker, a busca em runtime é um hash lookup cru que
-- devolve `nil` pra qualquer chave nunca inserida, sem erro).
type ProxyHandle = { __UserdataProxyHandleBrand: unknown }

type StateEntry = {
	TypeName: string,
	Fields: Fields,
}

-- Invariante 3 (ver cabeçalho): estado de TODA instância de TODO value type do território,
-- module-local, com chave FRACA (`__mode = "k"`) -- inatingível do sandbox do script (este módulo
-- nunca entra em `env`, ver `runtime/Sandbox.luau`) e coletado junto com o proxy quando o script
-- solta a última referência (spec cobre com `collectgarbage` antes/depois de 100k valores soltos).
local stateOf: { [ProxyHandle]: StateEntry } =
	(setmetatable({}, { __mode = "k" }) :: unknown) :: { [ProxyHandle]: StateEntry }

-- TypeNames já registrados por `Define` -- guarda contra registro duplicado. É um bug de
-- programação (dois módulos de `types/` reivindicando o mesmo nome corromperia silenciosamente o
-- comportamento de um deles, já que os dois passariam a compartilhar `descriptor.TypeName` mas
-- teriam `Methods`/`GetProperty`/etc. diferentes), então erra alto e cedo -- mesma disciplina de
-- `ClassRegistry`/`Context.Set`/`UnknownClassResolver.Set` (registro nunca silenciosamente
-- sobrescrito sem decisão explícita). NÃO usa `__mode`: o conjunto de TypeNames é fixo e pequeno
-- por processo (uma dúzia de tipos na leva 1), sem motivo pra coletar.
local registeredTypeNames: { [string]: boolean } = {}

-- Descreve `value` pra mensagem de erro de operador: o `TypeName` nosso se for um value type
-- registrado, senão o `typeof()` nativo do Luau (mesmo vocabulário que o erro NATIVO de
-- aritmética do Luau usaria, ex.: "attempt to perform arithmetic (add) on Vector3 and string").
local function describeOperand(value: unknown): string
	local entry = stateOf[value :: ProxyHandle]
	if entry ~= nil then
		return entry.TypeName
	end
	return typeof(value)
end

-- Constrói o wrapper de `__add`/`__sub`: desembrulha os dois operandos como `Fields` (exigido
-- pela assinatura de Add/Sub, ver `Descriptor` acima) e delega pra `impl`. Ver "Limitação
-- conhecida: despacho cruzado" no cabeçalho do módulo pro caso de tipos DIFERENTES.
local function buildFieldsBinaryOp(
	typeName: string,
	operatorSymbol: string,
	impl: (a: Fields, b: Fields, bTypeName: string) -> unknown
): (unknown, unknown) -> unknown
	return function(a: unknown, b: unknown): unknown
		local entryA = stateOf[a :: ProxyHandle]
		local entryB = stateOf[b :: ProxyHandle]

		if entryA ~= nil and entryA.TypeName == typeName and entryB ~= nil then
			return impl(entryA.Fields, entryB.Fields, entryB.TypeName)
		end

		-- Luau despachou pelo operando da DIREITA -- ver "Limitação conhecida" no cabeçalho.
		if entryB ~= nil and entryB.TypeName == typeName and entryA ~= nil then
			return impl(entryB.Fields, entryA.Fields, entryA.TypeName)
		end

		error(`attempt to perform arithmetic ({operatorSymbol}) on {describeOperand(a)} and {describeOperand(b)}`, 2)
	end
end

-- Constrói o wrapper de `__unm` (`-v`, um operando só).
local function buildUnm(typeName: string, impl: (a: Fields) -> unknown): (unknown) -> unknown
	return function(a: unknown): unknown
		local entry = stateOf[a :: ProxyHandle]
		if entry == nil or entry.TypeName ~= typeName then
			error(`attempt to perform arithmetic (unm) on {describeOperand(a)}`, 2)
		end
		return impl(entry.Fields)
	end
end

-- Registra um tipo e devolve a fábrica dele. Chamada UMA vez por tipo, no load do módulo daquele
-- tipo (`types/Vector3.luau`, etc.) -- ver `registeredTypeNames` acima pra o que acontece numa
-- segunda chamada com o mesmo `TypeName`.
function Userdata.Define(descriptor: Descriptor): Factory
	if descriptor.TypeName == "" then
		error("Userdata.Define: TypeName não pode ser uma string vazia", 2)
	end
	if registeredTypeNames[descriptor.TypeName] then
		error(
			`Userdata.Define: TypeName '{descriptor.TypeName}' já foi registrado -- bug de programação (dois módulos de types/ reivindicando o mesmo nome, ou Define chamado duas vezes pro mesmo tipo)`,
			2
		)
	end
	if not table.isfrozen(descriptor.Methods) then
		error(
			`Userdata.Define('{descriptor.TypeName}'): Methods precisa estar congelada (table.freeze) antes do registro -- é compartilhada por todas as instâncias do tipo e não pode ser mutável depois (mesma disciplina de Instance.SetClassMethods)`,
			2
		)
	end
	registeredTypeNames[descriptor.TypeName] = true

	local typeName = descriptor.TypeName

	-- Compartilhado entre TODAS as instâncias do tipo -- construído uma vez aqui, só
	-- REFERENCIADO (nunca recriado) em cada metatable nova dentro da Factory abaixo.
	local sharedIndex = function(self: unknown, key: unknown): unknown
		local entry = stateOf[self :: ProxyHandle]
		if entry == nil then
			error("Userdata.luau: __index chamado sobre um proxy sem estado registrado (bug interno do território valuetypes)", 2)
		end
		if typeof(key) ~= "string" then
			error(`{tostring(key)} is not a valid member of {typeName}`, 2)
		end
		local keyString = key :: string

		local method = descriptor.Methods[keyString]
		if method ~= nil then
			return method
		end

		local value, found = descriptor.GetProperty(entry.Fields, keyString)
		if found then
			return value
		end

		-- Mesmo formato de mensagem já usado por runtime/Instance.luau para Instance
		-- ("{key} is not a valid member of {ClassName}") -- aproximação de boa-fé para value
		-- types: não confirmado byte a byte contra o Roblox real para este caso específico
		-- (P10, seção 9 do desenho, só confirmou o formato pra Enum/EnumItem), mas é o mesmo
		-- vocabulário que o Roblox usa consistentemente em toda a plataforma pra "membro
		-- inválido", então é a aproximação mais segura disponível.
		error(`{keyString} is not a valid member of {typeName}`, 2)
	end

	-- Invariante 2 (ver cabeçalho): SEMPRE erra, sem exceção nesta leva. Texto exato do Roblox
	-- real não foi pesquisado (não é P4 nem nenhum item da seção 9 do desenho) -- aproximação de
	-- boa-fé, documentada aqui como tal (regra 00: divergência nunca silenciosa).
	local sharedNewIndex = function(_self: unknown, key: unknown, _value: unknown): ()
		error(`Unable to assign property {tostring(key)}. {typeName} is a read-only value type and cannot be mutated`, 2)
	end

	-- Invariante 4 (ver cabeçalho): só delega pra `descriptor.Equals` quando os dois lados são
	-- userdata NOSSO do MESMO TypeName. Comparação com userdata alheio (outro tipo nosso, ou um
	-- newproxy cru externo) devolve `false` SEM erro -- verificado empiricamente contra o Luau do
	-- Lune (arquiteto, seção 0.3; reconfirmado nesta tarefa).
	local sharedEq = function(a: unknown, b: unknown): boolean
		local entryA = stateOf[a :: ProxyHandle]
		local entryB = stateOf[b :: ProxyHandle]
		if entryA == nil or entryB == nil then
			return false
		end
		if entryA.TypeName ~= entryB.TypeName then
			return false
		end
		return descriptor.Equals(entryA.Fields, entryB.Fields)
	end

	local sharedTostring = function(self: unknown): string
		local entry = stateOf[self :: ProxyHandle]
		if entry == nil then
			error("Userdata.luau: __tostring chamado sobre um proxy sem estado registrado (bug interno do território valuetypes)", 2)
		end
		return descriptor.Format(entry.Fields)
	end

	-- Operadores opcionais: `nil` no descritor = NÃO instalar o metamétodo correspondente (ver
	-- comentário do campo `Add`/`Sub`/etc. em `Descriptor`, acima) -- decidido uma vez aqui, fora
	-- da Factory, pra não recalcular "esse tipo tem Add?" a cada instância criada.
	local sharedAdd = if descriptor.Add ~= nil then buildFieldsBinaryOp(typeName, "add", descriptor.Add) else nil
	local sharedSub = if descriptor.Sub ~= nil then buildFieldsBinaryOp(typeName, "sub", descriptor.Sub) else nil
	local sharedUnm = if descriptor.Unm ~= nil then buildUnm(typeName, descriptor.Unm) else nil

	return function(fields: Fields): unknown
		-- ÚNICO ponto do projeto (junto com Instance.NewBase, em runtime, pro caso de
		-- Instance) que chama newproxy(true) -- ver cabeçalho do módulo.
		local proxy = newproxy(true)
		local meta = (getmetatable(proxy) :: unknown) :: { [string]: unknown }
		meta.__index = sharedIndex
		meta.__newindex = sharedNewIndex
		meta.__eq = sharedEq
		meta.__tostring = sharedTostring
		meta.__metatable = LOCKED_METATABLE_MESSAGE

		if sharedAdd ~= nil then
			meta.__add = sharedAdd
		end
		if sharedSub ~= nil then
			meta.__sub = sharedSub
		end
		if descriptor.Mul ~= nil then
			meta.__mul = descriptor.Mul
		end
		if descriptor.Div ~= nil then
			meta.__div = descriptor.Div
		end
		if descriptor.IDiv ~= nil then
			meta.__idiv = descriptor.IDiv
		end
		if sharedUnm ~= nil then
			meta.__unm = sharedUnm
		end

		stateOf[(proxy :: unknown) :: ProxyHandle] = { TypeName = typeName, Fields = fields }
		return proxy
	end
end

-- Nome de tipo Roblox de um valor, ou `nil` se não for value type nosso (inclusive: não é
-- userdata, é userdata alheio, ou é uma tabela/número/string comum). Alimenta
-- `ValueTypes.TypeNameOf` -> `Runtime.TypeNameResolver.Set` (ponte com `runtime`, task futura --
-- ver .claude/agents-memory/arquiteto-valuetypes-2026-09-05.md, seção 3.4-runtime).
function Userdata.TypeNameOf(value: unknown): string?
	local entry = stateOf[value :: ProxyHandle]
	if entry == nil then
		return nil
	end
	return entry.TypeName
end

-- Campos crus de um valor NOSSO. Só para uso interno do território (um tipo lendo outro: CFrame
-- lendo os componentes de um Vector3) -- NUNCA exposto fora de `src/valuetypes/`. Erra se o valor
-- não for do TypeName pedido, citando o que ele É de verdade (nosso TypeName, se for outro value
-- type nosso, ou o `typeof()` nativo caso contrário) -- é o que dá a mensagem certa em
-- `CFrame.new(1, "x", 3)` (task futura).
function Userdata.Unwrap(value: unknown, expectedTypeName: string): Fields
	local entry = stateOf[value :: ProxyHandle]
	if entry == nil or entry.TypeName ~= expectedTypeName then
		error(`expected {expectedTypeName}, got {describeOperand(value)}`, 2)
	end
	return entry.Fields
end

return Userdata
