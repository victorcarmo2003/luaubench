--!strict

--[[
	Teste da task-valuetypes-006 (types/CFrame.luau). Cobre os 6 overloads de construtor, as
	constantes, cada propriedade vetorial, GetComponents/ToEulerAngles*/ToOrientation/ToAxisAngle/
	ToWorldSpace/ToObjectSpace/PointTo*/VectorTo*/Inverse/Lerp/Orthonormalize, os 4 operadores
	válidos, tostring, == e as duas divergências obrigatórias D1/D7 (ver cabeçalho de CFrame.luau).

	Roda com `lune run src/valuetypes/types/CFrame.spec.luau`.

	SEM `any` em lugar nenhum (regra 01) -- mesmo precedente de tipo sintético
	(`AnyOperable`/`StringIndexableProbe`) já usado em Vector3.spec.luau/Vector2.spec.luau pra
	exercitar operador/indexação em cenários que o tipo opaco real não declara (porque o Roblox real
	também não suporta essa combinação).
]]

local process = require("@lune/process")
local CFrame = require("./CFrame")
local Vector3 = require("./Vector3")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

local function almostEqual(a: number, b: number, epsilon: number?): boolean
	return math.abs(a - b) <= (epsilon or 1e-4)
end

-- Tipo sintético só pra emprestar assinatura de operador em cenários que o tipo opaco real
-- (CFrame) não declara (porque o Roblox real também não suporta essa combinação) -- mesmo
-- precedente de Vector3.spec.luau/Userdata.spec.luau.
type AnyOperable = typeof(setmetatable(
	{} :: {},
	{} :: {
		__add: (AnyOperable, AnyOperable) -> AnyOperable,
		__sub: (AnyOperable, AnyOperable) -> AnyOperable,
		__mul: (AnyOperable, AnyOperable) -> AnyOperable,
		__eq: (AnyOperable, AnyOperable) -> boolean,
	}
))
local function op(value: unknown): AnyOperable
	return value :: AnyOperable
end

type StringIndexableProbe = typeof(setmetatable({} :: { [string]: unknown }, {}))
local function asStringIndexable(value: unknown): StringIndexableProbe
	return value :: StringIndexableProbe
end

-- Invoca `CFrame.new` com uma aridade/tipo arbitrário de argumentos -- necessário pra testar os
-- caminhos de erro de `newRaw` (contagem de args inválida, argumento não-numérico) que o tipo
-- público `CFrameNewOverload` (intersecção dos 6 overloads reais) rejeitaria em tempo de análise.
-- Cast em DUAS etapas via `unknown` -- sem `any` -- mesmo padrão já usado em
-- `Userdata.luau`/`runtime/Instance.luau` pra "eu sei que o valor em runtime aceita isto, o
-- type-checker não tem como saber".
local function callNewWithRawArgs(...: unknown): unknown
	local newFn = (CFrame.new :: unknown) :: (...unknown) -> unknown
	return newFn(...)
end

-- ================================================================================================
-- Construtores -- os SEIS overloads de CFrame.new (ver pesquisa, seção 1)
-- ================================================================================================

test("CFrame.new() -- identidade (0 args)", function()
	local cf = CFrame.new()
	assert(cf.X == 0 and cf.Y == 0 and cf.Z == 0, "posição deveria ser (0,0,0)")
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	assert(
		x == 0 and y == 0 and z == 0 and r00 == 1 and r01 == 0 and r02 == 0 and r10 == 0 and r11 == 1 and r12 == 0 and r20 == 0 and r21 == 0 and r22 == 1,
		"componentes deveriam ser a identidade (0,0,0,1,0,0,0,1,0,0,0,1)"
	)
end)

test("CFrame.new(pos: Vector3) -- 1 arg, sem rotação", function()
	local cf = CFrame.new(Vector3.new(1, 2, 3))
	assert(cf.X == 1 and cf.Y == 2 and cf.Z == 3, "posição deveria ser (1,2,3)")
	assert(cf.RightVector.X == 1 and cf.UpVector.Y == 1, "rotação deveria ser identidade")
end)

