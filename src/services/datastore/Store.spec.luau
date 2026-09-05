--!strict

--[[
	Teste dedicado de `./Store.luau` (regra 01: teste na mesma tarefa da lógica que cobre). Cobre
	o acceptance de task-services-017: "Store.luau cobre set/get/update/remove com versão e
	tombstone" + "cópia profunda verificada (mutar o retorno não afeta o store, e vice-versa na
	leitura)".

	Roda SEM `Services.Bootstrap`/`Runtime` -- `Store.luau` não conhece Instance (ver cabeçalho do
	módulo). Roda com `lune run src/services/datastore/Store.spec.luau`.
]]

local process = require("@lune/process")
local Store = require("./Store")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- ================= Get/Set básicos =================

test("Get numa chave nunca escrita devolve (nil, nil)", function()
	local store = Store.new()
	local value, keyInfo = store:Get("players", "player_1")
	assert(value == nil, "value deveria ser nil para chave inexistente")
	assert(keyInfo == nil, "keyInfo deveria ser nil para chave inexistente")
end)

test("Set devolve uma string de versão; Get devolve o valor gravado", function()
	local store = Store.new()
	local version = store:Set("players", "player_1", { Coins = 100 })
	assert(type(version) == "string" and #version > 0, "Set deveria devolver uma string de versão não-vazia")

	local value, keyInfo = store:Get("players", "player_1")
	assert(value ~= nil, "Get deveria devolver o valor gravado")
	assert((value :: { Coins: number }).Coins == 100, "valor gravado deveria ter Coins == 100")
	assert(keyInfo ~= nil, "Get deveria devolver um keyInfo para chave existente")
	assert((keyInfo :: Store.VersionInfo).Version == version, "keyInfo.Version deveria bater com a versão devolvida por Set")
	assert((keyInfo :: Store.VersionInfo).Tombstone == false, "chave recém-gravada não deveria estar tombstoned")
end)

test("Set memoriza userIds/metadata; ausentes viram tabela vazia (nunca nil)", function()
	local store = Store.new()
	-- Anotado explicitamente como `{ [string]: unknown }`: um literal `{ Source = "test" }` sem
	-- anotação infere um tipo EXATO (`{ Source: string }`), que o Luau não aceita implicitamente
	-- onde `{ [string]: unknown }?` é esperado (indexador vs. registro exato -- questão de
	-- inferência de tipo do TESTE, não de `Store.luau`).
	local metadata: { [string]: unknown } = { Source = "test" }
	store:Set("players", "player_1", { Coins = 1 }, { 42 }, metadata)
	local _value, keyInfo = store:Get("players", "player_1")
	assert(keyInfo ~= nil, "keyInfo não deveria ser nil")
	local info = keyInfo :: Store.VersionInfo
	assert(#info.UserIds == 1 and info.UserIds[1] == 42, "UserIds deveria conter o valor passado a Set")
	assert(info.Metadata.Source == "test", "Metadata deveria conter o valor passado a Set")

	store:Set("players", "player_2", { Coins = 1 })
	local _value2, keyInfo2 = store:Get("players", "player_2")
	local info2 = keyInfo2 :: Store.VersionInfo
	assert(#info2.UserIds == 0, "UserIds ausente deveria virar tabela vazia, nunca nil")
	assert(next(info2.Metadata) == nil, "Metadata ausente deveria virar tabela vazia, nunca nil")
end)

test("dois storeId diferentes não compartilham dado, mesma key", function()
	local store = Store.new()
	store:Set("store-a", "shared-key", { From = "a" })
	store:Set("store-b", "shared-key", { From = "b" })

	local valueA = store:Get("store-a", "shared-key")
	local valueB = store:Get("store-b", "shared-key")
	assert((valueA :: { From: string }).From == "a", "store-a deveria manter o valor gravado em store-a")
	assert((valueB :: { From: string }).From == "b", "store-b deveria manter o valor gravado em store-b, sem interferência de store-a")
end)

test("duas instâncias de Store.new() são independentes", function()
	local storeOne = Store.new()
	local storeTwo = Store.new()
	storeOne:Set("s", "k", { Marker = "one" })
	local value = storeTwo:Get("s", "k")
	assert(value == nil, "Store.new() deveria criar um store novo e vazio, independente de outras instâncias")
end)

-- ================= Versionamento =================

test("cada Set cria uma versão NOVA e DIFERENTE da anterior", function()
	local store = Store.new()
	local versionOne = store:Set("s", "k", "first")
	local versionTwo = store:Set("s", "k", "second")
	assert(versionOne ~= versionTwo, "duas escritas deveriam produzir versões diferentes")

	local value, keyInfo = store:Get("s", "k")
	assert(value == "second", "Get deveria devolver o valor da versão MAIS RECENTE")
	assert((keyInfo :: Store.VersionInfo).Version == versionTwo, "keyInfo deveria refletir a versão mais recente")
end)

test("CreatedTime é constante entre versões da MESMA chave; UpdatedTime existe em cada versão", function()
	local store = Store.new()
	store:Set("s", "k", "v1")
	local _v1, infoAfterFirst = store:Get("s", "k")
	store:Set("s", "k", "v2")
	local _v2, infoAfterSecond = store:Get("s", "k")

	local createdFirst = (infoAfterFirst :: Store.VersionInfo).CreatedTime
	local createdSecond = (infoAfterSecond :: Store.VersionInfo).CreatedTime
	assert(createdFirst == createdSecond, "CreatedTime deveria ser o mesmo entre versões da mesma chave (é quando a CHAVE nasceu)")
	assert(type((infoAfterSecond :: Store.VersionInfo).UpdatedTime) == "number", "UpdatedTime deveria ser um number")
end)

-- ================= Update =================

test("Update numa chave inexistente recebe (nil, nil) como (oldValue, oldKeyInfo)", function()
	local store = Store.new()
	local receivedOldValue: unknown = "sentinel-nao-deveria-sobreviver"
	local receivedOldKeyInfoWasNil = false

	store:Update("s", "k", function(oldValue, oldKeyInfo)
		receivedOldValue = oldValue
		receivedOldKeyInfoWasNil = oldKeyInfo == nil
		return { Coins = 10 }, nil, nil
	end)

	assert(receivedOldValue == nil, "oldValue deveria ser nil para chave inexistente")
	assert(receivedOldKeyInfoWasNil, "oldKeyInfo deveria ser nil para chave inexistente")
end)

test("Update grava o novo valor e devolve (newValue, newKeyInfo)", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 10 })

	local newValue, newKeyInfo = store:Update("s", "k", function(oldValue, _oldKeyInfo)
		local old = oldValue :: { Coins: number }
		return { Coins = old.Coins + 5 }, nil, nil
	end)

	assert(newValue ~= nil, "Update deveria devolver o novo valor")
	assert((newValue :: { Coins: number }).Coins == 15, "transform deveria ter incrementado Coins de 10 para 15")
	assert(newKeyInfo ~= nil, "Update deveria devolver um keyInfo para a nova versão")

	local storedValue = store:Get("s", "k")
	assert((storedValue :: { Coins: number }).Coins == 15, "o valor gravado deveria refletir o resultado da transform")
end)

test("Update cuja transform devolve nil ABORTA a escrita: devolve (nil, nil) e NÃO altera o valor guardado", function()
	local store = Store.new()
	local originalVersion = store:Set("s", "k", { Coins = 10 })

	local newValue, newKeyInfo = store:Update("s", "k", function(_oldValue, _oldKeyInfo)
		return nil, nil, nil
	end)

	assert(newValue == nil, "Update abortado deveria devolver newValue == nil")
	assert(newKeyInfo == nil, "Update abortado deveria devolver newKeyInfo == nil")

	local storedValue, storedKeyInfo = store:Get("s", "k")
	assert((storedValue :: { Coins: number }).Coins == 10, "o valor guardado NÃO deveria ter mudado após um abort")
	assert((storedKeyInfo :: Store.VersionInfo).Version == originalVersion, "a versão guardada NÃO deveria ter avançado após um abort")
end)

test("Update repassa userIds/metadata devolvidos pela transform (3o e 4o valor de UpdateAsync real)", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 1 })

	store:Update("s", "k", function(oldValue, _oldKeyInfo)
		local old = oldValue :: { Coins: number }
		local newMetadata: { [string]: unknown } = { Note = "via-update" }
		return { Coins = old.Coins + 1 }, { 7, 8 }, newMetadata
	end)

	local _value, keyInfo = store:Get("s", "k")
	local info = keyInfo :: Store.VersionInfo
	assert(#info.UserIds == 2 and info.UserIds[1] == 7 and info.UserIds[2] == 8, "UserIds devolvidos pela transform deveriam ser gravados")
	assert(info.Metadata.Note == "via-update", "Metadata devolvida pela transform deveria ser gravada")
end)

