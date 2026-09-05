# Pesquisa: scheduler cooperativo (Lune) vs. semântica real do scheduler do Roblox

Contexto lido antes de pesquisar: `CLAUDE.md` e `.claude/rules/02-runtime-simulation.md` do projeto — LuauBench é **100% Luau rodando sob o executável `lune`** (via `lune build`), não um binário Rust que embute Lune como crate. Isso muda a resposta da pergunta 1 (não existe "loop principal" exposto a scripts Luau — só existe a nível de crate Rust, que o LuauBench não usa).

---

## 1. API do `task` do Lune para um scheduler cooperativo

**Resposta curta:** o `task` do Lune expõe só `spawn`/`wait`/`delay`/`defer`/`cancel` — sem nenhum primitivo de "frame" ou "main loop" acessível a partir de Luau. `task.delay` nem é implementação própria: é `defer` + `wait` + `spawn` compostos em Luau puro. O motor real (fila de threads, ordenação, `run()`) vive no crate Rust `mlua-luau-scheduler`, que o `lune` (o executável) usa internamente, mas que **um script Luau rodando sob `lune run` não enxerga nem controla diretamente**. Para simular `RunService.Heartbeat`/`Stepped`/`RenderStepped`, o `runtime` do LuauBench vai ter que construir esse loop *em Luau*, por cima de `task.wait`/`task.spawn` — Lune não dá isso pronto.

**Fatos verificados**
- `task.spawn<T...>(functionOrThread: thread | (T...) -> ...any, ...: T...): thread` — roda imediatamente; se a task spawnada yield, a thread chamadora retoma e a spawnada continua em background. Retorna a thread. — fonte: `crates/lune-std-task/types.d.luau`, repo `lune-org/lune`, branch `main` (consultado 2026-09-04; release estável mais recente é `v0.10.5`, 2026-07-02).
- `task.wait(duration: number?): number` — espera *pelo menos* `duration`; retorna o tempo exato esperado. Doc: "The minimum wait time possible using task.wait is limited by the underlying OS sleep implementation. For most systems this means accuracy down to about 5 milliseconds or less." — mesma fonte.
  - Implementação real (`crates/lune-std-task/src/lib.rs`, branch `main`): `yield_now().await` seguido de `Timer::after(duration).await` (timer assíncrono, não `Sleep` bloqueante de SO), com **mínimo de 1ms hardcoded no código** para evitar retorno instantâneo — dado ligeiramente diferente do "~5ms" da doc; o código é a fonte mais confiável aqui.
- `task.delay<T...>(duration: number, functionOrThread, ...: T...): thread` — retorna a thread que será atrasada. Implementação real é Luau puro, não Rust:
  ```lua
  return defer(function(...)
      wait(select(1, ...))
      spawn(select(2, ...))
  end, ...)
  ```
  Ou seja: `task.delay` entra na fila de **deferred** imediatamente na chamada; só a espera interna (`wait`) de fato pausa. — fonte: `crates/lune-std-task/src/lib.rs`, branch `main`.