test("CFrame.new(pos, lookAt: Vector3) -- 2 args, overload legado", function()
	-- at=(0,0,0), lookAt=(0,0,-1), up=(0,1,0) fixo -- deveria reproduzir a orientação identidade
	-- (LookVector=(0,0,-1), RightVector=(1,0,0), UpVector=(0,1,0)), verificado manualmente contra
	-- o exemplo oficial da pesquisa (seção 3) no cabeçalho de CFrame.luau.
	local cf = CFrame.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, -1))
	assert(cf.X == 0 and cf.Y == 0 and cf.Z == 0, "posição deveria ser (0,0,0)")
	assert(almostEqual(cf.LookVector.X, 0) and almostEqual(cf.LookVector.Y, 0) and almostEqual(cf.LookVector.Z, -1), "LookVector deveria apontar pra -Z")
	assert(almostEqual(cf.RightVector.X, 1) and almostEqual(cf.RightVector.Y, 0) and almostEqual(cf.RightVector.Z, 0), "RightVector deveria ser (1,0,0)")
	assert(almostEqual(cf.UpVector.X, 0) and almostEqual(cf.UpVector.Y, 1) and almostEqual(cf.UpVector.Z, 0), "UpVector deveria ser (0,1,0)")
end)

test("CFrame.new(x, y, z: number) -- 3 args, sem rotação", function()
	local cf = CFrame.new(4, 5, 6)
	assert(cf.X == 4 and cf.Y == 5 and cf.Z == 6, "posição deveria ser (4,5,6)")
	assert(cf.RightVector.X == 1 and cf.UpVector.Y == 1, "rotação deveria ser identidade")
end)

test("CFrame.new(x,y,z,qX,qY,qZ,qW) -- 7 args, quatérnion identidade", function()
	local cf = CFrame.new(1, 2, 3, 0, 0, 0, 1)
	assert(cf.X == 1 and cf.Y == 2 and cf.Z == 3, "posição deveria ser (1,2,3)")
	local _x, _y, _z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	assert(
		almostEqual(r00, 1) and almostEqual(r01, 0) and almostEqual(r02, 0) and almostEqual(r10, 0) and almostEqual(r11, 1) and almostEqual(r12, 0) and almostEqual(r20, 0) and almostEqual(r21, 0) and almostEqual(r22, 1),
		"quatérnion identidade deveria produzir matriz identidade"
	)
end)

test("CFrame.new(x,y,z,qX,qY,qZ,qW) -- 7 args, quatérnion de rotação 90° em Z bate com fromAxisAngle", function()
	local half = math.pi / 4 -- ângulo/2 = 45°
	local quaternionCf = CFrame.new(0, 0, 0, 0, 0, math.sin(half), math.cos(half))
	local axisAngleCf = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 2)
	assert(quaternionCf:FuzzyEq(axisAngleCf, 1e-4), "quatérnion (0,0,sin45,cos45) deveria equivaler a 90° em Z")
end)

test("CFrame.new(x,y,z,qX,qY,qZ,qW) -- quatérnion NÃO-unitário é normalizado automaticamente", function()
	-- Mesmo eixo/ângulo do teste anterior, mas escalado por 5 -- deveria dar o MESMO resultado
	-- (citação literal da pesquisa: "quatérnion não-unitário é normalizado").
	local half = math.pi / 4
	local scaled = CFrame.new(0, 0, 0, 0, 0, 5 * math.sin(half), 5 * math.cos(half))
	local unit = CFrame.new(0, 0, 0, 0, 0, math.sin(half), math.cos(half))
	assert(scaled:FuzzyEq(unit, 1e-4), "quatérnion escalado deveria normalizar pro mesmo resultado")
end)

test("CFrame.new(x,y,z,R00..R22) -- 12 args, matriz de rotação explícita (ordem confirmada = GetComponents)", function()
	local cf = CFrame.new(1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	assert(x == 1 and y == 2 and z == 3, "posição deveria ser (1,2,3)")
	assert(
		r00 == 1 and r01 == 0 and r02 == 0 and r10 == 0 and r11 == 1 and r12 == 0 and r20 == 0 and r21 == 0 and r22 == 1,
		"matriz explícita identidade deveria bater componente a componente"
	)
end)

test("CFrame.new: número de argumentos inválido erra", function()
	local ok = pcall(function()
		return callNewWithRawArgs(1, 2, 3, 4, 5)
	end)
	assert(not ok, "CFrame.new com 5 argumentos deveria errar (não é nenhum dos 6 overloads)")
end)

test("CFrame.new(1, 2, 'x') -- argumento não-numérico erra citando o tipo real", function()
	local ok, err = pcall(function()
		return callNewWithRawArgs(1, 2, "x")
	end)
	assert(not ok, "CFrame.new(1,2,'x') deveria errar")
	assert(string.find(tostring(err), "string", 1, true) ~= nil, `mensagem deveria citar o tipo real recebido, recebeu: {err}`)
end)

-- ================================================================================================
-- Construtores estáticos
-- ================================================================================================

test("CFrame.lookAt -- mesma orientação que o overload legado de 2 args", function()
	local viaLegacy = CFrame.new(Vector3.new(0, 0, 0), Vector3.new(1, 1, -1))
	local viaLookAt = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(1, 1, -1))
	assert(viaLegacy:FuzzyEq(viaLookAt, 1e-4), "lookAt e o overload legado deveriam produzir a mesma CFrame")
end)

