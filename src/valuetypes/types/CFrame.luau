--!strict

--[[
	CFrame simulado (task-valuetypes-006). Desenho completo em
	.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md (seção 3.2). Toda ASSINATURA (nomes de
	construtor/propriedade/método, aridade, aliases) confirmada contra o YAML oficial
	(`Roblox/creator-docs`) em .claude/agents-memory/pesquisa-datatypes-vector-cframe-2026-09-05.md,
	seções 1-9 -- nenhuma assinatura aqui vem de memória. O COMPORTAMENTO NUMÉRICO interno (fórmulas
	de composição/decomposição de matriz) é escrito à mão (regra 03: "o dump só dá a superfície, o
	comportamento é escrito à mão") e documentado abaixo onde não é uma citação literal da pesquisa.

	## DIVERGÊNCIA D1 (OBRIGATÓRIA -- ver desenho §8, linha D1)

	Os 12 componentes de ENTRADA e SAÍDA são float32 exatos (quantizados via `Float32.Quantize` no
	construtor privado único, `construct`, abaixo -- mesma disciplina de Vector3/Vector2). O CAMINHO
	INTERNO de cálculo (composição de CFrame*CFrame, slerp de `Lerp`, conversão quatérnion<->matriz,
	extração de Euler/eixo-ângulo) usa `number` do Luau, que é DOUBLE de 64 bits. Reproduzir a ordem
	EXATA de operações internas do motor fechado do Roblox exigiria o código-fonte dele -- fora de
	alcance. Erro relativo esperado ~1e-7 (ULP de float32), invisível pra lógica de jogo comum.
	Reproduzir aqui só pra não ser silencioso (regra 00).

	## DIVERGÊNCIA D7 (OBRIGATÓRIA -- ver desenho §8, linha D7)

	`:Orthonormalize()` é exposto como MÉTODO EXPLÍCITO abaixo -- existe no Roblox real, confirmado
	pela pesquisa (seção 4, lista de métodos). O que NÃO é reproduzido aqui é a re-ortonormalização
	IMPLÍCITA que o motor do Roblox real faz em ALGUNS caminhos internos (por exemplo, depois de
	multiplicações repetidas de CFrame que acumulam erro de ponto flutuante e desviam a matriz de
	rotação de ortonormal) -- P1 (seção 9 do desenho, "O Roblox re-ortonormaliza CFrame
	implicitamente? Em quais operações?") permanece ABERTA: a pesquisa não confirmou QUAIS operações
	fazem isso silenciosamente no motor real. Aqui, TODA operação (`*`, `Lerp`, `fromEulerAngles*`,
	etc.) produz exatamente a matriz calculada pela fórmula, sem nenhuma correção de deriva
	automática -- só `:Orthonormalize()` corrige, e só quando chamado explicitamente pelo script.
	Consequência prática: uma cadeia MUITO longa de multiplicações de CFrame pode acumular deriva de
	ortonormalidade um pouco mais visível aqui do que no Roblox real (que talvez corrija em algum
	ponto não documentado). Não é um bug -- é a pendência P1 sendo respeitada (não inventar onde a
	pesquisa não confirmou), reavaliar se P1 for pesquisada.

	## PENDÊNCIA P8 (NÃO CONFIRMADA -- mesma pendência de Vector3/Vector2, ver lá)

	`==` aqui é EXATO, componente a componente (`Equals`, abaixo), pelos 12 componentes. Mesma
	inferência não confirmada por citação direta (a existência de `FuzzyEq` como método separado só
	faz sentido se `==` já não fosse fuzzy).

	## Seis overloads de `CFrame.new` -- ordem exata confirmada pela pesquisa (seção 1)

	Luau não tem overload nativo por assinatura -- `newRaw` (abaixo) despacha em runtime pela
	CONTAGEM de argumentos, que sozinha já distingue os 6 casos (0/1/2/3/7/12 -- nenhum arg count se
	repete entre dois overloads diferentes, confirmado pela pesquisa: "não existem overloads de 1 ou
	2 argumentos além dos listados"), exposto publicamente com o tipo INTERSECÇÃO `CFrameNewOverload`
	(mesmo idioma de "overload por intersecção de tipos de função" já usado em
	`types/UDim2.luau:UDim2NewOverload`):

	1. `CFrame.new()` -- identidade: posição (0,0,0), matriz identidade.
	2. `CFrame.new(pos: Vector3)` -- sem rotação.
	3. `CFrame.new(pos: Vector3, lookAt: Vector3)` -- OVERLOAD LEGADO (a doc oficial diz
	   literalmente "replaced by CFrame.lookAt()"), `up` fixo em (0,1,0) -- mesmo algoritmo de
	   `CFrame.lookAt`, ver função `lookAtImpl` abaixo.
	4. `CFrame.new(x, y, z: number)` -- sem rotação.
	5. `CFrame.new(x, y, z, qX, qY, qZ, qW: number)` -- posição + quatérnion. "Quatérnion não-unitário
	   é normalizado automaticamente" (citação literal da pesquisa) -- `quaternionToMatrix` abaixo
	   normaliza sempre, defensivamente (inclusive pro caso qw=qx=qy=qz=0, que degenera pra
	   identidade em vez de dividir por zero -- caso não documentado pela pesquisa, aproximação de
	   boa-fé).
	6. `CFrame.new(x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22: number)` -- posição + matriz
	   de rotação 3×3 LINHA-MAJOR, ordem exata confirmada pela pesquisa e igual à ordem de
	   `GetComponents()`.

	## Representação interna (`Userdata.Fields`, 12 números)

	Índice 1=x, 2=y, 3=z, 4=R00, 5=R01, 6=R02, 7=R10, 8=R11, 9=R12, 10=R20, 11=R21, 12=R22 -- mesma
	ordem de `GetComponents()`/`tostring` (confirmado pela pesquisa, seção 4 e 6). Colunas da matriz
	(convenção confirmada pela pesquisa, seção 3): coluna 0 = (R00,R10,R20) = XVector/RightVector;
	coluna 1 = (R01,R11,R21) = YVector/UpVector; coluna 2 = (R02,R12,R22) = ZVector; LookVector =
	-ZVector.

	## Aproximações de boa-fé NÃO confirmadas por citação literal da pesquisa (regra 00 -- nunca
	## silenciosas; cada uma documentada de novo no ponto exato do código onde aparece)

	- **`lookAtImpl`** (usado por `CFrame.lookAt`/`lookAlong`/overload de 2 args): algoritmo padrão
	  de "lookAt" de câmera right-handed (zAxis = normalize(at-alvo), xAxis = normalize(up×zAxis),
	  yAxis = zAxis×xAxis). A pesquisa confirma a FÓRMULA CONCEITUAL ("assumindo (0,1,0) como up") e
	  o INTERVALO/CASO IDENTIDADE (verificado manualmente contra o exemplo oficial de
	  `CFrame.new(0,0,0)` no cabeçalho de `lookAtImpl`, abaixo) mas não cita o algoritmo exato do
	  motor fechado do Roblox.
	- **`fromEulerAnglesXYZ`/`fromEulerAnglesYXZ`**: a pesquisa confirma que os DOIS EXISTEM, que
	  `Angles`≡XYZ e `fromOrientation`≡YXZ (citação literal), e que XYZ/YXZ "aproximado, sujeito a
	  gimbal lock perto de ±90°" -- mas NÃO cita a fórmula de composição exata. Implementado aqui
	  como XYZ = `fromAxisAngle(xAxis,rx) * fromAxisAngle(yAxis,ry) * fromAxisAngle(zAxis,rz)` (forma
	  fechada, ver `fromEulerAnglesXYZ` abaixo) e YXZ = mesma ideia com Y aplicado por fora --
	  convenção amplamente usada por engines de jogo pra nomes "XYZ"/"YXZ" de Euler angles, mas não é
	  uma citação do motor Roblox fechado.
	- **`ToEulerAnglesXYZ`/`ToEulerAnglesYXZ`/`ToAxisAngle`**: extração (inversa das fórmulas acima)
	  via decomposição padrão de matriz de rotação -- construída para ser EXATAMENTE a inversa
	  matemática das fórmulas de composição deste módulo (round-trip garantido por construção, ver
	  spec), com tratamento de gimbal lock/ângulo degenerado documentado nos comentários de cada
	  função (`toEulerAnglesXYZ`/`toEulerAnglesYXZ`/`toAxisAngle`, abaixo).
	- **`Lerp`** (rotação via slerp): quatérnion extraído da matriz (`matrixToQuaternion`), slerp
	  padrão com fallback pra interpolação linear normalizada quando os dois quatérnions são quase
	  paralelos (evita divisão por sin(θ)≈0) -- técnica padrão de computação gráfica, não uma citação
	  do motor Roblox fechado. A doc só confirma QUE é slerp, não a implementação exata.
	- **`Orthonormalize`**: X mantido e normalizado; Z = (X×Y original) normalizado; Y = Z×X
	  (garante base ortonormal right-handed "próxima" da original) -- escolha própria razoável, não
	  o algoritmo interno do motor (não documentado).
	- **`FuzzyEq`**: posição component-wise (CITAÇÃO LITERAL da pesquisa). Rotação: "aproximação
	  rápida da diferença de ângulo" (citação literal, SEM fórmula) -- implementado via produto
	  interno de Frobenius entre as duas matrizes de rotação (sem trigonometria, daí "rápida"), ver
	  `fuzzyEqCFrame` abaixo.
	- **`AngleBetween`**: "só orientação, ignora posição, [0,π]" (citação literal) -- implementado via
	  ângulo da rotação relativa `Ra^T*Rb` extraído pela mesma fórmula de traço de `ToAxisAngle`.

	## Superfície da pesquisa DELIBERADAMENTE fora desta tarefa (declarado, não esquecido)

	A pesquisa confirma que também EXISTEM `CFrame.fromRotationBetweenVectors`,
	`CFrame.fromEulerAngles(rx,ry,rz,order?)` (genérico, parametrizado por `Enum.RotationOrder`) e
	`CFrame:ToEulerAngles(order?)` (genérico) -- nenhum dos três está na lista de superfície pedida
	por esta task (`task-valuetypes-006`, ver `.claude/tasks.json`) nem no desenho arquitetural §3.2.
	Ficam de fora aqui: `fromEulerAngles`/`ToEulerAngles` genéricos exigiriam `Enum.RotationOrder`
	como parâmetro (módulo `Enum` é território de outra tarefa, `task-valuetypes-003`, e importar só
	pra um enum específico aqui criaria acoplamento não desenhado) e `fromRotationBetweenVectors` não
	foi pedido. Reportado como pendência pro relatório da tarefa, não implementado por omissão
	silenciosa.

	Depende de: `../Float32`, `../Userdata`, `./Vector3`. Nenhuma dependência de
	`runtime`/`services`/`cli` (módulo-folha do território, ver desenho §2, exceto pela dependência
	interna a `types/Vector3.luau`, também dentro do território).
]]

local Float32 = require("../Float32")
local Userdata = require("../Userdata")
local Vector3 = require("./Vector3")

local TYPE_NAME = "CFrame"

-- Epsilon default de `FuzzyEq`, confirmado LITERAL e IGUAL nos três tipos (Vector3/Vector2/CFrame)
-- pela pesquisa (§9 do desenho, seção 9 da pesquisa): `0.00001` (`1e-5`).
local DEFAULT_FUZZY_EPSILON = 0.00001

-- Limiar pra detectar gimbal lock (cos/sin do ângulo médio perto de zero) nas extrações de Euler
-- angles e eixo-ângulo, abaixo -- valor próprio desta implementação (não confirmado contra o
-- Roblox real, ver "Aproximações de boa-fé" no cabeçalho).
local GIMBAL_EPSILON = 1e-6

export type CFrame = typeof(setmetatable(
	{} :: {
		X: number,
		Y: number,
		Z: number,
		Position: Vector3.Vector3,
		Rotation: CFrame,
		LookVector: Vector3.Vector3,
		RightVector: Vector3.Vector3,
		UpVector: Vector3.Vector3,
		XVector: Vector3.Vector3,
		YVector: Vector3.Vector3,
		ZVector: Vector3.Vector3,
		-- Métodos de instância -- precisam estar na parte de TABELA do tipo opaco, não na
		-- metatable (mesmo padrão de types/Vector3.luau/types/Vector2.luau). Vitrine pro
		-- type-checker; quem valida de verdade em runtime é `Userdata.luau:sharedIndex`.
		GetComponents: (
			self: CFrame
		) -> (number, number, number, number, number, number, number, number, number, number, number, number),
		-- Alias LITERAL de GetComponents (confirmado pela pesquisa: "Equivalent to GetComponents()").
		components: (
			self: CFrame
		) -> (number, number, number, number, number, number, number, number, number, number, number, number),
		Inverse: (self: CFrame) -> CFrame,
		Lerp: (self: CFrame, goal: CFrame, alpha: number) -> CFrame,
		Orthonormalize: (self: CFrame) -> CFrame,
		ToWorldSpace: (self: CFrame, ...CFrame) -> ...CFrame,
		ToObjectSpace: (self: CFrame, ...CFrame) -> ...CFrame,
		PointToWorldSpace: (self: CFrame, ...Vector3.Vector3) -> ...Vector3.Vector3,
		PointToObjectSpace: (self: CFrame, ...Vector3.Vector3) -> ...Vector3.Vector3,
		VectorToWorldSpace: (self: CFrame, ...Vector3.Vector3) -> ...Vector3.Vector3,
		VectorToObjectSpace: (self: CFrame, ...Vector3.Vector3) -> ...Vector3.Vector3,
		ToEulerAnglesXYZ: (self: CFrame) -> (number, number, number),
		ToEulerAnglesYXZ: (self: CFrame) -> (number, number, number),
		-- Alias LITERAL de ToEulerAnglesYXZ (confirmado pela pesquisa).
		ToOrientation: (self: CFrame) -> (number, number, number),
		ToAxisAngle: (self: CFrame) -> (Vector3.Vector3, number),
		FuzzyEq: (self: CFrame, other: CFrame, epsilon: number?) -> boolean,
		AngleBetween: (self: CFrame, other: CFrame) -> number,
	},
	{} :: {
		__mul: ((CFrame, CFrame) -> CFrame) & ((CFrame, Vector3.Vector3) -> Vector3.Vector3),
		__add: (CFrame, Vector3.Vector3) -> CFrame,
		__sub: (CFrame, Vector3.Vector3) -> CFrame,
		__eq: (CFrame, CFrame) -> boolean,
		__tostring: (CFrame) -> string,
	}
))

-- Tipo INTERSECÇÃO representando os SEIS overloads reais de `CFrame.new` (ver cabeçalho). Mesmo
-- padrão de `types/UDim2.luau:UDim2NewOverload`.
export type CFrameNewOverload = (() -> CFrame)
	& ((Vector3.Vector3) -> CFrame)
	& ((Vector3.Vector3, Vector3.Vector3) -> CFrame)
	& ((number, number, number) -> CFrame)
	& ((number, number, number, number, number, number, number) -> CFrame)
	& ((number, number, number, number, number, number, number, number, number, number, number, number) -> CFrame)

local function numAt(fields: Userdata.Fields, index: number): number
	return fields[index] :: number
end

-- Descreve `value` pra mensagem de erro de operador -- nosso TypeName se for value type
-- registrado, senão o `typeof()` nativo (mesmo vocabulário do erro nativo do Luau). Mesmo padrão
-- de types/Vector3.luau/types/Vector2.luau.
local function describeType(value: unknown): string
	local name = Userdata.TypeNameOf(value)
	if name ~= nil then
		return name
	end
	return typeof(value)
end

local CFrameFactory: Userdata.Factory

-- `up` default de `CFrame.lookAt`/`lookAlong`/overload legado de 2 args -- confirmado LITERAL pela
-- pesquisa: "up: Vector3? = Vector3.yAxis" e "assumindo (0,1,0) como up" no overload de 2 args.
local DEFAULT_UP_FIELDS: Userdata.Fields = { 0, 1, 0 }

-- Construtor privado ÚNICO (Decisão 3 do desenho arquitetural): quantiza os 12 componentes pra
-- float32 aqui, e só aqui -- como toda operação que produz um CFrame novo passa por esta função, a
-- aritmética inteira fica encadeada em float32 automaticamente (D1, ver cabeçalho).
local function construct(
	x: number,
	y: number,
	z: number,
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): CFrame
	local fields: Userdata.Fields = {
		Float32.Quantize(x),
		Float32.Quantize(y),
		Float32.Quantize(z),
		Float32.Quantize(r00),
		Float32.Quantize(r01),
		Float32.Quantize(r02),
		Float32.Quantize(r10),
		Float32.Quantize(r11),
		Float32.Quantize(r12),
		Float32.Quantize(r20),
		Float32.Quantize(r21),
		Float32.Quantize(r22),
	}
	return CFrameFactory(fields) :: CFrame
end

-- ====================================================================================================
-- Álgebra de matriz/vetor -- composição, transformação de ponto/vetor, inversa.
-- ====================================================================================================

-- CFrame*CFrame: "aplica a transformação do operando direito no espaço local do esquerdo"
-- (citação da pesquisa) -- posição = pa + Ra*pb, rotação = Ra*Rb (produto de matrizes, aplica Rb
-- primeiro e depois Ra sobre o resultado, ver derivação no relatório desta tarefa).
local function composeCFrame(aFields: Userdata.Fields, bFields: Userdata.Fields): CFrame
	local ax, ay, az = numAt(aFields, 1), numAt(aFields, 2), numAt(aFields, 3)
	local a00, a01, a02 = numAt(aFields, 4), numAt(aFields, 5), numAt(aFields, 6)
	local a10, a11, a12 = numAt(aFields, 7), numAt(aFields, 8), numAt(aFields, 9)
	local a20, a21, a22 = numAt(aFields, 10), numAt(aFields, 11), numAt(aFields, 12)

	local bx, by, bz = numAt(bFields, 1), numAt(bFields, 2), numAt(bFields, 3)
	local b00, b01, b02 = numAt(bFields, 4), numAt(bFields, 5), numAt(bFields, 6)
	local b10, b11, b12 = numAt(bFields, 7), numAt(bFields, 8), numAt(bFields, 9)
	local b20, b21, b22 = numAt(bFields, 10), numAt(bFields, 11), numAt(bFields, 12)

	local px = ax + a00 * bx + a01 * by + a02 * bz
	local py = ay + a10 * bx + a11 * by + a12 * bz
	local pz = az + a20 * bx + a21 * by + a22 * bz

	local r00 = a00 * b00 + a01 * b10 + a02 * b20
	local r01 = a00 * b01 + a01 * b11 + a02 * b21
	local r02 = a00 * b02 + a01 * b12 + a02 * b22
	local r10 = a10 * b00 + a11 * b10 + a12 * b20
	local r11 = a10 * b01 + a11 * b11 + a12 * b21
	local r12 = a10 * b02 + a11 * b12 + a12 * b22
	local r20 = a20 * b00 + a21 * b10 + a22 * b20
	local r21 = a20 * b01 + a21 * b11 + a22 * b21
	local r22 = a20 * b02 + a21 * b12 + a22 * b22

	return construct(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

-- CFrame*Vector3: transforma um PONTO objeto->mundo -- equivalente a PointToWorldSpace (citação
-- da pesquisa).
local function transformPoint(fields: Userdata.Fields, vFields: Userdata.Fields): Vector3.Vector3
	local x, y, z = numAt(fields, 1), numAt(fields, 2), numAt(fields, 3)
	local r00, r01, r02 = numAt(fields, 4), numAt(fields, 5), numAt(fields, 6)
	local r10, r11, r12 = numAt(fields, 7), numAt(fields, 8), numAt(fields, 9)
	local r20, r21, r22 = numAt(fields, 10), numAt(fields, 11), numAt(fields, 12)
	local vx, vy, vz = numAt(vFields, 1), numAt(vFields, 2), numAt(vFields, 3)
	return Vector3.new(
		x + r00 * vx + r01 * vy + r02 * vz,
		y + r10 * vx + r11 * vy + r12 * vz,
		z + r20 * vx + r21 * vy + r22 * vz
	)
end

-- VectorToWorldSpace/VectorToObjectSpace: "(CFrame - CFrame.Position) * v -- IGNORA translação"
-- (citação da pesquisa) -- equivalente a aplicar só a matriz de rotação, sem somar a posição.
local function rotateOnly(fields: Userdata.Fields, vFields: Userdata.Fields): Vector3.Vector3
	local r00, r01, r02 = numAt(fields, 4), numAt(fields, 5), numAt(fields, 6)
	local r10, r11, r12 = numAt(fields, 7), numAt(fields, 8), numAt(fields, 9)
	local r20, r21, r22 = numAt(fields, 10), numAt(fields, 11), numAt(fields, 12)
	local vx, vy, vz = numAt(vFields, 1), numAt(vFields, 2), numAt(vFields, 3)
	return Vector3.new(r00 * vx + r01 * vy + r02 * vz, r10 * vx + r11 * vy + r12 * vz, r20 * vx + r21 * vy + r22 * vz)
end

-- Inverse(): pra uma transformação rígida (matriz de rotação ortonormal), R^-1 = R^T (transposta) e
-- a posição inversa é q = -R^T * p -- derivação padrão de inversa de transformação afim rígida.
local function inverseOf(fields: Userdata.Fields): CFrame
	local x, y, z = numAt(fields, 1), numAt(fields, 2), numAt(fields, 3)
	local r00, r01, r02 = numAt(fields, 4), numAt(fields, 5), numAt(fields, 6)
	local r10, r11, r12 = numAt(fields, 7), numAt(fields, 8), numAt(fields, 9)
	local r20, r21, r22 = numAt(fields, 10), numAt(fields, 11), numAt(fields, 12)

	-- Transposta.
	local t00, t01, t02 = r00, r10, r20
	local t10, t11, t12 = r01, r11, r21
	local t20, t21, t22 = r02, r12, r22

	local qx = -(t00 * x + t01 * y + t02 * z)
	local qy = -(t10 * x + t11 * y + t12 * z)
	local qz = -(t20 * x + t21 * y + t22 * z)

	return construct(qx, qy, qz, t00, t01, t02, t10, t11, t12, t20, t21, t22)
end

-- ====================================================================================================
-- Quatérnion <-> matriz -- usado pelo overload de 7 args de `new` e por `Lerp` (slerp).
-- ====================================================================================================

-- Extrai um quatérnion (qx,qy,qz,qw) de uma matriz de rotação ortonormal -- algoritmo padrão do
-- traço (Shepperd), escolhendo o termo diagonal dominante pra evitar divisão por número pequeno.
local function matrixToQuaternion(
	r00: number,
	r01: number,
	r02: number,
	r10: number,
	r11: number,
	r12: number,
	r20: number,
	r21: number,
	r22: number
): (number, number, number, number)
	local trace = r00 + r11 + r22
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		return (r21 - r12) / s, (r02 - r20) / s, (r10 - r01) / s, 0.25 * s
	elseif r00 > r11 and r00 > r22 then
		local s = math.sqrt(1 + r00 - r11 - r22) * 2
		return 0.25 * s, (r01 + r10) / s, (r02 + r20) / s, (r21 - r12) / s
	elseif r11 > r22 then
		local s = math.sqrt(1 + r11 - r00 - r22) * 2
		return (r01 + r10) / s, 0.25 * s, (r12 + r21) / s, (r02 - r20) / s
	else
		local s = math.sqrt(1 + r22 - r00 - r11) * 2
		return (r02 + r20) / s, (r12 + r21) / s, 0.25 * s, (r10 - r01) / s
	end
end

-- Constrói a matriz de rotação a partir de um quatérnion -- normaliza defensivamente antes (a
-- pesquisa confirma que o Roblox real normaliza um quatérnion não-unitário no overload de 7 args de
-- `CFrame.new`). Caso degenerado (comprimento 0, não documentado pela pesquisa): devolve identidade
-- em vez de dividir por zero -- aproximação de boa-fé.
local function quaternionToMatrix(
	qx: number,
	qy: number,
	qz: number,
	qw: number
): (number, number, number, number, number, number, number, number, number)
	local lengthSquared = qx * qx + qy * qy + qz * qz + qw * qw
	if lengthSquared > 0 then
		local invLength = 1 / math.sqrt(lengthSquared)
		qx, qy, qz, qw = qx * invLength, qy * invLength, qz * invLength, qw * invLength
	end

	return 1 - 2 * (qy * qy + qz * qz),
		2 * (qx * qy - qz * qw),
		2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw),
		1 - 2 * (qx * qx + qz * qz),
		2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw),
		2 * (qy * qz + qx * qw),
		1 - 2 * (qx * qx + qy * qy)
end

-- Slerp (spherical linear interpolation) padrão entre dois quatérnions, com correção de caminho
-- mais curto (nega `b` se o produto interno for negativo) e fallback pra interpolação linear
-- normalizada quando os dois quatérnions são quase paralelos (evita divisão por sin(θ)≈0) --
-- técnica padrão de computação gráfica.
local function slerp(
	ax: number,
	ay: number,
	az: number,
	aw: number,
	bx: number,
	by: number,
	bz: number,
	bw: number,
	t: number
): (number, number, number, number)
	local dot = ax * bx + ay * by + az * bz + aw * bw
	if dot < 0 then
		bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
	end

	if dot > 0.9995 then
		local rx = ax + (bx - ax) * t
		local ry = ay + (by - ay) * t
		local rz = az + (bz - az) * t
		local rw = aw + (bw - aw) * t
		local length = math.sqrt(rx * rx + ry * ry + rz * rz + rw * rw)
		if length > 0 then
			return rx / length, ry / length, rz / length, rw / length
		end
		return rx, ry, rz, rw
	end

	dot = math.clamp(dot, -1, 1)
	local theta0 = math.acos(dot)
	local theta = theta0 * t
	local sinTheta0 = math.sin(theta0)
	local s0 = math.cos(theta) - dot * math.sin(theta) / sinTheta0
	local s1 = math.sin(theta) / sinTheta0
	return ax * s0 + bx * s1, ay * s0 + by * s1, az * s0 + bz * s1, aw * s0 + bw * s1
end

-- Lerp(goal, alpha): "posição interpolada linear, rotação via slerp" (citação literal da
-- pesquisa) -- `alpha` NÃO documentado como clampado (mesma convenção de Vector3/Vector2:Lerp),
-- então extrapola fora de [0,1] igual aos outros tipos da família.
local function lerpCFrame(aFields: Userdata.Fields, bFields: Userdata.Fields, alpha: number): CFrame
	local ax, ay, az = numAt(aFields, 1), numAt(aFields, 2), numAt(aFields, 3)
	local bx, by, bz = numAt(bFields, 1), numAt(bFields, 2), numAt(bFields, 3)
	local px = ax + (bx - ax) * alpha
	local py = ay + (by - ay) * alpha
	local pz = az + (bz - az) * alpha

	local aqx, aqy, aqz, aqw = matrixToQuaternion(
		numAt(aFields, 4),
		numAt(aFields, 5),
		numAt(aFields, 6),
		numAt(aFields, 7),
		numAt(aFields, 8),
		numAt(aFields, 9),
		numAt(aFields, 10),
		numAt(aFields, 11),
		numAt(aFields, 12)
	)
	local bqx, bqy, bqz, bqw = matrixToQuaternion(
		numAt(bFields, 4),
		numAt(bFields, 5),
		numAt(bFields, 6),
		numAt(bFields, 7),
		numAt(bFields, 8),
		numAt(bFields, 9),
		numAt(bFields, 10),
		numAt(bFields, 11),
		numAt(bFields, 12)
	)

	local qx, qy, qz, qw = slerp(aqx, aqy, aqz, aqw, bqx, bqy, bqz, bqw, alpha)
	local r00, r01, r02, r10, r11, r12, r20, r21, r22 = quaternionToMatrix(qx, qy, qz, qw)

	return construct(px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

-- Orthonormalize(): X mantido (só normalizado), Z = (X×Y original) normalizado, Y = Z×X --
-- garante uma base ortonormal right-handed "próxima" da original, preservando X como referência
-- (ver "Aproximações de boa-fé" no cabeçalho -- não é o algoritmo interno do motor, não
-- documentado).
local function orthonormalize(fields: Userdata.Fields): CFrame
	local x, y, z = numAt(fields, 1), numAt(fields, 2), numAt(fields, 3)
	local vx0, vx1, vx2 = numAt(fields, 4), numAt(fields, 7), numAt(fields, 10)
	local vy0, vy1, vy2 = numAt(fields, 5), numAt(fields, 8), numAt(fields, 11)

	local xLen = math.sqrt(vx0 * vx0 + vx1 * vx1 + vx2 * vx2)
	local xx, xy, xz = vx0 / xLen, vx1 / xLen, vx2 / xLen

	local zx, zy, zz = xy * vy2 - xz * vy1, xz * vy0 - xx * vy2, xx * vy1 - xy * vy0
	local zLen = math.sqrt(zx * zx + zy * zy + zz * zz)
	zx, zy, zz = zx / zLen, zy / zLen, zz / zLen

	local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx

	return construct(x, y, z, xx, yx, zx, xy, yy, zy, xz, yz, zz)
end

-- ====================================================================================================
-- Extração: Euler angles (XYZ/YXZ) e eixo-ângulo -- inversas matemáticas de
-- `fromEulerAnglesXYZ`/`fromEulerAnglesYXZ`/`fromAxisAngle`, abaixo.
-- ====================================================================================================

-- Decomposição XYZ (R = Rx*Ry*Rz): R02=sin(ry) é o elemento "limpo" pra extrair ry primeiro; rx/rz
-- vêm de atan2 nos elementos restantes. GIMBAL LOCK (ry perto de ±π/2, cos(ry)≈0): rz é
-- indeterminado -- convenção adotada aqui é rz=0 (aproximação de boa-fé, mesmo espírito da
-- ressalva "sujeito a gimbal lock" da doc oficial, ver cabeçalho).
local function toEulerAnglesXYZ(fields: Userdata.Fields): (number, number, number)
	local r00, r01, r02 = numAt(fields, 4), numAt(fields, 5), numAt(fields, 6)
	local r10, r11, r12 = numAt(fields, 7), numAt(fields, 8), numAt(fields, 9)
	local r22 = numAt(fields, 12)

	local ry = math.asin(math.clamp(r02, -1, 1))
	local cy = math.cos(ry)

	local rx: number
	local rz: number
	if math.abs(cy) > GIMBAL_EPSILON then
		rx = math.atan2(-r12, r22)
		rz = math.atan2(-r01, r00)
	else
		rz = 0
		if r02 > 0 then
			rx = math.atan2(r10, r11)
		else
			rx = math.atan2(-r10, r11)
		end
	end

	return Float32.Quantize(rx), Float32.Quantize(ry), Float32.Quantize(rz)
end

-- Decomposição YXZ (R = Ry*Rx*Rz): R12=-sin(rx) é o elemento "limpo". GIMBAL LOCK (rx perto de
-- ±π/2): mesma convenção, rz=0.
local function toEulerAnglesYXZ(fields: Userdata.Fields): (number, number, number)
	local r00, r02 = numAt(fields, 4), numAt(fields, 6)
	local r10, r11, r12 = numAt(fields, 7), numAt(fields, 8), numAt(fields, 9)
	local r20, r22 = numAt(fields, 10), numAt(fields, 12)

	local rx = math.asin(math.clamp(-r12, -1, 1))
	local cx = math.cos(rx)

	local ry: number
	local rz: number
	if math.abs(cx) > GIMBAL_EPSILON then
		ry = math.atan2(r02, r22)
		rz = math.atan2(r10, r11)
	else
		rz = 0
		ry = math.atan2(-r20, r00)
	end

	return Float32.Quantize(rx), Float32.Quantize(ry), Float32.Quantize(rz)
end

-- ToAxisAngle(): "eixo unitário + ângulo; inverso de fromAxisAngle" (citação da pesquisa) --
-- ângulo via traço (`acos((traço-1)/2)`), eixo via os termos anti-simétricos da matriz. Dois casos
-- degenerados NÃO confirmados pela pesquisa (aproximação de boa-fé): ângulo~0 (identidade, eixo
-- indefinido -- devolve (0,0,0) e ângulo 0) e ângulo~π (sin(θ)≈0, eixo extraído via os termos da
-- diagonal, técnica padrão pro caso simétrico).
local function toAxisAngle(fields: Userdata.Fields): (Vector3.Vector3, number)
	local r00, r01, r02 = numAt(fields, 4), numAt(fields, 5), numAt(fields, 6)
	local r10, r11, r12 = numAt(fields, 7), numAt(fields, 8), numAt(fields, 9)
	local r20, r21, r22 = numAt(fields, 10), numAt(fields, 11), numAt(fields, 12)

	local trace = r00 + r11 + r22
	local cosAngle = math.clamp((trace - 1) / 2, -1, 1)
	local angle = math.acos(cosAngle)
	local sinAngle = math.sin(angle)

	if sinAngle > GIMBAL_EPSILON then
		local scale = 1 / (2 * sinAngle)
		return Vector3.new((r21 - r12) * scale, (r02 - r20) * scale, (r10 - r01) * scale), Float32.Quantize(angle)
	elseif angle < GIMBAL_EPSILON then
		return Vector3.new(0, 0, 0), 0
	else
		local ax = math.sqrt(math.max((r00 + 1) / 2, 0))
		local ay = math.sqrt(math.max((r11 + 1) / 2, 0))
		local az = math.sqrt(math.max((r22 + 1) / 2, 0))
		if r01 + r10 < 0 then
			ay = -ay
		end
		if r02 + r20 < 0 then
			az = -az
		end
		return Vector3.new(ax, ay, az), Float32.Quantize(angle)
	end
end

-- ====================================================================================================
-- FuzzyEq / AngleBetween
-- ====================================================================================================

-- Posição component-wise (CITAÇÃO LITERAL da pesquisa). Rotação: "aproximação rápida da diferença
-- de ângulo" (citação literal, SEM fórmula) -- implementado via produto interno de Frobenius entre
-- as duas matrizes de rotação (soma de R_a[i][j]*R_b[i][j], que vale 3 quando idênticas e cai
-- suavemente conforme divergem, SEM trigonometria -- daí "rápida"). Aproximação de boa-fé.
local function fuzzyEqCFrame(aFields: Userdata.Fields, bFields: Userdata.Fields, epsilon: number): boolean
	for index = 1, 3 do
		if math.abs(numAt(aFields, index) - numAt(bFields, index)) > epsilon then
			return false
		end
	end

	local innerProduct = 0
	for index = 4, 12 do
		innerProduct += numAt(aFields, index) * numAt(bFields, index)
	end
	return (3 - innerProduct) <= epsilon
end

-- "Só orientação, ignora posição, [0,π]" (citação literal) -- ângulo da rotação relativa Ra^T*Rb,
-- cujo traço é exatamente o produto interno de Frobenius das duas matrizes (mesma soma usada em
-- `fuzzyEqCFrame`, ver derivação no relatório desta tarefa).
local function angleBetweenCFrames(aFields: Userdata.Fields, bFields: Userdata.Fields): number
	local innerProduct = 0
	for index = 4, 12 do
		innerProduct += numAt(aFields, index) * numAt(bFields, index)
	end
	local cosAngle = math.clamp((innerProduct - 1) / 2, -1, 1)
	return Float32.Quantize(math.acos(cosAngle))
end

-- ====================================================================================================
-- Propriedades
-- ====================================================================================================

local function getProperty(fields: Userdata.Fields, key: string): (unknown, boolean)
	if key == "X" then
		return numAt(fields, 1), true
	elseif key == "Y" then
		return numAt(fields, 2), true
	elseif key == "Z" then
		return numAt(fields, 3), true
	elseif key == "Position" then
		return Vector3.new(numAt(fields, 1), numAt(fields, 2), numAt(fields, 3)), true
	elseif key == "Rotation" then
		return construct(
			0,
			0,
			0,
			numAt(fields, 4),
			numAt(fields, 5),
			numAt(fields, 6),
			numAt(fields, 7),
			numAt(fields, 8),
			numAt(fields, 9),
			numAt(fields, 10),
			numAt(fields, 11),
			numAt(fields, 12)
		),
			true
	elseif key == "XVector" or key == "RightVector" then
		return Vector3.new(numAt(fields, 4), numAt(fields, 7), numAt(fields, 10)), true
	elseif key == "YVector" or key == "UpVector" then
		return Vector3.new(numAt(fields, 5), numAt(fields, 8), numAt(fields, 11)), true
	elseif key == "ZVector" then
		return Vector3.new(numAt(fields, 6), numAt(fields, 9), numAt(fields, 12)), true
	elseif key == "LookVector" then
		return Vector3.new(-numAt(fields, 6), -numAt(fields, 9), -numAt(fields, 12)), true
	end
	return nil, false
end

-- ====================================================================================================
-- Métodos
-- ====================================================================================================

local methods: { [string]: unknown } = {
	GetComponents = function(
		self: unknown
	): (number, number, number, number, number, number, number, number, number, number, number, number)
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		return numAt(fields, 1),
			numAt(fields, 2),
			numAt(fields, 3),
			numAt(fields, 4),
			numAt(fields, 5),
			numAt(fields, 6),
			numAt(fields, 7),
			numAt(fields, 8),
			numAt(fields, 9),
			numAt(fields, 10),
			numAt(fields, 11),
			numAt(fields, 12)
	end,

	Inverse = function(self: unknown): unknown
		return inverseOf(Userdata.Unwrap(self, TYPE_NAME))
	end,

	Lerp = function(self: unknown, goal: unknown, alpha: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(goal, TYPE_NAME)
		return lerpCFrame(a, b, alpha :: number)
	end,

	Orthonormalize = function(self: unknown): unknown
		return orthonormalize(Userdata.Unwrap(self, TYPE_NAME))
	end,

	ToWorldSpace = function(self: unknown, ...: unknown): ...unknown
		local aFields = Userdata.Unwrap(self, TYPE_NAME)
		local count = select("#", ...)
		local results: { unknown } = table.create(count)
		for index = 1, count do
			results[index] = composeCFrame(aFields, Userdata.Unwrap(select(index, ...), TYPE_NAME))
		end
		return table.unpack(results, 1, count)
	end,

	ToObjectSpace = function(self: unknown, ...: unknown): ...unknown
		local inverseFields = Userdata.Unwrap(inverseOf(Userdata.Unwrap(self, TYPE_NAME)), TYPE_NAME)
		local count = select("#", ...)
		local results: { unknown } = table.create(count)
		for index = 1, count do
			results[index] = composeCFrame(inverseFields, Userdata.Unwrap(select(index, ...), TYPE_NAME))
		end
		return table.unpack(results, 1, count)
	end,

	PointToWorldSpace = function(self: unknown, ...: unknown): ...unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		local count = select("#", ...)
		local results: { unknown } = table.create(count)
		for index = 1, count do
			results[index] = transformPoint(fields, Userdata.Unwrap(select(index, ...), "Vector3"))
		end
		return table.unpack(results, 1, count)
	end,

	PointToObjectSpace = function(self: unknown, ...: unknown): ...unknown
		local inverseFields = Userdata.Unwrap(inverseOf(Userdata.Unwrap(self, TYPE_NAME)), TYPE_NAME)
		local count = select("#", ...)
		local results: { unknown } = table.create(count)
		for index = 1, count do
			results[index] = transformPoint(inverseFields, Userdata.Unwrap(select(index, ...), "Vector3"))
		end
		return table.unpack(results, 1, count)
	end,

	VectorToWorldSpace = function(self: unknown, ...: unknown): ...unknown
		local fields = Userdata.Unwrap(self, TYPE_NAME)
		local count = select("#", ...)
		local results: { unknown } = table.create(count)
		for index = 1, count do
			results[index] = rotateOnly(fields, Userdata.Unwrap(select(index, ...), "Vector3"))
		end
		return table.unpack(results, 1, count)
	end,

	VectorToObjectSpace = function(self: unknown, ...: unknown): ...unknown
		local inverseFields = Userdata.Unwrap(inverseOf(Userdata.Unwrap(self, TYPE_NAME)), TYPE_NAME)
		local count = select("#", ...)
		local results: { unknown } = table.create(count)
		for index = 1, count do
			results[index] = rotateOnly(inverseFields, Userdata.Unwrap(select(index, ...), "Vector3"))
		end
		return table.unpack(results, 1, count)
	end,

	ToEulerAnglesXYZ = function(self: unknown): (number, number, number)
		return toEulerAnglesXYZ(Userdata.Unwrap(self, TYPE_NAME))
	end,

	ToEulerAnglesYXZ = function(self: unknown): (number, number, number)
		return toEulerAnglesYXZ(Userdata.Unwrap(self, TYPE_NAME))
	end,

	ToOrientation = function(self: unknown): (number, number, number)
		return toEulerAnglesYXZ(Userdata.Unwrap(self, TYPE_NAME))
	end,

	ToAxisAngle = function(self: unknown): (unknown, number)
		return toAxisAngle(Userdata.Unwrap(self, TYPE_NAME))
	end,

	FuzzyEq = function(self: unknown, other: unknown, epsilon: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		local eps: number = if epsilon == nil then DEFAULT_FUZZY_EPSILON else (epsilon :: number)
		return fuzzyEqCFrame(a, b, eps)
	end,

	AngleBetween = function(self: unknown, other: unknown): unknown
		local a = Userdata.Unwrap(self, TYPE_NAME)
		local b = Userdata.Unwrap(other, TYPE_NAME)
		return angleBetweenCFrames(a, b)
	end,
}
-- Alias LITERAL de GetComponents (confirmado pela pesquisa: "Equivalent to GetComponents()") --
-- atribuído fora do literal da tabela pra reusar a MESMA função (nunca duplicar a lógica).
methods.components = methods.GetComponents
table.freeze(methods)

-- ====================================================================================================
-- Operadores -- `CFrame*CFrame`, `CFrame*Vector3`, `CFrame+Vector3`, `CFrame-Vector3` (confirmados
-- pela pesquisa, seção 5). `CFrame+CFrame`/`CFrame-CFrame`/`CFrame*number`/qualquer `CFrame/...`
-- NÃO existem (ausência confirmada na seção `math_operations` da doc oficial) -- Div/IDiv/Unm
-- ficam de fora do Descriptor (nil = operador não instalado, erro nativo do Luau é o certo). Add/
-- Sub/Mul, abaixo, rejeitam qualquer combinação fora das 4 válidas com o MESMO mecanismo que
-- Vector3.luau/Vector2.luau já usam (checar o TypeName do lado direito e errar se não bater) --
-- NÃO uma segunda função de composição pra "CFrame+CFrame": só um guard que erra.
-- ====================================================================================================

local function add(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
	if bTypeName ~= "Vector3" then
		error(`attempt to perform arithmetic (add) on {TYPE_NAME} and {bTypeName}`, 3)
	end
	return construct(
		numAt(a, 1) + numAt(b, 1),
		numAt(a, 2) + numAt(b, 2),
		numAt(a, 3) + numAt(b, 3),
		numAt(a, 4),
		numAt(a, 5),
		numAt(a, 6),
		numAt(a, 7),
		numAt(a, 8),
		numAt(a, 9),
		numAt(a, 10),
		numAt(a, 11),
		numAt(a, 12)
	)
end

local function sub(a: Userdata.Fields, b: Userdata.Fields, bTypeName: string): unknown
	if bTypeName ~= "Vector3" then
		error(`attempt to perform arithmetic (sub) on {TYPE_NAME} and {bTypeName}`, 3)
	end
	return construct(
		numAt(a, 1) - numAt(b, 1),
		numAt(a, 2) - numAt(b, 2),
		numAt(a, 3) - numAt(b, 3),
		numAt(a, 4),
		numAt(a, 5),
		numAt(a, 6),
		numAt(a, 7),
		numAt(a, 8),
		numAt(a, 9),
		numAt(a, 10),
		numAt(a, 11),
		numAt(a, 12)
	)
end

-- CFrame*CFrame (composição) e CFrame*Vector3 (transforma ponto) -- SEM reverso (Vector3*CFrame
-- não é suportado; se acontecer, o `__mul` que dispara é o do Vector3, que já erra sozinho por não
-- reconhecer CFrame como operando válido -- ver types/Vector3.luau:mul). SEM CFrame*number (não
-- documentado pela pesquisa).
local function mul(a: unknown, b: unknown): unknown
	if Userdata.TypeNameOf(a) ~= TYPE_NAME then
		error(`attempt to perform arithmetic (mul) on {describeType(a)} and {describeType(b)}`, 2)
	end
	local aFields = Userdata.Unwrap(a, TYPE_NAME)
	local bTypeName = Userdata.TypeNameOf(b)
	if bTypeName == TYPE_NAME then
		return composeCFrame(aFields, Userdata.Unwrap(b, TYPE_NAME))
	elseif bTypeName == "Vector3" then
		return transformPoint(aFields, Userdata.Unwrap(b, "Vector3"))
	end
	error(`attempt to perform arithmetic (mul) on {TYPE_NAME} and {describeType(b)}`, 2)
end

-- P8 (ver cabeçalho): exato, componente a componente, pelos 12 campos. Aproximação de boa-fé não
-- confirmada.
local function equals(a: Userdata.Fields, b: Userdata.Fields): boolean
	for index = 1, 12 do
		if numAt(a, index) ~= numAt(b, index) then
			return false
		end
	end
	return true
end

-- "12 componentes na mesma ordem que GetComponents(), separados por ', '" (citação literal da
-- pesquisa, seção 6).
local function format(fields: Userdata.Fields): string
	local parts: { string } = table.create(12)
	for index = 1, 12 do
		parts[index] = Float32.Format(numAt(fields, index))
	end
	return table.concat(parts, ", ")
end

CFrameFactory = Userdata.Define({
	TypeName = TYPE_NAME,
	Methods = methods,
	GetProperty = getProperty,
	Format = format,
	Add = add,
	Sub = sub,
	Mul = mul,
	Equals = equals,
})

-- ====================================================================================================
-- Construtores estáticos
-- ====================================================================================================

-- Algoritmo padrão de "lookAt" de câmera right-handed: zAxis aponta PRA LONGE do alvo (LookVector
-- = -zAxis aponta PRA o alvo), xAxis = up×zAxis normalizado, yAxis = zAxis×xAxis (garante
-- ortogonalidade). Verificado manualmente contra o caso identidade do exemplo oficial da pesquisa
-- (`CFrame.new(0,0,0)`: LookVector=(-0,-0,-1), RightVector=(1,0,0), UpVector=(0,1,0)) -- ver
-- "Aproximações de boa-fé" no cabeçalho: a fórmula em si não é uma citação literal do motor
-- fechado do Roblox, mas reproduz o caso confirmado exatamente.
local function lookAtImpl(atFields: Userdata.Fields, targetFields: Userdata.Fields, upFields: Userdata.Fields): CFrame
	local ax, ay, az = numAt(atFields, 1), numAt(atFields, 2), numAt(atFields, 3)
	local tx, ty, tz = numAt(targetFields, 1), numAt(targetFields, 2), numAt(targetFields, 3)
	local ux, uy, uz = numAt(upFields, 1), numAt(upFields, 2), numAt(upFields, 3)

	local zx, zy, zz = ax - tx, ay - ty, az - tz
	local zLen = math.sqrt(zx * zx + zy * zy + zz * zz)
	zx, zy, zz = zx / zLen, zy / zLen, zz / zLen

	local xx, xy, xz = uy * zz - uz * zy, uz * zx - ux * zz, ux * zy - uy * zx
	local xLen = math.sqrt(xx * xx + xy * xy + xz * xz)
	xx, xy, xz = xx / xLen, xy / xLen, xz / xLen

	local yx, yy, yz = zy * xz - zz * xy, zz * xx - zx * xz, zx * xy - zy * xx

	return construct(ax, ay, az, xx, yx, zx, xy, yy, zy, xz, yz, zz)
end

-- Valida um argumento posicional numérico OBRIGATÓRIO (overloads de 3/7/12 args de `new` não têm
-- default nenhum, diferente de UDim2.new) -- mesmo vocabulário de erro que `Userdata.Unwrap`/
-- `types/UDim2.luau:toOptionalNumber` já usam pro resto do território.
local function requireNumber(value: unknown, index: number): number
	if typeof(value) == "number" then
		return value :: number
	end
	error(`invalid argument #{index} to 'CFrame.new' (number expected, got {typeof(value)})`, 4)
end

-- Implementação ÚNICA que despacha pelos SEIS overloads reais (ver cabeçalho) -- a CONTAGEM de
-- argumentos sozinha já distingue os 6 casos. `...: unknown` -- sem `any` -- é o único jeito de
-- aceitar assinaturas de aridade/tipo diferentes numa função Luau concreta; o tipo público exposto
-- (`CFrameNewOverload`, intersecção) é aplicado num ÚNICO cast na atribuição final de
-- `CFrameModule.new`, abaixo (mesmo padrão de `types/UDim2.luau:newRaw`).
local function newRaw(...: unknown): CFrame
	local argCount = select("#", ...)

	if argCount == 0 then
		return construct(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif argCount == 1 then
		local posFields = Userdata.Unwrap(select(1, ...), "Vector3")
		return construct(numAt(posFields, 1), numAt(posFields, 2), numAt(posFields, 3), 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif argCount == 2 then
		-- Overload LEGADO (a doc oficial diz literalmente "replaced by CFrame.lookAt()") -- mesmo
		-- algoritmo de `CFrame.lookAt`, `up` fixo em (0,1,0) (citação da pesquisa: "assumindo
		-- (0,1,0) como up").
		local atFields = Userdata.Unwrap(select(1, ...), "Vector3")
		local targetFields = Userdata.Unwrap(select(2, ...), "Vector3")
		return lookAtImpl(atFields, targetFields, DEFAULT_UP_FIELDS)
	elseif argCount == 3 then
		local x = requireNumber(select(1, ...), 1)
		local y = requireNumber(select(2, ...), 2)
		local z = requireNumber(select(3, ...), 3)
		return construct(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif argCount == 7 then
		local x = requireNumber(select(1, ...), 1)
		local y = requireNumber(select(2, ...), 2)
		local z = requireNumber(select(3, ...), 3)
		local qx = requireNumber(select(4, ...), 4)
		local qy = requireNumber(select(5, ...), 5)
		local qz = requireNumber(select(6, ...), 6)
		local qw = requireNumber(select(7, ...), 7)
		local r00, r01, r02, r10, r11, r12, r20, r21, r22 = quaternionToMatrix(qx, qy, qz, qw)
		return construct(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	elseif argCount == 12 then
		local values: { number } = table.create(12)
		for index = 1, 12 do
			values[index] = requireNumber(select(index, ...), index)
		end
		return construct(
			values[1],
			values[2],
			values[3],
			values[4],
			values[5],
			values[6],
			values[7],
			values[8],
			values[9],
			values[10],
			values[11],
			values[12]
		)
	end

	error(`CFrame.new: número de argumentos inválido ({argCount}) -- esperado 0, 1, 2, 3, 7 ou 12`, 3)
end

local CFrameModule = {}

CFrameModule.new = newRaw :: CFrameNewOverload

function CFrameModule.lookAt(at: Vector3.Vector3, lookAtTarget: Vector3.Vector3, up: Vector3.Vector3?): CFrame
	local atFields = Userdata.Unwrap(at, "Vector3")
	local targetFields = Userdata.Unwrap(lookAtTarget, "Vector3")
	local upFields: Userdata.Fields = if up == nil then DEFAULT_UP_FIELDS else Userdata.Unwrap(up, "Vector3")
	return lookAtImpl(atFields, targetFields, upFields)
end

-- "Equivalente a CFrame.lookAt(at, at + direction)" (citação literal da pesquisa).
function CFrameModule.lookAlong(at: Vector3.Vector3, direction: Vector3.Vector3, up: Vector3.Vector3?): CFrame
	local atFields = Userdata.Unwrap(at, "Vector3")
	local directionFields = Userdata.Unwrap(direction, "Vector3")
	local targetFields: Userdata.Fields = {
		numAt(atFields, 1) + numAt(directionFields, 1),
		numAt(atFields, 2) + numAt(directionFields, 2),
		numAt(atFields, 3) + numAt(directionFields, 3),
	}
	local upFields: Userdata.Fields = if up == nil then DEFAULT_UP_FIELDS else Userdata.Unwrap(up, "Vector3")
	return lookAtImpl(atFields, targetFields, upFields)
end

-- "`vZ` é OPCIONAL; se omitido, vZ = vX:Cross(vY).Unit" (citação literal da pesquisa). `vX`≡
-- RightVector, `vY`≡UpVector, `vZ`≡-LookVector -- viram as colunas 0/1/2 da matriz de rotação
-- diretamente (SEM ortonormalizar -- confiança de que o chamador passou vetores razoáveis; se não
-- passou, `:Orthonormalize()` corrige explicitamente, ver D7 no cabeçalho).
function CFrameModule.fromMatrix(
	pos: Vector3.Vector3,
	vX: Vector3.Vector3,
	vY: Vector3.Vector3,
	vZ: Vector3.Vector3?
): CFrame
	local posFields = Userdata.Unwrap(pos, "Vector3")
	local vxFields = Userdata.Unwrap(vX, "Vector3")
	local vyFields = Userdata.Unwrap(vY, "Vector3")

	local vzx: number, vzy: number, vzz: number
	if vZ == nil then
		local cx = numAt(vxFields, 2) * numAt(vyFields, 3) - numAt(vxFields, 3) * numAt(vyFields, 2)
		local cy = numAt(vxFields, 3) * numAt(vyFields, 1) - numAt(vxFields, 1) * numAt(vyFields, 3)
		local cz = numAt(vxFields, 1) * numAt(vyFields, 2) - numAt(vxFields, 2) * numAt(vyFields, 1)
		local length = math.sqrt(cx * cx + cy * cy + cz * cz)
		vzx, vzy, vzz = cx / length, cy / length, cz / length
	else
		local vzFields = Userdata.Unwrap(vZ, "Vector3")
		vzx, vzy, vzz = numAt(vzFields, 1), numAt(vzFields, 2), numAt(vzFields, 3)
	end

	return construct(
		numAt(posFields, 1),
		numAt(posFields, 2),
		numAt(posFields, 3),
		numAt(vxFields, 1),
		numAt(vyFields, 1),
		vzx,
		numAt(vxFields, 2),
		numAt(vyFields, 2),
		vzy,
		numAt(vxFields, 3),
		numAt(vyFields, 3),
		vzz
	)
end

-- "Eixo normalizado internamente, posição sempre (0,0,0), regra da mão direita" (citação literal
-- da pesquisa) -- fórmula de Rodrigues padrão pra matriz de rotação a partir de eixo+ângulo.
function CFrameModule.fromAxisAngle(axis: Vector3.Vector3, angle: number): CFrame
	local axisFields = Userdata.Unwrap(axis, "Vector3")
	local axRaw, ayRaw, azRaw = numAt(axisFields, 1), numAt(axisFields, 2), numAt(axisFields, 3)
	local length = math.sqrt(axRaw * axRaw + ayRaw * ayRaw + azRaw * azRaw)
	local ax, ay, az = axRaw / length, ayRaw / length, azRaw / length

	local c = math.cos(angle)
	local s = math.sin(angle)
	local t = 1 - c

	local r00 = t * ax * ax + c
	local r01 = t * ax * ay - s * az
	local r02 = t * ax * az + s * ay
	local r10 = t * ax * ay + s * az
	local r11 = t * ay * ay + c
	local r12 = t * ay * az - s * ax
	local r20 = t * ax * az - s * ay
	local r21 = t * ay * az + s * ax
	local r22 = t * az * az + c

	return construct(0, 0, 0, r00, r01, r02, r10, r11, r12, r20, r21, r22)
end

-- Composição Rx*Ry*Rz -- ver "Aproximações de boa-fé" no cabeçalho (fórmula não citada literalmente
-- pela pesquisa, mas `Angles`/`fromEulerAnglesXYZ` são confirmados EQUIVALENTES, e este é o
-- resultado fechado de compor três `fromAxisAngle` nos eixos X, Y, Z nessa ordem).
function CFrameModule.fromEulerAnglesXYZ(rx: number, ry: number, rz: number): CFrame
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)

	return construct(
		0,
		0,
		0,
		cy * cz,
		-cy * sz,
		sy,
		cx * sz + sx * sy * cz,
		cx * cz - sx * sy * sz,
		-sx * cy,
		sx * sz - cx * sy * cz,
		cx * sy * sz + sx * cz,
		cx * cy
	)
end

-- Composição Ry*Rx*Rz -- mesma ressalva de `fromEulerAnglesXYZ`, acima.
function CFrameModule.fromEulerAnglesYXZ(rx: number, ry: number, rz: number): CFrame
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)

	return construct(
		0,
		0,
		0,
		cy * cz + sx * sy * sz,
		sx * sy * cz - cy * sz,
		cx * sy,
		cx * sz,
		cx * cz,
		-sx,
		cy * sx * sz - sy * cz,
		sy * sz + cy * sx * cz,
		cy * cx
	)
end

-- Alias LITERAL de fromEulerAnglesXYZ (confirmado pela pesquisa: "Equivalent to
-- fromEulerAnglesXYZ()") -- reusa a MESMA função, nunca duplica a lógica.
CFrameModule.Angles = CFrameModule.fromEulerAnglesXYZ

-- Alias LITERAL de fromEulerAnglesYXZ (confirmado pela pesquisa: "Equivalent to
-- fromEulerAnglesYXZ()") -- CUIDADO: apesar do nome sugerir Euler genérico, é especificamente YXZ
-- (ressalva literal da pesquisa).
CFrameModule.fromOrientation = CFrameModule.fromEulerAnglesYXZ

CFrameModule.identity = construct(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

return CFrameModule