- `task.defer<T...>(functionOrThread, ...: T...): thread` — roda no fim da fila de tasks imediatas do resume point atual. Retorna a thread. — fonte: `types.d.luau`.
- `task.cancel(thread: thread)` — sem retorno documentado; para uma thread agendada. — fonte: `types.d.luau`.
- Ordenação garantida: `task.spawn`/threads imediatas rodam em FIFO estrito; `task.defer` só roda depois que **todas** as threads imediatas da fila atual yield ou terminam — fonte: doc do método `push_thread_front`/`push_thread_back` em `crates/mlua-luau-scheduler/src/scheduler.rs`, branch `main`: push_thread_front = "Threads are guaranteed to be resumed in the order that they were pushed to the queue"; push_thread_back = "Deferred threads are guaranteed to run after all spawned threads either yield or complete."
- O motor por trás do `task` é o crate `mlua-luau-scheduler` ("An async scheduler for Luau, using `mlua` and built on top of `async-executor`... runtime-agnostic"). API pública relevante (fonte: `scheduler.rs`, `lib.rs`, branch `main`):
  - `Scheduler::run(&self) -> impl Future` — "Runs the scheduler until all Lua threads have completed. This will return instantly if no threads have been scheduled." **Esse é o único "loop principal" que existe no ecossistema Lune** — mas é uma API Rust, chamada pelo host (`block_on(sched.run())`), não algo exposto para o script Luau.
  - `push_thread_front` / `push_thread_back` — enfileiram threads imediatas/deferidas.
  - `set_exit_code(code)` — força `run()` a retornar imediatamente (é o que embasa `process.exit()` do lado Luau).
  - `wait_for_thread(id)` — espera async por uma thread específica terminar.
  - **Implicação prática para o LuauBench:** como o processo Lune só termina quando `Scheduler::run` esgota todas as threads (ou alguém chama `set_exit_code`/`process.exit`), se o `runtime` do LuauBench spawnar um loop infinito (`while true do task.wait(dt) ... end`) para simular Heartbeat, **o processo `luaubench run` nunca vai terminar sozinho** — precisa de um gatilho explícito de saída (ex: `process.exit()` quando o script de entrada do usuário sinaliza fim, ou um comando de watch-mode que mata o processo). *Isso é inferência minha a partir dos dois fatos acima, não uma frase textual da doc — vale confirmar com o `arquiteto` antes de assumir.*
- Não existe, em nenhuma doc oficial ou no `types.d.luau`, qualquer primitivo tipo `RunService`, `requestAnimationFrame`, "on tick" ou hook de frame exposto ao script Luau — Lune é headless/CLI, sem conceito de frame de render.

**Exemplo mínimo**
```lua
-- Como o `defer`/`spawn` real do Lune se comporta (confirmado pelos fatos acima)
local task = require("@lune/task")

task.spawn(function()
	print("A: imediato")
end)

task.defer(function()
	print("C: depois de todo mundo imediato yield/terminar")
end)

task.spawn(function()
	print("B: imediato, ordem FIFO com A")
end)

-- saída: A, B, C
```

**Limites e pegadinhas**
- `task.wait` no Lune **não** tem noção de "frame"/Heartbeat — é puramente um timer assíncrono com piso de ~1ms (código) / ~5ms (doc). Se o `runtime` do LuauBench quiser que `task.wait` no *script simulado do usuário* se comporte como o Roblox (resolução de 1 frame, atrelado a um "Heartbeat" simulado), ele **não pode delegar isso ao `task.wait` nativo do Lune** — precisa interceptar/reimplementar a API `task` dentro do sandbox do `game` simulado, chamando o `task.wait` nativo do Lune só como primitivo de baixo nível (ex: para a espera real de tempo), nunca expondo-o direto ao script do usuário. Isso é coerente com a Regra 02 do projeto ("`task.wait` não é `os.clock` puro — é passo de scheduler").
- `task.cancel` no Lune não tem doc sobre se "fecha" a coroutine (`coroutine.close`) ou só remove da fila — o `types.d.luau` só diz "Stops a currently scheduled thread from resuming", sem detalhe de estado final da thread. (Contraste: no Roblox, a doc oficial diz explicitamente que cancela **e fecha** a thread — ver seção 2.)
- Não achei documentação explícita sobre como `coroutine.resume`/`coroutine.wrap` nativos do Luau interagem com a fila do `task` scheduler (ex: se resumir manualmente uma thread que o scheduler também está rastreando causa double-resume ou erro). Ver "Incerto".

**Incerto**
- Interação entre `coroutine.resume`/`coroutine.wrap` manuais e threads gerenciadas pelo `task` scheduler — não encontrei declaração explícita nem no livro (`the-book/9-task-scheduler`) nem nos crates lidos. Recomendo tratar como "não confirmado" até testar empiricamente ou perguntar no repositório.
- Se `push_thread_back`/`push_thread_front` são exatamente 1:1 com `defer`/`spawn` — o `lib.rs` do `lune-std-task` mostra `fns.spawn`/`fns.defer` vindo do `mlua_luau_scheduler::Functions`, o que sugere mapeamento direto, mas não vi o corpo exato de `Functions::spawn`/`Functions::defer` (só o glue de registro). Alta confiança, mas não é citação literal.
- Comportamento de `task.wait()` sem argumento (default `nil`→ tratado como quê exatamente, 0 segundos?) — o tipo é `duration: number?`, doc não especifica o default numérico explicitamente (diferente da doc do Roblox, que diz "default 0"). Marcar como não confirmado para o Lune especificamente.

