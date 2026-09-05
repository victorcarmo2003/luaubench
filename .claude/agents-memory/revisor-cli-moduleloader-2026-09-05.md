# Revisão — task-cli-005 (`ScriptEnvironment` + `UnsimulatedGlobals` + `ModuleLoader`)

Data: 2026-09-05. Revisor: `revisor-cli`. Read-only — nada foi alterado em `src/cli/`. O self-report
do coder NÃO foi aceito como evidência; todo achado abaixo foi reproduzido por mim, com comandos
próprios ou testes próprios (criados num arquivo escrato `src/cli/_ReviewScratch.spec.luau` +
`src/cli/_ModuleLoaderPatched.luau`, ambos **deletados ao final** — `git status` confirmado limpo
de novo, só os 6 arquivos novos do coder + diff de `Messages.luau` continuam pendentes).

## Arquivos revisados

- `src/cli/ScriptEnvironment.luau` + `.spec.luau`
- `src/cli/UnsimulatedGlobals.luau` + `.spec.luau`
- `src/cli/ModuleLoader.luau` + `.spec.luau`
- `git diff -- src/cli/Messages.luau`
- Leitura cruzada: `src/runtime/Sandbox.luau` (mecanismo real de `Sandbox.Load`/`Sandbox.Run`),
  `src/runtime/init.luau` (superfície pública reexportada), `src/runtime/Signal.luau` (`Wait()`
  roteando por `ThreadBroker`), `src/runtime/Instance.luau` (confirmação de `newproxy(true)`/
  `typeof == "userdata"`).

## Regressão — números confirmados por mim, rodando cada spec

Rodei `lune run` em cada um dos 29 arquivos `*.spec.luau` do repositório (12 cli + 8 runtime + 9
services), individualmente, e somei os totais impressos por cada um:

- **runtime: 162/162** (ClassRegistry 29, DataModel 12, Instance 63, Integration 9, Sandbox 20,
  Scheduler 16, Signal 7, init 6)
- **services: 73/73** (ClassBuilder 9, Context 3, Integration 14, RejectingSignal 5, init 16,
  behavior/Index 4, behavior/Players 8, behavior/RunService 11, behavior/StarterPlayer 3)
- **cli: 136/136** (Args 13, Diagnostics 7, JsonValue 8, Messages 10, ModuleLoader 12, ProjectFile
  17, ScriptEnvironment 6, SyncRules 28, TreeMaterializer 8, TreePlanner 17, UnsimulatedGlobals 5,
  init 5) — os 23 novos (ModuleLoader 12 + ScriptEnvironment 6 + UnsimulatedGlobals 5) batem
  exatamente com o que o coder alegou.

Todos os 29 processos saíram com exit code 0. **Os três números batem exatamente com o alegado
pelo coder** (162/162, 73/73, 136/136 = 113 pré-existentes + 23 novos).

`luau-lsp analyze --platform=standard` (sem `--definitions`, mesmo comando implícito usado nas
revisões anteriores do território) rodado por mim:
- Nos 6 arquivos novos isolados: exit 0, zero erros.
- Em todo `src/cli/*.luau` agregado: exit 1, mas os DOIS únicos erros são
  `src/cli/init.spec.luau(31,13)`/`(32,18)` — o falso-positivo de tooling do luau-lsp 1.69.0 com
  arquivos `init.*`, já documentado em tasks anteriores (`init.spec.luau` não faz parte desta
  tarefa). Nenhum erro nos 6 arquivos de `task-cli-005`.

`grep -w "any"` nos 3 arquivos de produção: zero ocorrências. `--!strict` confirmado como primeira
linha nos 6 arquivos (3 produção + 3 spec).

## Verificações específicas pedidas — todas reproduzidas por mim

1. **Regressão total** — confirmada acima, números exatos.
2. **Critério adicional (`task.spawn` dentro de módulo → 1 OutputRecord no Script original)** —
   confirmado pelo teste do próprio coder (`ModuleLoader.spec.luau`, passou), E reproduzido de
   forma independente: copiei `src/cli/ModuleLoader.luau` para um arquivo temporário com as 3
   linhas de override (`moduleGlobals.task/.spawn/.delay = moduleTaskGlobal...`) comentadas via
   `string.gsub` sobre o texto real do arquivo (nunca editei o arquivo de verdade), e rodei o
   mesmo cenário against essa cópia patcheada: **caiu para 0 OutputRecords**, exatamente como o
   coder alegou ter observado. A alegação de "regressão real reproduzida" é verdadeira, não
   self-report não verificado.