test("CFrame.lookAt -- LookVector aponta pro alvo, up customizado é respeitado", function()
	local at = Vector3.new(0, 0, 0)
	local target = Vector3.new(10, 0, 0)
	local cf = CFrame.lookAt(at, target, Vector3.new(0, 1, 0))
	local direction = (target - at).Unit
	assert(cf.LookVector:FuzzyEq(direction, 1e-4), `LookVector deveria apontar pra (target-at).Unit, recebeu {tostring(cf.LookVector)}`)
end)

test("CFrame.lookAlong -- equivalente a CFrame.lookAt(at, at + direction) (citação literal)", function()
	local at = Vector3.new(1, 2, 3)
	local direction = Vector3.new(0, 0, -5)
	local viaAlong = CFrame.lookAlong(at, direction)
	local viaAt = CFrame.lookAt(at, at + direction)
	assert(viaAlong:FuzzyEq(viaAt, 1e-4), "lookAlong deveria equivaler a lookAt(at, at+direction)")
end)

test("CFrame.fromMatrix -- vZ omitido usa vX:Cross(vY).Unit, reproduz identidade", function()
	local cf = CFrame.fromMatrix(Vector3.new(0, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0))
	assert(cf:FuzzyEq(CFrame.identity, 1e-6), "fromMatrix com eixos canônicos deveria reproduzir a identidade")
end)

test("CFrame.fromMatrix -- vZ explícito é usado como a 3a coluna, sem recalcular", function()
	local cf = CFrame.fromMatrix(Vector3.new(0, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
	assert(cf.ZVector:FuzzyEq(Vector3.new(0, 0, 1), 1e-6), "ZVector deveria ser o vZ passado explicitamente")
end)

test("CFrame.fromAxisAngle -- 90° em torno do eixo Z gira RightVector pra UpVector", function()
	local cf = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 2)
	assert(cf.X == 0 and cf.Y == 0 and cf.Z == 0, "posição deveria ser sempre (0,0,0)")
	assert(cf.RightVector:FuzzyEq(Vector3.new(0, 1, 0), 1e-4), `esperava RightVector ~ (0,1,0), recebeu {tostring(cf.RightVector)}`)
end)

test("CFrame.fromAxisAngle -- eixo não-unitário é normalizado internamente (citação da pesquisa)", function()
	local unit = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 2)
	local scaled = CFrame.fromAxisAngle(Vector3.new(0, 0, 5), math.pi / 2)
	assert(unit:FuzzyEq(scaled, 1e-4), "eixo escalado deveria produzir a mesma rotação que o eixo unitário")
end)

test("CFrame.fromEulerAnglesXYZ(pi/2, 0, 0) equivale a fromAxisAngle(xAxis, pi/2)", function()
	local viaEuler = CFrame.fromEulerAnglesXYZ(math.pi / 2, 0, 0)
	local viaAxis = CFrame.fromAxisAngle(Vector3.new(1, 0, 0), math.pi / 2)
	assert(viaEuler:FuzzyEq(viaAxis, 1e-4), "rotação pura em X deveria bater entre os dois construtores")
end)

test("CFrame.fromEulerAnglesXYZ(0,0,0) -- identidade", function()
	assert(CFrame.fromEulerAnglesXYZ(0, 0, 0):FuzzyEq(CFrame.identity, 1e-9), "ângulos zero deveriam produzir identidade")
end)

test("CFrame.fromEulerAnglesYXZ(0, pi/2, 0) equivale a fromAxisAngle(yAxis, pi/2)", function()
	local viaEuler = CFrame.fromEulerAnglesYXZ(0, math.pi / 2, 0)
	local viaAxis = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.pi / 2)
	assert(viaEuler:FuzzyEq(viaAxis, 1e-4), "rotação pura em Y deveria bater entre os dois construtores")
end)

test("CFrame.Angles -- alias LITERAL de fromEulerAnglesXYZ (mesmo resultado exato)", function()
	local viaAngles = CFrame.Angles(0.1, 0.2, 0.3)
	local viaXYZ = CFrame.fromEulerAnglesXYZ(0.1, 0.2, 0.3)
	assert(viaAngles == viaXYZ, "Angles deveria produzir EXATAMENTE o mesmo resultado que fromEulerAnglesXYZ")
end)

