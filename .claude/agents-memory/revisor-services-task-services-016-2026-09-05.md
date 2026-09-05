# Revisão — task-services-016 (AsyncCall.luau + InstanceState.luau)

Data: 2026-09-05. Revisor: `revisor-services` (read-only). Território: `src/services/AsyncCall.luau`,
`src/services/AsyncCall.spec.luau`, `src/services/InstanceState.luau`, `src/services/InstanceState.spec.luau`.

Nenhum achado aceito por self-report — todo item abaixo foi reproduzido por mim, com um script de
verificação descartável (`src/services/ZZZ_verify016_scratch.luau`, criado, executado e **apagado**
ao fim da sessão — não sobra no working tree).

## O que verifiquei e como

1. **Specs próprias**: `lune run src/services/AsyncCall.spec.luau` → 3/3 PASS. `lune run
   src/services/InstanceState.spec.luau` → 7/7 PASS. Confirmado por execução direta minha.

2. **Nível de erro (3) aponta pro call site do SCRIPT**, não pro `AsyncCall.luau`/`Scheduler.luau`
   internos. Testei com a pilha real (3 frames: `AsyncCall.Yield` <- `FakeGetAsync` simulando o
   "método real de services" <- closure de `pcall` simulando o call site do script). Resultado:
   `...ZZZ_verify016_scratch:31: [LuauBench] MyService:MyAsyncMethod can only yield...` — aponta
   exatamente para a linha que chamou `FakeGetAsync()`, nunca para dentro de `AsyncCall.luau` nem
   `Scheduler.luau`. Nota lateral: meu primeiro teste (chamando `AsyncCall.Yield` direto dentro do
   `pcall`, sem a camada intermediária) dava um erro SEM nenhum prefixo de posição — porque nível 3
   caía no frame C de `pcall`, sem debug info. Isso não é bug do código sob revisão; é um artefato
   de forma de teste — só reforça que o nível 3 está correto para a pilha real de produção
   (`AsyncCall.Yield` <- método real <- script), que tem exatamente 3 frames Luau.

3. **Nenhuma string em português vaza**: grep programático por 10 caracteres acentuados comuns
   (ã ç õ é í ó ê á ú à) e por palavras específicas da mensagem interna real de `Scheduler.Wait`
   ("gerida", "chamado", "dentro", "principal") na mensagem final capturada por `pcall`. Nenhum
   dos dois apareceu. Além disso, lendo o código: `local ok = pcall(function() scheduler:Wait(0)
   end)` **nem sequer captura o segundo retorno de `pcall`** (a mensagem de erro) — descarta
   completamente, e emite uma mensagem nova do zero. Isso é mais seguro que uma "retradução" restrita, que
   dependeria de nunca a string em português vazar por acidente numa reescrita futura.

4. **`Wait(0)` avança exatamente 1 passo de scheduler**: testei com duas threads via
   `scheduler:Spawn`, uma chamando `AsyncCall.Yield` e outra só marcando execução. Ordem observada:
   `A:before-yield -> B:before-wait -> A:after-yield`, com "A:after-yield" só aparecendo **depois**
   de um único `scheduler:StepOnce(0)` — nem 0 passos (thread A ficou de fato suspensa antes do
   `StepOnce`), nem busy-loop (nada mais avança sem outro `StepOnce`).

5. **Prefixo `_LuauBench` é prefixo real, não substring**: testei com a chave
   `"NotLuauBenchStuff_LuauBench"` (contém `_LuauBench` no MEIO, não no início) — `InstanceState.new`
   **rejeitou** corretamente. O código usa `string.sub(key, 1, string.len(REQUIRED_PREFIX)) ~=
   REQUIRED_PREFIX`, uma checagem de prefixo real, não `string.find`.

6. **Leitura direta de `_LuauBench*` na instância erra, não devolve nil**: registrei uma classe
   fictícia com schema não-vazio (modo estrito), fiz `InstanceState.new("_LuauBenchSecret").Set(...)`
   e depois `instance._LuauBenchSecret` (acesso dinâmico via `Dynamic = {[string]: unknown}`) — erro
   `"_LuauBenchSecret is not a valid member of Verify016Widget \"Verify016Instance\""`, família real
   do Roblox, não `nil` silencioso.

7. **Isolamento**: confirmado independentemente do spec — duas chaves na mesma instância não
   colidem, e a mesma chave em duas instâncias diferentes não compartilha valor.

8. **`--!strict`/sem `any`**: presente nas 4 primeiras linhas dos 4 arquivos. `grep ':: *any\b'`
   vazio nos 4 arquivos. As únicas ocorrências da palavra `any` são prosa em inglês dentro da
   mensagem de erro ("outside any scheduled thread") e um comentário — não anotação de tipo.
   `luau-lsp analyze --platform=standard` rodado só nos 4 arquivos (não no diretório inteiro, por
   causa do `coder-services`/Lighting concorrente) — zero diagnóstico.

9. **Território limpo**: `git status --porcelain` mostra só os 4 arquivos-alvo como untracked, mais
   `.claude/tasks.json` (modificado por outro agente, ignorado conforme instrução) e
   `src/services/behavior/Index.luau` + `Index.spec.luau` (modificados) + `behavior/Lighting.luau`
   (untracked) — exatamente o trabalho concorrente de `coder-services`/task-services-024 anunciado
   na nota de concorrência, fora do escopo desta revisão.

10. **`GetPropertyRaw`/`SetPropertyRaw` são API pública de `runtime`, não acesso interno**:
    confirmado em `src/runtime/init.luau:189-193` (`Runtime.Instance.GetPropertyRaw = ...`,
    `SetPropertyRaw = ...`, dentro do módulo público exportado) e já usado pelo mesmo canal em
    `src/runtime/init.spec.luau` e `src/services/Integration.spec.luau` (comentário: "a única forma
    pública de instalar propriedade sem passar pelo schema"). Não é `require` de módulo interno —
    é a via de engenharia documentada e deliberada (mesmo canal que `cli` já usa para
    `Script.Source`).

## Checagem extra que fiz por conta própria

Verifiquei se o `pcall` de `AsyncCall.Yield` poderia estar mascarando um erro DIFERENTE de
`Scheduler.Wait` (não só "thread não gerida") — lendo `src/runtime/Scheduler.luau:395-405`,
`Scheduler.Wait` tem exatamente UM `error(...)`, só para o caso de thread não rastreada. Não há
outro caminho de erro na função antes disso. Logo o `pcall`-e-reemite não esconde nenhuma outra
classe de bug — só o caso que ele diz tratar.

## Achados

Nenhum GRAVE/ALTO/MÉDIO. Nenhum BAIXO formal — a única observação é estilística: o cabeçalho de
`AsyncCall.luau` descreve o comportamento como "captura...e RETRADUZ" o erro em português, mas o
código na verdade descarta a mensagem original inteira e emite uma nova do zero (não inspeciona o
conteúdo capturado). Funcionalmente isso é ainda mais seguro (impossível vazar por acidente), então
não é um defeito — só uma imprecisão de vocabulário no comentário, não vale correção obrigatória.

## Veredito

APROVADO.
