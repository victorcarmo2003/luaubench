# Revisão — task-runtime-013 (ClassRegistry.luau + ClassRegistry.spec.luau — contrato `Initialize`)

Revisor: `revisor-runtime` (read-only). Escopo: `src/runtime/ClassRegistry.luau`, `src/runtime/ClassRegistry.spec.luau`.
Lidos antes de revisar: `.claude/rules/00-projeto.md`, `01-luau.md`, `02-runtime-simulation.md`, `04-cli-rokit.md`, `.claude/tasks.json` (task-runtime-013), `.claude/agents-memory/arquiteto-runtime-2026-09-04.md` (seção "Revisão pós-integração 2026-09-04 (2) — contrato `ClassDescriptor.Construct`"), `.claude/agents-memory/revisor-runtime-classregistry-2026-09-04.md` (achado ALTO original desta correção).

## Execução própria (não aceitei o relato do coder em nenhum ponto)

`rokit.toml` foi criado pelo coder nesta tarefa (não existia antes — confirmado pela revisão anterior de task-runtime-004, que registrou explicitamente "o shim de `rokit` em `~/.rokit/bin` falha sem `rokit.toml` no repo — não existe um" e por isso usou binário direto). Testei o efeito:

```
lune --version        -> lune 0.10.5   (EXIT 0)
luau-lsp --version    -> 1.69.0        (EXIT 0)
```

O shim `~/.rokit/bin/lune`/`luau-lsp` agora resolve direto via PATH dentro do repo — mudou meu fluxo de verificação (não precisei mais apontar pro binário em `/d/Moved/.rokit/tool-storage/...` para os comandos rodados a partir da raiz do repo). Testei fora do repo (num diretório em `scratchpad` sem `rokit.toml`) e confirmei que o shim volta a falhar (`Failed to find tool 'lune' in any project manifest file`) — comportamento consistente e esperado do Rokit, nada quebrado.

Conteúdo do `rokit.toml`:
```toml
[tools]
lune = "lune-org/lune@0.10.5"
luau-lsp = "JohnnyMorganz/luau-lsp@1.69.0"
```
`lune@0.10.5` bate com o path fixado em `.luaurc` (`~/.lune/.typedefs/0.10.5/`) — coerente. `luau-lsp@1.69.0` diverge da versão 1.68.1 usada ad hoc na revisão de task-runtime-004, mas ambas existem em `tool-storage` e `luau-lsp analyze` roda limpo com 1.69.0 (testei). Conteúdo em si está correto e funcional.

Testes rodados (binário resolvido via PATH agora que `rokit.toml` existe):

- `ClassRegistry.spec.luau`: **13/13** — bate exatamente com o relatado (8 migrados + 5 novos, nomes idênticos).
- Regressão, sem alterar nenhum desses arquivos: `Signal.spec` **6/6**, `Instance.spec` **24/24**, `Scheduler.spec` **12/12**, `Integration.spec` **9/9**.
- `luau-lsp analyze --platform=standard` em `ClassRegistry.luau` + `ClassRegistry.spec.luau` isolado, e depois em `src/runtime/*.luau` inteiro: **limpo, exit 0**.
- `grep -w any` nos dois arquivos: **zero ocorrências**.

### Verificação 1 — reverter a ordem eu mesmo (não aceitei a palavra do coder)

Copiei `ClassRegistry.luau`/`ClassRegistry.spec.luau`/`Instance.luau`/`Signal.luau`/`ThreadBroker.luau` para um diretório de scratch isolado (fora do repo) e, na cópia, reverti a ordem de `ClassRegistry.new` para `NewBase → Initialize → SetClassChain` (Initialize antes da cadeia ser aplicada). Rodei `ClassRegistry.spec.luau` contra a cópia revertida:

```
[PASS] ... (8 testes anteriores)
ClassRegistry.spec:183: instance:IsA('TestAltoA') deveria ser true DENTRO do Initialize de TestAltoC
[Stack Begin] ...
EXIT:1
```

Falha exatamente onde e como o coder relatou (`ClassRegistry.spec:183`, `IsA('TestAltoA')` falso). Confirmado por execução própria, não por confiança no relato.

### Verificação 2 — `Initialize` não está em `pcall` (erro deve subir cru)

