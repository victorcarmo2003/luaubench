# Revisão — task-runtime-007 (src/runtime/init.luau + init.spec.luau)

Data: 2026-09-05. Revisor: revisor-runtime (read-only). Escopo: `src/runtime/init.luau` (novo) e
`src/runtime/init.spec.luau` (novo). Nenhum outro arquivo do território foi tocado por esta tarefa
(confirmado via `git status`/`git diff --stat`: só `.claude/tasks.json` + os dois arquivos novos).

## O que foi verificado de fato (não só aceito do relato do coder)

### 1. Regressão dos 7 arquivos existentes — CONFIRMADA rodando cada um

`lune run` em cada spec, isoladamente, na árvore real (não copiada):

| Arquivo | Resultado |
|---|---|
| Signal.spec.luau | 6/6 |
| Instance.spec.luau | 33/33 |
| Scheduler.spec.luau | 16/16 |
| ClassRegistry.spec.luau | 17/17 |
| DataModel.spec.luau | 9/9 |
| Sandbox.spec.luau | 7/7 |
| Integration.spec.luau | 9/9 |
| **init.spec.luau** | **3/3** |

Nenhum desses 7 arquivos aparece no diff — regressão intacta por construção, não só por número batendo.

### 2. `init.spec.luau` só importa o agregador — CONFIRMADO por leitura

Únicos `require` do arquivo: `require("@lune/process")` e `require("./")`. Nenhum módulo interno
(`Signal`/`Instance`/`Scheduler`/`ClassRegistry`/`DataModel`/`Sandbox`/`ThreadBroker`) é importado
direto. Os três testes exercitam registro de classe (formato `Initialize`, sem `Construct`),
`DataModel.new`, `ClassRegistry.new`, hierarquia via `.Parent`, `Sandbox.Run` com `WaitForChild`
sem timeout + `task.wait` reais, e um script que erra e não derruba o processo — tudo via
`Runtime.*` só.

### 3. `Runtime.Instance` não vaza `NewBase`/`SetClassChain`/`SetClassMethods`; `ThreadBroker` não é reexportado — CONFIRMADO em runtime real, não só por leitura

Criei um diretório-irmão simulado fora do repositório (cópia de `src/runtime` para
`%TEMP%\luaubench-revisor-init-007\runtime`, com `services/` como irmão — exatamente a topologia
que `services`/`cli` vão ter) e rodei via `lune run` (não só li o código):

```
Runtime.Instance.NewBase is nil: true
Runtime.Instance.SetClassChain is nil: true
Runtime.Instance.SetClassMethods is nil: true
Runtime.ThreadBroker is nil: true
```

`Runtime.Instance` só tem `GetPropertyRaw`/`SetPropertyRaw`, batendo com a correção de
task-runtime-013 e com o cabeçalho do arquivo.

### 4. Achado de tooling do coder ("require ambíguo") — CONFIRMADO empiricamente, não aceito de relato

A partir do diretório-irmão simulado (`services/` ao lado de `runtime/`, replicando a topologia
real `src/services/` ao lado de `src/runtime/`):

| Forma de `require` | De onde | Resultado |
|---|---|---|
| `require("../runtime")` | `services/algo.luau` (fora do runtime) | **Funciona.** `Runtime.DataModel.new` é `function`, `DataModel.new()` cria instância de verdade. |
| `require("../runtime/init")` | `services/algo.luau` | **Erro:** `could not resolve child component "init" (ambiguous)` |
| `require("../runtime/init.luau")` | `services/algo.luau` | **Erro:** `could not resolve child component "init.luau"` |
| `require("./init")` | módulo irmão dentro do próprio `src/runtime/` | **Erro:** `could not resolve child component "init" (ambiguous)` (mesmo erro, confirmado também aqui, não só de fora) |
| `require("./")` | módulo irmão dentro do próprio `src/runtime/` | **Funciona** (é a forma que `init.spec.luau` usa) |

As quatro combinações batem exatamente com o que o cabeçalho de `init.luau` documenta. Não é
relato aceito de graça — reproduzido com `lune run` real, saída capturada acima.

### 5. "Gotcha do Lune" (identidade de chunk desloca a base de `require` relativos) — CONFIRMADO por teste de mutação, não só por leitura

O cabeçalho afirma que `init.luau`, carregado em estilo-diretório, é identificado pelo path do
**diretório** (`src/runtime`), deslocando a base de resolução em um nível — por isso os `require`
internos usam `./runtime/Xxx` em vez de `./Xxx`. Testei isso removendo a rede de segurança: editei
a *cópia* (nunca o arquivo real) trocando `require("./runtime/Signal")` por `require("./Signal")`
e rodei de novo via o diretório-irmão simulado. Resultado:

```
error requiring module "./Signal": could not resolve child component "Signal"
stack traceback:
  ...
  C:\...\luaubench-revisor-init-007\runtime:63: in function <...>
```

O traceback mostra a própria coluna do erro identificando o chunk como `...\runtime` (o
**diretório**, sem `\init`), confirmando exatamente o mecanismo descrito — não uma suposição, um
erro reproduzido de propósito para provar a causa.

### 6. Achado NOVO, não reportado pelo coder — bug de tooling adicional, MASCARADO pelo já documentado (BAIXO, não bloqueante)

