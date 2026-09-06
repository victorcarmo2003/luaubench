# Revisão — task-services-031 (fiação da persistência: CloudPersistence/Context/marca-suja/load no Bootstrap)

**Revisor:** revisor-services · **Data:** 2026-09-06 · Read-only, tudo abaixo reproduzido por mim (não aceito self-report).

## Metodologia

- Li `.claude/tasks.json` (task-services-031, descrição/acceptance completos) e `arquiteto-persistencia-cloud-2026-09-06.md` seção 10.
- Li integralmente `src/services/Types.luau`, `src/services/Context.luau`, `src/services/init.luau`, `src/services/behavior/GlobalDataStore.luau`, `src/services/datastore/Store.luau`, `src/services/datastore/Snapshot.luau`, `src/services/Context.spec.luau`, `src/services/init.spec.luau`, `src/services/behavior/GlobalDataStore.spec.luau`.
- Rodei `lune run` em **todos os 30 arquivos `*.spec.luau` de `src/services/`** (não 29 — ver achado BAIXO abaixo), um por um, capturando saída completa.
- Escrevi um script de verificação PRÓPRIO (`_revisor_verify_031_temp.luau`, criado temporariamente dentro de `src/services/`, rodado via `lune run`, e DELETADO logo em seguida — zero arquivo deixado no repositório) para cobrir os itens do pedido que os specs do coder NÃO cobrem (ver achado MÉDIO).
- `git diff`/`git diff --stat` de cada arquivo tocado, linha a linha, para confirmar que a alegação "só documentação, zero mudança de comportamento" (GlobalDataStore.luau) é literalmente verdadeira, e que o resto é aditivo.
- `luau-lsp analyze --platform=standard` nos 4 arquivos de produção — 0 diagnósticos.
- Grep de `@lune/fs` em todo `src/services/`.

## 1. Suite completa (item 1 do pedido)

Rodei os 30 specs individualmente com `lune run`. **30/30 passam, zero falha.** O coder relatou "29/29" — contei os arquivos `*.spec.luau` de `src/services/` (`find ... | wc -l` = 30) e todos os 30 passam. Não é uma regressão nem acobertamento (mais arquivos passando, não menos) — provavelmente uma contagem desatualizada do coder. Achado BAIXO, não bloqueia.

Contagens específicas pedidas:
- `Context.spec.luau`: **4/4**
- `src/services/behavior/GlobalDataStore.spec.luau`: **24/24**
- `src/services/init.spec.luau`: **26/26**

## 2–4. Invariante central: round-trip via port FAKE em memória, sem porta = zero I/O, flush não serializa quando limpo

Já coberto de ponta a ponta pelo teste do próprio coder em `init.spec.luau` ("round trip completo: SetAsync/RemoveAsync -> FlushCloudState -> um 'processo novo'..."), que eu li linha a linha (não só rodei) para confirmar que testa o que alega: usa um port fake com contadores de `Save`/`Load`, escreve em duas chaves (uma com 2 versões, outra removida/tombstoned), `FlushCloudState` (confirma `SaveCount==1`, um segundo flush sem sujeira não incrementa), limpa o `Store` module-local (`Store:Import({})`, técnica documentada e honesta para simular "processo novo" dado que o `Store` é singleton do processo Lune) e reidrata com um SEGUNDO `Services.Bootstrap` sobre Scheduler/DataModel frescos — confirma `Version`/`CreatedTime`/`UpdatedTime`/`UserIds`/`Metadata`/`Tombstone` intactos via `GetAsync`/`ListVersionsAsync`, incluindo o tombstone sobrevivendo ao reload. Rodei este spec eu mesmo (26/26, incluindo este teste).

Escrevi TAMBÉM meu próprio script independente (item4 do meu script de verificação) confirmando: `FlushCloudState` chamado 3x seguidas sem sujeira no meio chama `Save` exatamente 1 vez (a primeira). **Passou.**

Sem porta (`nil`): `init.spec.luau` tem teste dedicado confirmando `FlushCloudState() == (false, nil)`, `HasPendingCloudState()` não erra. Rodei — passou. Zero I/O é garantido por construção (nenhum fake sequer é criado nesse teste).

