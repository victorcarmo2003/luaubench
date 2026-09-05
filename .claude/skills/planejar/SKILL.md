---
name: planejar
description: Planeja uma feature do LuauBench — dispara o arquiteto para desenhar, o planejador para quebrar em tarefas paralelas no board, e o pesquisador em paralelo quando houver formato/API externa desconhecida. Use antes de construir sistema novo ou quando a mudança cruza mais de um território.
argument-hint: "[feature ou sistema a planejar]"
---

# /planejar

Planeja `$ARGUMENTS` até virar tarefas despacháveis em paralelo.

## 0. Decidir se precisa do arquiteto

Leia `.claude/CLAUDE.md` e o que já existe em `.claude/agents-memory/`.

- **Já existe desenho salvo** que cobre a mudança → pule para o passo 2. O arquiteto é caro; não o chame para redesenhar o que já está desenhado.
- **Sistema novo, ou a mudança cruza `src/runtime/`/`src/services/`/`src/cli/` sem contrato definido** → passo 1.

## 1. Arquiteto (+ pesquisador em paralelo)

Dispare na **mesma mensagem**:

- `arquiteto` — desenhar o sistema.
- `pesquisador` — **só se** houver formato/API externa (Lune, Roblox API Dump, formato de projeto Rojo, manifesto Rokit) cujo detalhe exato seja desconhecido. Roda em paralelo, não bloqueia.

No prompt do arquiteto inclua: o pedido do usuário, o que já existe decidido sobre isso, e a exigência de dividir por território (`runtime`/`services`/`cli`) com contrato explícito entre eles.

Aguarde o arquiteto. O resultado do pesquisador entra como insumo se chegar a tempo; se não, o planejador segue sem ele.

## 2. Planejador

Dispare `planejador` com:

- O desenho (caminho em `.claude/agents-memory/`).
- O estado atual do board.
- Instrução de preencher `agent`, `reviewer` e `wave` em toda tarefa.

O planejador escreve em `.claude/tasks.json`.

## 3. Consolidar

Apresente ao usuário:

```
## Plano: [feature]

**Desenho:** resumo em 3-5 linhas + caminho do arquivo

**Levas:**
Leva 1 (paralelo): task-xxx-001 [coder-runtime] · task-xxx-002 [coder-cli]
Leva 2 (paralelo): task-xxx-003 [coder-services] (depende de 001)
Leva 3: revisão

**Total:** N tarefas, M levas
**Riscos apontados:** o que o arquiteto sinalizou (inclusive divergências de fidelidade com o Roblox real)

Próximo passo: `/implementar`
```

Não despeje o desenho inteiro nem o JSON no chat.

## Regras

- Toda tarefa sai com `agent`, `reviewer`, `wave` e `acceptance` preenchidos. Sem isso o `/implementar` não consegue despachar em paralelo.
- Duas tarefas na mesma leva nunca compartilham arquivo nem território de escrita.
- Se o arquiteto sinalizar que a feature exige violar uma invariante de `.claude/rules/00-projeto.md` (ex: inventar propriedade fora do API Dump, dependência fora do Lune), **pare e pergunte ao usuário** antes de planejar.
