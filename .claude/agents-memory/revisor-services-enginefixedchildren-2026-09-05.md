# Revisão task-services-010 — EngineFixedChildren.luau + Services.IsEngineFixedChild (2026-09-05)

Read-only. Self-report do coder NÃO aceito como evidência — todo achado abaixo foi reproduzido
independentemente (lune run real, luau-lsp real, git diff real, script de sondagem descartável).

## Veredito

## Veredito
APROVADO

## O que foi verificado, com evidência

1. **Regressão total (`lune run` em TODOS os specs de runtime/services/cli).** Rodei os 33
   `*.spec.luau` encontrados por glob (8 em `src/runtime/`, 10 em `src/services/` incluindo os 2
   novos, 15 em `src/cli/`), um por um, com `EXIT:0` em todos. Números batem exatamente com o
   alegado pelo coder: `EngineFixedChildren.spec` 9/9 (5 casos de guarda), `init.spec` 18/18 (guarda
   pré-Bootstrap + coerência pós-Bootstrap), `StarterPlayer.spec` 3/3, `Integration.spec` (services)
   14/14 — arquivo intocado confirmado por `git diff --stat` (não aparece na lista de modificados).
   Total runtime+services+cli: 33/33 arquivos, zero falha, zero regressão.

2. **`EngineFixedChildren.luau` é módulo folha, dados puros.** Único `require` além de nenhum —
   o arquivo não importa `Context`, `Runtime`/`ClassRegistry`, `fs`, nem qualquer coisa com I/O
   (confirmado por leitura integral do arquivo, 89 linhas). `Of(parentClassName)` devolve
   `ENGINE_FIXED_CHILDREN[parentClassName] or {}` — nunca `nil`, testado explicitamente
   (`Of('Workspace')` e `Of('TotalmenteInventada123')` devolvem `{}` com `#children == 0`).

3. **Os 5 casos de guarda do acceptance** — testei eu mesmo via script descartável
   (`_revisor_edge_probe.luau` na raiz, criado, rodado e apagado nesta revisão) além de confirmar
   que já existem, duplicados intencionalmente, em `EngineFixedChildren.spec.luau` E em
   `init.spec.luau` (nível módulo interno e nível superfície pública `Services.IsEngineFixedChild`).
   Os cinco (`StarterPlayer/Terrain/Terrain`, `Workspace/Terrain/Terrain`,
   `DataModel/StarterPlayerScripts/StarterPlayerScripts`, `ReplicatedStorage/Folder/Folder`,
   `StarterPlayer/MyScripts/StarterPlayerScripts`) todos `false`, confirmados nos dois lugares e na
   minha sondagem manual.

4. **Teste de coerência** (`src/services/init.spec.luau`, linhas ~565-592): depois de
   `Services.Bootstrap` real (scheduler+DataModel reais, não mock), itera
   `KNOWN_ENGINE_FIXED_PARENTS = {"StarterPlayer"}` e, para cada entrada de
   `EngineFixedChildren.Of(parentClassName)`, confirma
   `game:GetService(parentClassName):FindFirstChild(entry.Name) ~= nil` E
   `found.ClassName == entry.ClassName`. Rodei o spec — passa (linha 613 do log:
   "[PASS] TESTE DE COERÊNCIA..."). Fecha exatamente o único modo de falha novo do desenho do
   arquiteto (`EngineFixedChildren` declarando algo que `behavior/**` não cria).

5. **`Services.IsEngineFixedChild` funciona ANTES de `Bootstrap`.** Teste dedicado em
   `init.spec.luau` roda logo depois do teste de `IsServiceClass`/`GetSimulatedServiceClasses` (que
   já prova `not Context.IsSet()`), e o próprio teste reafirma a guarda
   `assert(not Context.IsSet(), ...)` antes de chamar `IsEngineFixedChild` — se um teste anterior no
   arquivo tivesse chamado `Bootstrap`, este teste falharia por construção. Passou.

6. **Ordem de criação de `StarterPlayer` preservada.** `git diff` de
   `src/services/behavior/StarterPlayer.luau` mostra que o array `ENGINE_FIXED_CHILDREN.StarterPlayer`
   preserva a MESMA ordem do código antigo (`StarterPlayerScripts` primeiro, `StarterCharacterScripts`
   depois) — refatoração mecânica de "dois `NewEngineInstance` escritos à mão" para "for sobre
   `EngineFixedChildren.Of`", sem mudança de comportamento. `src/services/Integration.spec.luau`
   (seções "1b" e "6", confirmadas por grep) testa exatamente essa ordem e parenteamento
   (`game:GetService('StarterPlayer')` nasce com os dois filhos, parenteados a ELE, nunca a `game`) e
   **não está na lista de arquivos modificados** (`git status`/`git diff --stat`) — regressão passou
   sem precisar tocar o arquivo, confirmando que o refactor é comportamentalmente transparente.

7. **Nenhuma API de criação nova.** `grep -n "^function Services\."` em `src/services/init.luau`
   devolve exatamente 9 funções: `Register`, `Bootstrap`, `IsKnownClass`, `IsSimulatedClass`,
   `GetDumpVersion`, `IsServiceClass`, `GetSimulatedServiceClasses`, `IsEngineFixedChild`, `new`.
   Nenhuma `NewFixedChild`/variante. `EngineFixedChildren.Of` não é reexportado (confirmado por
   leitura — só `EngineFixedChildren.Is` é usado dentro de `IsEngineFixedChild`).