---

## 2. Semântica real do scheduler do Roblox

**Resposta curta:** `task.wait(t)` no Roblox é cooperativo (nunca preempção real dentro de um script), sem resolução mínima fixa documentada — ele garante retomar a thread no **primeiro `Heartbeat`** em que `t` já tiver decorrido, sem "throttle" além disso. Ordem de frame confirmada pelas próprias descrições dos eventos: `PreAnimation` → `PreSimulation` (substitui `Stepped`) → *física* → `PostSimulation` → `Heartbeat` (dispara logo após `PostSimulation`) → `PreRender` (substitui `RenderStepped`) → render. `WaitForChild` sem timeout **bloqueia (yield) a thread atual indefinidamente** até o filho ser adicionado — não há timeout implícito, só um aviso (warning) impresso no Output após 5s sem retorno, sem cancelar a espera.

**Fatos verificados**
- `task.wait`: "Yields the current thread until the given duration (in seconds) has elapsed, then resumes the thread on the next Heartbeat step" + "does not throttle and guarantees the resumption of the thread on the first Heartbeat that occurs when it is due." Parâmetro `duration` com default `0`. — fonte: `content/en-us/reference/engine/libraries/task.yaml`, repo `Roblox/creator-docs`, branch `main` (consultado 2026-09-04; sem número de versão do motor associado — doc de referência da API viva, não versionada por release do Studio).
  - Ou seja: resolução mínima = granularidade de 1 frame (não um número de ms fixo) — a thread só pode retomar em um `Heartbeat`, nunca "no meio" de um frame.
- `task.spawn`: "Calls/resumes a function/coroutine immediately through the engine's scheduler." — mesma fonte.
- `task.delay`: "Schedules it to be called/resumed on the next Heartbeat after the given amount of time in seconds has elapsed." — mesma fonte. (Difere do Lune: no Roblox `task.delay` também está amarrado a `Heartbeat`, não a um timer de SO livre.)
- `task.defer`: "Defers it until the end of the current resume point within the current frame." — mesma fonte.
- `task.cancel`: "Cancels a thread **and closes it**, preventing it from being resumed manually or by the engine's scheduler." — mesma fonte. (Diferente do que se confirmou para o Lune: no Roblox fica explícito que a thread é fechada/`coroutine.close`d, impedindo até resume manual.)
- Ordem de eventos de frame (descrições textuais oficiais, cada uma citada literalmente):
  - `PreAnimation`: "Fires every frame, prior to the physics simulation but after rendering."
  - `PreSimulation`: "Fires every frame, prior to the physics simulation." — documentado como substituto moderno de `Stepped`.
  - `Stepped` (legado): "Fires every frame, prior to the physics simulation." — nota de migração: superado por `PreSimulation`.
  - `PostSimulation`: "Fires every frame, after the physics simulation has completed." — e a doc afirma explicitamente que **dispara o `Heartbeat` em seguida**.
  - `Heartbeat`: "Fires every frame, after the physics simulation has completed." — ocorre no fim do frame, depois que scripts em espera já rodaram.
  - `PreRender`: "Fires every frame, prior to the frame being rendered." — só client-side (LocalScript/Script com `RunContext = Client`) — substitui `RenderStepped`.
  - `RenderStepped` (legado): "Fires every frame, prior to the frame being rendered." — nota de migração: superado por `PreRender`.
  - Ordem relativa reconstruída a partir dessas descrições (não há uma lista única e explícita numerada na doc, mas as relações "prior to X"/"after Y"/"triggers Z" fecham a cadeia): **PreAnimation → PreSimulation (Stepped) → [física] → PostSimulation → Heartbeat → PreRender (RenderStepped) → [render]**. — fonte: `content/en-us/reference/engine/classes/RunService.yaml`, repo `Roblox/creator-docs`, branch `main`, consultado 2026-09-04.
