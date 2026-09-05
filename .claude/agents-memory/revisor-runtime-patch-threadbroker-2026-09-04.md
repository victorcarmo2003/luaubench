# Revisão do patch `ThreadBroker.luau` — task-runtime-008

Revisão read-only de `src/runtime/ThreadBroker.luau` (novo), `Signal.luau`, `Instance.luau`, `Scheduler.luau` (patch), motivada pela reprovação anterior (`.claude/agents-memory/revisor-runtime-signal-instance-scheduler-2026-09-04.md`) e pela correção desenhada em `.claude/agents-memory/arquiteto-runtime-2026-09-04.md`, seção "Revisão pós-integração 2026-09-04 — contrato Wait/resume".

Nenhum arquivo de `src/runtime/` foi editado nesta revisão. Todos os repros foram escritos e rodados fora do território, sobre **cópias** dos quatro arquivos reais (`Instance.luau`, `Scheduler.luau`, `Signal.luau`, `ThreadBroker.luau`, copiados byte-a-byte para um diretório isolado do scratchpad) — a única alteração feita foi uma instrumentação de contagem de listeners adicionada só na cópia de `Signal.luau` usada num repro específico (achado novo, ver abaixo), nunca no arquivo real. Timestamps de `src/runtime/*.luau` conferidos antes e depois: inalterados.

## Números confirmados (rodando eu mesmo, Lune real em `D:\Moved\.rokit\tool-storage\lune-org\lune\0.10.5\lune.exe`)

- `Signal.spec.luau`: **6/6**.
- `Instance.spec.luau`: **24/24**.
- `Scheduler.spec.luau`: **12/12**.
- `luau-lsp analyze --platform=standard` nos quatro arquivos (`ThreadBroker.luau`, `Signal.luau`, `Instance.luau`, `Scheduler.luau`): sem erros de tipo.
- `grep coroutine\.resume` em `src/runtime/*.luau` (excluindo specs, que legitimamente crua coroutines cruas para se testar sem depender do Scheduler): só em `Scheduler.luau:209` (`resumeThread`, o ponto único) e `ThreadBroker.luau:102/107` (fallback standalone). Nenhum segundo ponto de resume solto em `Signal.luau`/`Instance.luau` — confirma a correção arquitetural central.
- `grep '\bany\b'` em `src/runtime/*.luau`: zero ocorrências de `:: any`/tipo `any` real (só comentários mencionando "nunca any"). `Scheduler.luau:525` confirmado usando `:: unknown` (era achado MÉDIO 5 da revisão anterior).
- `src/runtime/init.luau` ainda não existe (fora do escopo desta tarefa) e `ThreadBroker` só é referenciado dentro dos 4 arquivos do próprio módulo — nenhum vazamento para fora do território.

## Reprodução dos achados GRAVE originais (mesmos cenários da revisão anterior, contra o Lune real)

### GRAVE 1 — WaitForChild com timeout sob `Scheduler:Run()` real
Repro: `scheduler:Spawn(function() parent.WaitForChild(parent, "Nunca", 0.05) end)` dirigido por `scheduler:Run(shouldContinue)` de verdade (guarda de 2s só como rede de segurança, nunca acionada).

**Resultado: `elapsed = 0.0617s`, `result = nil`.** Antes do patch não resolvia em 2s de wall-clock; agora resolve dentro do intervalo esperado. **RESOLVIDO.**

### GRAVE 2 — `IsAlive()`/vazamento via `Signal:Wait()`/`Heartbeat:Wait()`/`WaitForChild` sem timeout
Três casos, incluindo o mais perigoso (`Run()` **sem** `shouldContinue`, que travaria o processo para sempre se o bug persistisse — rodado com timeout externo do Bash como rede de segurança):
1. `scheduler.Heartbeat:Wait()` puro + `StepOnce` → `finished == true` **e** `scheduler:IsAlive() == false`. OK.
2. `WaitForChild` sem timeout + `child.Parent = parent` → `wfcFinished == true` **e** `IsAlive() == false`. OK.
3. `Spawn` + `Heartbeat:Wait()` + `scheduler:Run()` **sem** `shouldContinue` → retorna sozinho, sem travar. OK.

**RESOLVIDO** nos três casos.

## Confirmação dos dois achados ALTO originais

### ALTO 3 — `Fire` isolando listeners entre si
Repro standalone (idêntico ao da revisão anterior: erro no primeiro listener, segundo listener deveria rodar mesmo assim) **e** uma variação sob `Scheduler` real (`scheduler.Heartbeat:Connect` com erro no primeiro listener): segundo listener roda nos dois casos; sob Scheduler, o erro do primeiro vira `ThreadError` (não trava o tick). **RESOLVIDO.**

### ALTO 4 — `ThreadError` atribuindo a thread errada após continuação de `Wait()`
Repro: `waiterHandle = scheduler:Spawn(function() scheduler.Heartbeat:Wait(); error(...) end)`, `StepOnce`, e verificação de que `ThreadError` reporta exatamente `waiterHandle` (não a thread hospedeira de `tick()`/`coroutine.running()` do laço principal). **RESOLVIDO.**

