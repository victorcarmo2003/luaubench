# Revisão — task-runtime-027 (newproxy(true) fecha getmetatable/setmetatable + rawset/rawget)

Data: 2026-09-05. Arquivos revisados: `src/runtime/Instance.luau`, `src/runtime/Instance.spec.luau`. Confirmado por `git diff --stat HEAD` que só esses dois arquivos + `.claude/tasks.json` mudaram (nenhum outro arquivo do território, nenhum arquivo de `services`/`cli`).

Contexto lido antes da revisão: `.claude/tasks.json` (task-runtime-027, descrição completa), `.claude/agents-memory/revisor-runtime-whitelist-completa-2026-09-05.md` (os dois exploits originais documentados pelo revisor da task-runtime-026, com código exato).

Esta revisão NÃO aceitou nada de graça — todo item abaixo foi reproduzido com script próprio, fora do `Instance.spec.luau` do coder, além de rodar o spec dele. Scripts de prova ficaram em `.scratch-revisor-check/` (dentro do repo, para o `rokit`/`lune` resolverem o manifesto) e foram apagados ao final — árvore de trabalho confirmada limpa (`git status --short` só mostra os 3 arquivos esperados).

## 1. Reprodução independente dos dois exploits originais, na versão REVERTIDA

Extraí `git show HEAD:src/runtime/Instance.luau` (pré-fix, o commit onde task-runtime-026 foi revisada) para uma cópia isolada de `src/runtime/` e escrevi um probe próprio (`exploit_before.luau`, não reaproveitando nada do coder):

```
[OK-EXPLOIT-FUNCIONOU] rawset(target, 'Name', ...) sucede (sem erro) na versão revertida
[OK-EXPLOIT-FUNCIONOU] target.Name lê o valor forjado (bypass de __index confirmado)
[OK-EXPLOIT-FUNCIONOU] rawset(target, 'Destroy', noop) sucede na versão revertida
[OK-EXPLOIT-FUNCIONOU] Destroy real foi neutralizado (Parent continua não-nil)
[OK-EXPLOIT-FUNCIONOU] getmetatable(target) devolve uma tabela real (vazamento)
[OK-EXPLOIT-FUNCIONOU] setmetatable(witness, {}) sucede (troca a metatable real)
[OK-EXPLOIT-FUNCIONOU] witness.Name parou de devolver o Name real após a troca de metatable (virou nil)
```

Confirma, de forma independente, que os quatro vetores (rawset sobre Name, rawset sobre Destroy, getmetatable vazando, setmetatable trocando a metatable e corrompendo leitura em OUTRA instância) funcionavam de verdade antes do patch.

## 2. Confirmação de que os dois exploits erram DEPOIS do fix

Rodei `lune run src/runtime/Instance.spec.luau` (o spec real do coder, sem alterar nada): **63/63 passou**, incluindo os 6 testes novos (linhas 995-1106) que cobrem exatamente os cenários pedidos pelo board.

Além disso, escrevi um probe independente (`exploit_after.luau`), sem reaproveitar o spec do coder, contra o código atual (não revertido):

```
[OK] type(instance) == 'userdata'
[OK] typeof(instance) == 'userdata'
[OK] getmetatable(instance) não é tabela
[OK] setmetatable(instance, {}) erra
[OK] rawset(instance, 'Name', ...) erra
[OK] Name não foi corrompido
[OK] rawset(instance, 'Destroy', noop) erra
[OK] Destroy real continua funcionando após a tentativa
[OK] rawget erra (aceitável -- também fecha o vetor)
```

`getmetatable(instance)` devolve a string sentinela (`"The metatable is locked"`), nunca a `InstanceMeta` real. `setmetatable`/`rawset`/`rawget` erram todos com `"table expected, got userdata"` — mesma família de erro do Roblox real para `rawset(workspace, ...)`.

## 3. Confirmação da alegação técnica central (mutual exclusion de `__metatable` + `table.freeze`)

Escrevi `mutual_exclusion.luau` testando as duas ordens possíveis sobre a MESMA tabela, mais uma terceira via alternativa que o coder não mencionou explicitamente:

- **Ordem 1** (`setmetatable` com `__metatable` primeiro, depois `table.freeze`): falha com `"invalid argument #1 to 'freeze' (table has a protected metatable)"`.
- **Ordem 2** (`table.freeze` primeiro, depois `setmetatable` com `__metatable`): falha com `"attempt to modify a readonly table"`.
- **Ordem 3** (tentativa de contornar congelando a TABELA DE METATABLE em vez do objeto — ideia própria, não do coder): `table.freeze(meta)` sozinho sucede, mas isso não impede `getmetatable(t)` de continuar vazando a metatable real (já que `__metatable` nunca foi setado nesse caminho) — não é um bypass, só confirma que não existe atalho escondido.