- `Instance:WaitForChild`:
  - Assinatura: `WaitForChild(childName: string, timeOut: number): Instance` (parâmetro `timeOut` opcional/double).
  - "Returns the child of the Instance with the given name. If the child does not exist, it will yield the current thread until it does."
  - "If a call to this method exceeds 5 seconds without returning, and no `timeOut` parameter has been specified, a warning will be printed" — o warning **não cancela a espera**, é só log.
  - Sem `timeOut`: espera indefinidamente (yield puro via scheduler, mesmo mecanismo de qualquer thread suspensa — não é polling nem timeout implícito).
  - Com `timeOut`: retorna `nil` se o tempo expirar sem o filho aparecer.
  - Não faz yield se o filho já existir no momento da chamada.
  — fonte: `content/en-us/reference/engine/classes/Instance.yaml`, repo `Roblox/creator-docs`, branch `main`, consultado 2026-09-04.

**Exemplo mínimo**
```lua
-- Ordem cooperativa esperada num frame do Roblox real (reconstrução a partir das docs, não snippet oficial)
game:GetService("RunService").PreSimulation:Connect(function(dt) end) -- antes da física
game:GetService("RunService").PostSimulation:Connect(function(dt) end) -- depois da física
game:GetService("RunService").Heartbeat:Connect(function(dt) end) -- logo após PostSimulation
```

**Limites e pegadinhas**
- Não existe, na doc, um número fixo de "resolução mínima" para `task.wait` (tipo "16ms" ou "1/60s") — a garantia documentada é só "primeiro Heartbeat em que já decorreu `duration`", o que na prática depende do framerate real do jogo (variável). Qualquer número fixo que o LuauBench queira usar para simular isso (ex: assumir 60 Hz) é uma decisão de projeto do `arquiteto`, não um fato do Roblox — precisa ser documentado como aproximação, conforme a Regra 02 já exige.
- `Stepped` e `RenderStepped` são eventos **legados** (a doc chama explicitamente de superados por `PreSimulation`/`PreRender`), mas continuam existindo e disparando — o LuauBench provavelmente precisa simular os dois pares (moderno + legado) se quiser fidelidade total com scripts antigos.
- `PreRender`/`RenderStepped` são **client-side only** (LocalScript, ModuleScript requerido por LocalScript, ou Script com `RunContext = Client`) — não disparam em Script de servidor. Como o LuauBench roda tudo localmente sem separação real client/server (ver Regra 00: "sem replicação client/server real" é uma divergência aceitável mas deve ser documentada), isso é um ponto que o `arquiteto` precisa decidir explicitamente como tratar.
- `WaitForChild` sem timeout: cuidado para não confundir "imprime warning após 5s" com "expira após 5s" — são coisas diferentes; a doc é explícita que é só log, a espera continua.

**Incerto**
- Não encontrei, nas páginas oficiais (`create.roblox.com/docs`) consultadas, uma lista numerada única e explícita da ordem completa de frame (a reconstrução acima vem de juntar frases "prior to X"/"after Y" de páginas de referência separadas, não de um diagrama/lista oficial linear). Achei referência a um diagrama visual em `create.roblox.com/docs/performance-optimization/microprofiler/task-scheduler` que several fontes citam como mostrando "a ordem em que o task scheduler categoriza e completa tasks", mas o conteúdo do diagrama em si (imagem) não pôde ser extraído via fetch de texto — só a legenda textual ao redor. Se a ordem exata frame-a-frame for crítica para o design do scheduler simulado, vale abrir essa página num browser para ver o diagrama diretamente.
- Se `task.wait()` sem argumento algum equivale exatamente a "resume no próximo Heartbeat, delay=0" (doc diz "with no duration... equivalent in behavior to RunService.Heartbeat", frase vista num resumo de busca, não confirmada por citação literal de página oficial) — tratar como pista, não fato confirmado.
