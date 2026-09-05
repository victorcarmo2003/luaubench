# Revisão — `task-services-001` — Esqueleto de `services` (Types/Context/ClassBuilder/init)

Data: 2026-09-05. Primeira revisão do território `services`. Arquivos revisados: `src/services/Types.luau`, `Context.luau`, `ClassBuilder.luau`, `init.luau` + specs correspondentes.

Insumos lidos por inteiro antes da revisão: `.claude/tasks.json` (task-services-001 completa) e `.claude/agents-memory/arquiteto-services-2026-09-05.md` (as 841 linhas — desenho completo do território, incluindo a revisão pós-pesquisa de Capabilities/RenderStepped, que não se aplica a esta tarefa mas foi lida para contexto).

## Método

Não confiei nos números do coder nem nos testes dele como prova suficiente. Rodei os três specs com o binário `lune` do projeto (`C:\Users\hakor\.rokit\bin\lune`), rodei `luau-lsp analyze --platform=standard` (`C:\Users\hakor\.rokit\bin\luau-lsp`) nos seis arquivos não-`init`, e escrevi probes independentes (fora de `src/services/`, apagados ao final — nunca editei nada dentro do território revisado) para reproduzir ativamente os pontos 3–6 e o achado de tooling do `init.luau` com dados diferentes dos usados no spec do coder.

## Verificações pontuais (1–10 do briefing)

1. **`Types.luau`** — lido por inteiro. Único `require` é `local Runtime = require("../runtime")`. Zero lógica: só `export type` (`GeneratedClass`, `Behavior`, `BootstrapOptions`) e `return {}` no fim. Confirmado.

2. **`Context.Get*` erram antes de `Bootstrap`** — `current: BootstrapOptions? = nil` é inicializado no load do módulo e só muda dentro de `Context.Set`, chamada só por `Services.Bootstrap`. Não há nenhum código de nível de módulo que chame `Set` como efeito colateral de `require`. Rodei `Context.spec.luau` isolado (`lune run`, processo próprio, sem vazamento de estado entre specs): `IsSet()` é `false` e `GetScheduler`/`GetDataModel` erram citando "Bootstrap" antes de qualquer `Set`. 3/3 passou.

3. **`ClassBuilder.Build` rejeita `Behavior.Methods` fora de `MethodNames`** — testei ativamente com um probe independente do coder (nomes `"Real"`/`"Fake"`, diferentes do `"Foo"`/`"Bar"` do spec dele): `Build({MethodNames={"Real"}}, {Methods={Real=fn, Fake=fn}})` erra de fato, mensagem em português citando `'Fake'` e `'ProbeReject'`, formato `método '{X}' não existe em '{Class}' segundo o Roblox API Dump {versão}`. Confirmado, não é um caso especial hardcoded para os nomes do spec original.

4. **Stub de método não implementado erra com a substring exata** — probe independente: `stub()` chamado via `pcall` própria erra com `[LuauBench] ProbeStub:Unimplemented() exists in the Roblox API Dump but is not simulated by LuauBench yet` — contém a substring `is not simulated by LuauBench yet` cobrada pelo acceptance. Confirmado por chamada real, não por leitura do código.

5. **Tabela de métodos REALMENTE congelada** — `table.isfrozen(descriptor.Methods)` retornou `true` no meu probe, e tentei escrever nela (`methods["Unimplemented"] = function() end`) — erro real do runtime Luau: `attempt to modify a readonly table`. Não é só o campo declarado `Methods: {[string]: unknown}` — é `table.freeze` de verdade.

6. **`Register()` idempotente** — probe chamando `Register()` três vezes, depois `Bootstrap`, depois `Register()` de novo, tudo dentro do mesmo `pcall`: não erra. Confirmado além do teste do coder (que só chama duas vezes seguidas).

7. **Teste de ponta a ponta usa `Runtime.ClassRegistry` de verdade** — lido `init.spec.luau` linha a linha: `Runtime.ClassRegistry.Register(ClassBuilder.Build(widgetGenerated, widgetBehavior))` é uma chamada real ao registro central do runtime (mesmo módulo que `task-runtime-004` construiu), não um mock/stub local. `Services.new` por baixo chama `Runtime.ClassRegistry.new(className, name)`, também real. A instância resultante é testada via `Runtime.Instance.GetPropertyRaw` para pegar o `Signal` fresco (`Pinged`) e `Connect`/`Fire` de verdade — mecanismo real do `Signal.luau`, não simulado.