test("CFrame.fromOrientation -- alias LITERAL de fromEulerAnglesYXZ (mesmo resultado exato)", function()
	local viaOrientation = CFrame.fromOrientation(0.1, 0.2, 0.3)
	local viaYXZ = CFrame.fromEulerAnglesYXZ(0.1, 0.2, 0.3)
	assert(viaOrientation == viaYXZ, "fromOrientation deveria produzir EXATAMENTE o mesmo resultado que fromEulerAnglesYXZ")
end)

-- ================================================================================================
-- Constante
-- ================================================================================================

test("CFrame.identity -- posição (0,0,0), rotação identidade", function()
	local cf = CFrame.identity
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	assert(
		x == 0 and y == 0 and z == 0 and r00 == 1 and r01 == 0 and r02 == 0 and r10 == 0 and r11 == 1 and r12 == 0 and r20 == 0 and r21 == 0 and r22 == 1,
		"CFrame.identity deveria ser (0,0,0,1,0,0,0,1,0,0,0,1)"
	)
end)

-- ================================================================================================
-- Propriedades vetoriais
-- ================================================================================================

test("Position/X/Y/Z", function()
	local cf = CFrame.new(7, 8, 9)
	assert(cf.X == 7 and cf.Y == 8 and cf.Z == 9, "X/Y/Z incorretos")
	local pos = cf.Position
	assert(pos.X == 7 and pos.Y == 8 and pos.Z == 9, "Position deveria ser (7,8,9)")
end)

test("Rotation -- mesma rotação, posição zerada", function()
	local cf = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 2) + Vector3.new(10, 20, 30)
	local rotation = cf.Rotation
	assert(rotation.X == 0 and rotation.Y == 0 and rotation.Z == 0, "Rotation deveria zerar a posição")
	assert(rotation.RightVector:FuzzyEq(cf.RightVector, 1e-6), "Rotation deveria preservar a mesma rotação")
end)

test("LookVector/RightVector/UpVector da identidade -- exemplo oficial da pesquisa (seção 3)", function()
	local cf = CFrame.new(0, 0, 0)
	assert(cf.LookVector.X == 0 and cf.LookVector.Y == 0 and cf.LookVector.Z == -1, `LookVector esperava (-0,-0,-1), recebeu {tostring(cf.LookVector)}`)
	assert(cf.RightVector.X == 1 and cf.RightVector.Y == 0 and cf.RightVector.Z == 0, "RightVector esperava (1,0,0)")
	assert(cf.UpVector.X == 0 and cf.UpVector.Y == 1 and cf.UpVector.Z == 0, "UpVector esperava (0,1,0)")
end)

test("XVector/YVector/ZVector == RightVector/UpVector/-LookVector", function()
	local cf = CFrame.fromAxisAngle(Vector3.new(1, 1, 1).Unit, 0.7)
	assert(cf.XVector:FuzzyEq(cf.RightVector, 1e-9), "XVector deveria ser igual a RightVector")
	assert(cf.YVector:FuzzyEq(cf.UpVector, 1e-9), "YVector deveria ser igual a UpVector")
	assert((-cf.ZVector):FuzzyEq(cf.LookVector, 1e-9), "LookVector deveria ser -ZVector")
end)

test("ler uma propriedade inválida erra citando a chave e o TypeName", function()
	local cf = CFrame.new()
	local ok, err = pcall(function()
		return asStringIndexable(cf).NaoExiste
	end)
	assert(not ok, "ler uma propriedade inválida deveria errar")
	local message = tostring(err)
	assert(string.find(message, "NaoExiste", 1, true) ~= nil, `mensagem deveria citar a chave, recebeu: {message}`)
	assert(string.find(message, "CFrame", 1, true) ~= nil, `mensagem deveria citar o TypeName, recebeu: {message}`)
end)

test("escrever numa propriedade erra -- CFrame é imutável", function()
	local cf = CFrame.new(1, 2, 3)
	local ok = pcall(function()
		asStringIndexable(cf).X = 99
	end)
	assert(not ok, "escrever em X deveria errar")
	assert(cf.X == 1, "X não deveria ter mudado")
end)

-- ================================================================================================
-- Métodos
-- ================================================================================================

