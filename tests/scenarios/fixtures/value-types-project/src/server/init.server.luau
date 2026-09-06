-- Fixture: script de usuário REAL exercitando Vector3/CFrame/Color3/Enum dentro do sandbox do
-- LuauBench (via `game`/`workspace`/`typeof`/globais de valuetype injetados pelo runtime real --
-- não é chamada in-process aos módulos de valuetypes). Usado por
-- tests/scenarios/value-types-real-project.scenario.luau (task-test-valuetypes-001).
--
-- Cada verificação é isolada em pcall (mesma disciplina do harness de
-- tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau, Parte 1): um assert falho aqui
-- não pode impedir os demais de rodar, então o cenário externo consegue ver TODOS os resultados
-- mesmo se um exercício específico vazar/quebrar. O cenário externo lê o stdout deste script (via
-- process.exec) procurando por "[FIXTURE-PASS]"/"[FIXTURE-FAIL]" e pela linha de resumo final.

local passed = 0
local failed = 0

local function check(name: string, run: () -> ())
	local ok, err = pcall(run)
	if ok then
		passed += 1
		print(`[FIXTURE-PASS] {name}`)
	else
		failed += 1
		print(`[FIXTURE-FAIL] {name}: {tostring(err)}`)
	end
end

-- ================================================================================================
-- 1. Propriedades REAIS lidas de volta da árvore materializada -- confirma que `$properties` com
--    array (o MESMO formato que "Tiktok" usa para Ambient/Position/Color/Size) decodificou para o
--    value type de verdade, não uma tabela crua, quando a classe dona JÁ é coberta por `services`
--    (Workspace/Lighting/StarterPlayer -- ao contrário de `Part`/Baseplate, ainda não simulado).
-- ================================================================================================

check("workspace.GlobalWind é um Vector3 de verdade (typeof), com os componentes do $properties", function()
	local wind = workspace.GlobalWind
	assert(typeof(wind) == "Vector3", `esperava typeof == "Vector3", recebeu {typeof(wind)}`)
	-- Mesmos valores literais usados no Position da Baseplate do projeto real "Tiktok" ([0,-10,0]) --
	-- reaproveitados aqui porque `Part` ainda não é simulado (não dá pra testar Baseplate.Position
	-- ponta a ponta ainda, ver cabeçalho do cenário externo).
	assert(wind == Vector3.new(0, -10, 0), `esperava Vector3.new(0, -10, 0), recebeu {tostring(wind)}`)
end)

check("Lighting.Ambient é um Color3 de verdade (typeof), com os componentes do $properties", function()
	local Lighting = game:GetService("Lighting")
	local ambient = Lighting.Ambient
	assert(typeof(ambient) == "Color3", `esperava typeof == "Color3", recebeu {typeof(ambient)}`)
	-- Mesmos valores literais usados no Color da Baseplate do projeto real "Tiktok" (mesmo motivo
	-- acima: Ambient em si no Tiktok é [0,0,0], pouco revelador para conferir precisão float32).
	assert(ambient == Color3.new(0.38823, 0.37254, 0.38823), `esperava Color3.new(0.38823, 0.37254, 0.38823), recebeu {tostring(ambient)}`)
end)

check("StarterPlayer.CameraMode é um EnumItem de verdade (typeof), igual a Enum.CameraMode.LockFirstPerson", function()
	local StarterPlayer = game:GetService("StarterPlayer")
	local cameraMode = StarterPlayer.CameraMode
	assert(typeof(cameraMode) == "EnumItem", `esperava typeof == "EnumItem", recebeu {typeof(cameraMode)}`)
	assert(cameraMode == Enum.CameraMode.LockFirstPerson, `esperava Enum.CameraMode.LockFirstPerson, recebeu {tostring(cameraMode)}`)
	assert(tostring(cameraMode) == "Enum.CameraMode.LockFirstPerson", `tostring incorreto: {tostring(cameraMode)}`)
end)

-- ================================================================================================
-- 2. Value types CONSTRUÍDOS e OPERADOS dentro do próprio script (não vindos de $properties) --
--    é a primeira vez que um script de usuário real (não um .spec.luau in-process) exercita estes
--    globais dentro do sandbox de execução real (`Sandbox.Run`/`ScriptEnvironment`), fechando a
--    pendência do item 5 do relatório de 2026-09-05 ("falso positivo de sandbox nunca foi
--    testável porque nenhum script de usuário que usasse esses tipos chegava a rodar").
-- ================================================================================================

check("Vector3.new + Vector3.new soma corretamente", function()
	local sum = Vector3.new(1, 2, 3) + Vector3.new(4, 5, 6)
	assert(sum == Vector3.new(5, 7, 9), `esperava (5, 7, 9), recebeu {tostring(sum)}`)
end)

check("CFrame.new(pos) * CFrame.new(pos) compõe translação corretamente", function()
	local cf = CFrame.new(1, 2, 3) * CFrame.new(10, 0, 0)
	assert(cf.Position == Vector3.new(11, 2, 3), `esperava Position (11, 2, 3), recebeu {tostring(cf.Position)}`)
end)

check("CFrame + Vector3 translada (mesma composição que Position da Baseplate usaria)", function()
	local cf = CFrame.new() + Vector3.new(0, -10, 0)
	assert(cf.Position == Vector3.new(0, -10, 0), `esperava Position (0, -10, 0), recebeu {tostring(cf.Position)}`)
end)

check("Color3.new: tostring no formato 'R, G, B'", function()
	local color = Color3.new(1, 0, 0)
	assert(tostring(color) == "1, 0, 0", `esperava "1, 0, 0", recebeu {tostring(color)}`)
end)

check("Enum: navegação Enum.<Nome>.<Item>, FromName e GetEnumItems funcionam de dentro do sandbox", function()
	local material = Enum.Material.Plastic
	assert(typeof(material) == "EnumItem", `esperava typeof == "EnumItem", recebeu {typeof(material)}`)
	assert(tostring(material) == "Enum.Material.Plastic", `tostring incorreto: {tostring(material)}`)
	assert(Enum.Material:FromName("Plastic") == material, "FromName deveria devolver o MESMO EnumItem (internamento)")
	local items = Enum.Material:GetEnumItems()
	assert(#items > 0, "GetEnumItems deveria devolver pelo menos 1 item")
end)

print(`[FIXTURE-SUMMARY] {passed}/{passed + failed} verificações passaram, {failed} falharam`)
