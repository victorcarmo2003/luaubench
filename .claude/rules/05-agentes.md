# Regra 05 — Orquestração e paralelismo

Vale para a **thread principal**. O objetivo é manter o chat principal livre e o paralelismo alto.

## Princípio

A thread principal **orquestra, não implementa**. Entende o pedido, escolhe os agentes, dispara em paralelo, consolida os relatórios, responde ao usuário.

Execute inline apenas: mudança trivial de uma linha, leitura pontual para decidir a quem delegar, resposta a pergunta que você já sabe responder.

## Disparo

- **Múltiplas chamadas de Agent na mesma mensagem.** Agente disparado sozinho quando dois poderiam rodar juntos é tempo desperdiçado.
- **`run_in_background: true` por padrão.** Só use `false` quando o próximo passo depende literalmente daquele resultado e nada mais pode avançar enquanto isso.
- Antes de disparar, verifique se já existe agente rodando ou recém-concluído sobre o mesmo assunto — continue por `SendMessage` em vez de gastar um spawn frio.
- Nunca invente ou antecipe resultado de agente pendente. Se o usuário perguntar antes da notificação chegar, diga que ainda está rodando.

## Territórios (garantia de não-conflito)

Estes agentes de escrita **nunca** podem receber o mesmo território na mesma leva:

| Agente | Território exclusivo |
|---|---|
| `coder-runtime` | `src/runtime/` — DataModel, base de Instance, scheduler |
| `coder-services` | `src/services/` — Services simulados a partir do API Dump |
| `coder-cli` | `src/cli/` — comando `luaubench run`, integração Rojo, Rokit |
| `coder-valuetypes` | `src/valuetypes/` (+ `tools/generate-enums.luau`) — Value Types simulados |
| `testador` | `tests/scenarios/` — cenários práticos de uso |
| `github` | git, nada de código |

Revisores (`revisor-runtime`, `revisor-services`, `revisor-cli`, `revisor-valuetypes`), `pesquisador`, `debugger` e `testador` são read-only fora do próprio território — dispare quantos quiser, sempre em paralelo, inclusive junto com coders. `testador` também lê (nunca escreve) `C:\Users\hakor\Documents\Roblox-Games`, fora do repositório.

Se uma tarefa cruza territórios (ex: mudar a API pública que `runtime` expõe para `services`): **quebre em duas tarefas** com o contrato definido entre elas, ou chame o `arquiteto` primeiro para redesenhar a fronteira. Nunca dê o mesmo arquivo a dois agentes.

## Sequências que precisam ser série

- `arquiteto` → `planejador`: o planejador precisa do desenho pronto.
- `coder-runtime` → `coder-services`: `services` depende da API pública que `runtime` expõe. Se a tarefa de `services` precisa de algo que `runtime` ainda não tem, isso é dependência explícita (`depends`) no board, não paralelo.
- coder → revisor **do mesmo território**: revisar código que ainda não existe não serve.
- `planejador` → coders: as tarefas precisam existir no board antes do despacho.

Todo o resto é paralelo — em especial, `coder-cli` normalmente roda em paralelo com `coder-runtime`/`coder-services` sempre que a tarefa de CLI não depende de uma API nova que ainda não existe (ex: melhorar parsing do `.project.json` não depende de nada em `services`).

## Briefing de agente

Agente começa frio. O prompt precisa carregar:

1. **Objetivo** em uma frase.
2. **Território** — quais caminhos ele pode tocar, e explicitamente que não pode sair deles.
3. **Contexto necessário** — arquivos relevantes, decisões já tomadas, contrato com o território vizinho, versão do API Dump em uso.
4. **Critério de pronto** — como saber que terminou.
5. **Formato do relatório** — o que devolver.

Agente mal instruído volta com trabalho errado e custa mais que fazer inline.

## Relatório

- Agente devolve para você um **resumo curto**. Relatório longo vai para `.claude/agents-memory/{agente}-{assunto}-{AAAA-MM-DD}.md` e o agente entrega só o caminho.
- Você consolida e responde ao usuário **uma vez**. Nada de repassar relatório bruto de agente.
- Resultado de agente não é verdade automática. Se um relatório contradiz o que você sabe do código, verifique antes de repassar.

## Board

`.claude/tasks.json` é a fonte da verdade. Toda tarefa tem campo `agent` — é o que permite despachar várias em paralelo sem colisão.

- Antes de despachar, leia o board.
- Ao concluir, o estado da tarefa é atualizado (`todo` → `in-progress` → `done`).
- Preserve IDs existentes. IDs novos no formato `task-{sistema}-{numero}`.

## Modelo por agente

| Papel | Modelo | Por quê |
|---|---|---|
| `arquiteto` | opus | Decisão de design tem custo alto de erro — define o contrato entre runtime/services/cli e a fidelidade da simulação |
| coders, revisores, `debugger`, `planejador`, `pesquisador`, `testador` | sonnet | Volume e paralelismo |
| `github` | haiku | Mecânico |

`arquiteto` com moderação — não chame para tarefa que já tem desenho pronto em `.claude/agents-memory/`.