test(":GetComponents()/:components() -- alias LITERAL, mesmos 12 valores", function()
	local cf = CFrame.new(1, 2, 3, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	local a = { cf:GetComponents() }
	local b = { cf:components() }
	assert(#a == 12 and #b == 12, "os dois deveriam devolver 12 valores")
	for index = 1, 12 do
		assert(a[index] == b[index], `componente {index} diverge entre GetComponents e components`)
	end
end)

test(":Inverse() -- cf * cf:Inverse() == identidade", function()
	local cf = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), 0.9) + Vector3.new(3, -2, 5)
	local roundTrip = cf * cf:Inverse()
	assert(roundTrip:FuzzyEq(CFrame.identity, 1e-4), `cf * cf:Inverse() deveria ser a identidade, recebeu {tostring(roundTrip)}`)
end)

test(":Lerp() -- posição interpolada linear (translação pura)", function()
	local a = CFrame.new(0, 0, 0)
	local b = CFrame.new(10, 20, 30)
	local half = a:Lerp(b, 0.5)
	assert(half.X == 5 and half.Y == 10 and half.Z == 15, "Lerp de translação pura deveria interpolar linear")
end)

test(":Lerp() -- rotação via slerp (metade de 90° em Z é ~45° em Z)", function()
	local a = CFrame.identity
	local b = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 2)
	local half = a:Lerp(b, 0.5)
	local expected = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 4)
	assert(half:FuzzyEq(expected, 1e-4), `Lerp(alpha=0.5) da rotação deveria ~ metade do ângulo, recebeu {tostring(half)}`)
end)

test(":Lerp() -- alpha 0/1 devolvem os extremos exatos", function()
	local a = CFrame.new(1, 2, 3)
	local b = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), 1.2) + Vector3.new(9, 8, 7)
	assert(a:Lerp(b, 0):FuzzyEq(a, 1e-6), "Lerp(alpha=0) deveria devolver o início")
	assert(a:Lerp(b, 1):FuzzyEq(b, 1e-4), "Lerp(alpha=1) deveria devolver o fim")
end)

test(":Orthonormalize() -- corrige uma matriz não-ortonormal (colunas viram unitárias e ortogonais)", function()
	-- vX e vY levemente não-ortogonais/não-unitários de propósito.
	local skewed = CFrame.fromMatrix(Vector3.new(0, 0, 0), Vector3.new(2, 0, 0), Vector3.new(1, 1, 0))
	local fixed = skewed:Orthonormalize()

	local x, y, z = fixed.RightVector, fixed.UpVector, fixed.ZVector
	assert(almostEqual(x.Magnitude, 1, 1e-4), `RightVector deveria ser unitário, Magnitude={x.Magnitude}`)
	assert(almostEqual(y.Magnitude, 1, 1e-4), `UpVector deveria ser unitário, Magnitude={y.Magnitude}`)
	assert(almostEqual(z.Magnitude, 1, 1e-4), `ZVector deveria ser unitário, Magnitude={z.Magnitude}`)
	assert(almostEqual(x:Dot(y), 0, 1e-4), "RightVector e UpVector deveriam ser ortogonais")
	assert(almostEqual(x:Dot(z), 0, 1e-4), "RightVector e ZVector deveriam ser ortogonais")
	assert(almostEqual(y:Dot(z), 0, 1e-4), "UpVector e ZVector deveriam ser ortogonais")
end)

test(":ToWorldSpace() -- equivalente a self * cf (citação literal), inclusive variádico", function()
	local self_ = CFrame.new(1, 2, 3)
	local other = CFrame.new(4, 5, 6)
	assert((self_:ToWorldSpace(other)):FuzzyEq(self_ * other, 1e-6), "ToWorldSpace(cf) deveria equivaler a self*cf")

	local otherB = CFrame.new(7, 8, 9)
	local r1, r2 = self_:ToWorldSpace(other, otherB)
	assert(r1:FuzzyEq(self_ * other, 1e-6) and r2:FuzzyEq(self_ * otherB, 1e-6), "ToWorldSpace variádico deveria devolver uma tupla, uma por argumento")
end)

test(":ToObjectSpace() -- equivalente a self:Inverse() * cf (citação literal)", function()
	local self_ = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), 0.4) + Vector3.new(2, 0, 0)
	local other = CFrame.new(5, 5, 5)
	assert((self_:ToObjectSpace(other)):FuzzyEq(self_:Inverse() * other, 1e-4), "ToObjectSpace(cf) deveria equivaler a self:Inverse()*cf")
	assert((self_:ToObjectSpace(self_)):FuzzyEq(CFrame.identity, 1e-4), "self:ToObjectSpace(self) deveria ser a identidade")
end)