-- ================= Remove / tombstone =================

test("Remove devolve o valor ANTERIOR à remoção", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 42 })

	local removedValue, removedKeyInfo = store:Remove("s", "k")
	assert(removedValue ~= nil, "Remove deveria devolver o valor que estava guardado antes da remoção")
	assert((removedValue :: { Coins: number }).Coins == 42, "valor removido deveria bater com o que estava guardado")
	assert(removedKeyInfo ~= nil, "Remove deveria devolver um keyInfo")
end)

test("Get depois de Remove devolve (nil, nil) -- RemoveAsync NÃO apaga, mas Get trata tombstone como ausente", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 42 })
	store:Remove("s", "k")

	local value, keyInfo = store:Get("s", "k")
	assert(value == nil, "Get deveria devolver nil depois de Remove (chave está tombstoned)")
	assert(keyInfo == nil, "Get deveria devolver keyInfo nil depois de Remove")
end)

-- ================= GetVersion: versões antigas continuam legíveis (L2.1.3) =================

test("GetVersion: depois de um Remove, a versão ANTERIOR à remoção continua legível por Version, mesmo Get() mostrando nil", function()
	local store = Store.new()
	local versionBeforeRemove = store:Set("s", "k", { Coins = 42 })
	store:Remove("s", "k")

	-- Get (o "estado corrente") mostra ausente -- comportamento já coberto acima.
	local currentValue = store:Get("s", "k")
	assert(currentValue == nil, "Get deveria mostrar ausente depois do Remove")

	-- Mas a versão de ANTES do Remove continua acessível por Version -- histórico preservado.
	local oldValue, oldKeyInfo = store:GetVersion("s", "k", versionBeforeRemove)
	assert(oldValue ~= nil, "GetVersion deveria devolver a versão anterior à remoção -- versões antigas continuam legíveis")
	assert((oldValue :: { Coins: number }).Coins == 42, "o valor da versão antiga deveria ser o que estava lá antes do Remove")
	assert((oldKeyInfo :: Store.VersionInfo).Version == versionBeforeRemove, "keyInfo.Version deveria bater com a versão pedida")
	assert((oldKeyInfo :: Store.VersionInfo).Tombstone == false, "a versão ANTERIOR ao Remove não era, ela mesma, um tombstone")
end)