3. **Cache por identidade, não por nome/path** — testei duas Instances `ModuleScript` diferentes
   com o **mesmo `Name`** (`"SameName"`), cada uma com `Source` diferente (`return "A"` /
   `return "B"`): `require` da primeira devolveu `"A"`, da segunda devolveu `"B"` — se o cache
   fosse por nome, a segunda teria devolvido `"A"` de novo (cache hit incorreto). Confirmado que é
   por identidade de Instance.
4. **Ciclo mesma thread vs. espera cross-thread** — o teste do coder (A→B→A, auto-referência)
   confirma o erro de recursão na mesma thread. Fiz um teste adicional: duas threads DIFERENTES
   (`scheduler:Spawn` duas vezes) requerendo o MESMO módulo (com `task.wait(0.03)` no corpo) ao
   mesmo tempo — nenhuma errou como ciclo; as duas esperaram e receberam o MESMO valor
   (`"shared-value"`) depois de alguns `StepOnce`. Confirma a distinção "mesma thread = ciclo" vs.
   "outra thread = espera via Signal" está correta.
5. **`pcall` no script chamador captura erro do módulo** — confirmado pelo teste do coder
   (`ModuleLoader.spec.luau`, "erro SÍNCRONO... capturável por pcall"), que roda um `Sandbox.Run`
   real de ponta a ponta. Passou.
6. **`Vector3.new(...)` (e os outros 22 da lista) erram com `[LuauBench]`, nunca "index nil"** —
   confirmado pelo spec do coder (`UnsimulatedGlobals.spec.luau`, teste dentro de um `Sandbox.Run`
   real com `pcall(function() return Vector3.new(1,2,3) end)`) e por leitura do código
   (`buildSentinel` usa `error(message, 2)` no `__index`/`__newindex`, `table.freeze` aplicado
   DEPOIS de `setmetatable`, ordem correta). A lista tem **23** nomes (não 22 — contei
   explicitamente no array `UNSIMULATED_GLOBAL_NAMES` e no teste `Build()`, que assere
   `#names == 23`), batendo com a Decisão 12 do arquiteto (a lista lá também tem 23, incluindo
   `Enum`). Isso é só uma imprecisão de contagem no meu briefing de entrada, não um problema do
   código.
7. **`_G` compartilhado dentro do mesmo run** — confirmado pelo spec do coder
   (`ScriptEnvironment.spec.luau`, dois `script` diferentes recebendo a MESMA `GlobalTable`,
   escrita por um lida pelo outro). Vazamento entre runs diferentes não é testável neste nível —
   `ScriptEnvironment.luau` nunca cria a tabela, só a recebe via `EnvironmentContext`; quem cria
   uma tabela nova por `run` é `RunCommand` (`task-cli-006`, ainda não escrito) — delegação
   correta e documentada no cabeçalho, não uma lacuna desta tarefa.
8. **`_G`/`shared` são tabelas SEPARADAS** — confirmado por leitura do código
   (`ScriptEnvironment.Build` faz `globals._G = context.GlobalTable` e
   `globals.shared = context.SharedTable`, dois campos distintos de `EnvironmentContext`) e pelo
   teste dedicado do coder (`globals._G ~= globals.shared`, escrever numa não afeta a outra).
   Bate com a correção de task-cli-007 citada no cabeçalho.
9. **Família de mensagens** — confirmado por leitura do `git diff` de `Messages.luau`:
   `RequireRecursedSameThread`/`RequireDidNotReturnOneValue`/`RequireInvalidArgument` devolvem
   strings SEM prefixo; `RequireAssetIdNotSupported` devolve `"[LuauBench] require by asset id..."`
   COM prefixo. Confirmado também pelos testes (`string.find(..., "[LuauBench]", 1, true)` só no
   caso do asset id).
