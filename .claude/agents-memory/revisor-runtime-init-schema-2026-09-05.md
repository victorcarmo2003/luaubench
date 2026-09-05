# Revisão — task-runtime-022 (src/runtime/init.luau + init.spec.luau)

Data: 2026-09-05. Revisor: revisor-runtime (read-only). Escopo tocado nesta tarefa, confirmado por
`git status`/`git diff --stat`: só `.claude/tasks.json` (coluna + `result`), `src/runtime/init.luau`,
`src/runtime/init.spec.luau`. Nenhum outro arquivo do território mudou.

Nada foi aceito de relato sem reprodução própria — todos os 5 pontos pedidos foram checados rodando
o binário Lune/luau-lsp de sempre nesta sessão.

## 1. Os 4 tipos ficam acessíveis via `require("../runtime")` — CONFIRMADO em diretório-irmão próprio

Criei `D:\...\luaubench-revisor-init-022-tmp\{runtime,services}` (cópia de `src/runtime` +
`.luaurc`/`rokit.toml`), e um arquivo de nome NORMAL `services/probe.luau` (não começando com
"init") que faz `require("../runtime")`, usa `MemberKind`/`MemberDescriptor`/`ClassSchema` em
anotação de tipo real (declara um `ClassSchema`, registra uma classe com `Schema`, chama
`ClassRegistry.new`, confirma `Default` de `Property` semeado) e estreita o `unknown` de
`GetPropertyRaw` para `Runtime.FireableSignal<string>` sem cast cego, disparando o evento de
ponta a ponta.

- `lune run services/probe.luau` → roda, imprime `PROBE_OK`, `Fire`/`Connect` do `FireableSignal`
  estreitado funcionam de verdade.
- `luau-lsp analyze --platform=standard services/probe.luau` → **exit 0, limpo** (depois de corrigir
  um erro no MEU probe, não no código: acesso estático `instance.Foo` falha porque `Instance` é
  opaco por design — troquei para `GetPropertyRaw`, mesmo padrão que o próprio código usa).

Diretório de verificação removido ao final (`rm -rf`), nada ficou fora do repo.

## 2. `SetClassSchema` não vaza por nenhum caminho — CONFIRMADO estático + dinâmico

- `grep -rn SetClassSchema src/runtime` → só aparece em `Instance.luau` (definição), chamada única
  em `ClassRegistry.luau:272`, testes em `Instance.spec.luau`/`ClassRegistry.spec.luau`, e comentários
  em `init.luau`/`init.spec.luau` explicando por que NÃO é reexportada. Nenhum outro módulo
  redeclara ou repassa a função.
- No probe do item 1, `(Runtime.Instance :: unknown) :: {[string]: unknown}` indexado por
  `"SetClassSchema"` devolve `nil` — confirmado em runtime real, fora do repositório, não só lendo
  `init.luau`.
- `init.spec.luau` (comitado) tem teste dedicado que verifica o mesmo para
  `NewBase`/`SetClassChain`/`SetClassMethods`/`SetClassSchema`/`ThreadBroker` — 5/5 passou.

## 3. `init.spec.luau` — os 3 testes originais continuam intactos, por diff (não só "ainda passa")

`git diff -- src/runtime/init.spec.luau` tem **zero linhas removidas** (`grep -E "^-" | grep -v
"^---"` não retornou nada) — o patch é estritamente aditivo: type aliases novos, segunda classe de
teste, e 2 testes novos anexados ao final. Os 3 testes originais (registro+DataModel+hierarquia,
Sandbox.Run com WaitForChild/task.wait real, erro proposital não derruba o processo) não têm um
único byte alterado.

`init.luau`: diff tem linhas removidas, mas só dentro do comentário de cabeçalho (reescrita de
"duas correções" → "três correções" e do comentário acima do dicionário `Instance`) — nenhuma linha
de código executável foi removida, só acrescida (`FireableSignal`, `MemberKind`, `MemberDescriptor`,
`ClassSchema` como novos `export type`; nada saiu da tabela `Runtime` além do comentário atualizado).