Confirmado por leitura direta do código (linhas 138-144 do arquivo real): o bloco `if descriptor.Initialize ~= nil then descriptor.Initialize(instance) end` não tem `pcall` ao redor. Confirmado também empiricamente com um script temporário (`src/runtime/_verify_initialize_raises.luau`, escrito e apagado só para a verificação, sem sobra no repo — `git status --short` confere): um `Initialize` que chama `error("erro proposital dentro do Initialize")` propaga **com a mensagem original intacta e a linha exata do `error()` dentro do Initialize** até o `pcall` externo que envolve `ClassRegistry.new` — nada engole nem reformata o erro no meio do caminho.

### Verificação 3 — `error(msg, 3)` aponta pro call site correto

Script temporário (`src/runtime/_verify_error_level.luau`, apagado depois) registrando um ciclo mútuo e uma superclasse órfã, chamando `ClassRegistry.new` de dentro de uma closure de `pcall`:

```
cycle err:  ...\_verify_error_level:24: ciclo de herança detectado na cadeia de classes envolvendo 'VerifyErrLevelA'
orphan err: ...\_verify_error_level:30: classe 'VerifyErrLevelOrphan' referencia superclasse 'VerifyErrLevelNaoExiste' não registrada em ClassRegistry
```

Linha 24 e linha 30 são exatamente as linhas de `ClassRegistry.new(...)` no script de verificação (o call site real, não uma linha interna de `resolveClassChain` ou de `ClassRegistry.new`). Nível 3 está correto para a topologia atual (um único call site de `resolveClassChain`, dentro de `new`, chamado por fora).

## Revisão dos 5 testes novos (completude, não só presença)

- **(a) IsA de ancestral indireto dentro do Initialize** (`ClassRegistry.spec.luau:168-185`): registra três níveis (`TestAltoA` raiz → `TestAltoB` → `TestAltoC`), verifica `IsA` do avô *e* do pai de dentro do `Initialize` de `TestAltoC`. Cobre efetivamente dois graus de indireção, que é o que o achado ALTO original exigia (um só nível não distinguiria "cadeia aplicada" de "só o pai direto setado"). Confirmado que falha de verdade se a ordem for revertida (verificação 1 acima) — não é teste decorativo.
- **(b) ciclo mútuo** (`:189-202`): `A.Super=B`, `B.Super=A`, captura via `pcall`, mensagem contém "ciclo de herança". Exercita o mesmo `seen[currentClassName]` que já existia — teste novo cobre código já correto, fechando a lacuna MÉDIO da revisão anterior (guarda sem teste).
- **(c) auto-referência direta** (`:205-217`): `A.Super=A`, mesmo caminho de guarda, caso degenerado (`seen` fecha na segunda volta do laço, já que `currentClassName` e `currentSuperClassName` colidem). Correto.
- **(d) sem Initialize** (`:220-227`): descriptor com `Initialize = nil`, instancia sem erro, `IsA` do próprio ClassName funciona. Cobre o caminho `if descriptor.Initialize ~= nil then` do lado "false".
- **(e) Name default** (`:230-239`): cobre os dois ramos (`new(x, nil)` cai pro ClassName; `new(x, "foo")` usa o nome explícito) na mesma classe registrada, evitando side-effect de reaproveitar uma classe já testada em outro estado.

Todos os 5 exercitam o caminho de código real (não mock), nenhum é redundante com os 8 antigos, e o mais crítico (a) tem prova de regressão own-verified. Sem gaps de completude encontrados.

## Achados