test(":PointToWorldSpace()/:PointToObjectSpace() -- ida e volta", function()
	local cf = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), 0.6) + Vector3.new(3, -1, 2)
	local localPoint = Vector3.new(1, 2, 3)
	local worldPoint = cf:PointToWorldSpace(localPoint)
	assert(worldPoint:FuzzyEq(cf * localPoint, 1e-6), "PointToWorldSpace deveria equivaler a cf*v")
	local roundTrip = cf:PointToObjectSpace(worldPoint)
	assert(roundTrip:FuzzyEq(localPoint, 1e-4), `PointToObjectSpace(PointToWorldSpace(v)) deveria devolver v, recebeu {tostring(roundTrip)}`)
end)

test(":PointToWorldSpace() -- posição pura, ponto (0,0,0) local vira a Position do CFrame", function()
	local cf = CFrame.new(5, 10, 0)
	local world = cf:PointToWorldSpace(Vector3.new(0, 0, 0))
	assert(world.X == 5 and world.Y == 10 and world.Z == 0, "PointToWorldSpace((0,0,0)) deveria devolver a Position")
end)

test(":VectorToWorldSpace()/:VectorToObjectSpace() -- IGNORAM translação (citação literal)", function()
	local cf = CFrame.new(10, 0, 0) -- só translação, rotação identidade
	local asVector = cf:VectorToWorldSpace(Vector3.new(1, 0, 0))
	local asPoint = cf:PointToWorldSpace(Vector3.new(1, 0, 0))
	assert(asVector.X == 1 and asVector.Y == 0 and asVector.Z == 0, "VectorToWorldSpace deveria ignorar a translação")
	assert(asPoint.X == 11 and asPoint.Y == 0 and asPoint.Z == 0, "PointToWorldSpace deveria somar a translação (contraste)")

	local roundTrip = cf:VectorToObjectSpace(asVector)
	assert(roundTrip:FuzzyEq(Vector3.new(1, 0, 0), 1e-6), "VectorToObjectSpace deveria desfazer VectorToWorldSpace")
end)

test(":ToEulerAnglesXYZ() -- round-trip com fromEulerAnglesXYZ (fora de gimbal lock)", function()
	local rx0, ry0, rz0 = 0.3, 0.4, 0.5
	local cf = CFrame.fromEulerAnglesXYZ(rx0, ry0, rz0)
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	assert(almostEqual(rx, rx0) and almostEqual(ry, ry0) and almostEqual(rz, rz0), `esperava ({rx0},{ry0},{rz0}), recebeu ({rx},{ry},{rz})`)
end)

test(":ToEulerAnglesYXZ() -- round-trip com fromEulerAnglesYXZ (fora de gimbal lock)", function()
	local rx0, ry0, rz0 = 0.2, -0.35, 0.6
	local cf = CFrame.fromEulerAnglesYXZ(rx0, ry0, rz0)
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	assert(almostEqual(rx, rx0) and almostEqual(ry, ry0) and almostEqual(rz, rz0), `esperava ({rx0},{ry0},{rz0}), recebeu ({rx},{ry},{rz})`)
end)

test(":ToOrientation() -- alias LITERAL de ToEulerAnglesYXZ (mesmos valores exatos)", function()
	local cf = CFrame.fromEulerAnglesYXZ(0.1, 0.2, 0.3)
	local a1, a2, a3 = cf:ToOrientation()
	local b1, b2, b3 = cf:ToEulerAnglesYXZ()
	assert(a1 == b1 and a2 == b2 and a3 == b3, "ToOrientation deveria devolver EXATAMENTE o mesmo que ToEulerAnglesYXZ")
end)

test(":ToEulerAnglesXYZ()/:ToEulerAnglesYXZ() não crasham perto de gimbal lock (±90°)", function()
	local cf = CFrame.fromEulerAnglesXYZ(0.2, math.pi / 2, 0.3)
	local ok = pcall(function()
		return cf:ToEulerAnglesXYZ()
	end)
	assert(ok, "ToEulerAnglesXYZ perto de gimbal lock não deveria erra")

	local cf2 = CFrame.fromEulerAnglesYXZ(math.pi / 2, 0.2, 0.3)
	local ok2 = pcall(function()
		return cf2:ToEulerAnglesYXZ()
	end)
	assert(ok2, "ToEulerAnglesYXZ perto de gimbal lock não deveria errar")
end)

test(":ToAxisAngle() -- round-trip com fromAxisAngle", function()
	local axis0 = Vector3.new(1, 2, 3).Unit
	local angle0 = math.pi / 3
	local cf = CFrame.fromAxisAngle(axis0, angle0)
	local axis, angle = cf:ToAxisAngle()
	assert(axis:FuzzyEq(axis0, 1e-4), `eixo esperava ~{tostring(axis0)}, recebeu {tostring(axis)}`)
	assert(almostEqual(angle, angle0), `ângulo esperava ~{angle0}, recebeu {angle}`)
end)