**Confirmado independentemente: não existe ordem de chamadas que produza as duas propriedades (`__metatable` setado E tabela congelada) na mesma tabela no Luau/Lune 0.10.5.** A alegação do coder está correta.

## 4. `newproxy(true)` vira userdata de verdade e não quebra nada que dependa de tabela

- `type(instance)` e `typeof(instance)` confirmados `"userdata"` (não `"table"`).
- Grep por `type(`/`typeof(` combinado com Instance em todo `src/`: nenhuma ocorrência depende de Instance ser tabela. As únicas ocorrências de `== "table"`/`~= "table"` fora do próprio `Instance.luau` são: (a) `Sandbox.spec.luau:177` — usa um DOUBLE de teste (`game = { fake = true }`), não uma Instance real, não afetado; (b) `Sandbox.spec.luau:318`/`364` — testam `getmetatable`/`os.date` genéricos, sem relação com Instance; (c) o próprio teste novo do coder que verifica que `getmetatable(instance)` NÃO é tabela (o comportamento esperado).
- Grep por `pairs(self|instance|target|game|workspace|...)`: nenhuma ocorrência no código de produção — nada itera uma Instance como tabela.
- `DataModel.luau` e `ClassRegistry.luau` (os dois únicos outros módulos que chamam `Instance.NewBase`) só consomem a API pública (`SetClassChain`/`SetClassMethods`/`SetClassSchema`/`GetPropertyRaw`/`SetPropertyRaw`) — nunca fazem `setmetatable`/`rawset`/`rawget` sobre o valor retornado. Confirmado lendo o código, não só grep.
- `src/cli/` ainda não importa `runtime`/`Instance` (grep confirmou) — não é afetado por esta mudança, corretamente fora do escopo de regressão declarado (228 = 155 runtime + 73 services, sem cli).
- Testado à parte: uma tabela `{[userdata]: T}` com `__mode = "k"` (o mesmo padrão de `internals`) aceita userdata como chave e lê/escreve normalmente — a troca de representação de Instance para userdata não quebra o mapa fraco que guarda o estado real.

## 5. `GetPropertyRaw`/`SetPropertyRaw` não usam `rawset`/`rawget` sobre a instância

Lido o código diretamente (`Instance.luau:850-863`):

```lua
function Instance.GetPropertyRaw(instance: Instance, name: string): unknown
	local data = getInternal(instance)
	return data.properties[name]
end

function Instance.SetPropertyRaw(instance: Instance, name: string, value: unknown): ()
	local data = getInternal(instance)
	data.properties[name] = value
	data.changed:Fire(name)
end
```

Ambas operam exclusivamente sobre `internals[instance]` (o mapa fraco externo), nunca tocam a Instance (userdata) diretamente com `rawset`/`rawget`. Confirmado por leitura própria, não por relato do coder. Grep geral por `rawset|rawget` em todo `src/` não encontrou nenhuma outra ocorrência de engenharia interna que dependesse da representação antiga (tabela).

## 6. Busca ativa por um SÉTIMO vetor

Escrevi `seventh_vector.luau` caçando especificamente superfícies que userdata poderia ter e tabela não (ou vice-versa):

- **`debug.getmetatable`/`debug.setmetatable`**: confirmado ativamente que NENHUM dos dois existe no Luau (`debugLib["getmetatable"] == nil`, `debugLib["setmetatable"] == nil`) — não haveria bypass de `__metatable` mesmo que o Sandbox expusesse `debug` (e não expõe, confirmado em `Sandbox.spec.luau:485`).
- **Metamétodos que `InstanceMeta` não define** (`__tostring`, `__len`, `__call`, `__eq`, `__concat`, `__lt`, `__add`): nenhum vaza nada nem trava o processo. `#instance`, `instance()`, `"x"..instance`, `instance < instance`, `instance + 1` erram todos de forma limpa (tipo incompatível). `instance == other` continua comparando por identidade (sem `__eq`), como esperado. `tostring(instance)` devolve o endereço genérico (`"userdata: 0x..."`) — não vaza estado interno.
- **`pairs`/`ipairs`/`next`** sobre a Instance: erram `"table expected, got userdata"` — na verdade uma MELHORIA de isolamento em relação à versão anterior (antes, `pairs(instance)` rodava silenciosamente sobre a tabela crua vazia, sem erro, sem iterar nada — agora nem isso é possível).
- **`string.pack`/`buffer.len`/`table.clone`** recebendo a Instance como argumento: todos erram com mensagens de tipo (`"number expected, got userdata"`, etc.) — não há leitura de memória crua do userdata nem vazamento por essas vias (preocupação de memory-safety, não só lógica, descartada).
- **Janela de corrida (TOCTOU)** entre `newproxy(true)` e o lock de `__metatable`: inexistente — não há `yield`/`wait` entre a criação do proxy e `proxyMeta.__metatable = "..."`, e `proxy` não é uma referência acessível por nenhum outro código (nem sequer é atribuída a `internals` ainda) até depois de travada. Luau é cooperativo/single-thread, então não há como outra coroutine interceptar o proxy nessa janela.

