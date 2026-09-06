# Revisão — task-services-025 (SoundService)

Data: 2026-09-06. Revisor: `revisor-services`. Read-only, nada rodando em `src/services/` no momento da revisão. Nada aceito por self-report — todo número abaixo foi reproduzido por mim.

## Arquivos no escopo

- `src/services/generated/classes/SoundService.luau` (novo, GERADO)
- `src/services/behavior/SoundService.luau` (novo, À MÃO — o desvio de escopo)
- `src/services/behavior/SoundService.spec.luau` (novo)
- `src/services/generated/Index.luau`, `Manifest.luau` (modificados — 1 linha cada, registro/Covered)
- `src/services/behavior/Index.luau`, `Index.spec.luau` (modificados — 18ª entrada)
- `tools/coverage.luau` (modificado — `SoundService` acrescentada)
- `tools/generate-services.spec.luau` (modificado — 44 classes/201 métodos)

`git status --porcelain=v1 -uall` confirma que **nenhum outro arquivo** foi tocado — nada em `runtime/`, `cli/`, `valuetypes/`, `src/services/init.luau` (território de `task-services-033`, concorrente). Território limpo.

## Reprodução (rodada por mim, `lune 0.10.5`)

| Suite | Resultado | Bate com o alegado? |
|---|---|---|
| `SoundService.spec.luau` | **16/16** | Sim |
| `behavior/Index.spec.luau` | **17/17** (18 entradas confirmadas no teste 1) | Sim |
| `tools/generate-services.spec.luau` | **19/19** (44 classes, 201 métodos) | Sim |
| Suíte completa `src/services/**` + `tools/**` (33 arquivos `.spec.luau`) | **zero regressão** | Sim — só `HttpService.spec.luau` falhou |
| `HttpService.spec.luau` isolado | FALHOU: watchdog de 10s em "RequestAsync contra host inexistente" (linha 625/629) | **Confirmado ambiental**, não regressão |

`HttpService.spec.luau`/`.luau` não foram tocados por esta tarefa (confirmado por `git status`/`git log -1`). O teste que falha depende de resolução DNS real contra um domínio `.invalid` (RFC 2606) só para confirmar que a tentativa falha rápido; neste ambiente a tentativa trava até o watchdog, consistente com ausência de saída de rede, não com bug introduzido por `task-services-025`.

`luau-lsp analyze --platform=standard --settings=".luaurc"` rodado nos 9 arquivos tocados/criados: **zero erro**. Todos abrem com `--!strict`; `grep -n '\bany\b'` não achou `any` fora de comentário em nenhum dos 9.

## Verificação direta contra o dump (não confiei no relatório do gerador)

Extraí eu mesmo `Classes["SoundService"]` de `.cache/api-dump/28360dea4b90b35dc3fe9f829baae64fb6c50e75.json` via script Lune ad-hoc. Resultado bate exatamente com o schema gerado:

- 17 `Property` no dump; 4 excluídas pelo filtro (`AudioApiByDefault`/`DefaultListenerLocation`: `Security.Read ≠ None`; `IsNewExpForAudioApiByDefault`: idem; `VolumetricAudio`: tag `NotScriptable`) → **13 sobrevivem**, exatamente as 13 do schema gerado.
- `CharacterSoundsUseNewApi`: `Read=None, Write=PluginSecurity` → `ReadOnly=true` pela regra de emissão (Security.Write≠None). Confirmado no schema e no teste (erra com a string padrão de propriedade somente leitura).
- `RespectFilteringEnabled`: `Default` no dump é literalmente `"false"` (li a string bruta) — o dump vence a doc oficial (regra 03), como o schema gerado e o spec afirmam.
- Métodos: só `GetListener`/`GetMixerTime`/`PlayLocalSound`/`SetListener` têm `Security = None`; todos os outros (`BeginRecording`, `GetAudioApiByDefault`, etc.) são `RobloxScriptSecurity`/`PluginSecurity` → corretamente fora de `MethodNames`. 4 métodos batem exatamente.
- Eventos: todos com `Security` não-`None` (`RobloxScriptSecurity`/`RobloxSecurity`) → 0 sobrevivem, como alegado.

Nenhuma superfície inventada. Nenhuma propriedade/evento/método fora do dump.

## O desvio de escopo — avaliado, não aceito de graça