test(":ToAxisAngle() da identidade não crasha (ângulo ~0, eixo degenerado)", function()
	local ok = pcall(function()
		return CFrame.identity:ToAxisAngle()
	end)
	assert(ok, "ToAxisAngle da identidade não deveria errar")
end)

test(":FuzzyEq() -- dentro do epsilon default é true, fora é false", function()
	local a = CFrame.new(1, 1, 1)
	local closeEnough = CFrame.new(1.0000001, 1, 1)
	local tooFar = CFrame.new(1.01, 1, 1)
	assert(a:FuzzyEq(closeEnough), "diferença de 1e-7 na posição deveria passar no FuzzyEq default (1e-5)")
	assert(not a:FuzzyEq(tooFar), "diferença de 0.01 na posição não deveria passar no FuzzyEq default (1e-5)")
end)

test(":FuzzyEq() -- também compara rotação, aceita epsilon customizado", function()
	-- A medida de rotação (produto interno de Frobenius, ver cabeçalho de CFrame.luau) é
	-- QUADRÁTICA no ângulo pra ângulos pequenos (3-innerProduct ~ θ²) -- diferente da medida de
	-- posição, que é LINEAR na diferença. Os limiares abaixo respeitam essa escala: θ=0.001 ->
	-- θ²~1e-6 (dentro do epsilon default 1e-5); θ=0.01 -> θ²~1e-4 (fora do default, dentro de
	-- 1e-3).
	local a = CFrame.identity
	local closeRotation = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), 0.001)
	local farRotation = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), 0.01)
	local veryFarRotation = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), 0.5)
	assert(a:FuzzyEq(closeRotation), "rotação de 0.001 rad (θ²~1e-6) deveria passar no epsilon default (1e-5)")
	assert(not a:FuzzyEq(farRotation), "rotação de 0.01 rad (θ²~1e-4) não deveria passar no epsilon default (1e-5)")
	assert(a:FuzzyEq(farRotation, 0.001), "rotação de 0.01 rad (θ²~1e-4) deveria passar com epsilon 0.001")
	assert(not a:FuzzyEq(veryFarRotation, 0.01), "rotação de 0.5 rad não deveria passar nem com epsilon 0.01")
end)

test(":AngleBetween() -- só orientação, ignora posição, [0,pi]", function()
	local a = CFrame.identity
	local b = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 3)
	assert(almostEqual(a:AngleBetween(b), math.pi / 3), `esperava ~pi/3, recebeu {a:AngleBetween(b)}`)

	local sameRotationDifferentPosition = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 3) + Vector3.new(100, 200, 300)
	assert(almostEqual(b:AngleBetween(sameRotationDifferentPosition), 0, 1e-3), "AngleBetween deveria ignorar a posição")

	assert(almostEqual(a:AngleBetween(a), 0, 1e-6), "AngleBetween de uma CFrame consigo mesma deveria ser ~0")
end)

-- ================================================================================================
-- Operadores -- os 4 válidos (*CFrame, *Vector3, +Vector3, -Vector3) e os inválidos (documentados
-- como NÃO existentes: +CFrame, -CFrame, *number)
-- ================================================================================================

test("* CFrame*CFrame compõe (translação pura soma as posições)", function()
	local a = CFrame.new(5, 0, 0)
	local b = CFrame.new(0, 5, 0)
	local composed = a * b
	assert(composed.X == 5 and composed.Y == 5 and composed.Z == 0, `esperava (5,5,0), recebeu {tostring(composed.Position)}`)
end)

test("* CFrame*CFrame -- rotação aplica a transformação do direito no espaço local do esquerdo", function()
	local rotated = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), math.pi / 2)
	local translated = CFrame.new(1, 0, 0)
	local composed = rotated * translated
	-- Ponto local (1,0,0) transformado por `translated` primeiro dá (1+1,0,0)=(2,0,0) no espaço
	-- de `translated`; `rotated` então rotaciona esse resultado 90° em Z -- equivalente a
	-- transformar o PONTO (1,0,0) direto por `composed`.
	local transformedPoint = composed * Vector3.new(0, 0, 0)
	assert(transformedPoint:FuzzyEq(rotated * (translated * Vector3.new(0, 0, 0)), 1e-6), "composição deveria bater com aplicar as duas transformações em sequência")
end)

test("* CFrame*Vector3 transforma ponto (equivalente a PointToWorldSpace)", function()
	local cf = CFrame.new(1, 2, 3)
	local transformed = cf * Vector3.new(1, 0, 0)
	assert(transformed.X == 2 and transformed.Y == 2 and transformed.Z == 3, `esperava (2,2,3), recebeu {tostring(transformed)}`)
end)

