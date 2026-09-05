---
name: implementar
description: Despacha tarefas do board em paralelo por território, leva a leva, e dispara os revisores ao fim de cada leva. Use depois de /planejar, ou quando o usuário pedir para tocar as tarefas pendentes.
argument-hint: "[leva, id de tarefa, ou vazio para a próxima leva]"
---

# /implementar

Despacha o trabalho do board com paralelismo máximo. **A thread principal não implementa — orquestra.**

## 1. Ler o board

Leia `.claude/tasks.json`.

- `$ARGUMENTS` vazio → menor `wave` que ainda tem tarefa em `todo`.
- `$ARGUMENTS` é número → aquela leva.
- `$ARGUMENTS` são IDs → só essas tarefas.

Se o board estiver vazio: pare e diga para rodar `/planejar` primeiro.

## 2. Checar conflito antes de disparar

Duas tarefas da mesma leva **nunca** podem tocar o mesmo arquivo ou o mesmo território de escrita.

| Agente | Território exclusivo |
|---|---|
| `coder-runtime` | `src/runtime/` |
| `coder-services` | `src/services/` |
| `coder-cli` | `src/cli/` |

Se houver colisão: quebre a tarefa, ou empurre uma para a leva seguinte. **Nunca** dê o mesmo arquivo a dois agentes. Cheque especialmente se uma tarefa de `coder-services` depende de uma API de `coder-runtime` que ainda não existe — nesse caso não vão para a mesma leva.

## 3. Disparar a leva inteira de uma vez

Todas as chamadas de Agent na **mesma mensagem**, com `run_in_background: true`.

Prompt de cada coder precisa carregar:

1. `id` e `title` da tarefa.
2. `description` completa, com o contrato com o território vizinho.
3. **Território permitido**, explícito, e a proibição de sair dele.
4. `acceptance` — o critério de pronto.
5. Arquivos/API já existentes que ele precisa ler antes (inclusive versão do API Dump em uso, se for tarefa de `services`).
6. Formato do relatório (está no arquivo do agente).

Marque as tarefas como `in-progress` no board.

Dispare `pesquisador` junto, em paralelo, se alguma tarefa depende de formato/API externa não confirmada (Lune, API Dump, Rojo, Rokit).

## 4. Revisar ao fim da leva

Quando os coders da leva voltarem, dispare **todos os revisores da leva na mesma mensagem** — são read-only, nunca conflitam:

| Território tocado | Revisor |
|---|---|
| `src/runtime/` | `revisor-runtime` |
| `src/services/` | `revisor-services` |
| `src/cli/` | `revisor-cli` |

Mova as tarefas para `review`.

## 5. Fechar a leva

- Achado **GRAVE** ou **ALTO** → despache correção de volta ao coder do território, na mesma mensagem se houver mais de um.
- Só **MÉDIO**/**BAIXO** → mova para `done` e registre os achados na `description` para depois.
- Atualize `updatedAt` no board.

## 6. Reportar

```
## Leva N concluída

**Implementado:** task-id — o que ficou pronto (uma linha cada)
**Revisão:** X achados — N graves, M altos
**Corrigido:** o que voltou e foi resolvido
**Pendente:** o que ficou registrado no board

Próxima leva: N+1 (K tarefas) — `/implementar`
```

Consolide. Não repasse relatório bruto de agente.

## Regras

- Agente disparado sozinho quando dois poderiam rodar juntos é tempo desperdiçado.
- Nunca invente resultado de agente pendente. Se o usuário perguntar antes da notificação chegar, diga que ainda está rodando.
- Resultado de agente não é verdade automática — se contradiz o que você sabe do código, verifique antes de repassar.
- Não commite nada. Commit é `github`, e só quando o usuário pedir.
