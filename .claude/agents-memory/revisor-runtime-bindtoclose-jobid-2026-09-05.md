# Revisão — task-runtime-033 / task-runtime-034 / task-runtime-035

Data: 2026-09-05. Território: `src/runtime/`. Read-only, nenhum arquivo editado pelo revisor.

Escopo revisado (diff não commitado no momento da revisão, working tree): `src/runtime/DataModel.luau`, `src/runtime/DataModel.spec.luau`, `src/runtime/Instance.luau`, `src/runtime/ClassRegistry.luau`, `src/runtime/init.luau`.

Nota operacional: durante a revisão, um agente concorrente (`coder-cli`) commitou (`85e6506`) as mudanças de `src/cli/*`/`.claude/tasks.json` que estavam soltas na working tree desde antes desta revisão começar. Isso não afeta o escopo desta revisão — o diff de `src/runtime/` revisado permanece idêntico, não commitado, antes e depois.

## Método (nada foi aceito por self-report)

1. Rodei `lune run` eu mesmo em **todos** os 36 arquivos `*.spec.luau` do repositório (`runtime`, `services`, `cli`, `valuetypes`). Todos passaram, sem exceção. `DataModel.spec.luau`: **25/25**, confirmando o número exato alegado.
2. Contei os testes de `DataModel.spec.luau` antes/depois do diff via `git show HEAD:... | grep -c "^test("`: **16 → 25**, delta de exatamente 9 (6 de task-runtime-033 + 3 de task-runtime-034), batendo com a alegação.
3. Escrevi 2 scripts de verificação independentes (fora de `src/runtime/`, na raiz do repo, apagados ao final — não deixei nenhum arquivo novo no território) que **não reusam nenhuma asserção do `DataModel.spec.luau` do coder** e reproduzem os cenários pedidos:
   - `BindToClose`: dois callbacks (um com `scheduler:Wait`), medindo tempo de parede para confirmar que `RunBindToCloseCallbacks` só retorna depois que os dois terminam (`elapsed >= 0.04s` com `Wait(0.05)`); callback que erra não impede o outro e o erro sai só por `ThreadError` (1 evento capturado, mensagem original preservada, `pcall` externo sempre `ok`); sobrescrita de `BindToClose` (`= nil` e `= function() end`) sempre erra.
   - `JobId`/`PlaceId`/`GameId`/`PlaceVersion`: `Instance.SetReadOnlyRawProperties` chamada isolada (fora do construtor do `DataModel`, sobre uma `Instance.NewBase("Folder", ...)` com `Changed` já conectado) não disparou `Changed` nenhuma vez; valores corretos (`PlaceId`/`GameId`/`PlaceVersion == 0`, `JobId` string não vazia); escrever em qualquer uma das quatro erra com string contendo `"read only"`; uma propriedade fora do canal `ReadOnlyRaw` continua leniente (grava sem erro); `JobId` idêntico entre duas `DataModel.new()` no mesmo processo.