10. **Isolamento entre `ModuleLoader`s de Scripts diferentes** — testei dois `ModuleLoader`
    distintos (dois Scripts, `ScriptA`/`ScriptB`), com o MESMO `Cache` compartilhado (decisão
    intencional) mas construídos separadamente, cada um requerendo um módulo próprio com
    `task.spawn(error(...))`: `recordsA` recebeu EXATAMENTE 1 registro (o de A), `recordsB`
    EXATAMENTE 1 (o de B) — nenhum vazamento cruzado de `ownThreads`/assinatura de `ThreadError`
    além do `Cache` intencionalmente compartilhado. Nota informacional (BAIXO, não bloqueante,
    fora do acceptance desta tarefa): se dois Scripts DIFERENTES requerem o MESMO módulo, ainda
    não cacheado, verdadeiramente ao mesmo tempo (só possível se o primeiro Script ceder antes do
    `require` terminar — `Scheduler:Spawn` roda síncrono até o primeiro yield), um erro
    assíncrono (`task.spawn`) disparado durante ESSE carregamento compartilhado seria atribuído ao
    Script que iniciou o carregamento primeiro, não ao segundo que só esperou — consequência
    natural de "quem carrega primeiro" ser dono do `ScriptEnvironment`/`ownThreads` usados na
    única execução real do módulo. Isso é coerente com a aproximação já declarada na Decisão 13
    do arquivo de arquitetura ("scriptName nunca é o módulo que de fato errou, é quem originou a
    cadeia") — não é um bug novo, só um caso extremo não testado explicitamente. Não bloqueia.
11. **Forma estrutural `{ [string]: unknown }` no lugar de `Runtime.SandboxGlobals`** — confirmei
    por leitura direta: `src/runtime/Sandbox.luau:145` define
    `export type SandboxGlobals = { [string]: unknown }`; `src/runtime/init.luau` reexporta
    `SandboxOptions`/`SandboxResult`/`SandboxChunkOptions`/`OutputRecord`/`OutputLevel` mas **não**
    `SandboxGlobals` (confirmado lendo a lista completa de `export type` do arquivo, linhas
    117-134). `ScriptEnvironment.Build` retorna `{ [string]: unknown }` literal — byte-a-byte
    idêntico à definição real, aceito estruturalmente por Luau em `SandboxOptions.extraGlobals`
    sem cast nenhum. **Confirmado: honesto, não é `any` disfarçado** — é dívida técnica real (só
    falta o `runtime` reexportar o alias de nome), não um contorno de segurança de tipos.
    Recomendo ao orquestrador considerar uma tarefa pequena e não-bloqueante para
    `coder-runtime`: adicionar `export type SandboxGlobals = SandboxModule.SandboxGlobals` em
    `runtime/init.luau` — puramente cosmético (nomeação), sem urgência.
12. **`--!strict` sem `any` real** — confirmado por grep (`grep -w "any"` → zero ocorrências nos 3
    arquivos de produção) e pela primeira linha de cada arquivo.
13. **`Messages.luau` só recebeu adições** — `git diff --stat` mostra
    `40 insertions(+), 0 deletions(-)`; `git diff` completo confirma que todo o hunk é um bloco
    novo no fim do arquivo (`Messages.UnsimulatedGlobal`, `Messages.RequireRecursedSameThread`,
    `Messages.RequireDidNotReturnOneValue`, `Messages.RequireInvalidArgument`,
    `Messages.RequireAssetIdNotSupported`), nenhuma linha existente removida ou alterada.

## Achados

Nenhum GRAVE, ALTO ou MÉDIO. Um BAIXO não-bloqueante já coberto no item 11 acima (recomendação de
reexportar `SandboxGlobals`, cosmética) e uma nota informacional no item 10 (atribuição de erro
assíncrono em corrida cross-Script rara, coerente com aproximação já declarada, não testada
explicitamente mas não contradiz o acceptance da tarefa).

A decisão de design não ditada literalmente pelo board — `ModuleLoader` como uma instância POR
SCRIPT em vez de uma instância global por `run`, com `Cache` compartilhado via
`ModuleLoader.NewCache()` — está bem fundamentada no cabeçalho do arquivo, é coerente com o
mecanismo real de `Sandbox.Load`/`ThreadError` que já existe em `runtime` (li o código-fonte de
`Sandbox.luau` para confirmar, não só o comentário do coder), e a reprodução independente da
regressão (item 2 acima) prova que não é uma alegação vazia.

## Veredito

```
## Veredito
APROVADO
```
