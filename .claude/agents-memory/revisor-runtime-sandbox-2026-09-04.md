# Revisão de segurança — Sandbox.luau (task-runtime-006)

Revisão executada rodando o binário Lune real (`C:\Users\hakor\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe`) e `luau-lsp` (`1.68.1`), não apenas lendo o código. Testes adversariais próprios (4 rounds de scripts-sonda) escritos temporariamente em `src/runtime/_revisor_escape_probe*.luau`, executados, e **removidos ao final** (revisor é read-only — nenhum arquivo da tarefa foi editado; os probes eram arquivos novos e descartáveis, já apagados).

## O que foi verificado e passou

- `Sandbox.spec.luau`: 7/7 rodando de verdade via `lune run` (não confiei no relato do coder).
- Regressão completa: `Signal.spec` 6/6, `Instance.spec` 24/24, `Scheduler.spec` 12/12, `Integration.spec` 9/9, `ClassRegistry.spec` 8/8 — todos rodados por mim.
- `luau-lsp analyze --platform=standard` limpo em `Sandbox.luau`, `Sandbox.spec.luau` e em todo `src/runtime/*.luau`.
- **Isolamento de `fs`/`net`/`process`/`serde`/`io`/`require`: confirmado, nenhuma forma de escape encontrada.** Tentei ativamente:
  - Indexação direta (`typeof(fs)` etc.) → `nil`, idêntico a indexar chave ausente de tabela comum (já coberto pelo teste do coder, reconfirmei).
  - `getmetatable`/`setmetatable`/`rawget`/`rawset`/`rawequal`/`rawlen` sobre os globals expostos (`math`, `table`, `string`, `os`, `coroutine`) — **nenhuma dessas funções existe no ambiente do script** (todas `nil`), então nem o vetor de ataque existe.
  - `debug.getupvalue`/`debug.getinfo` — `debug` inteiro é `nil` no ambiente do script.
  - `_G`, `_ENV`, `getfenv`, `setfenv` — todos `nil`/inexistentes (confirma a pesquisa salva: Luau não registra `getfenv`/`setfenv` como globals de qualquer forma).
  - Mutação das bibliotecas compartilhadas (`math.floor = ...`, `table.myKey = 1`, `coroutine.wrap = ...`, `string.myKey = 1`) — todas bloqueadas com `"attempt to modify a readonly table"`. Confirma que o `lua.sandbox(true)` que o próprio Lune chama no boot (documentado na pesquisa) já congela essas tabelas compartilhadas antes de qualquer `luau.load`; um script não corrompe o ambiente de outro script nem do CLI através delas.
  - Sem `setmetatable` no ambiente e sem `setmetatable` chamado pelo próprio `Sandbox.luau` sobre a tabela `environment` (confirmado lendo o código: nunca há um `setmetatable(environment, ...)`) → sem `__index` residual apontando pra tabela global real do Lune.
- **Erro nunca derruba o processo — três casos confirmados rodando eu mesmo:**
  1. Erro síncrono (`error("deu ruim")`) → `OutputRecord{level="error"}`, processo segue.
  2. Erro de compilação (`source` com sintaxe inválida) → mesmo mecanismo, mesmo resultado.
  3. Erro dentro de `task.spawn` interno ao script → capturado, `scriptName` correto mesmo vindo de thread aninhada.
- `print`/`warn` chegam só via `onOutput`; confirmei que não há nenhuma linha crua extra no stdout do processo em nenhum dos meus 4 rounds de sonda (só as linhas que eu mesmo imprimi para depuração).
- `:: any` (Sandbox.luau:270) — grep confirma que é a **única** ocorrência de `any` no arquivo, confinada à variável local `loadOptions` (nunca exportada), na fronteira exata com `LoadOptions.environment` do stub do Lune. Não vaza para `SandboxOptions`/`SandboxGlobals`/`OutputRecord`/`SandboxResult` (todos usam só `unknown`).
- `coroutine` cru exposto no ambiente do script (Sandbox.luau:216) é decisão do desenho congelado (arquiteto, "Globals expostos por padrão"), não do coder — testei `coroutine.yield()` cru sem passar por `task.wait`: a thread fica suspensa para sempre (ninguém tem `WakeAfter` registrado pra ela), mas **não trava o processo** — o script simplesmente nunca mais roda, igual ao comportamento real do Roblox nesse mesmo cenário. Overlap conhecido com task-runtime-011 (Cancel não limpa listeners/threads penduradas), não é achado novo.

