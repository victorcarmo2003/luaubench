-- Fixture: script de usuário REAL confirmando que hidratação de `$properties` (via TreeMaterializer,
-- task-cli-038) e acesso por SCRIPT (via runtime, task-runtime-039) são dois eixos INDEPENDENTES --
-- exatamente a garantia D3/D4 do desenho (arquiteto-rojo-properties-2026-09-07.md). Usado por
-- tests/scenarios/rojo-init-template-hydration.scenario.luau (task-test-rojo-properties-001).
--
-- Mesma disciplina de `tests/scenarios/fixtures/value-types-project/src/server/init.server.luau`:
-- cada verificação isolada em pcall, marcadores "[FIXTURE-PASS]"/"[FIXTURE-FAIL]" no stdout, lidos
-- de fora via process.exec.

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
-- 1. `Workspace.FilteringEnabled` -- ScriptVisible=true, ReadOnly=true no schema gerado (Security.
--    Write=PluginSecurity, Deprecated). A hidratação (task-cli-038) IGNORA ReadOnly/Security e grava
--    `true` direto no DOM (paridade com `rojo build`, D4) -- mas o eixo de ACESSO POR SCRIPT nunca
--    muda: leitura funciona (ScriptVisible=true), escrita continua barrada (ReadOnly=true).
-- ================================================================================================

check("workspace.FilteringEnabled lê true (valor hidratado por $properties, apesar de Security.Write=PluginSecurity)", function()
	local value = workspace.FilteringEnabled
	assert(value == true, `esperava true (hidratado pelo $properties do projeto), recebeu {tostring(value)}`)
end)

check("workspace.FilteringEnabled = false ainda ERRA por script (ReadOnly continua valendo -- só a HIDRATAÇÃO ignora ReadOnly, não o script)", function()
	local ok, err = pcall(function()
		workspace.FilteringEnabled = false
	end)
	assert(not ok, "esperava erro ao tentar escrever FilteringEnabled por script -- ReadOnly não pode ter sido afrouxado pela correção de hidratação")
	assert(
		string.find(tostring(err), "read only", 1, true) ~= nil,
		`esperava mensagem citando "read only", recebeu: {tostring(err)}`
	)
end)

-- ================================================================================================
-- 2. `Lighting.Technology` -- ScriptVisible=false no schema gerado (Security.Read=RobloxScriptSecurity).
--    A hidratação grava o Enum no DOM (dado morto, DV-1 do desenho -- nenhum render reage) mas o
--    SCRIPT continua sem enxergar o membro: "invisível" precisa continuar indistinguível de
--    "ausente do schema" (D3), com a MESMA mensagem que uma chave inexistente produziria.
-- ================================================================================================

check("Lighting.Technology continua INVISÍVEL para o script (ScriptVisible=false não muda com a hidratação) -- mesma mensagem de membro inexistente", function()
	local Lighting = game:GetService("Lighting")
	local ok, err = pcall(function()
		return Lighting.Technology
	end)
	assert(not ok, "esperava erro ao ler Lighting.Technology por script -- ScriptVisible=false não pode ter sido afrouxado pela correção de hidratação")
	assert(
		string.find(tostring(err), "is not a valid member of Lighting", 1, true) ~= nil,
		`esperava mensagem "is not a valid member of Lighting" (mesma de uma chave ausente), recebeu: {tostring(err)}`
	)
end)

-- ================================================================================================
-- 3. `SoundService.RespectFilteringEnabled` -- ScriptVisible=true, ReadOnly=false no schema gerado
--    (Security.Read=Security.Write=None no dump -- NUNCA precisou do bypass de ScriptVisible; esta
--    propriedade em si sempre foi gravável por script. O que bloqueava o template inteiro do
--    Tiktok antes desta leva era só Lighting.Technology/Workspace.FilteringEnabled -- ver relatório
--    do cenário externo). Confirma leitura normal, sem exceção nenhuma.
-- ================================================================================================

check("SoundService.RespectFilteringEnabled lê true (property normal, sempre foi gravável por script)", function()
	local SoundService = game:GetService("SoundService")
	local value = SoundService.RespectFilteringEnabled
	assert(value == true, `esperava true (hidratado pelo $properties do projeto), recebeu {tostring(value)}`)
end)

print(`[FIXTURE-SUMMARY] {passed}/{passed + failed} verificações passaram, {failed} falharam`)
