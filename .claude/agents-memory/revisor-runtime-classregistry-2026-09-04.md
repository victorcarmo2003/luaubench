# Revisão — task-runtime-004 (ClassRegistry.luau + ClassRegistry.spec.luau)

Revisor: `revisor-runtime` (read-only). Escopo: `src/runtime/ClassRegistry.luau`, `src/runtime/ClassRegistry.spec.luau`.
Lidos antes de revisar: `.claude/rules/00-projeto.md`, `01-luau.md`, `02-runtime-simulation.md`, `.claude/tasks.json` (task-runtime-004), `.claude/agents-memory/arquiteto-runtime-2026-09-04.md` (seção "ClassRegistry.luau" + "Revisão pós-integração").

## Execução própria (não confiei no relato do coder)

Binário real do Lune (o shim de `rokit` em `~/.rokit/bin` falha sem `rokit.toml` no repo — não existe um; usei o binário real em `/d/Moved/.rokit/tool-storage/lune-org/lune/0.10.5/lune.exe`, a mesma versão pinada em `.luaurc`):

- `ClassRegistry.spec.luau`: **8/8 passaram**, nomes e contagem batem exatamente com o relatado.
- Regressão: `Signal.spec.luau` **6/6**, `Instance.spec.luau` **24/24**, `Scheduler.spec.luau` **12/12**, `Integration.spec.luau` **9/9** — todos passaram, sem alterar nenhum desses arquivos.
- `luau-lsp analyze --platform=standard` (binário real em `/d/Moved/.rokit/tool-storage/johnnymorganz/luau-lsp/1.68.1/luau-lsp.exe`) em `ClassRegistry.luau` + `ClassRegistry.spec.luau` isolado e depois em `src/runtime/*.luau` inteiro: **limpo, zero erros**.
- `grep -w any` nos dois arquivos: **zero ocorrências**.
- Escrevi dois scripts de verificação temporários na raiz do repo (`_verify_classchain_order.luau`, `_verify_cycle_guard.luau`), rodei com o Lune real, **apaguei os dois depois** (`git status --short` confirma árvore de trabalho sem resíduo) — usados para provar empiricamente os achados 1 e 2 abaixo, não fazem parte do código revisado.

## Achados

**[ALTO] ClassRegistry.luau:98-111**
Problema: `ClassRegistry.new` chama `descriptor.Construct(name)` **antes** de `Instance.SetClassChain(instance, chain)` — durante a execução do próprio `Construct`, `instance:IsA(className)` retorna `false` para qualquer ancestral indireto (avô, bisavô), porque a única cadeia que existe nesse momento é o default `{ClassName, "Instance"}` que `Instance.NewBase` seta sozinho (`Instance.luau:534`), não a cadeia completa resolvida por `resolveClassChain`.

Cenário de falha (reproduzido com script de verificação, apagado depois): registrei `VerifyA` (raiz), `VerifyB` (`SuperClassName = "VerifyA"`), `VerifyC` (`SuperClassName = "VerifyB"`). Dentro do `Construct` de `VerifyC`, chamei `instance:IsA("VerifyA")` → devolveu `false` (deveria ser `true`, já que `VerifyC` herda de `VerifyB` que herda de `VerifyA`). Assim que `ClassRegistry.new` retorna para quem chamou, a mesma chamada em cima da mesma instância já devolve `true` — a inconsistência existe só durante a janela de execução do `Construct`. Isso é exatamente o padrão de "acesso silenciosamente incorreto" que a regra 00 pede para nunca deixar implícito: nada em `ClassDescriptor.Construct` (nem no tipo, nem no comentário do módulo, nem no desenho do arquiteto) avisa quem escreve um `Construct` em `services` que `self:IsA(ancestralIndireto)` não funciona ainda dentro da própria função — é um contrato implícito, não documentado em lugar nenhum. Um `Construct` real que decida configuração condicional por ancestral (ex.: "se este é um `PVInstance`, crie tal propriedade default") ou que parenteie um filho recém-criado sob outra instância já existente cujo listener de `ChildAdded` cheque `IsA` do filho vai observar o valor errado sem nenhum erro, sem crash — corrompe decisão silenciosamente.
Correção: documentar explicitamente essa limitação no tipo `ClassDescriptor.Construct` (comentário) e no corpo de `ClassRegistry.new`, ou — melhor — resolver a ordem: já que `Construct` só devolve a `Instance` depois de já ter chamado `NewBase` internamente, considerar mudar a assinatura de `Construct` para receber a cadeia já resolvida (ex.: `Construct: (name: string?, chain: {string}) -> Instance`, deixando `services` chamar `Instance.SetClassChain` ele mesmo antes do resto do corpo de `Construct` rodar) — isso é mudança de contrato público e não deveria ser decidida por `coder-runtime` sozinho; volta para o `arquiteto`.

**[MÉDIO] ClassRegistry.luau:71-74**
Problema: a guarda de ciclo de herança (`error("ciclo de herança detectado...")`) é uma das duas decisões de robustez que o coder relata ter adicionado, mas nenhum dos 8 testes do spec exercita esse caminho — os dois testes de robustez cobrem só "ordem fora de topológica" e "superclasse não registrada", não ciclo.
Cenário de falha: verifiquei manualmente (script de verificação apagado depois) registrando `CycleA.SuperClassName = "CycleB"` e `CycleB.SuperClassName = "CycleA"` — `ClassRegistry.new("CycleA")` de fato lança erro capturável via `pcall` (`"ciclo de herança detectado na cadeia de classes envolvendo 'CycleA'"`) em vez de travar, então o código está correto hoje. Mas como não há teste automatizado cobrindo isso, uma regressão futura nesse laço (ex.: alguém "otimizando" `resolveClassChain` e quebrando a condição `seen[currentClassName]`) reintroduziria um `while true` verdadeiramente infinito — síncrono, dentro do processo do Scheduler, sem nenhum yield — e ninguém pegaria isso rodando a suíte. É precisamente o tipo de falha que a regra 01 ("teste na mesma tarefa da lógica que cobre") existe para prevenir, e aqui ficou faltando para metade da robustez extra reivindicada.
Correção: adicionar um teste explícito de ciclo de herança (2 classes se referenciando mutuamente, e idealmente também o caso de auto-referência direta) ao `ClassRegistry.spec.luau`.