## 3. Save/Load que erram (itens 5 e 6 do pedido) — GAP DE TESTE ENCONTRADO

**Achado MÉDIO:** grep em toda `src/services/**` por um `Load`/`Save` fake que **lança erro** não encontrou NENHUM teste no território. `init.spec.luau` só usa fakes que nunca erram (`Load` devolve `nil`/documento válido, `Save` sempre sucede). Ou seja: os dois itens explícitos do acceptance da tarefa —

> "Save que erra vira (false, mensagem), nunca exceção propagada."
> "Load que erra no Bootstrap PROPAGA."

— **não têm cobertura automatizada no código entregue.** O comportamento está implementado corretamente (código lido e confirmado — `Services.FlushCloudState` faz `pcall(cloudPersistence.Save, ...)` e devolve `(false, firstLineOf(err))` em caso de erro; `loadCloudStateIfPresent` chama `cloudPersistence.Load(...)` e `Snapshot.DecodeDocument(...)` SEM `pcall`, então qualquer erro sobe cru), mas uma regressão futura nesses dois pontos não seria pega por `lune run`.

Escrevi e rodei eu mesmo (script temporário, deletado depois) 4 testes cobrindo exatamente isso:
- `item5`: port com `Save` que lança erro → `Services.FlushCloudState()` (via `pcall` externo, para provar que NADA propaga) devolve `(false, mensagem contendo "boom")`; confirmei também que `HasPendingCloudState()` continua `true` depois (marca-suja preservada, `ClearDirty` só roda em sucesso). **PASSOU.**
- `item6`: port com `Load` que lança erro → `Services.Bootstrap(...)` propaga (o `pcall` externo captura `not ok`, mensagem contém "boom"). **PASSOU.**
- `item6b`: port cujo `Load` devolve uma string JSON inválida → `Services.Bootstrap` propaga o erro de `Snapshot.DecodeDocument` (mensagem: `invalid JSON: key must be a string...`). **PASSOU.**
- `item7`: `Context.GetCloudPersistence()` antes de qualquer `Bootstrap`/`Set` neste processo (script isolado, `lune run` próprio) não erra e devolve `nil`. **PASSOU** (e bate com o teste equivalente já existente em `Context.spec.luau`, que também li e confirmei que testa isso de verdade).

**Correção recomendada (não bloqueia aprovação, mas deve entrar antes de fechar a tarefa ou como task-services seguinte):** portar os 4 testes acima (ou equivalentes) para `init.spec.luau`/`Context.spec.luau` reais, cobrindo Save-que-erra e Load-que-erra-propaga com fakes que lançam exceção. Comportamento correto ✅, cobertura de teste ausente ⚠️.

## 4. Marca-suja cobre OrderedDataStore "de graça" / escrita abortada não suja (itens 8 e 9)

Confirmado lendo `GlobalDataStore.spec.luau` seção "task-services-031" (5 testes, todos rodados por mim, 24/24 no arquivo total):
- `SetAsync` sobre `OrderedDataStore` marca sujo (mesmo `Store` singleton, achatamento de classe) — teste dedicado, passou.
- `UpdateAsync` abortado (transform devolve `nil`) NÃO marca sujo; sucesso marca — passou.
- `RemoveAsync` sobre chave já ausente/tombstoned (no-op idempotente) NÃO marca sujo; remoção real marca — passou.
- `IncrementAsync` que erra (valor corrente não-número) NÃO marca sujo; sucesso marca — passou.

Também confirmei via leitura de `../datastore/Store.luau` que a marca-suja é de fato um ponto único (`writeVersion`, chamado só por `Set`/`Update` não-abortado/`Remove` não-no-op) — a alegação do coder de que `GlobalDataStore.luau` "não precisou mudar nenhuma linha de comportamento" está correta.

## 5. `GlobalDataStore.luau`: só documentação (achado zero regressão)

`git diff --stat` mostra `17 insertions(+), 0 deletions(-)`. Filtrei o diff removendo linhas de comentário/branco — **zero linha de código real mudou.** Confirma a alegação do coder byte a byte.

## 6. `--!strict` / zero `any`