A task original (L2.5.3) previa **nenhum** `behavior/SoundService.luau`; a `acceptance` gravada no board ainda diz literalmente "os 4 metodos erram com [LuauBench]" e "nenhum behavior/SoundService.luau foi criado". A `description` da tarefa, porém, tem um parágrafo "ATUALIZACAO" citando `task-services-028` (string verbatim confirmada para `PlayLocalSound` no servidor) e instruindo explicitamente a reabrir B.5.5 e usar a string exata em vez do stub genérico — ou seja, **a própria tarefa, na sua versão mais recente, pede o desvio**; só o campo `acceptance` (boilerplate mais antigo) ficou desatualizado.

Segui a instrução do usuário e não aceitei a alegação "não há mecanismo mais leve" de graça — li `Types.luau` e `ClassBuilder.luau` eu mesmo:

- `Types.GeneratedClass` (o que o gerador emite) não tem campo de mensagem de erro por método — confirmado por leitura direta, é só `{ClassName, Superclass, IsService, IsAbstract, Schema, MethodNames}`.
- `ClassBuilder.Build` só tem UM jeito de substituir o stub genérico de um método: uma entrada em `Types.Behavior.Methods` (passo (b) do `Build`, `src/services/ClassBuilder.luau:167-176`). Não existe parâmetro/canal alternativo.
- `RejectingSignal.luau` é estruturalmente um `Runtime.Signal<...>` (`Connect`/`Once`/`Wait`/`DisconnectAll`) — serve para **propriedade que é Signal/evento**, nunca para instalar como valor de `ClassDescriptor.Methods` (que espera função chamável, não um objeto Signal-shaped). `PlayLocalSound` é `Function` no dump, não `Event` — `RejectingSignal` não se aplica estruturalmente, não é só "não é a decisão certa", é incompatível com o formato.

**Conclusão: a justificativa é factualmente correta.** Não existe mecanismo mais leve no desenho atual para sobrescrever a mensagem de um único método sem passar por `Types.Behavior`. O arquivo criado é o menor caso possível desse mecanismo (uma entrada, sem `Initialize`, sem estado) — não é um Behavior "inteiro" na acepção que a decisão original queria evitar (sincronizar propriedades, manter estado, etc., como em `Lighting`/`WorldRoot`).

**Achado (processo, não código):**

```
[BAIXO] .claude/tasks.json:2143 (task-services-025, campo "acceptance")
Problema: o campo acceptance ainda diz "os 4 metodos erram com [LuauBench]" e "nenhum behavior/SoundService.luau foi criado", contradizendo o parágrafo "ATUALIZACAO" da própria description (que pede exatamente o oposto para PlayLocalSound).
Cenário de falha: um agente/humano que leia só o acceptance (sem a description inteira) reprovaria um trabalho correto, ou aprovaria um trabalho que ignorasse a atualização de B.5.5.
Correção: planejador atualiza o campo acceptance de task-services-025 para refletir a reabertura (PlayLocalSound com string exata; os OUTROS 3 métodos continuam [LuauBench]; behavior/SoundService.luau mínimo é esperado, não proibido).
```

Não trato isso como bloqueio: o código implementa a intenção mais recente e mais bem fundamentada (citação ao vivo, regra B.5.5), documenta a mudança extensivamente no cabeçalho do módulo e no `coverage.luau`, e os testes cobrem exatamente a distinção (3 métodos com stub genérico vs. 1 com string exata sem prefixo).

## Itens pedidos, checados

1. `game:GetService("SoundService")` devolve instância (singleton, testado) — OK.
2. 13 propriedades leem o default do dump — verificado contra o dump bruto, OK.
3. 12 propriedades escritáveis aceitam escrita; `CharacterSoundsUseNewApi` erra (ReadOnly) — testado e confirmado, string bate com a família confirmada em `task-runtime-018`.
4. `PlayLocalSound` erra com a string EXATA, sem prefixo `[LuauBench]` — testado e confirmado.
5. `GetListener`/`SetListener`/`GetMixerTime` erram com o stub genérico `[LuauBench] ... not simulated by LuauBench yet` — testado e confirmado.
6. `RespectFilteringEnabled` lê `false` — confirmado contra o dump bruto (a doc oficial diz `true`; dump vence, regra 03, registrado no código e no spec).
7. `--!strict` + zero `any` real — confirmado por grep e por `luau-lsp analyze` limpo nos 9 arquivos.
8. Território limpo — confirmado por `git status --porcelain -uall`.
9. `HttpService.spec.luau` isolado — confirmado ambiental (watchdog de rede), não regressão.

## Veredito

**APROVADO COM RESSALVAS**

Nenhum achado GRAVE ou ALTO. Um achado BAIXO, de processo (campo `acceptance` desatualizado no board, não no código) — não bloqueia, mas o planejador deveria corrigir o texto do board para não gerar falso-positivo em auditorias futuras.