## Achados

```
[ALTO] Sandbox.luau:212-249 (buildEnvironment)
Problema: whitelist fixa de globals omite setmetatable/getmetatable/rawget/rawset/rawequal/rawlen/type/collectgarbage — todos presentes no Roblox real — sem nenhum comentário no código admitindo a divergência.
Cenário de falha: qualquer módulo Roblox real que usa o idioma de OOP mais comum em Luau (`local Class = {}; Class.__index = Class; function Class.new() return setmetatable({}, Class) end` — literalmente o padrão que ProfileStore e a esmagadora maioria de state managers/data managers usam, exatamente os casos de uso citados no CLAUDE.md do projeto) falha na primeira linha com "attempt to call a nil value (global 'setmetatable')". O sandbox não consegue rodar a classe de código que o LuauBench existe para rodar.
Correção: confirmei via probe que setmetatable/getmetatable/rawget/rawset/rawequal/rawlen são seguros de expor (as tabelas compartilhadas já são readonly por conta do sandbox nativo do Lune, então nada disso abre uma via de mutação cross-script) — adicionar ao whitelist de Sandbox.luau E ao trecho "Globals expostos por padrão" do desenho congelado em arquiteto-runtime-2026-09-04.md (é uma decisão de contrato, não algo que coder-runtime deveria decidir sozinho sem atualizar o desenho — mesmo padrão do achado ALTO de task-runtime-004). Regra 00 exige que a omissão, se for deliberada, fique documentada — hoje não está em lugar nenhum.

[MÉDIO] Sandbox.luau:189-207 (splitErrorMessage)
Problema: mensagem de erro MULTI-LINHA escrita pelo próprio usuário (não a stack traceback do VM) é truncada na primeira quebra de linha, perdendo conteúdo que o script explicitamente quis reportar.
Cenário de falha: `error("Erro principal:\nDetalhe extra que o usuario queria mostrar")` → `OutputRecord.message` chega como só `"Erro principal:"`, a segunda linha desaparece silenciosamente (confirmado rodando). O comentário do código já documenta a perda da stack traceback do VM como aceitável, mas não menciona que a MESMA lógica (corte no primeiro "\n" de `raw`) também apaga conteúdo do próprio usuário que porventura venha antes da traceback.
Correção: cortar especificamente no marcador literal "\nstack traceback:\n" (com plain=true, igual já se faz para o marcador de scriptName) em vez de no primeiro "\n" de toda a string — preserva quebras de linha que pertencem à mensagem do usuário.

[MÉDIO] Sandbox.luau:278-290 (Sandbox.Run — options.scheduler.ThreadError:Connect)
Problema: a Connection criada aqui nunca é desconectada — confirmado lendo o código (nenhum Disconnect em lugar nenhum de Sandbox.luau). Já auto-reportado pelo coder no campo `result` da task como pendência não-bloqueante; confirmo que é real.
Cenário de falha: `cli` roda N Scripts do mesmo projeto contra o mesmo Scheduler (um Sandbox.Run por Script, design documentado) — cada chamada deixa um listener permanente vivo pelo resto do processo. Em watch mode de longa duração com muitos Scripts, isso cresce sem limite (vazamento de listeners, não de correção — cada erro futuro de qualquer script paga uma checagem extra de `ownThreads` por listener morto-mas-vivo).
Correção: guardar a Connection devolvida por `:Connect` e expor uma forma de desconectá-la (ex: SandboxResult ganhar um campo opcional de teardown, ou Sandbox.Run desconectar sozinho quando a thread do script morrer via um segundo listener interno). Já rastreado como pendência conhecida — não bloqueia esta tarefa, mas confirmo que é um achado real, não hipotético.

[MÉDIO] Sandbox.spec.luau (cobertura de teste)
Problema: nenhum dos 7 testes exercita os caminhos de degradação de splitErrorMessage que o comentário do código promete (valor de erro não-string, error(msg, 0), mensagem multi-linha) — só o caminho feliz (error("string") de uma linha só, batendo o padrão esperado).
Cenário de falha: uma futura mudança em splitErrorMessage que faça o fallback lançar erro em vez de degradar (quebrando a garantia "nunca falha, só degrada" que o próprio comentário do módulo promete) passaria pelos 7 testes atuais sem detecção.
Correção: adicionar pelo menos 2 testes: error() com valor não-string, e error(msg, 0) sem o marcador — confirmando level=nil e que não lança.

[BAIXO] Sandbox.luau:189-207 (splitErrorMessage) — falsificação do próprio line
Problema: error(msg, 0) desliga o prefixo de posição automático do VM; se o texto do usuário por acaso contém algo que bate o padrão `[string "scriptName"]:N: `, isso é interpretado como se fosse a localização real.
Cenário de falha: `error('[string "MeuScript"]:12345: mensagem forjada', 0)` dentro do próprio script "MeuScript" → OutputRecord.line chega como 12345 (forjado pelo próprio script, sem relação com a linha real do erro). Impacto baixo: um script só pode forjar isso para si mesmo (scriptName do OutputRecord nunca vem do parsing, sempre de options.scriptName — confirmei que não há vazamento cross-script), então não há escalonamento nem falsificação de identidade de outro script.
Correção: opcional — documentar a limitação no comentário de splitErrorMessage (hoje ele documenta o caso "marcador não encontrado" mas não este).

[BAIXO] Sandbox.luau:189-207 (splitErrorMessage) — prefixo de categoria vaza no fallback
Problema: quando o marcador de scriptName não é encontrado (fallback), o rótulo de categoria do Lune ("runtime error: "/"syntax error: ") permanece dentro de `message` (só é removido quando o marcador É encontrado, porque nesse caso `rest` já começa depois do marcador).
Cenário de falha: error({tabela}) → message final é `"runtime error: table: 0x..."` em vez de só `"table: 0x..."` — ruído cosmético de implementação vazando pro output voltado ao usuário.
Correção: opcional, cosmético — stripar os rótulos de categoria conhecidos ("runtime error: ", "syntax error: ") do início de `firstLine` antes de procurar o marcador, mesmo no caminho de fallback.
```

