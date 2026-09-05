# Revisão task-runtime-032 — TypeNameResolver + typeof fiel no Sandbox + MemberDescriptor.ValueType/ValueCategory

Revisor: revisor-runtime (read-only). Data: 2026-09-05. Nenhum self-report aceito sem
reprodução própria — todos os itens abaixo foram executados por este revisor, não copiados do
`result` da task.

## Veredito

**APROVADO**

## Método

- Lido `.claude/tasks.json` (task-runtime-032, descrição + acceptance + `result`), seção 3.4
  "runtime" e "Decisão 4" de `.claude/agents-memory/arquiteto-valuetypes-2026-09-05.md`.
- Lido o diff real (`git diff`) de `Instance.luau`, `Instance.spec.luau`, `Signal.luau`,
  `Signal.spec.luau`, `Sandbox.luau`, `Sandbox.spec.luau`, `init.luau`, e o conteúdo integral dos
  dois arquivos novos `TypeNameResolver.luau`/`.spec.luau`.
- Comparado `TypeNameResolver.luau` linha a linha contra `UnknownClassResolver.luau` (precedente
  citado).
- Rodado **os 33 arquivos `*.spec.luau`** de `src/runtime`+`src/services`+`src/cli` via
  `lune run` um a um, checando exit code e a linha `N/N testes passaram`.
- Escrito e rodado um script descartável próprio (não commitado, apagado depois) na raiz do repo
  chamando `typeof` nativo, `Instance.IsInstance`/`Signal.IsSignal`/`IsConnection`, e
  `Sandbox.Run` com/sem `TypeNameResolver.Set` instalado.
- Para o `luau-lsp analyze` "diff vazio contra baseline": como o repositório está **com outros
  agentes escrevendo concorrentemente** (`git status` mudou 3x durante esta revisão —
  `TreePlanner.luau`, `RunCommand.luau`, `Float32.luau`/`.spec.luau` apareceram como modificados
  entre uma checagem e outra), `git stash` no working tree ao vivo foi **evitado de propósito**
  (risco de colidir com escrita concorrente de outro processo). Em vez disso: criado um
  `git worktree --detach HEAD` isolado, `git diff` extraído só dos arquivos de `src/runtime/`
  desta task, aplicado (`git apply`) nesse worktree limpo + cópia dos dois arquivos novos, e
  `luau-lsp analyze` rodado nos dois estados (HEAD puro vs. HEAD+diff-desta-task), scoped a
  `src/runtime src/services src/cli`. Isso isola exatamente o efeito desta task, sem contaminação
  do WIP concorrente de outros agentes.

## Verificação item a item

1. **33 specs, `lune run` um a um** — reproduzido: 33/33 processos, exit 0 em todos.
   `Instance.spec.luau` 64/64, `Signal.spec.luau` 8/8, `Sandbox.spec.luau` 22/22,
   `TypeNameResolver.spec.luau` 4/4 — todos batem exatamente com o `result` da task.

2. **`grep -ri valuetypes src/runtime/` vazio** — reproduzido, case-sensitive e
   case-insensitive, exit 1 (sem match) nos dois.

3. **`typeof` com/sem resolvedor** — reproduzido com script próprio:
   - `typeof(instância)` nativo = `"userdata"` (não `"table"`).
   - `typeof(signal)`/`typeof(connection)` nativos = `"table"`.
   - Via `Sandbox.Run` (wrapper `resolveTypeName`), sem resolvedor instalado:
     Instance→`"Instance"`, Signal→`"RBXScriptSignal"`, Connection→`"RBXScriptConnection"`,
     `number`/`string`/`boolean`/`nil`/`table` caem no fallback nativo corretamente.
   - Com um resolvedor de Value Types instalado que só reconhece um marcador de string
     específico: Instance/Signal/Connection continuam corretos (passos 1-3 vêm antes do
     resolvedor), o marcador reconhecido devolve o nome do resolvedor, e `number`/`string`
     continuam nativos — confirma o fallback não quebra com resolvedor presente.