## Cenários da lista "Testes de integração exigidos" checados por mim (3, 5, 7, 9 — os que o coder não checou manualmente)

- **3** (`Run()` sem `shouldContinue` termina sozinho): coberto junto do repro GRAVE 2, caso 3 acima. OK.
- **5** (`WaitForChild(nome, 5)` sob `StepOnce` determinístico: 4× `StepOnce(1)` ainda esperando, 5º resolve `nil`): reproduzido exatamente — não resolveu cedo nos 4 primeiros steps, resolveu `nil` no 5º. OK.
- **7** (corrida deadline × `ChildAdded` no mesmo tique → resultado único, zero `ThreadError` espúrio): construí a corrida com `Delay(1, function() child.Parent = parent end)` competindo com um `WaitForChild(nome, 1)` — `ChildAdded` venceu (roda antes de `resumeDueWaiting` dentro de `tick()`), resultado foi o filho (não `nil`), e **zero** `ThreadError` disparou nesse tique nem em 5 tiques seguintes (confirma que a entrada de deadline cancelada/podada não gera resume espúrio depois). OK.
- **9** (regressão: specs sem alteração): confirmado por conteúdo lido + números batendo (6/6, 24/24, 12/12) + timestamps dos `.spec.luau` mais antigos que os arquivos patcheados. OK.

Não escrevi o `Integration.spec.luau` formal — isso é `task-runtime-009`, rodando em paralelo, para não duplicar trabalho.

## Desvio sintático do `if...then...else` em `ThreadBroker.Resume` (fallback sem driver)

Testei os 4 branches do `if` statement reescrito (era `if...then...else` como expressão, rejeitado por `luau-lsp` porque não repassa dois retornos de `coroutine.resume`) mais o caso de thread já morta:

1. `args == nil`, sucesso → não propaga erro, `coroutine.yield()` do lado retomado recebe exatamente **0** argumentos (medido via `select("#", coroutine.yield())`, não pelos argumentos iniciais de `coroutine.create`, que é uma armadilha fácil de confundir num teste — corrigi meu próprio repro depois de um falso-negativo inicial causado por essa confusão).
2. `args ~= nil`, sucesso → argumentos empacotados chegam corretos e na ordem certa no ponto de retomada.
3. `args == nil`, erro dentro da coroutine → `ThreadBroker.Resume` **repropaga** o erro (não engole).
4. `args ~= nil`, erro dentro da coroutine → mesma checagem, com argumento repassado corretamente antes do erro.
5. Thread já morta (`coroutine.status == "dead"`) → no-op silencioso tanto com `args == nil` quanto `args ~= nil`, sem erro espúrio.

**Nenhuma regressão de comportamento — os dois branches (`args == nil` / `args ~= nil`) fazem exatamente o que o pseudo-código original do desenho pretendia, incluindo repasse de argumentos e de erro.**

## Achado novo (não coberto pela revisão anterior nem pelo desenho do patch)

### [MÉDIO] `Scheduler.luau:388-398` (`Cancel`) × `Instance.luau:408-435` (`WaitForChild` branch B) / `Signal.luau:96-102` (`Wait`) — `Cancel()` não desconecta a `Connection`/listener que a thread suspensa havia registrado no `Signal` alheio; listener fica pendurado até o evento disparar de novo (ou para sempre)

**Problema:** `Scheduler:Cancel(handle)` só limpa o estado do próprio `Scheduler` (`removeFromQueues`, `liveThreads`, `ThreadBroker.Release`, `coroutine.close`). Ele não sabe — e, pelo desenho (`Signal.luau` sem dependência de `Scheduler.luau`), não *pode* saber — que a thread cancelada tinha uma `Connection` viva registrada num `Signal` de terceiros (`data.childAdded` de uma `Instance`, ou o listener `once` que `Signal:Wait()` registra internamente para qualquer `signal:Wait()`/`scheduler.Heartbeat:Wait()`/`WaitForChild` sem timeout). Cancelar a thread mata a coroutine, mas o listener continua na lista interna do `Signal` até ele disparar (aí sim se autolimpa, via `Disconnect()`/auto-disconnect do `once`) ou, se o evento nunca mais disparar, para sempre.

**Cenário de falha (reproduzido empiricamente):**
```lua
local handle = scheduler:Spawn(function()
    parent:WaitForChild("Alvo", 10) -- branch (B): thread gerida, timeout 10s
end)
scheduler:Cancel(handle) -- coroutine.status(handle) == "dead" depois disto
-- parent.ChildAdded ainda tem 1 listener conectado (medido via instrumentação isolada:
-- contagem de listeners ficou em 1 antes e depois do Cancel, quando deveria cair a 0)
```
Medido também o efeito colateral quando o evento finalmente dispara: `child.Parent = parent` depois do `Cancel` roda o callback órfão (que checa `settled`, ainda `false`, tenta `ThreadBroker.Resume(co, nil)` sobre uma coroutine morta sem driver) — isso é seguro (`ThreadBroker.Resume` faz no-op silencioso para thread não-suspensa, confirmado no repro do desvio sintático acima) e o listener órfão se autolimpa nesse momento (contagem volta a cair). Não há crash, não há `ThreadError` espúrio, não há corrupção de estado — é estritamente um vazamento de listener até o próximo `Fire` compatível (ou permanente, se nunca houver um).