Todos os 7 arquivos tocados (produção + specs) começam com `--!strict`. Grep por `\bany\b` (fora de comentário) nos 4 arquivos de produção (`Types.luau`, `Context.luau`, `init.luau`, `GlobalDataStore.luau`): **zero ocorrência real.** `luau-lsp analyze --platform=standard` nos 4 arquivos: 0 diagnósticos.

Único hit de `@lune/fs` em todo `src/services/**`: `HttpService.spec.luau:1046` — confirmei pessoalmente (li o trecho) que é exatamente o meta-teste "SEM ANY" que lê o próprio texto-fonte de `HttpService.luau` via `fs.readFile` para checar mecanicamente ausência da string `any` — não é I/O de produção, é um padrão pré-existente (task-services-026), não introduzido por esta tarefa. Confirmo a checagem do orquestrador, não apenas aceito.

## 7. Território limpo

`git diff --stat` dos arquivos modificados por esta tarefa: exatamente `src/services/Types.luau`, `src/services/Context.luau`, `src/services/Context.spec.luau`, `src/services/init.luau`, `src/services/init.spec.luau`, `src/services/behavior/GlobalDataStore.luau`, `src/services/behavior/GlobalDataStore.spec.luau`. Nada em `src/runtime/`, `src/valuetypes/`, `tools/`. `src/cli/RunCommand.luau`/`.spec.luau` aparecem modificados no `git status` geral, mas são do agente concorrente em `task-cli-032` (território diferente, sem overlap, conforme aviso do orquestrador) — não tocados por `coder-services` aqui.

## 8. Decisão "Bootstrap sem guarda de carregar uma vez só" (item 12)

Avaliada e considerada **aceitável**: verifiquei em `src/cli/RunCommand.luau:255` que `Services.Bootstrap` é chamado exatamente uma vez por execução real do pipeline (`RunCommand.Execute`); não há watch mode implementado ainda (grep confirma nenhum loop de reexecução no cli). A decisão está documentada explicitamente no código (`init.luau`, comentário de `loadCloudStateIfPresent`) e no relatório do coder, com o raciocínio de que isso é o que permite testar "processo novo" sem inventar um mecanismo de reset. Risco real só aparece quando watch mode existir (uma segunda chamada a `Bootstrap` com o mesmo port, sobre um `Store` que já tem mutações da sessão anterior em memória, sobrescreveria via `Import` o que estivesse em memória, potencialmente perdendo mutações feitas por scripts entre reloads que não foram flushadas) — mas isso é hoje inatingível no pipeline real, e fica registrado (já está, no próprio código) para quando `task-cli-030`/watch mode existir.

## Veredito

**APROVADO COM RESSALVAS**

Nenhum achado GRAVE ou ALTO. Comportamento implementado bate com o desenho do arquiteto e com o acceptance da tarefa em TODOS os pontos que testei pessoalmente (incluindo os dois que o coder não tinha testado). A ressalva é pontual:

- **MÉDIO** — `src/services/init.luau` (comportamento correto, teste ausente): os dois cenários de erro do acceptance ("Save que erra vira (false, mensagem)" e "Load que erra no Bootstrap PROPAGA") não têm teste automatizado no território, apesar de estarem corretos no código. Cenário de falha: uma refatoração futura em `Services.FlushCloudState`/`loadCloudStateIfPresent` que quebre o `pcall`/a propagação não seria pega por `lune run`. Correção: portar os 4 testes que escrevi (Save-que-erra, Load-que-erra, Load-devolve-JSON-inválido, GetCloudPersistence-antes-de-Bootstrap-em-processo-isolado) para `init.spec.luau`/`Context.spec.luau` antes de fechar a tarefa.
- **BAIXO** — contagem "29/29" do coder está desatualizada; são 30 arquivos `*.spec.luau` em `src/services/`, todos passando (30/30). Não é regressão, só corrigir o número no relatório final da tarefa.

Nenhuma superfície de API inventada fora do dump nesta tarefa (não há classe/propriedade/evento novo do Roblox aqui — `CloudPersistence` é extensão deliberada do LuauBench, documentada fora do namespace de qualquer classe simulada, exatamente como a regra 00 permite).