4. **Contrato PARCIAL de `TypeNameResolver.Resolve`** — lido o cabeçalho do módulo (diferença
   deliberada vs. `UnknownClassResolver.Resolve`, que é TOTAL) e confirmado pelo teste acima:
   com resolvedor instalado e um valor que ele não reconhece (`42`, `"outra string qualquer"`),
   `Resolve` devolve `nil` sem erro, e o wrapper cai no `typeof` nativo — não é desculpa para
   preguiça, é o único jeito de `typeof(5)=="number"` sobreviver a um resolvedor instalado.

5. **`MemberDescriptor.ValueType`/`ValueCategory` são opcionais de fato** — inspecionado
   `src/services/generated/classes/Lighting.luau` (gerado ANTES desta tarefa, não tocado por
   ela): `["Ambient"] = { Kind = "Property", Default = nil, ReadOnly = false }`, sem os dois
   campos novos. Compila e passa (`services/init.spec.luau` 24/24,
   `services/Integration.spec.luau` 14/14 rodados nesta revisão).

6. **`IsInstance`/`IsSignal`/`IsConnection` não reexportadas** — `grep` em `init.luau` não
   encontra nenhum dos três nomes; `Runtime.Instance` só expõe `GetPropertyRaw`/`SetPropertyRaw`,
   `Runtime.Signal` só expõe `new` — mesmo padrão de `NewBase` (também ausente de
   `Runtime.Instance`).

7. **`typeof(instance)` é `"userdata"`, não `"table"`** — confirmado empiricamente (item 3),
   fato correto desde task-runtime-027 (`newproxy(true)`).

8. **`--!strict` sem `any` novo** — os dois arquivos novos têm `--!strict` na primeira linha;
   `git diff -- src/runtime/ | grep "^+" | grep -w any` não encontra nenhuma linha adicionada
   com `any` (as ocorrências de `any` em `Sandbox.luau`/`Scheduler.luau`/`ThreadBroker.luau` são
   todas pré-existentes, fronteira do stub `LoadOptions.environment`/`luau.load` do próprio Lune).

9. **Sem validação de escrita por `ValueType`** — `InstanceMeta.__newindex` (linha 692) não
   referencia `ValueType`/`ValueCategory` em nenhum ponto do corpo; os dois campos só aparecem na
   declaração de tipo e nos comentários.

## luau-lsp analyze — nuance encontrada (não é defeito desta task)

Rodar `luau-lsp analyze` no working tree AO VIVO agora (`src/runtime src/services src/cli`) dá
**62 erros**, não os 58 do HEAD puro — mas isso é 100% explicado por WIP concorrente de outros
agentes (`TreePlanner.luau`, `RunCommand.luau` modificados por `coder-cli`, `Float32.luau`
modificado por `coder-valuetypes`, todos aparecendo/mudando durante esta revisão). Isolando via
worktree limpo (HEAD vs. HEAD + só o diff de `src/runtime/` desta task), o resultado do
`luau-lsp analyze` é **byte-a-byte idêntico** (`diff` vazio de verdade) — confirma a alegação
"diff vazio" da task, só que o método ingênuo (`git stash` no repo ao vivo agora) daria um falso
positivo de regressão por causa de outro agente escrevendo ao mesmo tempo. Registrado aqui só
como nota de processo/timing — não é problema do código desta task nem motivo para ressalva.

## Achados

Nenhum GRAVE/ALTO/MÉDIO/BAIXO. Toda alegação do `result` da task foi reproduzida
independentemente e bateu exatamente (contagens de teste, comportamento de `typeof`, contrato
parcial, campos opcionais, não-reexportação, ausência de `valuetypes` no grep, zero `any` novo,
ausência de validação de escrita).

## Verificado e descartado

- Vazamento de memória via `registeredSignals`/`registeredConnections` (`__mode = "k"`): chaves
  são sempre tabelas (`self`/`listener` de `Signal.luau`), uso de tabela fraca é válido e segue o
  mesmo padrão de `internals` em `Instance.luau`.
- `Instance.IsInstance` indexando `internals` com `value :: Instance` para um `value: unknown`
  arbitrário (número, string, `nil`, userdata alheio): não levanta erro em runtime (cast é só
  compile-time; indexação de tabela Luau aceita qualquer valor como chave) — confirmado pelo
  spec e pelo script próprio.