O mesmo mecanismo se aplica a **qualquer** thread cancelada enquanto suspensa num `Signal:Wait()` genérico (`scheduler.Heartbeat:Wait()`, `algumSignal:Wait()` de `services` futuro, `WaitForChild` sem timeout via `childAdded:Wait()` em loop) — não é exclusivo do branch (B) com timeout, é uma lacuna na fronteira `Scheduler` ↔ `Signal` que o desenho do `ThreadBroker` não cobriu (a seção "Riscos residuais" do desenho não menciona isto).

**Por que importa:** não é regressão deste patch — o mesmo padrão (`once`-listener em `Signal:Wait()`, sem ninguém desconectando no `Cancel`) já existia antes do `ThreadBroker`, só que o achado GRAVE 2 escondia o sintoma mais grave. Agora que `IsAlive()`/`liveThreads` estão corretos, este é o próximo ponto onde um script real que cancela `task.spawn`s (padrão comum: timeout manual, watchdog, cleanup de `Destroy`) pode acumular listeners mortos em `Signal`s de vida longa (`Heartbeat`, `ChildAdded` de uma `Instance` raiz) ao longo de uma sessão `luaubench run` continuada — crescimento de memória não-crítico, mas silencioso e não documentado (regra 00 pede declarar toda divergência/limitação, esta não está declarada em lugar nenhum).

**Correção sugerida:** não é um patch trivial de uma linha — exige o `arquiteto` decidir o mecanismo, dado que `Signal.luau` propositalmente não conhece `Scheduler.luau`. Duas linhas possíveis: (a) `ThreadBroker.Driver` ganhar um canal de "cleanup" que `Cancel`/`resumeThread` (ao podar por erro/morte) possam invocar, e `Signal:Wait()`/`WaitForChild` branch B registrarem sua função de desconexão nele; (b) aceitar o vazamento como limitação documentada nesta fase (mesmo padrão de outras limitações já aceitas no desenho, ex. preempção de coroutine travada) e abrir tarefa própria depois. **Não bloqueia a aprovação deste patch** — não é regressão introduzida por `ThreadBroker.luau`, é uma lacuna pré-existente só agora visível/verificável porque o bookkeeping de threads finalmente ficou correto. Recomendo o `arquiteto` registrar isto explicitamente nos "Riscos residuais" da seção do patch e abrir uma tarefa de acompanhamento antes de `services` começar a se apoiar pesado em `Signal:Wait()`/`Cancel` (ex. `Touched`, timeouts de rede simulados).

## Verificações adicionais feitas (checklist da revisão)

- Sandbox/execução de script de usuário: nenhum dos quatro arquivos expõe `fs`/`net`/`process` cru; `ThreadBroker.luau` não importa nada, `Instance.luau`/`Scheduler.luau` só `@lune/task` (uso interno, não vaza para o script do usuário — fora do escopo desta tarefa, que ainda não tem `Sandbox.luau`).
- Herança/hierarquia de `Instance`: não alterada por este patch (só o corpo de `WaitForChild`); os 24 testes de `Instance.spec.luau`, incluindo a ordem de reparenting, continuam passando sem alteração no arquivo de teste.
- `WaitForChild` sem timeout: continua bloqueando de verdade via `Signal:Wait()`, nunca retorna `nil` cedo — confirmado nos testes e nos repros GRAVE 2.
- `--!strict` presente nos quatro arquivos (linha 1); nenhuma função pública sem assinatura tipada completa (`ThreadBroker.Adopt/Release/DriverOf/IsManaged/Resume/ReportError` todas tipadas).
- `init.luau` ainda não existe; `ThreadBroker` não vaza para fora de `src/runtime/` (grep confirma).

## Veredito

**task-runtime-008: APROVADO COM RESSALVAS.**

Os dois achados GRAVE e os dois achados ALTO da revisão anterior estão **confirmadamente corrigidos**, reproduzidos por mim com o Lune real (não apenas aceitos do relato do coder). Os 4 cenários de integração que o coder não checou manualmente (3, 5, 7, 9) também se confirmam corretos. O desvio sintático do `if`/`else` em `ThreadBroker.Resume` foi testado nos 4 branches e não introduz regressão de comportamento. `luau-lsp analyze` limpo, zero `any`, zero segundo ponto de `coroutine.resume` fora do ponto único.

A ressalva é o achado **[MÉDIO]** novo acima: `Scheduler:Cancel()` não desconecta listeners que a thread cancelada tinha registrado em `Signal`s de terceiros, gerando vazamento até o evento disparar de novo (ou permanente, se nunca disparar). Não é regressão deste patch e não bloqueia a integração — mas precisa ser registrado explicitamente (regra 00: divergência/limitação nunca silenciosa) e endereçado antes de `services` depender pesadamente de `Signal:Wait()`/cancelamento em produção.