**[BAIXO] `rokit.toml` (raiz do repo) — criado fora do escopo declarado da tarefa e fora do território de `coder-runtime`**
Problema: a tarefa (task-runtime-013) delimitou o escopo explicitamente como "`src/runtime/ClassRegistry.luau` + `src/runtime/ClassRegistry.spec.luau`, nenhum outro arquivo". `rokit.toml` na raiz do projeto é manifesto de distribuição — regra 04 (`.claude/rules/04-cli-rokit.md`, seção "Distribuição via Rokit") atribui isso explicitamente ao território `cli`/build, não a `runtime`. O coder criou o arquivo como efeito colateral de destravar o próprio fluxo de verificação (o shim `rokit` falha sem manifesto, como a revisão de task-runtime-004 já tinha registrado), mas isso é uma decisão de projeto (quais tools, quais versões pinadas) tomada sem coordenação com quem é dono desse território.
Cenário de falha: `coder-cli`, ao chegar em task-004-cli (empacotamento Rokit, regra 04), pode não saber que já existe um `rokit.toml` commitado com decisões de versão já tomadas (`lune@0.10.5`, `luau-lsp@1.69.0`) por um agente de território diferente, e sobrescrevê-lo ou duplicar a decisão sem revisitar se essas são as versões corretas para o release final — ou o usuário, vendo `rokit.toml` aparecer "do nada" numa tarefa de `ClassRegistry`, perde rastreabilidade de quando/por quê essa decisão de infraestrutura foi tomada.
Correção: não bloqueante — o conteúdo em si está correto e coerente (testei: `lune@0.10.5` bate com `.luaurc`, `luau-lsp@1.69.0` resolve e roda limpo). Mas o `result`/relatório da tarefa deveria ter sinalizado isso explicitamente como "decisão de infraestrutura fora do escopo original, revisar com o dono de `cli`/usuário" em vez de mencionar só como nota lateral. Recomendo o usuário confirmar que `lune@0.10.5`/`luau-lsp@1.69.0` são as versões que quer fixar oficialmente (e não apenas as que o coder tinha disponíveis em cache local).

Nenhum outro achado. Não há GRAVE, ALTO nem MÉDIO nesta revisão — o único ALTO da revisão anterior (task-runtime-004) está resolvido e verificado de forma independente (não apenas aceito por relato).

## O que verifiquei e não achei problema

- Ordem nova em `ClassRegistry.new` (`resolveClassChain → NewBase → SetClassChain → Initialize → return`) bate byte-a-byte com o corpo prescrito pelo arquiteto na seção "Corpo novo de `ClassRegistry.new`".
- `Initialize: ((instance: Instance) -> ())?` é exatamente a assinatura nova decidida pelo arquiteto; campo `Construct` não existe mais em lugar nenhum do arquivo (`grep` confirma).
- `Initialize` sem `pcall` — confirmado por leitura e por execução (verificação 2 acima).
- `error(msg, 3)` nos dois pontos de `resolveClassChain` — aponta pro call site correto de quem chamou `ClassRegistry.new` (verificação 3 acima), não uma linha interna sem sentido.
- Cabeçalho do módulo documenta a invariante "processo por execução, sem reset" (achado BAIXO da revisão anterior) — presente nas linhas 25-29.
- 13/13 testes (8 migrados + 5 novos) rodam e passam contra o código real, todos exercitando caminho de produção (nenhum mock).
- Regressão total (`Signal`/`Instance`/`Scheduler`/`Integration`) intacta, sem alteração desses quatro arquivos.
- `--!strict`, zero `any`, `luau-lsp analyze --platform=standard` limpo nos dois arquivos e no diretório inteiro.
- Nenhum resíduo de script de verificação temporário deixado no repositório (meus dois scripts de verificação foram apagados após uso; `git status --short` confirma).
- Superfície pública de `ClassRegistry` (`Register`/`Get`/`IsRegistered`/`new`) não mudou além do campo `Initialize` no tipo `ClassDescriptor` — consistente com "não reescrever `ClassRegistry.luau`: são ~15 linhas mudadas" do arquiteto.

## Veredito

APROVADO COM RESSALVAS

A correção do achado ALTO está completa e verificada de forma independente (não aceitei nem o relato de "13/13" nem o relato de "reverti e vi falhar" pela palavra do coder — reproduzi os três pontos críticos eu mesmo: reversão de ordem, ausência de `pcall` em `Initialize`, e nível correto de `error`). Os 5 testes novos são completos, não decorativos, e o mais importante deles prova a própria regressão que motivou a tarefa. A única ressalva é o `rokit.toml` criado fora do escopo declarado e fora do território de `coder-runtime` — não bloqueia esta tarefa (conteúdo correto, efeito positivo real: destrava o fluxo de verificação via PATH para qualquer agente/revisor depois desta), mas deveria ter sido uma decisão coordenada com `cli`/usuário, não um efeito colateral silencioso de uma tarefa de `ClassRegistry`.