## 4. Regressão nos 7 arquivos não tocados — CONFIRMADO rodando cada um

| Arquivo | Resultado |
|---|---|
| Signal.spec.luau | 7/7 |
| Instance.spec.luau | 57/57 |
| Scheduler.spec.luau | 16/16 |
| ClassRegistry.spec.luau | 24/24 |
| DataModel.spec.luau | 9/9 |
| Sandbox.spec.luau | 7/7 |
| Integration.spec.luau | 9/9 |
| **init.spec.luau** | **5/5** |

Nenhum desses 7 arquivos aparece no diff (`git status` só lista os 3 arquivos esperados) —
regressão intacta por construção, números conferidos rodando `lune run` de verdade (não recontados
do relato do coder; os números são maiores que os do relatório de task-runtime-007 porque tarefas
posteriores da mesma leva de runtime já tinham crescido a suíte antes desta tarefa — consistente
com o board).

Zero ocorrências de `: any`/uso de `any` em `init.luau`/`init.spec.luau` (a única ocorrência da
palavra é dentro de um comentário em prosa dizendo "nunca `any`"). `--!strict` na primeira linha
dos dois arquivos.

## 5. Bug de tooling do `luau-lsp` em `init*` — não regrediu, mesma natureza

- `luau-lsp analyze --platform=standard src/runtime/init.luau` (análise direta do agregador) →
  **exit 0, limpo**, igual a antes.
- `luau-lsp analyze --platform=standard src/runtime/init.spec.luau` → mesma cascata de sempre:
  `Unknown require` na linha do `require("./")` seguido de `Unknown type 'Runtime.X'` para TODOS os
  tipos reexportados — agora incluindo, como esperado, os 4 novos (`Runtime.MemberKind`,
  `Runtime.MemberDescriptor`, `Runtime.ClassSchema`, `Runtime.FireableSignal`), porque são
  consequência em cascata da mesma causa raiz (nome de arquivo começando com "init"), não erros
  novos e independentes.
- Controle: copiei `init.spec.luau` para `control_probe_022.spec.luau` (nome normal, mesmo
  conteúdo) dentro do próprio `src/runtime/` e rodei `luau-lsp analyze` nele (removido depois, não
  ficou no working tree). O falso-positivo de "Unknown require"/"Unknown type" desaparece (confirma
  que o gatilho continua sendo o nome do arquivo, não o conteúdo novo desta tarefa), mas revela o
  MESMO segundo bug mascarado já registrado na revisão de task-runtime-007 (mismatch de generics em
  `Defer` via auto-`require("./")`) — erro idêntico, incluindo a mensagem exata sobre
  `<A...>(Scheduler, (A...) -> (), A...) -> thread` vs. `(Scheduler, (a...) -> (), a...) -> thread`.
  Nenhuma mudança de natureza, nenhum bug novo introduzido por esta tarefa.

## Achados

Nenhum. Não é elogio — é o resultado de tentar ativamente achar problema nos 5 pontos pedidos
(inclusive reproduzindo em ambiente isolado, não só lendo o diff) e não encontrar divergência do
que o coder relatou nem do que o board exige.

## Veredito

```
## Veredito
APROVADO
```

Os 4 tipos (`MemberKind`, `MemberDescriptor`, `ClassSchema`, `FireableSignal<T...>`) ficam
acessíveis via `require("../runtime")` de um consumidor real fora do território, comprovado com
`lune run` E `luau-lsp analyze` limpo (não só leitura de código). `SetClassSchema` confirmadamente
não vaza por nenhum caminho, estático (grep exaustivo) e dinâmico (probe + teste comitado). Os 3
testes originais de `init.spec.luau` estão byte-a-byte intactos (diff sem remoções). Regressão dos
7 módulos + `init.spec.luau` = 5/5. O bug de tooling do `luau-lsp` em arquivos `init*` não regrediu
nem mudou de natureza — mesma causa raiz, cascata esperada incluindo os 4 tipos novos, segundo bug
mascarado idêntico ao já documentado.

**`task-services-001` fica desbloqueada.**
