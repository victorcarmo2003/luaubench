# Regra 02 — Runtime e simulação de Instance (`src/runtime/`)

## DataModel e Instance

- Toda Instance simulada tem: `ClassName` (imutável), `Name`, `Parent`, filhos ordenados, propriedades tipadas conforme a classe (vindas do API Dump), e os métodos herdados da cadeia de classes (`Instance` → ... → classe concreta) — herança do dump é respeitada, não achatada arbitrariamente.
- `Instance.new(className)` só aceita `className` presente no API Dump. Classe abstrata do dump (ex: `Instance` em si, `PVInstance`) não é instanciável diretamente — mesma regra do Roblox real.
- Hierarquia (`Parent`/`Children`, `FindFirstChild`, `WaitForChild`, `GetChildren`, `GetDescendants`) segue exatamente a semântica do Roblox: `WaitForChild` sem filho existente **espera** (usa o scheduler, não retorna `nil` imediatamente a menos que receba timeout).
- Evento (`Changed`, `ChildAdded`, `AncestryChanged`, evento específico de classe como `Touched`) dispara na mesma ordem relativa que o Roblox real dispararia, mesmo que o gatilho real (física, render) não exista aqui.

## Scheduler

- `task.spawn`, `task.wait`, `task.delay`, `task.defer`, `coroutine.*` seguem a semântica real de agendamento do Roblox (`task.wait` não é `os.clock` puro — é passo de scheduler). Não implemente como `Sleep` bloqueante do SO.
- `RunService.Heartbeat`/`Stepped`/`RenderStepped` existem como eventos simulados no laço principal do LuauBench — `RenderStepped` pode não disparar (sem render), mas se disparar precisa ser documentado como aproximação.
- Erro não tratado dentro de uma `coroutine`/`task.spawn` não derruba o processo — é capturado e reportado como o Roblox faria no Output, com stack trace.

## Fidelidade vs. pragmatismo

- Quando fidelidade total exigiria reimplementar física/render (ex: `Touched` baseado em colisão real, `Raycast` geométrico), a via padrão é: implementar a superfície de API real (assinatura, tipo de retorno) com um comportamento simulado simplificado e documentado — nunca omitir a API silenciosamente, nunca fingir que o resultado é fisicamente exato.
- Toda simplificação dessas é uma decisão que o `arquiteto` registra explicitamente — `coder-runtime` não decide sozinho que uma classe "não vale a pena simular direito".

## Contrato com `services`

- `runtime` expõe a base (`Instance`, `DataModel`, scheduler, sistema de eventos) que `services` consome para construir cada Service concreto. `runtime` nunca conhece um Service específico por nome — isso é inversão de dependência: `services` depende de `runtime`, nunca o contrário.
- `runtime` nunca lê o API Dump diretamente para gerar classe de Service — isso é responsabilidade de `services`. `runtime` só sabe como registrar/instanciar uma classe cuja definição já foi resolvida.

## Contrato com `cli`

- `runtime` não sabe o que é um `.project.json` do Rojo nem lê filesystem do projeto do usuário — quem popula o `DataModel` a partir do projeto é `cli`, chamando a API pública que `runtime` expõe (`DataModel.new()`, `Instance.new`, `instance:SetParent(...)`, etc).