test("+ CFrame+Vector3 translada, rotação inalterada", function()
	local cf = CFrame.fromAxisAngle(Vector3.new(0, 0, 1), 0.5)
	local translated = cf + Vector3.new(1, 2, 3)
	assert(translated.X == 1 and translated.Y == 2 and translated.Z == 3, "posição deveria ser a soma")
	assert(translated.RightVector:FuzzyEq(cf.RightVector, 1e-9), "rotação não deveria mudar")
end)

test("- CFrame-Vector3 -- equivalente a CFrame + (-v) (citação literal)", function()
	local cf = CFrame.new(5, 5, 5)
	local v = Vector3.new(1, 2, 3)
	assert((cf - v):FuzzyEq(cf + (-v), 1e-9), "CFrame-Vector3 deveria equivaler a CFrame+(-v)")
end)

test("CFrame+CFrame NÃO existe -- erra (ver cabeçalho: guard, não composição)", function()
	local a, b = CFrame.new(), CFrame.new()
	local ok, err = pcall(function()
		return op(a) + op(b)
	end)
	assert(not ok, "CFrame+CFrame deveria errar")
	assert(string.find(tostring(err), "arithmetic", 1, true) ~= nil, `esperava erro de aritmética, recebeu: {err}`)
end)

test("CFrame-CFrame NÃO existe -- erra", function()
	local a, b = CFrame.new(), CFrame.new()
	local ok = pcall(function()
		return op(a) - op(b)
	end)
	assert(not ok, "CFrame-CFrame deveria errar")
end)

test("CFrame*number NÃO existe -- erra", function()
	local a = CFrame.new()
	local ok = pcall(function()
		return op(a) * op(5)
	end)
	assert(not ok, "CFrame*number deveria errar")
end)

test("number*CFrame NÃO existe -- erra", function()
	local a = CFrame.new()
	local ok = pcall(function()
		return op(5) * op(a)
	end)
	assert(not ok, "number*CFrame deveria errar")
end)

-- ================================================================================================
-- tostring
-- ================================================================================================

test("tostring: 12 componentes na ordem de GetComponents, separados por ', '", function()
	assert(
		tostring(CFrame.identity) == "0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
		`esperava "0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1", recebeu "{tostring(CFrame.identity)}"`
	)
	assert(
		tostring(CFrame.new(5, 10, 0)) == "5, 10, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1",
		`esperava "5, 10, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1", recebeu "{tostring(CFrame.new(5, 10, 0))}"`
	)
end)

test("tostring: usa Float32.Format (shortest round-trip), não o tostring cru do Luau", function()
	local cf = CFrame.new(0.1, 0, 0)
	local text = tostring(cf)
	assert(string.sub(text, 1, 3) == "0.1", `esperava começar com "0.1", recebeu "{text}"`)
end)

-- ================================================================================================
-- ==
-- ================================================================================================

test("== é EXATO componente a componente (P8, aproximação não confirmada)", function()
	local a = CFrame.new(1, 2, 3)
	local b = CFrame.new(1, 2, 3)
	local c = CFrame.new(1, 2, 3.0000005)
	assert(a == b, "duas CFrame com os mesmos componentes deveriam ser ==")
	assert(not (a == c), "== deveria ser EXATO -- uma diferença mínima já quebra a igualdade")
end)

test("== entre CFrame e Vector3 -> false SEM erro (tipos diferentes, invariante 4 de Userdata.luau)", function()
	local cf = CFrame.new(1, 2, 3)
	local v = Vector3.new(1, 2, 3)
	local ok, result = pcall(function()
		return op(cf) == op(v)
	end)
	assert(ok, `comparar CFrame com Vector3 não deveria errar, erro: {tostring(result)}`)
	assert(result == false, "CFrame == Vector3 deveria ser false")
end)

-- ================================================================================================
-- type()/typeof() -- CFrame continua "userdata" nos dois mundos (SEM a divergência D8 de Vector3)
-- ================================================================================================

test('type(CFrame.new()) é "userdata" -- CFrame NÃO foi migrado pro tipo `vector` nativo (diferente de Vector3, ver D8 em Vector3.luau)', function()
	assert(type(CFrame.new()) == "userdata", `esperava "userdata", recebeu "{type(CFrame.new())}"`)
	assert(typeof(CFrame.new()) == "userdata", "typeof() cru do Luau (fora do sandbox) também devolve userdata -- fidelidade real vem do TypeNameResolver de runtime, fora deste território")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