**Nenhum sétimo vetor novo encontrado.**

## 7. Regressão total

Rodei cada spec individualmente (não confiei no número agregado do coder):

| Runtime | Resultado |
|---|---|
| ClassRegistry.spec | 29/29 |
| DataModel.spec | 12/12 |
| init.spec | 6/6 |
| Instance.spec | 63/63 |
| Integration.spec | 9/9 |
| Sandbox.spec | 13/13 |
| Scheduler.spec | 16/16 |
| Signal.spec | 7/7 |
| **Total runtime** | **155** |

| Services | Resultado |
|---|---|
| behavior/Index, Players, RunService, StarterPlayer | 4+8+11+3 = 26 |
| ClassBuilder.spec | 9 |
| Context.spec | 3 |
| init.spec | 16 |
| Integration.spec | 14 |
| RejectingSignal.spec | 5 |
| **Total services** | **73** |

**Total geral: 228/228**, batendo exatamente com o relatado.

`git diff HEAD -- src/runtime/Instance.spec.luau` mostrado só com linhas ADICIONADAS (zero remoções) — nenhum dos 57 testes pré-existentes foi alterado, só os 6 novos (995-1106) foram anexados ao final.

`git diff HEAD -- src/runtime/Instance.luau` mostra exatamente **uma linha removida** (`local self = (setmetatable({}, InstanceMeta) :: unknown) :: Instance`) e o bloco novo (comentário extenso + `newproxy(true)` + reatribuição de `__index`/`__newindex`/`__metatable` na metatable do proxy) — confirma que a mudança é cirúrgica: `InstanceMeta.__index`/`__newindex` (toda a lógica dos passos 1-9, schema estrito/leniente, resolução de filho por nome, etc.) permanecem literalmente as mesmas funções, só o objeto físico que carrega a metatable mudou.

`luau-lsp analyze --platform=standard src/runtime/Instance.luau`: sem erros. Grep por `\bany\b` em `Instance.luau`/`Instance.spec.luau`: só ocorrências em comentário (nunca `any` real no código).

## Nota BAIXA, não bloqueante, não é achado desta tarefa

`tostring(instance)` devolve o endereço genérico `"userdata: 0x..."` em vez do nome da instância (o Roblox real define `__tostring` para Instance, então `print(workspace)` imprime `"Workspace"`). Isso NÃO é uma regressão introduzida por esta tarefa — a versão anterior (tabela sem `__tostring`) também devolvia o endereço genérico (`"table: 0x..."`), então o comportamento observável não piorou. É uma lacuna de fidelidade pré-existente, fora do escopo de uma tarefa de segurança; registro aqui só para não ficar silenciosa (regra 00), não para bloquear.

## Veredito

**APROVADO.**

Os dois vetores GRAVE da revisão anterior (getmetatable/setmetatable vazando e trocando a metatable real; rawset/rawget bypassando `__index`/`__newindex` e corrompendo estado visível cross-script) estão fechados, confirmados por reprodução independente antes E depois do fix — não só pelo relato do coder. A mudança de abordagem (userdata via `newproxy(true)` em vez de `__metatable` + `table.freeze`) foi tecnicamente necessária: reproduzi eu mesmo a mutual exclusion alegada, em duas ordens e uma terceira via alternativa, e não existe caminho que produza as duas propriedades na mesma tabela Luau. A mudança aumenta a fidelidade (Instance é userdata no Roblox real) em vez de divergir dela, e a superfície ampliada de userdata (metamétodos não definidos, `debug.getmetatable/setmetatable` inexistentes, `pairs`/`next`/`string.pack`/`buffer`/`table.clone` sobre o proxy) foi ativamente varrida sem achar um sétimo vetor. `GetPropertyRaw`/`SetPropertyRaw` confirmados por leitura própria como já usando a via correta (`internals[instance]`), sem exigir ajuste. Regressão total 228/228 confirmada spec a spec, território intacto (só os 2 arquivos + tasks.json), zero teste pré-existente alterado, zero `any`.