test("GetVersion: uma versão SOBRESCRITA por um Set posterior continua legível pela sua própria Version", function()
	local store = Store.new()
	local versionOne = store:Set("s", "k", "first")
	local versionTwo = store:Set("s", "k", "second")

	local valueOne = store:GetVersion("s", "k", versionOne)
	local valueTwo = store:GetVersion("s", "k", versionTwo)
	assert(valueOne == "first", "a 1a versão deveria continuar legível pela sua própria Version, mesmo não sendo mais a corrente")
	assert(valueTwo == "second", "a 2a versão (corrente) também deveria ser legível por Version")

	local currentValue = store:Get("s", "k")
	assert(currentValue == "second", "Get deveria continuar mostrando só a versão corrente")
end)

test("GetVersion com um Version que nunca existiu (ou de outra key/store) devolve (nil, nil)", function()
	local store = Store.new()
	store:Set("s", "k", "value")

	local value, keyInfo = store:GetVersion("s", "k", "versao-inventada-que-nunca-existiu")
	assert(value == nil and keyInfo == nil, "Version desconhecida deveria devolver (nil, nil), nunca erro nem dado de outra versão")
end)

test("Remove numa chave inexistente é NO-OP idempotente: devolve (nil, nil)", function()
	local store = Store.new()
	local value, keyInfo = store:Remove("s", "chave-nunca-escrita")
	assert(value == nil and keyInfo == nil, "Remove numa chave inexistente não deveria produzir valor nenhum")
end)

test("Remove duas vezes seguidas: a segunda é NO-OP (devolve nil,nil), não um novo tombstone", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 1 })
	local firstRemove = store:Remove("s", "k")
	assert(firstRemove ~= nil, "1a remoção deveria devolver o valor anterior")

	local secondValue, secondKeyInfo = store:Remove("s", "k")
	assert(secondValue == nil and secondKeyInfo == nil, "2a remoção (já tombstoned) deveria ser NO-OP")