8. **Nenhum arquivo fora de `src/services/` tocado.** `git status --porcelain` +
   `git diff --stat HEAD`: só `.claude/tasks.json` (bookkeeping do board), um `.md` novo em
   `.claude/agents-memory/` (relatório do coder) e os 4 arquivos de `src/services/`
   (`behavior/StarterPlayer.luau`, `init.luau`, `init.spec.luau` modificados;
   `EngineFixedChildren.luau`/`.spec.luau` novos). Nada em `src/runtime/` ou `src/cli/`.

9. **`--!strict` sem `any`.** Todos os 5 arquivos (novo módulo, novo spec, os 3 patches) começam com
   `--!strict`. `grep -n '\bany\b'` em cada um: zero ocorrências. `luau-lsp analyze --platform=standard`
   rodado individualmente em `EngineFixedChildren.luau`, `EngineFixedChildren.spec.luau`,
   `behavior/StarterPlayer.luau` e `init.luau`: limpo, zero erro/warning de tipo.
   `init.spec.luau` sozinho reproduz uma lista de `TypeError: Unknown require .../*.lua` e
   `Unknown type 'Runtime.Instance'`/`'Types.GeneratedClass'`/etc. — mas confirmei por `git diff` que
   essas linhas (as que referenciam `Runtime.Instance` como anotação de tipo, por exemplo) já
   existiam ANTES desta tarefa como código não tocado (aparecem como contexto, não como `+` no diff),
   e é o MESMO bug de tooling já documentado extensivamente no próprio repositório (achado BAIXO de
   `revisor-runtime-init-2026-09-04.md`: luau-lsp 1.69.0 resolve mal `require("./")` estilo-diretório
   para arquivos `init.luau`, produzindo falsos positivos de "Unknown require"/"Unknown type" só
   quando o arquivo anotação usa esses tipos explicitamente). Confirmei isolando: `Integration.spec.luau`
   (usa o MESMO `require("./")`) não dispara os erros porque não anota variáveis com
   `Runtime.Instance`/`Types.GeneratedClass` explicitamente — é o padrão de anotação, não o código
   novo desta tarefa, que aciona o bug pré-existente. Não é achado desta tarefa.

10. **Divergência de fidelidade documentada.** Cabeçalho de `EngineFixedChildren.luau` (linhas
    23-29) tem a seção "DIVERGÊNCIA DE FIDELIDADE DECLARADA" explícita: no Roblox real os filhos
    fixos são propriedade do motor (indestrutíveis/protegidos), no LuauBench a instância é uma
    `Runtime.Instance` comum e `Destroy()`/reparent funcionam — aceito nesta fase, não implementado
    silenciosamente como se fosse fiel. Bate com a regra 00.

11. **Tentativas de quebra (edge cases), reproduzidas com script descartável
    (criado e apagado, fora de `src/services/`):**
    - `Is('starterplayer', ...)` (minúsculo) -> `false` (case-sensitive, correto — Roblox
      `ClassName`/nomes são case-sensitive).
    - `Of('starterplayer')` -> `{}`.
    - `Is('', '', '')` -> `false`.
    - `Of('')` -> `{}`.
    - Nome/ClassName com case trocado individualmente -> `false` nos dois casos.
    - `'StarterPlayer '` (espaço à direita) -> `false` (sem trim silencioso escondendo bug de
      projeto).
    Nenhuma quebra encontrada. Assinatura confirmada como `string` estrito em `Of`/`Is` (não
    `string?`) — passar `nil` explícito não compila (não testável em runtime sem violar
    `--!strict`, mas a assinatura no arquivo confirma o tipo).

## Achados

Nenhum GRAVE/ALTO/MÉDIO/BAIXO. Implementação bate byte-a-byte com o desenho do arquiteto
(`arquiteto-cli-2026-09-05.md`, seção "Revisão pós-implementação 2026-09-05 (task-cli-015)"): mesma
assinatura de `Of`/`Is`, mesma tabela `ENGINE_FIXED_CHILDREN` com só `StarterPlayer`, mesmo padrão
de comentário/divergência, `Workspace`/`Terrain` deliberadamente fora, `EngineFixedChildren.Of`
mantido interno, `Services.IsEngineFixedChild` pura e segura pré-Bootstrap, nenhuma API de criação
nova, nenhum arquivo fora do território tocado.

## O que eu verifiquei (checklist para quem ler este relatório)

- `lune run` real em 33/33 `*.spec.luau` de runtime/services/cli — todos EXIT:0, números batendo.
- Leitura integral de `EngineFixedChildren.luau`, `EngineFixedChildren.spec.luau`,
  `behavior/StarterPlayer.luau` (+ diff), `init.luau` (+ diff), `init.spec.luau` (+ diff).
- `git status`/`git diff --stat HEAD` para confirmar território.
- `grep -n "^function Services\."` em `init.luau`.
- `luau-lsp analyze` individual nos 4 arquivos tocados/criados + isolamento do falso-positivo em
  `init.spec.luau` comparando com `Integration.spec.luau`.
- Script de sondagem descartável (`_revisor_edge_probe.luau`, criado e apagado) para case
  sensitivity, strings vazias e espaço em branco.
- Leitura de `Integration.spec.luau` seções 1b/6 (grep, sem editar) para confirmar cobertura de
  ordem/parenteamento sem precisar tocar o arquivo.