8. **Regra de idioma dos erros** — audit de toda mensagem `error()` do território:
   - `Context.luau` (2x): português, "Bootstrap ainda não foi chamado..." — engenharia interna (uso errado da API por `cli`), correto.
   - `ClassBuilder.luau`: `método '{X}' não existe em '{Class}' segundo o Roblox API Dump {versão}` — português, engenharia interna (agente/behavior inventando método), correto. Stub: `[LuauBench] {Class}:{Method}() exists in the Roblox API Dump but is not simulated by LuauBench yet` — inglês, prefixo `[LuauBench]`, sem contraparte real, correto.
   - `init.luau`: `Unable to create an Instance of type "{className}"` (2 branches: inexistente e abstrata) — inglês, família Roblox, sem prefixo, correto (é a mensagem real do Roblox para classe não-criável/inexistente). `[LuauBench] {className} exists in the Roblox API Dump ({versão}) but is not simulated by LuauBench yet` — inglês com prefixo, correto (branch hoje inalcançável, mas a mensagem está certa).
   Nenhuma mensagem fora do padrão nas três categorias.

9. **Julgamento da tradução `Superclass == "Instance" -> SuperClassName = nil`** — fui conferir contra o contrato real de `src/runtime/ClassRegistry.luau` (não só contra o desenho): `resolveClassChain` trata `SuperClassName == nil` **e** o literal `"Instance"` como equivalentes (`if currentSuperClassName == nil or currentSuperClassName == "Instance" then break end`, linha 135). Ou seja, o runtime já aceitaria o literal `"Instance"` sem tradução nenhuma — a tradução do coder para `nil` é uma escolha estilística **correta e segura**, não uma necessidade estrita: `nil` é semanticamente mais claro ("sem superclasse" em vez de uma string que se refere a si mesma na raiz) e evita qualquer ambiguidade se algum dia o runtime deixar de aceitar o literal como caso especial. Concordo com a decisão do coder — não é invenção de comportamento, é o mapeamento correto para o contrato existente de `ClassDescriptor.SuperClassName: string?` (`"nil = herda direto de Instance"`, comentário original de `task-runtime-004`).

10. **Nenhum arquivo fora de `src/services/` tocado** — `git status --porcelain` mostra só `?? src/services/` como território novo (mais `.claude/tasks.json`, que já aparecia modificado no snapshot de git no início da sessão — bookkeeping do board, não código). Nenhum arquivo de `src/runtime/` ou `src/cli/` tocado.

## Testes — rodados por mim, não só relatados pelo coder

```
lune run src/services/Context.spec.luau       -> 3/3
lune run src/services/ClassBuilder.spec.luau  -> 7/7
lune run src/services/init.spec.luau          -> 7/7
```

`luau-lsp analyze --platform=standard` limpo (zero diagnóstico) em `Types.luau`, `Context.luau`, `ClassBuilder.luau`, `Context.spec.luau`, `ClassBuilder.spec.luau`. `--!strict` presente nos 7 arquivos do território; zero ocorrências de `any` (`grep -w any` vazio).

### Achado de tooling em `init.luau`/`init.spec.luau` — reproduzido, não é bug de código

`luau-lsp analyze` nesses dois arquivos devolve 16 erros (`Unknown require`, `Unknown type 'Runtime.X'`, `Function only returns 1 value...`). Mesma classe de bug já documentada e aceita em `revisor-runtime-init-2026-09-04.md` para `src/runtime/init.luau`. Não aceitei a alegação do coder de graça: copiei o conteúdo de `init.luau`/`init.spec.luau` para dois arquivos na raiz do repo com nomes que NÃO começam com `init` (requires ajustados só para o novo caminho, lógica idêntica) e rodei `luau-lsp analyze` neles — **zero `TypeError`** (só um lint `ImportUnused` cosmético, sem relação). Rodei a cópia renomeada com `lune run` também: executa e produz o mesmo resultado funcional. Confirma que o gatilho é o nome do arquivo (`init*`), não o conteúdo — mesmo bug de tooling já aceito no território `runtime`, não é achado novo nem motivo de reprovação. Probes apagados ao final, árvore de trabalho limpa (verificado por `git status --porcelain`).

## Nada de GRAVE/ALTO/MÉDIO/BAIXO encontrado

Verifiquei ativamente, com código meu independente do spec do coder, os quatro pontos mais sensíveis (rejeição de método inventado, stub que erra, congelamento real, idempotência) e não encontrei divergência entre o que o coder relatou e o que o código realmente faz. A tradução de `Superclass`/`SuperClassName` está correta e é consistente com o contrato já existente em `ClassRegistry.luau`. Idioma dos erros consistente em toda a superfície. Nenhum arquivo fora do território tocado. Tooling do `init.luau` é o mesmo bug já aceito no território `runtime`, reproduzido de forma independente.

## Veredito

```
## Veredito
APROVADO
```