end)

test("Update numa chave tombstoned recebe (nil, nil) como old, igual a uma chave nunca escrita", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 1 })
	store:Remove("s", "k")

	local receivedOldValue: unknown = "sentinel"
	store:Update("s", "k", function(oldValue, oldKeyInfo)
		receivedOldValue = oldValue
		assert(oldKeyInfo == nil, "oldKeyInfo deveria ser nil para chave tombstoned")
		return { Coins = 99 }, nil, nil
	end)
	assert(receivedOldValue == nil, "oldValue deveria ser nil para chave tombstoned (Update trata tombstone como ausente)")

	-- E a escrita depois do Remove "revive" a chave normalmente.
	local value = store:Get("s", "k")
	assert((value :: { Coins: number }).Coins == 99, "Update depois de um Remove deveria revivir a chave com o novo valor")
end)

test("Set depois de Remove também revive a chave (fora do caminho de Update)", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 1 })
	store:Remove("s", "k")
	store:Set("s", "k", { Coins = 2 })

	local value, keyInfo = store:Get("s", "k")
	assert((value :: { Coins: number }).Coins == 2, "Set depois de Remove deveria revivir a chave")
	assert((keyInfo :: Store.VersionInfo).Tombstone == false, "a versão revivida não deveria estar tombstoned")
end)

-- ================= Deep copy (leitura e escrita) =================

test("Set: mutar o valor ORIGINAL depois de Set não afeta o valor guardado", function()
	local store = Store.new()
	local original = { Coins = 100, Inventory = { "Sword" } }
	store:Set("s", "k", original)

	original.Coins = 999
	table.insert(original.Inventory, "Shield")

	local stored = store:Get("s", "k") :: { Coins: number, Inventory: { string } }
	assert(stored.Coins == 100, "mutar o original depois de Set não deveria afetar o valor guardado")
	assert(#stored.Inventory == 1, "mutar o array original depois de Set não deveria afetar o array guardado")
end)

test("Get: mutar o valor RETORNADO não afeta o que está guardado (nem uma segunda leitura, nem o store)", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 100, Inventory = { "Sword" } })

	local firstRead = store:Get("s", "k") :: { Coins: number, Inventory: { string } }
	firstRead.Coins = 1
	table.insert(firstRead.Inventory, "Shield")

	local secondRead = store:Get("s", "k") :: { Coins: number, Inventory: { string } }
	assert(secondRead.Coins == 100, "mutar o retorno de uma leitura não deveria afetar uma leitura seguinte")
	assert(#secondRead.Inventory == 1, "mutar o array retornado não deveria afetar o array de uma leitura seguinte")
end)

test("Update: mutar oldValue recebido pela transform não afeta o valor já guardado (e vice-versa)", function()
	local store = Store.new()
	store:Set("s", "k", { Coins = 100, Inventory = { "Sword" } })

	store:Update("s", "k", function(oldValue, _oldKeyInfo)
		local old = oldValue :: { Coins: number, Inventory: { string } }
		old.Coins = -1 -- mutação que NÃO deveria vazar para o valor guardado
		table.insert(old.Inventory, "Shield")
		return { Coins = 100, Inventory = { "Sword" } }, nil, nil -- devolve um valor NOVO, sem relação de aliasing
	end)

	local stored = store:Get("s", "k") :: { Coins: number, Inventory: { string } }
	assert(stored.Coins == 100, "mutar oldValue dentro da transform não deveria ter afetado o valor guardado antes de Update escrever o novo")
	assert(#stored.Inventory == 1, "idem para o array aninhado")
end)

test("dois Set consecutivos com a MESMA tabela Lua (por referência) não fazem uma versão 'enxergar' mudança feita depois na tabela original", function()
	local store = Store.new()
	local shared = { Coins = 1 }
	store:Set("s", "k", shared)
	local firstVersionValue = store:Get("s", "k")

	shared.Coins = 2
	store:Set("s", "k", shared)
	local secondVersionValue = store:Get("s", "k")

	assert((firstVersionValue :: { Coins: number }).Coins == 1, "a leitura da 1a versão não deveria ter sido afetada pela mutação da tabela compartilhada")
	assert((secondVersionValue :: { Coins: number }).Coins == 2, "a leitura da 2a versão deveria refletir o valor no momento do 2o Set")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