Ao investigar o falso-positivo do `luau-lsp` (que o coder já documentou: qualquer arquivo cujo
nome comece com "init" tem sua própria base de `require` deslocada pela ferramenta), tentei uma
cópia de controle renomeada de `init.spec.luau` (mesmo conteúdo, nome diferente) para confirmar a
hipótese do coder — e ela realmente resolve o `require("./")` corretamente (sem "Unknown
require"), mas revela um **segundo problema distinto**, escondido atrás do primeiro:

```
control_probe.spec.luau(122,23): TypeError: ...
  Property 'scheduler' is not compatible.
  Expected this to be exactly 'Scheduler' from '...\Scheduler.luau', but got 'Scheduler' from '...\Scheduler.luau'
  caused by:
    Property 'Defer' is not compatible.
    Expected this to be exactly '<A...>(Scheduler, (A...) -> (), A...) -> thread'
    but got '(Scheduler, (a...) -> (), a...) -> thread'; different number of generic type pack parameters
```

Isolei a causa comparando três variações (todas com `rokit.toml`/`.luaurc` copiados para não
confundir com a resolução de `@lune/*`):

- `require("./")` de dentro de `src/runtime/` (o próprio `init.spec.luau`/cópia renomeada) →
  dispara o erro de `Defer` acima.
- `require("../runtime")` de um `services/algo.luau` externo, construindo o mesmo
  `SandboxOptions` com `scheduler = Runtime.Scheduler.new()` → **limpo**.
- Mesmo teste externo, mas chamando `scheduler:Spawn(...)`/`scheduler:Wait(...)` **antes** de
  montar a tabela (replicando o padrão do teste 2 de `init.spec.luau`) → **limpo também**.

Ou seja: o mismatch de generics em `Defer` só aparece quando o `luau-lsp` resolve o agregador via
`require("./")` (auto-referência de dentro do próprio diretório) — a forma real usada por
`require("../runtime")` de fora (o contrato documentado para `services`/`cli`) não sofre disso.
Hoje isso é 100% invisível porque o bug do item 5 (nome começando com "init") já interrompe a
análise antes de chegar nesse ponto — mas se alguém corrigir/atualizar o `luau-lsp` e o
falso-positivo de nome sumir, este segundo problema apareceria como um novo erro bloqueante
especificamente em `init.spec.luau` (o único arquivo do projeto que hoje usa `require("./")` de
dentro do próprio `src/runtime/`).

**Classificação: BAIXO, não bloqueante.** É um artefato de análise estática do `luau-lsp`
(a execução real via `lune run` não é afetada — os 3/3 testes passam), confinado à forma de
`require` que só `init.spec.luau` usa, e não afeta o contrato externo real que `services`/`cli`
vão consumir. Não é um defeito de `init.luau`/`init.spec.luau` em si.

**Recomendação:** registrar esta segunda pendência de tooling ao lado da já documentada (no
cabeçalho de `init.luau`/`init.spec.luau`, ou num `pesquisa-*.md` de acompanhamento), para que
quem eventualmente mitigar o bug de nomenclatura não seja pego de surpresa por este segundo layer.
Não abre task nova por conta própria — decisão de arquiteto/pesquisador se vale a pena rastrear
antes disso virar relevante (ex: quando `luau-lsp` for atualizado).

### 7. Superfície pública, campo a campo — CONFIRMADA idêntica ao desenho corrigido

Comparado `Runtime = {...}` de `init.luau` contra a seção `init.luau` do desenho do arquiteto
(já com as duas correções pós-integração aplicadas):

- `Signal = { new }` ✓
- `Instance = { GetPropertyRaw, SetPropertyRaw }` ✓ (sem `NewBase`/`SetClassChain`/`SetClassMethods`)
- `ClassRegistry = { Register, Get, IsRegistered, new }` ✓
- `DataModel = { new }` ✓
- `Scheduler = { new }` ✓
- `Sandbox = { Run }` ✓
- Tipos reexportados: `Signal<T...>`, `Connection`, `Instance`, `ClassDescriptor`, `DataModel`,
  `Scheduler`, `TaskHandle`, `SandboxOptions`, `SandboxResult`, `OutputRecord`, `OutputLevel` — os
  11 do desenho, nem mais nem menos. `FireableSignal` continua fora (correto — não é pública).

### 8. `--!strict`/sem `any` — CONFIRMADO por grep

Zero ocorrências de `any` em `init.luau`/`init.spec.luau`; `--!strict` na primeira linha dos dois.

### 9. `luau-lsp analyze` no próprio `init.luau` (não via `require`, análise direta do arquivo) — limpo

`luau-lsp analyze --platform=standard src/runtime/init.luau` → exit 0, sem erros. O falso-positivo
do item 5/6 só aparece quando se analisa um arquivo **consumidor** cujo nome começa com "init"
(como `init.spec.luau`) — o agregador em si type-checa limpo isoladamente.

## Veredito

```
## Veredito
APROVADO
```

Runtime fecha com esta tarefa. Superfície pública bate exatamente com o desenho corrigido
(incluindo a remoção de `NewBase`/`SetClassChain`/`SetClassMethods`/`ThreadBroker`), o teste de
integração cobre fim-a-fim sem sair do agregador, a regressão dos 7 arquivos anteriores está
intacta (rodada de verdade, não só recontada), e o achado de tooling do coder sobre `require`
ambíguo foi reproduzido de forma independente (diretório-irmão simulado + teste de mutação), não
apenas aceito. Achado novo (item 6) é de tooling, não bloqueante, e não reportado pelo coder —
registrado para acompanhamento futuro, não impede a aprovação.