## Itens já auto-reportados pelo coder, confirmados sem novidade

- `OutputRecord` de print/warn nunca tem `line` (precisaria de `debug`, fora da whitelist) — confirmado, trade-off aceitável e documentado no código.
- `OutputRecord` de erro nunca carrega a stack traceback completa — confirmado, documentado no código, aceitável (não há campo pra isso no tipo público).

## Veredito

[APROVADO COM RESSALVAS]

A garantia de segurança que motivou a prioridade máxima desta tarefa **se sustentou sob teste adversarial ativo**: nenhuma forma de alcançar `fs`/`net`/`process`/`serde`/`io`/`require` cru, nenhuma forma de crashar o processo (síncrono, task.spawn interno, erro de compilação), print/warn/error corretamente roteados, `:: any` genuinamente confinado à fronteira do stub do Lune. Nenhum achado GRAVE.

A ressalva que mais importa é o ALTO: a whitelist de globals, do jeito que está (mesma tanto no código quanto no desenho congelado do arquiteto), impede rodar o padrão de OOP mais comum do ecossistema Roblox por faltar `setmetatable`/`getmetatable`/`rawget`/`rawset`/`rawequal`/`rawlen`/`type`. Isso não é uma falha de segurança, mas ameaça a utilidade prática do LuauBench para o caso de uso citado no próprio CLAUDE.md (rodar ProfileStore/data managers/state managers fora do Studio) — recomendo voltar ao arquiteto para decidir a extensão do contrato antes de fechar a tarefa, mesmo que a tarefa em si não bloqueie por isso.