4. `math.random` semeado por processo: rodei `lune run` **duas vezes em processos separados de verdade** (não threads/coroutines) sobre um script que imprime 20 `math.random()`. As duas sequências saíram completamente diferentes, sem `math.randomseed` manual em lugar nenhum do código — confirma a alegação do coder empiricamente, de novo, por mim.
5. `luau-lsp analyze --no-strict-dm-types` nos 5 arquivos do diff: **zero erros/warnings**. Sanity check: rodei o mesmo analyzer sobre um arquivo com erro de tipo deliberado (`local x: number = "not a number"`) e ele acusou corretamente — confirma que a ausência de erros acima é sinal real, não silêncio de ferramenta mal configurada.
6. Grep manual em todo o diff por `\bany\b` em linhas adicionadas: zero ocorrências. Todos os 5 arquivos mantêm `--!strict` na primeira linha.
7. Confirmei via `git diff` que o diff de `ClassRegistry.luau`/`init.luau` é 100% dentro de blocos `--[[ ... ]]` já abertos (cabeçalho de módulo) — nenhuma linha de código executável foi tocada nesses dois arquivos pela mudança do item 3 da lista fechada (task-runtime-035). O único código novo em `init.luau` (a reexportação `RunBindToCloseCallbacks = DataModelModule.RunBindToCloseCallbacks`) é atribuído no próprio comentário a task-runtime-033, não a task-runtime-035, e está corretamente fora do escopo "zero código" daquela task.
8. Confirmei que nenhum arquivo fora de `src/runtime/` foi tocado pelas três tasks (o `git status` mostrava outros arquivos de `src/cli/`/`src/valuetypes/`/`.claude/tasks.json` soltos na working tree, mas pertencem a outras tasks da mesma leva, não a estas três — nenhum overlap).
9. Verifiquei ausência de dependência circular nova: `DataModel.luau` passou a `require("./Scheduler")`; `Scheduler.luau` só requer `Signal`/`ThreadBroker`/`@lune/task` — sem ciclo.
10. Confirmei que `bindToCloseCallbacks` usa exatamente o mesmo padrão já estabelecido e testado (`internals`, `validatedClassMethodTables`, `validatedClassSchemas` em `Instance.luau`) de mapa fraco `{ [Instance]: T }` com `setmetatable({}, { __mode = "k" })` + cast duplo via `unknown` — não é um padrão novo arriscado, é reuso do que já existe.
11. Confirmei que `RunBindToCloseCallbacks` é inalcançável por script de usuário: não é método de instância (só `BindToClose` registra é), e `Runtime` (o módulo `init.luau`) nunca é exposto ao sandbox — `ScriptEnvironment.Build` (`src/cli/ScriptEnvironment.luau`) só injeta `game`/`workspace`/`script`/`Instance.new`/`require`/`_G`/`shared`, nunca o módulo `Runtime` inteiro.
12. Confirmei que a família de erro `"Unable to assign property {key}. Property is read only"` usada pelo novo canal é literalmente a mesma string já usada e **confirmada contra o Roblox real** para `ClassName`/`ClassSchema.ReadOnly` (task-runtime-014, pesquisa citada no código) — não é uma string nova inventada.
13. Confirmei que `Instance.SetPropertyRaw`/`GetPropertyRaw` (canal de engenharia usado por `services`/`cli`) escrevem direto em `data.properties`, sem passar por `InstanceMeta.__newindex` — ou seja, continuam podendo escrever `JobId` etc. por baixo dos panos se `services`/`cli` precisarem um dia; só o script do usuário (via `__newindex`) é bloqueado. Isso é o comportamento correto e intencional, não uma brecha.
14. Sobre o item 6 do pedido (JobId compartilhado entre `DataModel.new()` no mesmo processo é decisão certa ou bug?): busquei todos os call sites de `DataModel.new()` em `src/cli` — há exatamente **um**, em `RunCommand.luau:174`, chamado uma vez por execução real de `luaubench run`. Os specs que criam múltiplas `DataModel.new()` no mesmo processo (`DataModel.spec.luau`, `Integration.spec.luau`, etc.) são artefato de teste, não uso real. Logo "um processo Lune == um servidor" (a premissa documentada) é factualmente verdadeira para o único caminho de produção existente hoje — compartilhar `PROCESS_JOB_ID` por processo é a decisão certa, não um bug latente. Concordo com o coder.

## Achados

Nenhum achado GRAVE, ALTO, MÉDIO ou BAIXO. Não encontrei nada de errado nas três tasks depois de reproduzir cada alegação de forma independente.

Duas observações não-bloqueantes, registradas por completude (não são "achados" no sentido do rubric — não têm cenário de falha concreto):

- A mensagem de erro para `BindToClose(callback_inválido)` (`Invalid argument #1 to 'BindToClose' (function expected, got {typeof(callback)})`) está corretamente marcada no próprio código como "APROXIMAÇÃO DE BOA-FÉ... string exata do Roblox real NÃO confirmada" — já é uma divergência declarada como a regra 00 exige, não uma pendência escondida.
- O GUID gerado por `generateProcessGuid` não é um UUIDv4 RFC 4122 real (não força os bits de versão/variante) — também já declarado explicitamente no comentário do código como limitação de forma, não de unicidade prática. Nenhum consumidor atual (`MessagingService`, ainda não implementado nesta leva) depende dos bits de versão.

## Veredito

**task-runtime-033: APROVADO**
**task-runtime-034: APROVADO**
**task-runtime-035: APROVADO**