**[BAIXO] ClassRegistry.luau:37**
Problema: `registry` é estado de módulo global mutável sem função de reset/teardown. Hoje isso é seguro só porque cada `*.spec.luau` termina com `process.exit(0)` (confirmado nos 5 specs existentes) — o que força cada spec a rodar como processo do SO isolado via `lune run` separado, então o `require` cacheado (e portanto `registry`) nunca vaza entre arquivos de teste. Essa dependência de "isolamento por `process.exit` incondicional no fim de cada spec" não está documentada em lugar nenhum como invariante — é um acidente estrutural, não uma decisão registrada.
Cenário de falha: se no futuro alguém criar um executor de testes que agregue múltiplos `*.spec.luau` num único processo Lune (por exemplo para rodar mais rápido, ou um harness de CI que faça `require` de vários specs numa única chamada em vez de invocar `lune run` várias vezes), classes de teste com o mesmo `ClassName` registradas em specs diferentes (hoje não colidem — todos usam prefixo `Test*` diferenciado neste arquivo) passariam a colidir com `error("já registrada")`, ou pior, testes de `services`/`cli` que também usem `ClassRegistry` para smoke tests futuros poderiam herdar classes de teste de uma sessão anterior dentro do mesmo processo (ex.: um watch mode do `cli` que não reinicia o processo Lune inteiro entre reloads).
Correção: não é bloqueante agora (nenhum executor agregado existe), mas vale documentar no cabeçalho do módulo que `ClassRegistry` assume processo-por-execução e não oferece reset, e considerar expor uma função interna de reset (não pública, só para harness de teste) se/quando um executor agregado for construído.

**[BAIXO] ClassRegistry.luau:73,84-87**
Problema: os dois erros de `resolveClassChain` (ciclo e superclasse ausente) usam `error(msg, 0)` — sem nenhuma informação de localização —, enquanto os dois erros de `ClassRegistry.new` (não registrada, abstrata) usam `error(msg, 2)`, apontando para quem chamou `new`. Inconsistência de nível dentro do mesmo módulo.
Cenário de falha: não é um bug de comportamento (a mensagem já cita os nomes de classe envolvidos), só uma perda pequena de contexto de debug para quem investiga um erro de registro malformado vindo de `services` — mensagem chega sem "arquivo:linha" nenhum, enquanto os erros irmãos de `new()` chegariam com a linha de quem chamou `ClassRegistry.new`.
Correção: trocar para `error(msg, 3)` nos dois pontos de `resolveClassChain` (um nível a mais que os erros de `new()`, já que há um frame extra de chamada), para manter o mesmo padrão de "aponta pra quem chamou `ClassRegistry.new`" em toda a função.

## O que verifiquei e não achei problema

- Superfície pública (`ClassDescriptor`, `Register`, `Get`, `IsRegistered`, `new`) bate byte-a-byte com o desenho do arquiteto (`arquiteto-runtime-2026-09-04.md`, seção "ClassRegistry.luau") — nenhuma assinatura divergente, nenhum campo a mais/a menos.
- `resolveClassChain` tratar `SuperClassName == nil` **e** o literal `"Instance"` como terminal não diverge do desenho (o próprio código cita a mesma justificativa do desenho) e não muda o resultado observável de `IsA` de nenhuma forma — é defensivo contra `services` popular `SuperClassName = "Instance"` literal (o que é plausível se o gerador mapear o campo `Superclass` do API Dump real sem normalizar para `nil`), sem introduzir path diferente.
- `Register`/`Get`/`IsRegistered` refletem estado corretamente; `new()` nunca devolve `nil` — todo caminho de falha usa `error()`.
- `ClassRegistry.luau` só importa `Instance.luau` (nenhuma dependência de `ThreadBroker`/`Scheduler`), sem ciclo de `require`, exatamente como o desenho exige.
- Nenhuma função interna (`resolveClassChain`, `registry`) vaza para fora do módulo — não há superfície acessível por `services`/`cli` além de `Register/Get/IsRegistered/new`.
- `--!strict` no topo dos dois arquivos; zero `any`; `luau-lsp analyze` limpo (validado, não só relatado).
- Contagens de teste e regressão relatadas pelo coder (8/8, 6/6, 24/24, 12/12, 9/9) — todas reproduzidas por mim rodando o binário real do Lune, batem exatamente.

## Veredito

APROVADO COM RESSALVAS

O achado ALTO (ordem `Construct` → `SetClassChain`) não quebra nenhum teste existente e não é GRAVE (não derruba processo, não dá acesso indevido), mas é uma lacuna de fidelidade silenciosa e não documentada que `services` (task-runtime-005 em diante) vai herdar sem saber, exatamente o tipo de risco que este board pediu para eu verificar com atenção. Recomendo resolver ou ao menos documentar explicitamente antes que `services` comece a escrever `Construct` de verdade — e frisar ao arquiteto que mudar a assinatura de `Construct` é decisão dele, não do coder. Os achados MÉDIO/BAIXO não bloqueiam merge, mas o de teste de ciclo ausente deveria virar tarefa pequena de acompanhamento (mesmo padrão de task-runtime-011/012 já usado no board para achados pós-revisão não bloqueantes).
