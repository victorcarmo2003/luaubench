## `runtime` — Arquitetura

### Propósito

Prover a "máquina" genérica — Instance/hierarquia/eventos/scheduler/sandbox — sobre a qual `services` constrói cada classe real do Roblox e `cli` executa o projeto do usuário, sem que `runtime` conheça nome de classe concreta nem leia API Dump/`.project.json`.

### Convenção de nomes usada neste desenho

`.new` minúsculo é reservado a construtores que espelham `Instance.new`/`ClassName.new` do próprio Roblox/Luau (`Signal.new`, `DataModel.new`, `Scheduler.new`, `ClassRegistry.new`). Toda outra função pública é `PascalCase`, seguindo o estilo do próprio Roblox API Dump (`FindFirstChild`, `Register`, `GetPropertyRaw`). Arquivo de classe em `PascalCase` (regra 01).

### Módulos

- `src/runtime/Signal.luau` — sistema de eventos genérico (Signal/Connection), reaproveitado por `Instance`, `Scheduler` e por `services`.
  - Superfície pública:
    ```luau
    export type Connection = {
        Connected: boolean,
        Disconnect: (self: Connection) -> (),
    }

    export type Signal<T...> = {
        Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
        Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
        Wait: (self: Signal<T...>) -> T..., -- yield cooperativo via Scheduler; ver nota abaixo
        DisconnectAll: (self: Signal<T...>) -> (),
    }

    -- Capacidade de disparo NÃO é exposta no tipo `Signal<T...>` público — só quem possui
    -- o objeto (Instance.luau, Scheduler.luau, uma classe de `services`) importa este tipo.
    export type FireableSignal<T...> = Signal<T...> & {
        Fire: (self: FireableSignal<T...>, T...) -> (),
    }

    local Signal = {}
    function Signal.new<T...>(): FireableSignal<T...> end
    return Signal
    ```
  - `Signal:Wait()` não usa `coroutine.yield` cru direto sem controle: internamente registra um `Once` e cede a coroutine chamadora através do mesmo mecanismo central que o `Scheduler` usa para resumir threads (ver Scheduler) — não é um yield "solto" fora do controle do Scheduler, senão `Scheduler.ThreadError`/contagem de threads vivas perderia rastro dessa thread.
  - Depende de: nada (raiz da árvore de módulos).
  - Usado por: `Instance.luau`, `Scheduler.luau`, `services` (para eventos próprios como `Touched`), `cli` (indiretamente, via tipos).

- `src/runtime/Instance.luau` — classe base `Instance`: hierarquia, eventos universais, propriedade genérica. É a **única** classe cujo comportamento `runtime` codifica por nome — não por violar a regra de "runtime nunca lê o dump", mas porque `Instance` é a base universal que toda classe herda (está no escopo explícito desta tarefa) e sua superfície é estável; `services` nunca precisa reimplementá-la.
  - Superfície pública (tipo consumido por `services`/`cli`, alcançável via `:` pelo script do usuário):
    ```luau
    export type Instance = {
        ClassName: string,      -- imutável, setado só na construção
        Name: string,
        Parent: Instance?,      -- atribuição intercepta via metatable (__newindex), dispara eventos — ver Fluxo de dados

        Changed: Signal<string>,                    -- (propertyName)
        ChildAdded: Signal<Instance>,
        ChildRemoved: Signal<Instance>,
        AncestryChanged: Signal<Instance, Instance?>,-- (child_ou_self, parentAtualDoChild)
        Destroying: Signal<()>,

        GetChildren: (self: Instance) -> { Instance },
        GetDescendants: (self: Instance) -> { Instance },
        FindFirstChild: (self: Instance, name: string, recursive: boolean?) -> Instance?,
        FindFirstChildOfClass: (self: Instance, className: string) -> Instance?,
        FindFirstChildWhichIsA: (self: Instance, className: string) -> Instance?,
        FindFirstAncestor: (self: Instance, name: string) -> Instance?,
        WaitForChild: (self: Instance, name: string, timeout: number?) -> Instance?,
        IsA: (self: Instance, className: string) -> boolean,
        IsDescendantOf: (self: Instance, ancestor: Instance?) -> boolean,
        IsAncestorOf: (self: Instance, descendant: Instance) -> boolean,
        ClearAllChildren: (self: Instance) -> (),
        Destroy: (self: Instance) -> (),
        GetFullName: (self: Instance) -> string,
    }
    ```
  - Superfície de **engenharia interna** (funções de módulo, `Instance.Foo(instance, ...)` — nunca aparecem na metatable `__index`, logo `instance:GetPropertyRaw(...)` falha para o script do usuário; só quem faz `require` direto do módulo, ou seja `runtime`/`services`, alcança):
    ```luau
    -- constrói só a base genérica; `services` envolve com campos tipados da classe concreta
    Instance.NewBase: (className: string, name: string?) -> Instance

    -- propriedade genérica: storage é `unknown` (tipo genuinamente desconhecido aqui — regra 01),
    -- `services` narrowa no getter/setter tipado que gera para cada classe concreta.
    Instance.GetPropertyRaw: (instance: Instance, name: string) -> unknown
    Instance.SetPropertyRaw: (instance: Instance, name: string, value: unknown) -> () -- dispara Changed

    -- resolvido uma única vez por `ClassRegistry.new` (ver módulo seguinte) para alimentar IsA
    -- sem Instance.luau precisar depender de ClassRegistry.luau (evita require circular).
    Instance.SetClassChain: (instance: Instance, chain: { string }) -> ()
    ```
  - Depende de: `Signal.luau`.
  - Usado por: `ClassRegistry.luau`, `DataModel.luau`, `Sandbox.luau`, e por `services` (via `require(runtime)`, nunca `require("runtime/Instance")` direto — ver Contrato).

- `src/runtime/Scheduler.luau` — `task.spawn/wait/delay/defer/cancel`, laço principal, `Heartbeat`/`Stepped`.
  - Superfície pública:
    ```luau
    export type TaskHandle = thread

    export type Scheduler = {
        Spawn: <A...>(self: Scheduler, fn: (A...) -> (), A...) -> TaskHandle,
        Defer: <A...>(self: Scheduler, fn: (A...) -> (), A...) -> TaskHandle,
        Delay: <A...>(self: Scheduler, seconds: number, fn: (A...) -> (), A...) -> TaskHandle,
        Wait: (self: Scheduler, seconds: number?) -> number, -- só válido de dentro de thread gerida pelo Scheduler
        Cancel: (self: Scheduler, handle: TaskHandle) -> (),

        Heartbeat: Signal<number>,        -- (deltaTime)
        Stepped: Signal<number, number>,  -- (time, deltaTime)
        ThreadError: Signal<thread, string>, -- fire toda vez que uma thread gerida erra; NUNCA silencioso

        Run: (self: Scheduler, shouldContinue: (() -> boolean)?) -> (), -- laço principal
        StepOnce: (self: Scheduler, dt: number) -> (),                  -- avança 1 frame manualmente (testes)
        IsAlive: (self: Scheduler) -> boolean, -- há thread viva ou conexão em Heartbeat/Stepped?
    }

    local Scheduler = {}
    function Scheduler.new(): Scheduler end
    return Scheduler
    ```
  - Ponto único de `coroutine.resume`: todo `Spawn`/`Defer`/`Delay`/retomada de `Wait` passa pelo mesmo laço interno de resume, protegido — se `coroutine.resume` retorna `false, err`, dispara `ThreadError:Fire(thread, err)` e **segue** (nunca propaga o erro pra fora, nunca derruba `Scheduler:Run()`). Essa é a garantia central da regra "erro de coroutine nunca é engolido silenciosamente nem derruba o processo": ela vive aqui, num único lugar, não espalhada.
  - `Run()` continua enquanto `IsAlive()` for verdadeiro (há `TaskHandle` pendente — spawnado, aguardando `Wait`/`Delay`/`Signal:Wait` — ou pelo menos uma `Connection` viva em `Heartbeat`/`Stepped`) e `shouldContinue()` (se passado) não retornar `false`. Script que roda e não deixa nada pendente termina o processo sozinho; script com `RunService.Heartbeat:Connect(...)` mantém o processo vivo. `cli` usa `shouldContinue` para plugar watch mode por cima.
  - Depende de: `Signal.luau`.
  - Usado por: `Sandbox.luau` (via `extraGlobals.task`), `services` (`RunService` se pendura em `Heartbeat`/`Stepped`), `cli` (chama `Run`).

- `src/runtime/ClassRegistry.luau` — registro central de classes; é o mecanismo de inversão de dependência que permite `services` "avisar" `runtime` de uma classe sem `runtime` conhecer o nome dela de antemão.
  - Superfície pública:
    ```luau
    export type ClassDescriptor = {
        ClassName: string,
        SuperClassName: string?,   -- nil = herda direto de Instance
        IsAbstract: boolean,       -- ex.: "Instance"/"PVInstance" não instanciáveis via .new
        IsService: boolean,        -- true = DataModel:GetService cria singleton sob a raiz
        Construct: (name: string?) -> Instance, -- factory de `services`; já devolve com campos tipados prontos
    }

    local ClassRegistry = {}
    function ClassRegistry.Register(descriptor: ClassDescriptor): () end        -- erro se ClassName já registrado
    function ClassRegistry.Get(className: string): ClassDescriptor? end
    function ClassRegistry.IsRegistered(className: string): boolean end
    function ClassRegistry.new(className: string, name: string?): Instance end -- ver contrato abaixo
    return ClassRegistry
    ```
  - `ClassRegistry.new(className, name)`: erro `"classe '%s' não registrada"` se `ClassRegistry.Get(className)` for `nil`; erro `"'%s' é abstrata, não pode ser instanciada"` se `IsAbstract`; senão resolve a cadeia de `SuperClassName` (para `IsA`), chama `descriptor.Construct(name)`, e faz `Instance.SetClassChain(instance, chain)` antes de devolver. É esta função — não `Instance.NewBase` direto — que vira o `Instance.new` que o sandbox expõe ao script do usuário (embrulhado por `services`, que pode diferenciar "não está no dump" de "está no dump mas não implementado ainda" nessa camada, sem `runtime` precisar saber a diferença).
  - Depende de: `Instance.luau` (para o tipo `Instance` e `Instance.SetClassChain`).
  - Usado por: `DataModel.luau`, `services` (chama `Register` uma vez por classe no load), `cli` (chama `new`/consulta via `Runtime.ClassRegistry`).

- `src/runtime/DataModel.luau` — raiz da árvore (equivalente a `game`).
  - Superfície pública:
    ```luau
    export type DataModel = Instance & {
        GetService: (self: DataModel, className: string) -> Instance, -- cria singleton se IsService e ainda não existe
        FindService: (self: DataModel, className: string) -> Instance?, -- nunca cria, só consulta
    }

    local DataModel = {}
    function DataModel.new(): DataModel end
    return DataModel
    ```
  - `GetService` parenteia o singleton criado diretamente sob a raiz com `Name == ClassName`, replicando o comportamento real do Roblox.
  - Depende de: `Instance.luau`, `ClassRegistry.luau`.
  - Usado por: `cli` (raiz de tudo), `services` (referência à raiz para pendurar singletons, se precisar).

- `src/runtime/Sandbox.luau` — executa Source de um Script do usuário isolado, nunca deixa erro escapar pro processo.
  - Superfície pública:
    ```luau
    export type OutputLevel = "print" | "warn" | "error"

    export type OutputRecord = {
        level: OutputLevel,
        message: string,
        scriptName: string?,
        line: number?,
        timestamp: number,
    }

    export type SandboxGlobals = { [string]: unknown } -- globals extra que `cli`/`services` injetam (game, workspace, script, require)

    export type SandboxOptions = {
        scriptName: string,   -- ex: "ServerScriptService.Main", usado em erro/print
        source: string,       -- Source do Script/ModuleScript, já lido do disco por `cli`
        scheduler: Scheduler.Scheduler,
        extraGlobals: SandboxGlobals?,
        onOutput: (record: OutputRecord) -> (), -- sink; `cli` decide como imprimir no terminal
    }

    export type SandboxResult = {
        thread: thread, -- handle devolvido por Scheduler:Spawn, útil pra Scheduler:Cancel
    }

    local Sandbox = {}
    function Sandbox.Run(options: SandboxOptions): SandboxResult end
    return Sandbox
    ```
  - Globals expostos por padrão (whitelist fixa, sem exceção por script): `task` (fechado sobre `options.scheduler`), `Instance` (só `{new = ...}` fechado sobre o `ClassRegistry.new` que `services`/`cli` decidem passar via `extraGlobals`, já que `runtime` puro nem tem classes registradas), `print`/`warn`/`error` redirecionados para `options.onOutput`, `coroutine`, `math`, `string`, `table`, `os.clock`/`os.time`, `bit32`, `utf8`, `typeof`, `tostring`/`tonumber`, `pcall`/`xpcall`/`assert`/`select`/`pairs`/`ipairs`/`next`. **Nunca** `fs`/`net`/`process`/`serde`/`io` cru do Lune — isso é o que separa o sandbox de simplesmente rodar o Lune puro.
  - Todo o Source roda como **uma thread gerida pelo `Scheduler`** (`Scheduler:Spawn`), nunca `coroutine.resume` fora do laço central — é assim que a garantia "erro nunca derruba o processo" se aplica também ao script de entrada, não só a `task.spawn` internos do próprio script.
  - Sandbox se inscreve em `scheduler.ThreadError`, mantém um mapa interno `{[thread]: scriptName}` (populado no `Spawn`) para anexar `scriptName`/linha ao formatar o `OutputRecord{level="error"}` antes de repassar a `onOutput`.
  - Depende de: `Scheduler.luau`, `Instance.luau` (tipos).
  - Usado por: `cli` (uma chamada por Script/LocalScript do projeto).

- `src/runtime/init.luau` — único ponto de entrada público. `services`/`cli` só fazem `require` deste arquivo, nunca de um módulo individual dentro de `src/runtime/`.
  - Superfície pública (agregador, re-exporta os tipos e as funções acima sob namespaces):
    ```luau
    local Runtime = {
        Signal = { new = Signal.new },
        Instance = {
            NewBase = InstanceModule.NewBase,
            GetPropertyRaw = InstanceModule.GetPropertyRaw,
            SetPropertyRaw = InstanceModule.SetPropertyRaw,
        },
        ClassRegistry = {
            Register = ClassRegistry.Register,
            Get = ClassRegistry.Get,
            IsRegistered = ClassRegistry.IsRegistered,
            new = ClassRegistry.new,
        },
        DataModel = { new = DataModel.new },
        Scheduler = { new = Scheduler.new },
        Sandbox = { Run = Sandbox.Run },
    }
    return Runtime
    ```
    Mais os `export type` re-exportados: `Signal<T...>`, `Connection`, `Instance`, `ClassDescriptor`, `DataModel`, `Scheduler`, `TaskHandle`, `SandboxOptions`, `SandboxResult`, `OutputRecord`, `OutputLevel`.
  - Depende de: todos os módulos acima.
  - Usado por: `services` (registra classes), `cli` (monta árvore, roda scripts).

### Contrato entre territórios

**`runtime` → `services`** (`services` só chama isto, nunca `require("runtime/Instance")` etc. direto):
```luau
local Runtime = require("../runtime")

Runtime.ClassRegistry.Register(descriptor: Runtime.ClassDescriptor): ()
Runtime.Instance.NewBase(className: string, name: string?): Runtime.Instance
Runtime.Instance.GetPropertyRaw(instance: Runtime.Instance, name: string): unknown
Runtime.Instance.SetPropertyRaw(instance: Runtime.Instance, name: string, value: unknown): ()
```
`services` chama `Register` uma vez por classe no carregamento do módulo (antes de `cli` popular qualquer árvore). Cada `Construct` de um `ClassDescriptor` usa `NewBase` + `Get/SetPropertyRaw` para montar os campos tipados da classe concreta, fazendo **um único `::` cast** no fim do construtor para reconciliar a tabela com metatable com o tipo público declarado (`local self = setmetatable(raw, WorkspaceMeta) :: Workspace`) — padrão idiomático de OOP em Luau estrito, não introduz `any` em lugar nenhum.

**`runtime` → `cli`** (`cli` só chama isto):
```luau
local Runtime = require("../runtime")

Runtime.DataModel.new(): Runtime.DataModel
Runtime.ClassRegistry.new(className: string, name: string?): Runtime.Instance
Runtime.Scheduler.new(): Runtime.Scheduler
Runtime.Sandbox.Run(options: Runtime.SandboxOptions): Runtime.SandboxResult
-- + .Parent (propriedade) para montar hierarquia, .GetService em DataModel
```
`cli` chama primeiro `DataModel.new()`, depois popula a árvore lendo `.project.json`/sourcemap (fora do escopo de `runtime`), depois cria `Scheduler.new()`, injeta `game`/`workspace`/`script`/`require` (do próprio `cli`) como `extraGlobals` em cada `Sandbox.Run`, e por fim chama `scheduler:Run(shouldContinue)`.

**Quem chama primeiro:** `services` registra todas as suas classes via `ClassRegistry.Register` **antes** de `cli` tentar `ClassRegistry.new` qualquer coisa — isso não é imposto por `runtime` (que não sabe a ordem), é uma invariante que `cli`'s bootstrap garante (`require("services")` primeiro, que roda os `Register` como efeito de carregar o módulo, só depois `require("cli")` monta a árvore).

### Fluxo de dados

1. `Full-API-Dump.json` (versão fixada, fora do escopo deste desenho) → gerador de `services` → um `ClassDescriptor` por classe coberta → `Runtime.ClassRegistry.Register(descriptor)` no load de `services`.
2. `.project.json`/sourcemap do Rojo (lido por `cli`) → `cli` chama `Runtime.DataModel.new()` e, para cada nó do projeto, `Runtime.ClassRegistry.new(className, name)`, setando `.Parent` para replicar a árvore exatamente como o Rojo descreve.
3. `Source` de cada `Script`/`LocalScript`/`ModuleScript` (lido do disco por `cli`) → `Runtime.Sandbox.Run({source=..., scriptName=..., scheduler=..., extraGlobals={game=dataModel, workspace=dataModel:GetService("Workspace"), script=instanciaDoScript}, onOutput=cli.Imprimir})`.
4. Dentro do sandbox, o script de usuário só enxerga a whitelist (ver módulo `Sandbox`) — nunca `fs`/`net`/`process`/`serde` cru do Lune, só o que `cli`/`services` decidiram injetar deliberadamente em `extraGlobals`.
5. Erro do script (síncrono ou dentro de `task.spawn`) → capturado no ponto único de `coroutine.resume` do `Scheduler` → `Scheduler.ThreadError:Fire(thread, err)` → `Sandbox` traduz para `OutputRecord{level="error", scriptName, message, timestamp}` → `cli.onOutput` imprime formatado, parecido com o Output do Studio.
6. `Scheduler:Run()` pulsa `Heartbeat`/`Stepped` a cada iteração do laço principal → `services`' `RunService` (fora deste desenho) se pendura nesses hooks e reexpõe sob o nome real do Roblox; o script do usuário nunca vê `Scheduler` diretamente, só `task.*`/o que `services` expuser como `RunService`.

### Divisão por território

| Território | O que constrói | Contrato com o vizinho |
|---|---|---|
| `runtime` (`src/runtime/`) | `Signal`, `Instance` base (única classe conhecida por nome, por ser universal), `ClassRegistry`, `DataModel`, `Scheduler`, `Sandbox`, `init.luau` agregador | Expõe `Runtime.*` via `require("runtime")` — ver Contrato acima. Nunca lê API Dump nem `.project.json`, nunca conhece nome de Service. |
| `services` (`src/services/`) | Gerador a partir do dump → `ClassDescriptor` por classe, registrado via `Runtime.ClassRegistry.Register`; getters/setters tipados por classe usando `Runtime.Instance.GetPropertyRaw/SetPropertyRaw` | Só consome `Runtime.*`; nunca importa `runtime/Instance.luau` etc. diretamente |
| `cli` (`src/cli/`) | Parser de `.project.json`/sourcemap, popula a árvore via `Runtime.DataModel.new()`/`Runtime.ClassRegistry.new()`, injeta `game`/`workspace`/`script` como `extraGlobals`, chama `Runtime.Sandbox.Run()` por script, decide formatação de `OutputRecord` no terminal | Só consome `Runtime.*`; usa `services` só através do registro central (nunca `require("services/Workspace")` direto) |

### Fidelidade vs. pragmatismo

- **Hierarquia/eventos (`Parent`, `Changed`, `ChildAdded`, `WaitForChild`)** — fidelidade alta: `WaitForChild` sem timeout bloqueia de verdade via `Scheduler` (nunca retorna `nil` cedo), eventos disparam via o mesmo `Signal` real usado em toda a árvore.
- **`task.wait`/`delay`/`spawn`/`defer`** — cooperativo de verdade (nunca `Sleep` de SO), mas o "clock" avança pelos passos do laço principal do LuauBench, não por vsync real do Roblox — `Heartbeat` não bate em 60Hz garantido. Aproximação documentada, não escondida.
- **`RenderStepped`** — pode nem disparar (sem render). Se `services` decidir disparar mesmo assim (ex: alias de `Heartbeat`), isso é aproximação documentada no código de `services`, não decisão implícita.
- **Propriedade genérica (`unknown` no storage + accessor tipado por classe em `services`)** — pragmatismo de engenharia de tipos, não de comportamento: concilia uma tabela de propriedades genérica com `--!strict`/sem `any`. Cada classe concreta gerada por `services` expõe campos honestamente tipados (`Gravity: number`), só a implementação interna usa `unknown` + um único `::` cast no construtor.
- **Ordem exata de eventos ao reparentar** (`Changed("Parent")` vs `AncestryChanged` vs `ChildAdded`/`ChildRemoved`) — desenho assume: (1) unlink/link interno → (2) `ChildRemoved` no pai antigo → (3) `ChildAdded` no pai novo → (4) `AncestryChanged` na instância e em cada descendente, raiz primeiro → (5) `Changed:Fire("Parent")` só na instância diretamente reparentada. **Esta ordem não foi confirmada contra o Roblox real nesta sessão** — fica marcada como pendência de `pesquisador` antes de `coder-runtime` fechar `Instance.luau` (ver Riscos).
- **Sem preempção real de coroutine travada** — divergência do watchdog do Roblox real (que mata thread por "exhausted execution time"); LuauBench, nesta fase, não tem confirmação de que Lune expõe algum hook de interrupção de VM para replicar isso. Ver Riscos.

### Riscos e decisões

- **Script trava (`while true do end` sem yield):** o laço de `coroutine.resume` do `Scheduler` é síncrono — uma coroutine que nunca cede trava a chamada de `resume` indefinidamente, o que trava `Scheduler:Run()` inteiro (processo LuauBench single-thread). Sem confirmação de que Lune/Luau expõem algum hook de interrupção de VM (contagem de instruções, deadline) chamável do lado do script, não há como preemptar isso de dentro do Luau puro. **Decisão:** documentar como limitação conhecida e aceita nesta fase (não silenciosa — vai no código e no relatório), e marcar para `pesquisador` confirmar se existe alternativa via Lune antes de qualquer tentativa de mitigação futura. Não implementar workaround pesado (ex: rodar o script engine inteiro num processo/thread do SO com timeout externo via `process` do Lune) nesta leva — ver "não fazer agora".
- **Erro de coroutine:** nunca escapa. Garantia centralizada no ponto único de `coroutine.resume` do `Scheduler`, que sempre dispara `ThreadError` em vez de propagar — testável isoladamente (conectar em `ThreadError`, spawnar uma função que dá erro, assertar que o sinal disparou e `Scheduler:Run()` não lançou).
- **`.project.json` inválido:** fora do território de `runtime` (regra 02 é explícita: quem lê e valida é `cli`). O contrato que `runtime` garante é que toda função pública (`ClassRegistry.new`, atribuição de `.Parent`, `GetService`) lança erro Luau estruturado e capturável — nunca corrompe a árvore silenciosamente nem retorna valor inconsistente — para que `cli` consiga formatar a mensagem certa apontando o campo problemático do projeto.
- **Mecanismo exato de isolamento de globals do `Sandbox`:** este desenho assume que existe alguma forma de compilar/rodar um chunk Luau dentro do mesmo processo Lune com uma tabela de globals restrita (sem `fs`/`net`/`process`/`serde`) — por exemplo via a biblioteca `@lune/luau` do próprio Lune, que (segundo o que se sabe do Lune, não confirmado nesta sessão) permite `load`/`compile` de código com um `environment` customizado. **Não confirmado nesta sessão** — `pesquisador` precisa validar a API exata (nome da função, formato dos parâmetros) antes de `coder-runtime` implementar `Sandbox.luau`. Se a premissa cair, o desenho do `Sandbox` precisa voltar ao `arquiteto`.
- **Ordem de eventos Parent/Changed/ChildAdded/AncestryChanged:** ver Fidelidade vs. pragmatismo — assumida, pendente de confirmação de `pesquisador`/validação de `revisor-runtime` contra o comportamento documentado do Roblox.
- **`Instance.new` de classe não registrada:** erro claro `"classe '%s' não registrada"` (genérico, de `ClassRegistry.new`) — nunca `nil` silencioso. Diferenciar "não existe no dump" de "existe no dump mas não implementado ainda" é decisão de `services` (regra 03), que pode pré-registrar descritores com `Construct` que erra "ainda não simulado no LuauBench" para classes conhecidas-mas-pendentes.
- **Dependência circular evitada de propósito:** `Instance.luau` **não** importa `ClassRegistry.luau` (que precisaria pra resolver `IsA` andando a cadeia de superclasses) — em vez disso, `ClassRegistry.new` resolve a cadeia uma vez na construção e grava via `Instance.SetClassChain`, e `IsA` só consulta esse cache local. Isso evita um require circular entre dois arquivos do mesmo território.

### O que deliberadamente NÃO fazer agora

- `Instance:Clone()` — depende de saber clonar campos tipados por classe, que só `services` conhece; fica para quando houver ao menos uma classe concreta gerada.
- Qualquer preempção forçada de coroutine travada (watchdog tipo "script exhausted execution time" do Roblox) — risco aceito e documentado, não mitigado nesta leva.
- `RenderStepped` "de verdade" atrelado a frame de render — não há render neste projeto.
- Replicação client/server (múltiplos `DataModel`, rede entre eles) — fora do escopo total do projeto por ora.
- Persistência do `DataModel` entre execuções do watch mode — recarregar do zero a cada mudança é aceitável nesta fase (nota já prevista na regra 04, não é decisão nova daqui).
- Ordem de execução entre múltiplos Scripts replicando exatamente a ordem real do Roblox (ex: prioridade `ServerScriptService` vs `StarterPlayerScripts`) — nesta fase, `cli` decide a ordem de disparo dos `Sandbox.Run`, sem garantia formal de paridade com o Roblox real; se isso importar, é uma tarefa própria depois, não implícita aqui.

---

## Revisão pós-integração 2026-09-04 — contrato Wait/resume

Motivada pelos dois achados GRAVE de `.claude/agents-memory/revisor-runtime-signal-instance-scheduler-2026-09-04.md`, ambos reproduzidos empiricamente. Esta seção **substitui** os pontos do desenho acima explicitamente listados em "Correções ao texto acima". Todo o resto do desenho continua valendo — nenhuma API pública de `runtime` para `services`/`cli` muda.

### Diagnóstico: falta um dono único da suspensão

O desenho original definiu um **ponto único de `coroutine.resume`** (dentro de `Scheduler.luau`) mas não definiu um **ponto único de `coroutine.yield`**. Consequência: quem precisa suspender uma thread (`Signal:Wait`, `Instance:WaitForChild` com timeout) não tem por onde falar com o Scheduler, porque o desenho proibiu esses módulos de importarem `Scheduler.luau` — e a proibição estava certa (evita ciclo de require), mas a saída de emergência que ela forçou (cada um inventar seu próprio par yield/resume) é o que quebrou.

Os dois achados GRAVE, o achado ALTO 4 (`ThreadError` com a thread errada) e o achado ALTO 3 (`Fire` abortando os listeners seguintes) são **um só problema**: não existe canal pelo qual um módulo-folha diga "suspenda esta thread / retome esta thread / este erro é desta thread" sem conhecer quem é o driver.

A correção é a mesma inversão de dependência que o desenho já usa para `IsA` (`Instance.SetClassChain` em vez de `Instance` → `ClassRegistry`): um **módulo-folha compartilhado, menor que `Scheduler.luau`**, no qual o driver se registra.

### Decisão: `ThreadBroker.luau` (módulo novo, folha da árvore)

Nem `Scheduler:Await(signal)` nem injeção de função por parâmetro. Razões:

- **`Scheduler:Await(signal)` não resolve nada** — o script do usuário escreve `event:Wait()` / `obj:WaitForChild(n)`, nunca `scheduler:Await(...)`. Adicionar `Await` deixaria a superfície fiel ao Roblox (`Wait`) exatamente igual de quebrada e criaria dois jeitos de esperar. **Rejeitado.**
- **Injeção de função por parâmetro** exigiria propagar um handle de scheduler por dentro de `Signal.new`, de `Instance.NewBase` e de todo `Construct` de `services` — vaza orquestração para toda a árvore de tipos. **Rejeitado.**
- **`ThreadBroker`** resolve por identidade de thread: quem suspende pergunta "esta thread tem dono?" e o dono aparece sozinho. Custa um arquivo de ~70 linhas sem dependência nenhuma de módulo do runtime, e `services` não precisa saber que ele existe — um `Signal` criado por `services` (ex: `Touched`) passa a cooperar com o Scheduler de graça.

Grafo de dependências resultante (continua acíclico):

```
ThreadBroker.luau   → (nada; só @lune/task NÃO — ver abaixo)
Signal.luau         → ThreadBroker
Instance.luau       → Signal, ThreadBroker, @lune/task (só no caminho standalone de WaitForChild)
Scheduler.luau      → Signal, ThreadBroker, @lune/task
```

`ThreadBroker.luau` não importa `@lune/task`: o fallback de tempo real fica em `Instance.luau` (onde já está hoje) e o fallback de resume é `coroutine.resume` cru. Assim o broker fica genuinamente sem dependências.

### Módulo novo: `src/runtime/ThreadBroker.luau`

Responsabilidade em uma linha: dizer quem é o dono de uma thread e rotear retomada/agendamento/erro para esse dono, com fallback correto quando não há dono.

```luau
--!strict

-- Argumentos empacotados (mesmo formato interno que Scheduler.luau já usa em Delay/Defer).
-- Trafegar os args como TABELA, e não como pack variádico, é deliberado: mantém o tipo
-- honesto (`unknown`, nunca `any`) sem tentar casar um pack genérico `T...` com `...unknown`.
export type PackedArgs = { n: number, [number]: unknown }

-- Implementado por Scheduler.luau (hoje o único driver do projeto). ThreadBroker NUNCA
-- importa Scheduler.luau — é o driver que se registra, invertendo a dependência.
export type Driver = {
    -- Retoma `co` pelo ponto único de resume do driver. Contrato obrigatório:
    -- (a) NUNCA propaga erro para quem chamou (converte em ThreadError e segue);
    -- (b) é no-op silencioso se `coroutine.status(co) ~= "suspended"` (corrida entre
    --     deadline e evento não pode virar erro espúrio de "cannot resume dead coroutine");
    -- (c) `args == nil` significa retomar sem argumentos.
    Resume: (co: thread, args: PackedArgs?) -> (),

    -- Agenda a retomada de `co` daqui a `seconds` NO RELÓGIO DO DRIVER (nunca em timer
    -- nativo do Lune). Devolve um cancelador idempotente; cancelar depois de já ter
    -- acordado é no-op.
    WakeAfter: (co: thread, seconds: number) -> (() -> ()),

    -- Canal central de erro do driver (vira ThreadError no Scheduler).
    ReportError: (co: thread, message: string) -> (),
}

local ThreadBroker = {}

-- Chamado pelo driver uma vez por thread que ele cria (Spawn/Defer/Delay).
function ThreadBroker.Adopt(co: thread, driver: Driver): () end
function ThreadBroker.Release(co: thread): () end

function ThreadBroker.DriverOf(co: thread): Driver? end
function ThreadBroker.IsManaged(co: thread): boolean end

-- Retoma `co`: pelo driver dono se houver; senão `coroutine.resume` cru, re-lançando o erro
-- via `error(err, 0)` — exatamente o comportamento de hoje, que é o que mantém `Signal`
-- utilizável sem Scheduler (Signal.spec.luau, 6/6, não pode quebrar).
function ThreadBroker.Resume(co: thread, args: PackedArgs?): () end

-- Entrega uma falha ao driver dono de `co`. Devolve `true` se algum driver assumiu o erro,
-- `false` se não há dono — nesse caso quem chamou decide (Signal acumula e re-lança DEPOIS
-- de rodar todos os listeners; ver patch de Fire).
function ThreadBroker.ReportError(co: thread, message: string): boolean end

return ThreadBroker
```

Armazenamento interno: `local drivers: { [thread]: Driver } = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [thread]: Driver }` — mapa fraco por chave, mesmo padrão (e mesmo cast em duas etapas por `unknown`, nunca `any`) já usado em `Instance.luau:74`. **Validado com `luau-lsp analyze --platform=standard`: tipa limpo.**

Fallback de `ThreadBroker.Resume` sem driver (comportamento idêntico ao de hoje):

```luau
if coroutine.status(co) ~= "suspended" then return end
local ok, err = if args == nil then coroutine.resume(co) else coroutine.resume(co, table.unpack(args, 1, args.n))
if not ok then error(err, 0) end
```

### Patch em `src/runtime/Signal.luau`

**Tipos públicos `Signal<T...>`/`FireableSignal<T...>`/`Connection`: inalterados.** Muda só o corpo de dois campos.

1. `Wait` (linhas 88-97) — trocar o `coroutine.resume` direto por roteamento pelo broker:

```luau
Wait = function(_self: Signal<T...>): T...
    local co = coroutine.running()
    connect(listeners, function(...: T...)
        -- Se esta thread é gerida por um Scheduler, quem retoma é o ponto único de resume
        -- dele (liveThreads e ThreadError ficam corretos); sem driver, o broker faz o
        -- coroutine.resume cru — mesmo comportamento de hoje, uso standalone preservado.
        ThreadBroker.Resume(co, table.pack(...) :: ThreadBroker.PackedArgs)
    end, true)
    return coroutine.yield()
end,
```

`table.pack(...) :: PackedArgs` sobre um pack genérico `T...` e `return coroutine.yield()` devolvendo `T...` foram **validados com `luau-lsp analyze`: tipam limpo** (é o mesmo cast que `Scheduler.luau:323` já usa).

2. `Fire` (linhas 106-127) — isolar listeners entre si (achado ALTO 3, decisão do arquiteto pedida pelo revisor: **sim, isolar**):

```luau
local pendingError: string? = nil
for _, listener in snapshot do
    if listener.Connected then
        if listener.once then <auto-disconnect, como hoje> end
        -- ATENÇÃO ao escrever isto: `pcall(listener.callback, ...)` NÃO tipa em --!strict
        -- (o stub do pcall dá "Function only returns 1 value, but 2 are required here"
        -- quando a função protegida retorna `()` — verificado com luau-lsp). A forma que
        -- tipa limpo é a mesma já usada em Scheduler.fireProtected: closure com pack
        -- variádico explícito. O custo é uma closure por listener por Fire — aceito.
        local ok, err = pcall(function(...: T...)
            listener.callback(...)
        end, ...)
        if not ok then
            local message = tostring(err)
            if not ThreadBroker.ReportError(coroutine.running(), message) and pendingError == nil then
                pendingError = message
            end
        end
    end
end
if pendingError ~= nil then
    error(pendingError, 0)
end
```

Efeito: erro num listener **nunca** cancela os listeners seguintes do mesmo disparo (fidelidade ao Roblox, onde cada conexão roda na própria coroutine). Se há driver, cada erro vira `ThreadError` na hora e o laço segue; se não há, o primeiro erro é re-lançado **depois** do laço, preservando "erro escapa de `Fire`" para o uso standalone e para o `fireProtected` do Scheduler.

Nenhum dos 6 testes de `Signal.spec.luau` toca erro de listener nem depende do momento exato do resume sem driver — **os 6 continuam passando** (o teste 6, `Fire` seguido de `assert(finished)` na mesma linha de execução, depende do resume síncrono, que o fallback sem driver mantém).

### Patch em `src/runtime/Instance.luau`

**Tipo público `Instance`: inalterado.** Muda só o ramo `timeout ~= nil` de `WaitForChild` (linhas 380-418) e o comentário de cabeçalho.

Passa a existir **dois caminhos, escolhidos por `ThreadBroker.IsManaged(coroutine.running())`**:

```luau
function Methods.WaitForChild(self: Instance, name: string, timeout: number?): Instance?
    local existing = Methods.FindFirstChild(self, name)
    if existing ~= nil then return existing end

    local data = getInternal(self)

    -- (A) SEM timeout: inalterado. `childAdded:Wait()` num laço; agora o resume passa pelo
    -- driver automaticamente (patch de Signal.luau), sem Instance.luau saber quem é o driver.
    if timeout == nil then
        while true do
            local child = data.childAdded:Wait()
            if getInternal(child).name == name then return child end
        end
    end

    local co = coroutine.running()
    local driver = ThreadBroker.DriverOf(co)

    -- (B) COM timeout, thread GERIDA: um único yield; quem acorda é o driver, pelas filas
    -- dele. Zero timer nativo do Lune envolvido -> os dois schedulers deixam de competir.
    if driver ~= nil then
        local settled = false
        local found: Instance? = nil
        local cancelDeadline: (() -> ())? = nil
        local connection: SignalModule.Connection
        connection = data.childAdded:Connect(function(child: Instance)
            if settled or getInternal(child).name ~= name then return end
            settled = true
            found = child
            connection:Disconnect()
            if cancelDeadline ~= nil then cancelDeadline() end
            ThreadBroker.Resume(co, nil)
        end)
        cancelDeadline = driver.WakeAfter(co, timeout :: number)
        coroutine.yield()
        if not settled then
            settled = true
            connection:Disconnect()
        end
        return if found ~= nil then found else Methods.FindFirstChild(self, name)
    end

    -- (C) COM timeout, thread NÃO gerida: polling com `@lune/task` — o código de hoje,
    -- linha por linha. É o caminho dos testes de Instance.spec.luau (que chamam WaitForChild
    -- do chunk principal do Lune, onde um `coroutine.yield()` cru não teria quem retomasse)
    -- e continua correto justamente porque, sem Scheduler simulado, não há competição.
    <bloco atual, sem alteração>
end
```

Por que manter (C) em vez de unificar: no chunk principal do Lune a coroutine já pertence ao scheduler do próprio Lune — suspendê-la com `coroutine.yield()` e retomá-la por fora é exatamente a classe de bug que esta revisão existe para eliminar. `IsManaged` é o discriminador honesto: "existe um dono que sabe retomar isto?".

Também atualizar o comentário de cabeçalho (linhas 13-16) e o bloco de RISCO das linhas 380-407: a decisão "não importar `Scheduler.luau`" **continua valendo** (`Instance.luau` importa `ThreadBroker.luau`, folha sem dependências, nunca `Scheduler.luau`), mas o texto que apresenta o polling nativo como a única saída está obsoleto e o achado GRAVE 1 precisa ficar registrado como resolvido, não como risco aberto. Registrar também a dependência de `@lune/task` (achado BAIXO 6).

### Patch em `src/runtime/Scheduler.luau`

**Tipo público `Scheduler`: inalterado — nenhum método novo, nenhuma assinatura mudada.** O driver é construído dentro de `Scheduler.new()` e vive só no estado interno.

1. `type WaitingEntry` ganha `cancelled: boolean`; `resumeDueWaiting` pula entradas com `cancelled == true` (fecha a corrida em que o evento resolve o waiter **depois** de `resumeDueWaiting` já ter tirado a entrada da fila para a lista local `due`).
2. `type Internal` ganha `driver: ThreadBroker.Driver`.
3. `resumeThread` ganha guarda de status na entrada:

```luau
local function resumeThread<A...>(self: Internal, co: thread, ...: A...)
    if coroutine.status(co) ~= "suspended" then
        -- Já retomada/morta por outro caminho (corrida deadline × evento). Só poda o
        -- bookkeeping — nunca dispara ThreadError espúrio de "cannot resume dead coroutine".
        if coroutine.status(co) == "dead" then
            self.liveThreads[co] = nil
            ThreadBroker.Release(co)
        end
        return
    end
    local ok, err = coroutine.resume(co, ...)
    if not ok then
        self.liveThreads[co] = nil
        ThreadBroker.Release(co)
        self.threadErrorSignal:Fire(co, tostring(err))
        return
    end
    if coroutine.status(co) == "dead" then
        self.liveThreads[co] = nil
        ThreadBroker.Release(co)
    end
end
```

4. `trackThread` passa a fazer `ThreadBroker.Adopt(co, self.driver)` além de `liveThreads[co] = true`; `Cancel` passa a fazer `ThreadBroker.Release(handle)`.
5. `IsAlive` poda threads mortas antes de responder (rede de segurança pedida pelo revisor — com o roteamento acima ela não é mais o mecanismo principal, mas protege contra qualquer `coroutine.resume` de terceiros sobre uma thread gerida):

```luau
function Scheduler.IsAlive(self: Internal): boolean
    for co in self.liveThreads do
        if coroutine.status(co) == "dead" then
            self.liveThreads[co] = nil
            ThreadBroker.Release(co)
        end
    end
    if next(self.liveThreads) ~= nil then return true end
    return self.heartbeatHasConnections() or self.steppedHasConnections()
end
```

6. `Scheduler.new()` constrói o driver antes de `raw` (forward-declare `local raw: Internal`, mesmo padrão de `local self: FireableSignal<T...>` em `Signal.new`):

```luau
local raw: Internal
local driver: ThreadBroker.Driver = {
    Resume = function(co: thread, args: ThreadBroker.PackedArgs?)
        if args == nil then
            resumeThread(raw, co)
        else
            resumeThread(raw, co, table.unpack(args, 1, args.n))
        end
    end,
    WakeAfter = function(co: thread, seconds: number): () -> ()
        local entry: WaitingEntry = { thread = co, wakeAt = raw.time + math.max(seconds, 0), cancelled = false }
        table.insert(raw.waiting, entry)
        local cancelled = false
        return function()
            if cancelled then return end
            cancelled = true
            entry.cancelled = true
            local index = table.find(raw.waiting, entry)
            if index then table.remove(raw.waiting, index) end
        end
    end,
    ReportError = function(co: thread, message: string)
        raw.threadErrorSignal:Fire(co, message)
    end,
}
raw = { ..., driver = driver }
```

O cancelador remove **por identidade da entrada**, nunca por thread — `removeFromQueues` (usado por `Cancel`) continua removendo por thread, e as duas disciplinas não podem se confundir.

7. `fireProtected` **fica** — vira rede de segunda linha (o erro de continuação de `Wait` já não chega mais nele; o que ainda chega é erro genuíno de callback de listener re-lançado por `Fire` quando não há driver dono da thread hospedeira).
8. Achado MÉDIO 5: linha 432, `:: any` → `:: unknown` (o revisor já provou que tipa limpo).

### Correções ao texto acima (o que desta revisão substitui o desenho original)

| Linha/seção original | O que muda |
|---|---|
| `Signal.luau` — "Depende de: nada (raiz da árvore de módulos)" | Depende de `ThreadBroker.luau`, que passa a ser a raiz |
| `Signal.luau` — nota sobre `Wait` usar "o mesmo mecanismo central que o Scheduler usa" | Deixa de ser intenção e vira mecanismo concreto: `ThreadBroker.Resume` |
| `Instance.luau` — "Depende de: `Signal.luau`" | Depende de `Signal.luau`, `ThreadBroker.luau` e `@lune/task` (só no caminho (C)) |
| Riscos — "Dependência circular evitada de propósito" | Continua valendo para `ClassRegistry`; para `Scheduler` a saída passa a ser o broker, não "cada um inventa seu yield" |
| Fidelidade — "`WaitForChild` sem timeout bloqueia de verdade via `Scheduler`" | Passa a valer também **com** timeout, quando a thread é gerida |
| `init.luau` | **Não** reexporta `ThreadBroker` — é plumbing interno de `runtime`; `services`/`cli` nunca o tocam |

### Fidelidade vs. pragmatismo (entradas novas)

- **Retomada de `Wait` é imediata (síncrona, dentro da pilha do `Fire`), não diferida.** Isso corresponde ao modo `SignalBehavior = Immediate` do Roblox; o padrão de lugares novos é `Deferred` (retomada no próximo resumption point). Escolhido `Immediate` porque (a) é o comportamento que os 30 testes existentes já assumem, (b) é a mudança mínima, e (c) com tudo roteado pelo driver, migrar para `Deferred` depois vira uma alteração de política **dentro de `Driver.Resume`**, em um lugar só, sem tocar `Signal.luau` nem `Instance.luau`. **A correspondência exata `Immediate`/`Deferred` não foi confirmada nesta sessão — pendência de `pesquisador`.**
- **Timeout de `WaitForChild` em thread gerida é medido no relógio do Scheduler, não no wall-clock.** Sob `Run()` os dois coincidem (o `dt` vem de `os.clock()`); sob `StepOnce(dt)` o timeout passa a ser determinístico e simulado — ganho de testabilidade, e uma divergência real do Roblox que precisa ficar escrita no código.
- **Erro em callback de listener é atribuído à thread que disparou o `Fire`**, não a uma coroutine própria daquela conexão. LuauBench não cria uma coroutine por conexão (seria redesenho maior, e cada `Fire` de `Heartbeat` alocaria N coroutines por frame). Divergência documentada; a atribuição de erro de **continuação de `Wait`** — que era o caso realmente danoso — passa a ser correta.
- **Uma thread gerida suspensa num `Signal` que nunca dispara mantém `IsAlive()` verdadeiro para sempre**, logo `Run()` não termina. É fiel ao Roblox (um script parado em `WaitForChild` mantém o jogo rodando) e não é regressão; a válvula prática é o `shouldContinue` que `cli` já passa.

### Testes de integração exigidos (novo `src/runtime/Integration.spec.luau`)

Nenhum spec atual exercita dois módulos reais juntos — foi por isso que os bugs passaram. Obrigatórios antes de re-submeter à revisão:

1. `Spawn` + `scheduler.Heartbeat:Wait()` + `StepOnce` → thread termina **e** `IsAlive() == false`.
2. `Spawn` + `WaitForChild` sem timeout + `child.Parent = parent` → resolve **e** `IsAlive() == false`.
3. `Run()` **sem** `shouldContinue` termina sozinho nos dois casos acima (o teste pode ter guarda de tempo, mas precisa assertar que não foi a guarda que parou o laço).
4. `WaitForChild(nome, 0.05)` dentro de `Run()` → devolve `nil` com wall-clock decorrido dentro de `[0.05, 0.5]` (é o repro exato do GRAVE 1, que hoje não resolve em 2s).
5. `WaitForChild(nome, 5)` sob `StepOnce` determinístico: 4 × `StepOnce(1)` ainda esperando; o 5º resolve `nil`.
6. `Heartbeat:Wait()` seguido de `error(...)` → `ThreadError` recebe **o handle devolvido por `Spawn`**, não a thread hospedeira (achado ALTO 4).
7. Corrida deadline × `ChildAdded` no mesmo tique → resultado único, **zero** `ThreadError` espúrio de "cannot resume dead coroutine".
8. Erro no primeiro de dois listeners → o segundo roda mesmo assim (achado ALTO 3).
9. Regressão: `Signal.spec` 6/6 e `Instance.spec` 24/24 continuam passando **sem nenhuma alteração nesses arquivos**. Se algum precisar mudar, o patch está errado — voltar ao arquiteto.

### Riscos residuais

- **Reentrância**: `Fire` → `Driver.Resume` → `resumeThread` → thread acorda → dispara outro `Signal` → `Fire` de novo. `resumeThread` é reentrante (só mexe em `liveThreads` e no broker) e a guarda de status impede resume duplo, mas uma cadeia patológica de eventos pode empilhar. Não há limite de profundidade nesta fase — aceito, documentado; se aparecer stack overflow em uso real, o remédio é migrar `Driver.Resume` para o modo diferido (que já está previsto como troca de uma política em um lugar só).
- **Thread criada pelo script do usuário com `coroutine.create`/`coroutine.wrap` cru** não é adotada pelo broker, então um `Wait()` nela cai no fallback standalone. É o comportamento razoável (no Roblox, coroutine crua também não é thread do task scheduler), mas fica registrado como divergência a confirmar.
- **`WaitForChild` reagindo a `Name` mudando** (no Roblox real, renomear um filho existente para o nome esperado também resolve o `WaitForChild`): não coberto nem antes nem depois deste patch — só `ChildAdded`. Pendência de `pesquisador` + tarefa própria, fora do escopo desta correção.

### O que deliberadamente NÃO fazer agora

- **Não** adicionar `Scheduler:Await(signal)` nem qualquer método público novo em `Scheduler`/`Signal` — a correção inteira é interna.
- **Não** migrar para retomada diferida (`SignalBehavior = Deferred`) nesta leva — decidido acima, com o caminho de migração deixado pronto num ponto só.
- **Não** dar uma coroutine por conexão de `Signal` (fidelidade máxima de isolamento entre listeners) — custo por frame alto demais para o ganho nesta fase.
- **Não** reescrever `Signal.luau`/`Instance.luau`/`Scheduler.luau` do zero: são três patches cirúrgicos sobre arquivos que já passam nos próprios testes.
- **Não** expor `ThreadBroker` em `src/runtime/init.luau`.

---

## Revisão pós-integração 2026-09-04 (2) — contrato `ClassDescriptor.Construct`

Motivada pelo achado ALTO de `.claude/agents-memory/revisor-runtime-classregistry-2026-09-04.md`, reproduzido empiricamente pelo revisor. Esta seção **substitui** os pontos do desenho original listados em "Correções ao texto acima (2)". Nenhuma outra parte do desenho muda.

### Diagnóstico: o construtor cria o objeto que ele mesmo ainda não pode descrever

`ClassRegistry.new` hoje faz, nesta ordem: `resolveClassChain` → `descriptor.Construct(name)` → `Instance.SetClassChain`. Como é o `Construct` de `services` que chama `Instance.NewBase` lá dentro, a instância nasce com o chain default de `NewBase` (`{ClassName, "Instance"}`, `Instance.luau:534`) e só recebe a cadeia real **depois** que `Construct` já retornou. Durante a janela do `Construct`, `IsA` de qualquer ancestral indireto mente.

Mas `IsA` é só o sintoma mais visível. A mesma inversão de responsabilidade produz outros três buracos, todos silenciosos, todos herdados por `services`:

1. **`ClassName` pode divergir do descriptor.** Nada impede um `Construct` de chamar `NewBase("Prt", name)` num descriptor cujo `ClassName` é `"Part"`. A instância fica com `ClassName == "Prt"` e um `classChain` que começa em `"Part"` — dois valores contraditórios na mesma instância, sem erro.
2. **Identidade da tabela é um contrato implícito e não checado.** `Instance.SetClassChain` chama `getInternal`, que só encontra estado para a tabela exata criada por `NewBase` (`internals` é indexado pela identidade, `Instance.luau:81`). Um `Construct` que devolva um wrapper novo em vez da tabela do `NewBase` faz `ClassRegistry.new` estourar com um erro de `getInternal`, que não diz nada sobre a causa real.
3. **Default de `Name` fica replicado.** `NewBase` já resolve `name == nil` → `className`. Com `Construct` fazendo a chamada, cada uma das dezenas de classes de `services` precisa lembrar de repassar `name` corretamente para ganhar esse default.

Um único ponto de desenho causa os quatro: **quem cria a instância base não é quem conhece as invariantes dela.**

### Decisão: `ClassRegistry.new` cria a base; `services` só configura

`ClassRegistry.new` passa a chamar `Instance.NewBase` e `Instance.SetClassChain` ele mesmo, **antes** de entregar a instância pronta ao descriptor. O descriptor deixa de ser factory e vira inicializador.

Alternativas rejeitadas:

- **Só documentar a limitação** (opção 1 do revisor). Rejeitada: empurra uma pegadinha não verificável para dezenas de arquivos gerados. Um `Construct` que consulte `IsA` errado não falha — decide errado em silêncio, que é exatamente o que a invariante 2 da regra 00 proíbe. E não resolve os três buracos adicionais acima.
- **`Construct: (name: string?, chain: {string}) -> Instance`, com `services` chamando `SetClassChain`** (opção 2 do revisor). Rejeitada: transforma "a cadeia precisa estar aplicada antes do corpo rodar" numa obrigação que cada classe pode esquecer, e esquecer é silencioso. A invariante tem que morar no único lugar que consegue garanti-la.
- **Manter `Construct` e só reordenar** não é possível: não existe instância para marcar antes de `Construct` rodar. A reordenação exige a inversão.

### Assinatura nova

```luau
export type ClassDescriptor = {
    ClassName: string,
    SuperClassName: string?,   -- nil = herda direto de Instance
    IsAbstract: boolean,
    IsService: boolean,

    -- Chamado por ClassRegistry.new SOBRE uma instância base JÁ criada e JÁ com a cadeia de
    -- classes aplicada — logo `instance:IsA(qualquerAncestral)` é confiável aqui dentro.
    -- Só configura: não cria, não devolve nada. `instance.Name` já vem preenchido (o `name`
    -- passado a ClassRegistry.new, ou o ClassName como default).
    -- Opcional: classe sem propriedade default nem método próprio dispensa a função inteira.
    Initialize: ((instance: Instance) -> ())?,
}
```

`Construct` → `Initialize` é rename deliberado, não cosmético: um campo chamado `Construct` que recebe algo já construído e devolve `()` mente sobre o próprio papel, e o rename faz qualquer código escrito contra o contrato antigo virar erro de tipo em vez de mudança silenciosa de comportamento. Custo zero — `services` não existe, e o único call site é `ClassRegistry.luau` + seu spec.

`Initialize` opcional reduz atrito no gerador: uma classe do dump sem propriedade default vira um descriptor de 4 campos, sem função nenhuma. Um typo (`Initalize`) não passa despercebido — em `--!strict` um campo desconhecido num literal tipado como `ClassDescriptor` é erro do checker.

### Corpo novo de `ClassRegistry.new`

```luau
function ClassRegistry.new(className: string, name: string?): Instance
    local descriptor = registry[className]
    if descriptor == nil then
        error(`classe '{className}' não registrada`, 2)
    end
    if descriptor.IsAbstract then
        error(`'{className}' é abstrata, não pode ser instanciada`, 2)
    end

    -- Ordem obrigatória, é o ponto inteiro desta correção: resolver a cadeia, criar a base e
    -- APLICAR a cadeia antes de qualquer código de `services` rodar. Assim `IsA` já responde
    -- pela cadeia completa dentro do próprio Initialize (achado ALTO da revisão de
    -- task-runtime-004), e ClassName/identidade/Name ficam garantidos aqui, não confiados a
    -- dezenas de classes geradas.
    local chain = resolveClassChain(descriptor)
    local instance = InstanceModule.NewBase(className, name)
    InstanceModule.SetClassChain(instance, chain)

    if descriptor.Initialize ~= nil then
        descriptor.Initialize(instance)
    end

    return instance
end
```

Sem `pcall` em volta de `Initialize`: erro em construtor de classe é erro real e sobe para quem chamou (`cli`/Sandbox), como no Roblox. A base meio-inicializada fica sem referência e é coletada pelo GC — `internals` é mapa fraco por chave (`Instance.luau:81`), não precisa de limpeza explícita.

### Como `services` escreve uma classe (padrão canônico — substitui o do desenho original)

O desenho original dizia que o `Construct` fecharia com `setmetatable(raw, WorkspaceMeta) :: Workspace`. **Isso está errado e não deve ser escrito**: trocar a metatable da instância remove `InstanceMeta`, e com ela todo o roteamento de `__index`/`__newindex` (`Instance.luau:472-523`) — os métodos de `Instance`, a interceptação de `Parent`/`Name` e o storage genérico de propriedades param de funcionar de uma vez. `services` **nunca** chama `setmetatable` numa instância.

Não precisa: `InstanceMeta.__index` já cai em `data.properties[key]` para qualquer chave desconhecida, e `__newindex` já grava em `data.properties[key]` disparando `Changed`. Uma classe concreta é, portanto, **um tipo Luau + valores default semeados**:

```luau
local Runtime = require("../runtime")

export type Workspace = Runtime.Instance & {
    Gravity: number,
}

Runtime.ClassRegistry.Register({
    ClassName = "Workspace",
    SuperClassName = "Model",
    IsAbstract = false,
    IsService = true,
    Initialize = function(instance: Runtime.Instance)
        -- Cast único por classe. Se o checker recusar o cast direto (Instance -> interseção),
        -- usar o padrão de duas etapas por `unknown` já usado em Instance.luau:82,544 —
        -- nunca `any` (regra 01).
        local self = (instance :: unknown) :: Workspace
        self.Gravity = 196.2
    end,
})
```

Semear propriedade dispara `Changed` durante o `Initialize`. É inofensivo por construção: a instância acabou de nascer dentro de `ClassRegistry.new` e ainda não tem referência fora dela, então não existe `Connection` possível nesse instante.

**`Initialize` não deve setar `Parent`.** Quem parenteia é o chamador (`cli` montando a árvore do Rojo, `DataModel:GetService` pendurando o singleton na raiz). Regra de contrato documentada, não imposta em runtime — se alguma classe de `services` precisar violar isso, volta ao arquiteto em vez de virar exceção local.

### Consequência: `Runtime.Instance.NewBase` sai da superfície pública

`src/runtime/init.luau` (ainda não escrito — task-runtime-007) **não** deve reexportar `NewBase`. Com a inversão acima, `services` não tem mais nenhum uso legítimo para ele, e mantê-lo exposto preserva exatamente o caminho que esta correção elimina: criar uma instância sem descriptor, sem cadeia resolvida e sem `ClassName` validado. O único criador de instância disponível a `services`/`cli` passa a ser `Runtime.ClassRegistry.new`.

Uma classe que precise criar um filho dentro do `Initialize` (ex.: `Workspace` criando `Terrain`) chama `Runtime.ClassRegistry.new("Terrain")` — funciona porque `services` registra todas as classes no load, antes de qualquer instanciação. Classe não registrada nesse caminho dá o erro alto e claro que já existe (`"classe 'X' não registrada"`).

`Runtime.Instance.GetPropertyRaw`/`SetPropertyRaw` **continuam** exportados: são o caminho tipado de leitura/escrita quando `services` precisa mexer em propriedade sem passar pelo `__newindex` público (ex.: escrever uma propriedade somente-leitura do ponto de vista do script do usuário).

### Achados menores da mesma revisão — decisões

- **[MÉDIO] Guarda de ciclo sem teste** — aceito, vira teste na mesma tarefa de correção. Dois casos: ciclo mútuo (`A.Super = "B"`, `B.Super = "A"`) e auto-referência (`A.Super = "A"`; o laço atual já cobre esse caminho corretamente — `seen["A"]` fecha na segunda volta). Ambos precisam ser capturáveis por `pcall`, nunca travar.
- **[BAIXO] `error(msg, 0)` vs `error(msg, 2)`** — aceito, `error(msg, 3)` nos dois pontos de `resolveClassChain`. A conta bate: `resolveClassChain` é local, chamada de exatamente um lugar (`ClassRegistry.new`) e não em posição de tail call, então nível 3 aponta para quem chamou `ClassRegistry.new` — o mesmo alvo do nível 2 usado dentro de `new`. Comentar no código que o nível depende dessa função ter um único call site.
- **[BAIXO] `registry` global sem reset** — não construir reset agora (nenhum executor agregado existe). Documentar no cabeçalho do módulo a invariante "`ClassRegistry` assume um processo por execução; não há desregistro nem reset", para que ela deixe de ser acidente estrutural e vire decisão registrada. Se um harness agregado ou um watch mode que invalide o cache de `require` aparecer, volta ao arquiteto.

### Pendência adjacente (NÃO faz parte desta correção — decidir antes de task-runtime-005/services)

Com o padrão canônico acima, um **método** de classe concreta (`workspace:Raycast(...)`, `Players:GetPlayerByUserId(...)`) seria armazenado como valor em `data.properties` e servido pelo fallback de `__index`. Funciona, mas: (a) `__newindex` só protege os métodos de `Instance` (`Instance.luau:515`), então o script do usuário conseguiria sobrescrever `workspace.Raycast = nil` — divergência do Roblox real; (b) instalar método via `SetPropertyRaw` dispara `Changed` com nome de método. O remédio provável é um `Instance.SetClassMethods(instance, methods)` gravando numa tabela separada, consultada por `__index` antes de `properties` e protegida por `__newindex`. **Não decidir isso aqui** — é questão própria, precisa de confirmação do `pesquisador` sobre o comportamento real do Roblox ao atribuir sobre um método, e deve ser resolvida antes de `services` escrever a primeira classe com método.

Nota relacionada para task-runtime-005: `DataModel.new()` cria a raiz por dentro de `runtime` (sem passar por `ClassRegistry`), logo nasce com o chain default `{"DataModel", "Instance"}`. No Roblox real a cadeia é `DataModel` → `ServiceProvider` → `Instance`. Decidir explicitamente naquela tarefa (aplicar a cadeia à mão via `SetClassChain` ou registrar `DataModel`), não deixar implícito.

### Correções ao texto acima (2) — o que desta seção substitui o desenho original

| Trecho original | O que muda |
|---|---|
| `ClassRegistry.luau` — `Construct: (name: string?) -> Instance` | `Initialize: ((instance: Instance) -> ())?` — recebe base pronta com cadeia aplicada, não devolve nada, é opcional |
| `ClassRegistry.luau` — "resolve a cadeia..., chama `descriptor.Construct(name)`, e faz `SetClassChain` antes de devolver" | Ordem invertida: resolve a cadeia → `NewBase` → `SetClassChain` → `Initialize` → devolve |
| Contrato `runtime → services` — `Runtime.Instance.NewBase(...)` na lista pública | Removido da superfície pública; `Runtime.ClassRegistry.new` vira o único criador de instância para `services`/`cli` |
| Contrato `runtime → services` — "cada `Construct` usa `NewBase` + `Get/SetPropertyRaw` ... `setmetatable(raw, WorkspaceMeta) :: Workspace`" | `services` nunca chama `NewBase` nem `setmetatable`; escreve tipo + `Initialize` que semeia defaults, com um cast único por classe |
| `init.luau` — `Instance = { NewBase, GetPropertyRaw, SetPropertyRaw }` | `Instance = { GetPropertyRaw, SetPropertyRaw }` |

### Fidelidade vs. pragmatismo (entradas novas)

- **`IsA` passa a ser confiável em todo o ciclo de vida da instância, inclusive dentro do inicializador da própria classe.** Era a única janela em que a hierarquia simulada divergia da real; fecha aqui.
- **`Changed` dispara para as propriedades semeadas no `Initialize`.** No Roblox real, os defaults de uma classe não geram `Changed` (nascem com o objeto). Divergência sem efeito observável — não há listener possível nesse instante —, registrada por honestidade e não mitigada.

### O que deliberadamente NÃO fazer agora

- **Não** validar em runtime que `Initialize` não setou `Parent` — regra de contrato documentada; guarda só se alguma classe de `services` violar.
- **Não** construir `Instance.SetClassMethods` nesta correção (ver Pendência adjacente).
- **Não** adicionar reset/desregistro ao `ClassRegistry`.
- **Não** reescrever `ClassRegistry.luau`: são ~15 linhas mudadas (tipo, corpo de `new`, dois níveis de `error`, cabeçalho) mais testes novos.


---

## Revisão pós-integração 2026-09-04 (3) — acesso a membro: métodos de classe e membro desconhecido

Motivada por `.claude/agents-memory/pesquisa-instance-member-access-2026-09-04.md` (task-runtime-014), que fecha a "Pendência adjacente" aberta na revisão (2). Esta seção **substitui** os pontos listados em "Correções ao texto acima (3)". Nenhuma outra parte do desenho muda.

### Diagnóstico: são dois problemas, não um — e só um deles é resolvível hoje

A pesquisa confirmou que `InstanceMeta.__index` cair em `data.properties[key]` para qualquer chave desconhecida **já diverge do Roblox real hoje** (o real erra `"X is not a valid member of Y"`, nunca devolve `nil`), independentemente de método entrar em jogo. O pesquisador recomendou tratar as duas metades juntas por serem a mesma causa raiz. **Discordo parcialmente da recomendação, por um motivo estrutural, não de conveniência** — e é isso que esta seção decide:

| Metade | O que `runtime` precisa saber para implementar | Existe hoje? |
|---|---|---|
| **Métodos de classe** — `__index` serve o método, `__newindex` recusa sobrescrevê-lo | a lista de métodos daquela classe | **Sim** — vem do `ClassDescriptor`, que `services` já entrega no `Register`. Nenhum dado do dump é necessário para o *mecanismo*. |
| **Membro desconhecido erra** — `__index`/`__newindex` erram para nome que a classe não declara | a lista de **propriedades** que a classe declara, com default e escrituralidade | **Não** — exige um schema por classe que só o dump fornece, e `services` não existe. |

A segunda metade não é "cara demais agora": é **impossível de implementar corretamente agora**. Sem schema, `runtime` não consegue distinguir `workspace.Gravity` (válida, valor corrente `nil` antes de ser semeada) de `workspace.Gravty` (typo). O único sinal disponível — presença de entrada em `data.properties` — não serve, porque **tabela Lua não armazena `nil`**, e propriedade de tipo Instance no Roblox tem default `nil` de verdade (`Humanoid.SeatPart`, `ObjectValue.Value`). Enforçar hoje só teria duas saídas, ambas ruins: quebrar toda leitura de propriedade, ou criar um modo estrito que nenhum chamador consegue ligar.

### Decisão explícita: corrigir agora a metade dos métodos; decidir agora e implementar depois a metade do schema

Escolha consciente entre os dois caminhos que a thread principal pediu para eu pesar, com o risco de reabrir `Instance.luau` (24/24, três revisões) avaliado com dado, não com impressão:

**Verificado antes de decidir** (não assumido): `Instance.spec.luau` acessa, através da metatable pública, **apenas** `ClassName`/`Name`/`Parent`, os cinco sinais e os métodos base. A propriedade genérica é testada por `Instance.GetPropertyRaw`/`SetPropertyRaw` (linhas 217-229), que **não passam por `__index`/`__newindex`**. Nenhum teste casa texto de mensagem de erro — os `pcall` checam só `not ok` (linhas 129-131, 244-255). Logo o patch de métodos tem **zero quebra esperada** nos 24, e as mensagens podem ser reescritas sem tocar o spec.

- **Metade dos métodos: FAZER AGORA.** É a metade que muda o contrato contra o qual `services` vai ser **gerado**. Adiar significa que toda classe gerada guarda método em `data.properties`, e a correção posterior invalida o gerador inteiro. O patch é cirúrgico (um campo em `Internal`, uma função de módulo, ~16 linhas nas duas metametades) e verificadamente não regride os 24.
- **Metade do schema: DECIDIR AGORA, IMPLEMENTAR DEPOIS.** Ganha **zero fidelidade hoje** (nenhum chamador consegue fornecer schema) e exige uma decisão que eu **não posso tomar sem o pesquisador**: se o modelo certo é `ReadOnly: boolean` ou o `Scriptability` do dump (`ReadWrite`/`Read`/`Write`/`None`/`Custom`), e como o `Default` do dump chega serializado. Fixar `ReadOnly: boolean` agora seria exatamente o palpite sobre formato externo que a regra 03 proíbe. Fica como **divergência declarada e datada** no ponto exato do código, com o contrato-alvo escrito abaixo e duas tarefas amarradas.

Rejeitado: **implementar as duas juntas agora**, como o pesquisador recomendou. O acoplamento que ele viu é real na *causa* (mesmo metamétodo), mas não na *viabilidade*: juntar arrasta um modo estrito sem consumidor, um segundo campo especulativo no `ClassDescriptor` e um terceiro reabrir de `ClassRegistry.luau` (que ainda está em `review` por task-runtime-013), em troca de nenhuma divergência fechada hoje.

### Módulo novo? Não. Patch em `Instance.luau` + `ClassRegistry.luau`

#### `src/runtime/Instance.luau` — superfície de engenharia interna nova

```luau
-- Tabela ACHATADA (métodos próprios + herdados) e CONGELADA de uma classe concreta,
-- COMPARTILHADA por todas as instâncias dela. `unknown` no valor é o tipo honesto, mesmo
-- motivo de `properties: { [string]: unknown }`: o valor tipado que `services`/o script
-- enxergam vem da interseção declarada por `services`
-- (`export type Workspace = Runtime.Instance & { Raycast: (self: Workspace, ...) -> ... }`),
-- não deste storage. `SetClassMethods` valida em runtime que todo valor é função.
export type ClassMethods = { [string]: unknown }

-- Chamada por ClassRegistry.new, DEPOIS de SetClassChain e ANTES de Initialize — mesma razão
-- da ordem decidida na revisão (2): a identidade de classe precisa estar completa antes de
-- qualquer código de `services` rodar, para que dentro do próprio Initialize tanto
-- `instance:IsA(ancestral)` quanto `instance:MetodoDaPropriaClasse()` já funcionem.
-- NÃO copia a tabela: guarda a referência (uma tabela por classe, não por instância).
-- Erra se: a tabela não estiver congelada; algum valor não for função; alguma chave colidir
-- com a superfície fixa de Instance (ClassName/Name/Parent, os 5 sinais, os 14 métodos base).
Instance.SetClassMethods: (instance: Instance, methods: ClassMethods) -> ()
```

Validação memoizada **por identidade de tabela** (mapa fraco por chave, mesmo padrão de `internals`, `Instance.luau:81`): `ClassRegistry` passa sempre a mesma tabela para todas as instâncias de uma classe, então a varredura completa roda uma vez por classe e as instanciações seguintes custam um lookup. Isso mantém a invariante dentro do único módulo que conhece a superfície fixa de `Instance` — mesmo princípio da revisão (2) ("a invariante mora no único lugar que consegue garanti-la") — sem pagar O(nº de métodos) a cada `Instance.new`.

`Internal` ganha **um** campo: `classMethods: ClassMethods?` (`nil` = instância criada direto por `NewBase`, sem classe concreta).

`Instance.SetClassMethods` **não** é reexportada por `src/runtime/init.luau` — mesma decisão e mesma razão de `NewBase`/`SetClassChain` na revisão (2): expô-la deixaria `services` instalar métodos numa instância qualquer, fora da ordem que garante a validação. `ClassRegistry.new` é o único chamador legítimo. **Consequência para task-runtime-007.**

#### Ordem de resolução de `__index` (final)

```
1. campos fixos: ClassName, Name, Parent
2. sinais fixos: Changed, ChildAdded, ChildRemoved, AncestryChanged, Destroying
3. métodos base de Instance (tabela `Methods` do módulo)
4. métodos da classe concreta (data.classMethods), se houver
5. data.properties[key]  <- DIVERGÊNCIA DECLARADA (deveria ERRAR; ver "metade do schema")
```

3 antes de 4 é escolha de caminho quente, **não** de semântica: colisão entre método de classe e superfície fixa de `Instance` é **rejeitada com erro alto em `SetClassMethods`**, então as duas ordens seriam equivalentes. Colisão é bug do gerador de `services`, e bug de gerador tem que estourar uma vez no load, não decidir em silêncio qual dos dois vence. (Se algum dia o dump redeclarar de verdade um membro de `Instance` numa subclasse, isso volta ao arquiteto — não vira exceção local no `coder`.)

Herança entre classes de `services` (ex.: `Workspace` herdando métodos de `Model`) **não** é colisão: é resolvida pelo achatamento em `ClassRegistry` (abaixo), onde a classe mais concreta vence. Isso implementa a resposta da pergunta 2 da pesquisa — método herdado e método próprio ficam **indistinguíveis** do lado do script, que é exatamente o que ela concluiu.

#### Ordem de resolução de `__newindex` (final)

```
1. Parent    -> setParent
2. Name      -> setName (valida string)
3. ClassName -> ERRO
4. sinal     -> ERRO
5. método base de Instance -> ERRO   (já existe hoje)
6. método da classe concreta -> ERRO (NOVO — é a lacuna que a revisão (2) apontou)
7. resto -> data.properties[key] = value + Changed:Fire(key)
            <- DIVERGÊNCIA DECLARADA (deveria ERRAR para nome desconhecido, e dar a mensagem
               confirmada de read-only para propriedade conhecida-porém-somente-leitura)
```

#### Mensagens de erro: decisão de idioma e de fidelidade

Decisão de contrato que não existia e que cada `coder` estaria adivinhando: **erro que o script do usuário pode observar (via `pcall` ou pelo Output) segue o formato do Roblox, em inglês. Erro de engenharia interna do LuauBench (estado inválido, uso errado da API por `services`/`cli`) continua em português.** Sem essa linha, a família de acesso a membro fica meio em português e meio em inglês assim que a mensagem confirmada de read-only (que é inglês) entrar.

Escopo desta correção: **só** as mensagens produzidas por `InstanceMeta.__index`/`__newindex`. As guardas de `setParent` (ciclo, instância destruída) e o `getInternal` ficam como estão — o Roblox real também erra nesses casos, mas as strings dele não foram confirmadas e não fazem parte desta família (fica registrado como backlog, não como decisão implícita).

| Caso | Mensagem | Status de fidelidade |
|---|---|---|
| `instance.ClassName = x` | `Unable to assign property ClassName. Property is read only` | **Confirmada** — `ClassName` é `Property` somente-leitura de verdade, então a família confirmada pela pesquisa se aplica direto |
| `instance.Changed = x` (sinal) | `Unable to assign property {key}. {key} is an event of {ClassName} and cannot be reassigned` | **Aproximação de boa-fé** do LuauBench — string real não confirmada |
| `instance.GetChildren = x` / `instance.Raycast = x` (método base ou de classe) | `Unable to assign property {key}. {key} is a method of {ClassName} and cannot be reassigned` | **Aproximação de boa-fé** do LuauBench — a pesquisa buscou ativamente e não achou a string real; a melhor inferência dela é a família `"is not a valid member of"`, que é **rejeitada aqui de propósito** (ver abaixo) |
| (FUTURO) leitura/escrita de membro desconhecido | `{key} is not a valid member of {ClassName} "{GetFullName()}"` | Formato **confirmado** pela pesquisa (citação verbatim inclui o nome completo entre aspas); a nossa string ainda é aproximação porque `error(msg, 2)` prefixa `arquivo:linha:` e o `GetFullName` do LuauBench já é aproximado |

**Por que rejeitar a inferência do pesquisador para escrita sobre método:** ele deduziu que o Roblox provavelmente cai em `"Raycast is not a valid member of Workspace"`, mas marcou como não confirmado. Adotar uma string que *parece* fiel para um caso que sabidamente não verificamos é o oposto da invariante 2 da regra 00 — e ela é ativamente enganosa para quem lê o Output, porque `Raycast` **é** um membro válido de `Workspace`. Uma mensagem obviamente do LuauBench, na mesma família em inglês, é a saída honesta. Comentar isso no código, no ponto do erro, citando o arquivo da pesquisa.

#### `src/runtime/ClassRegistry.luau` — campo novo + achatamento

```luau
export type ClassDescriptor = {
    ClassName: string,
    SuperClassName: string?,
    IsAbstract: boolean,
    IsService: boolean,

    -- Métodos que ESTA classe declara — nunca os herdados. Espelha como o dump modela herança
    -- (campo `Superclass`, sem redeclarar membro da superclasse): o gerador de `services` emite
    -- exatamente o que o dump diz, e quem achata a cadeia é ClassRegistry, aqui, uma vez por
    -- classe. Opcional: classe sem método próprio dispensa o campo.
    Methods: InstanceModule.ClassMethods?,

    Initialize: ((instance: Instance) -> ())?,
}
```

`ClassRegistry` ganha um cache module-local `{ [string]: ClassMethods }` com a tabela achatada+congelada por `ClassName`, construída **preguiçosamente no primeiro `new`** (não no `Register`) — mesma razão já documentada para `resolveClassChain`: `services` pode registrar fora de ordem topológica, então a cadeia só precisa estar completa na hora de instanciar.

Achatamento: percorrer a cadeia resolvida **de trás para frente** (`resolveClassChain` devolve `{Concreta, ..., Super, "Instance"}`, então iterar em ordem reversa) mesclando `descriptor.Methods` de cada elo — assim a classe mais concreta sobrescreve a superclasse, que é a semântica de override correta. `table.freeze` no fim.

Corpo novo de `ClassRegistry.new` (ordem obrigatória, extensão da que a revisão (2) fixou):

```
lookup do descriptor -> guarda de IsAbstract -> resolveClassChain -> NewBase
  -> SetClassChain -> SetClassMethods (tabela achatada do cache) -> Initialize -> return
```

`SetClassMethods` **depois** de `SetClassChain` e **antes** de `Initialize`, exatamente como a thread principal supôs, e pela mesma razão que valeu para a cadeia: é o ponto em que a identidade de classe fica definitiva, e `Initialize` precisa poder chamar os métodos da própria classe. Classe sem `Methods` em nenhum elo da cadeia: pular a chamada (mantém `classMethods == nil`, modo idêntico ao de hoje).

### Contrato-alvo da metade adiada (decidido aqui, implementado em task-runtime-018)

Escrito agora para que a tarefa futura não seja vaga e para que ninguém redecida isso sozinho. **Não virar código antes de task-runtime-017** (o pesquisador precisa confirmar o modelo de membro do dump).

```luau
-- PROVISÓRIO no campo de escrituralidade: `ReadOnly: boolean` pode estar errado — o dump
-- modela isso como `Scriptability` (ReadWrite/Read/Write/None/Custom), e `Read`+`Write`
-- separados não colapsam num booleano sem perda. task-runtime-017 decide.
export type PropertyDescriptor = { Default: unknown, ReadOnly: boolean }
export type ClassSchema = { [string]: PropertyDescriptor }   -- achatada + congelada, como Methods

-- em ClassDescriptor: Properties: { [string]: PropertyDescriptor }?
-- em Instance:        Instance.SetClassSchema(instance, schema: ClassSchema) -> ()
-- em Internal:        classSchema: ClassSchema?
```

Dois modos, discriminados por `classSchema ~= nil` — e o modo leniente é **transitório, não permanente**:

- **`classSchema == nil` (leniente):** comportamento de hoje. É o caminho de `NewBase` direto — os specs atuais e, enquanto não for registrada, a raiz criada por `DataModel.new()` (task-runtime-005).
- **`classSchema ~= nil` (estrito):** leitura de nome fora do schema → erro `"is not a valid member of"`; escrita idem; escrita em propriedade do schema com escrituralidade de leitura → `Unable to assign property {key}. Property is read only` (**string confirmada**).

Ganho colateral que justifica a forma declarativa em vez de `Initialize` semeando por atribuição: (a) `ClassRegistry.new` semeia os defaults direto no storage interno, o que **fecha a divergência "`Changed` dispara durante o `Initialize`"** registrada na revisão (2); (b) propriedade com default `nil` passa a ser representável, que é justamente o que o storage sozinho não consegue expressar; (c) a maioria das classes geradas deixa de precisar de `Initialize`.

### Correções ao texto acima (3) — o que desta seção substitui o desenho

| Trecho | O que muda |
|---|---|
| Revisão (2), "Pendência adjacente" | Resolvida. `Instance.SetClassMethods` entra; `ClassDescriptor.Methods` entra; a metade de propriedade desconhecida vira contrato decidido + tarefa datada, não pendência aberta |
| Revisão (2), "Não precisa: `InstanceMeta.__index` já cai em `data.properties[key]`..." | Continua valendo **só para propriedade**. Método de classe **nunca** vai para `properties`: vai para a tabela congelada de `SetClassMethods` |
| Revisão (2), `ClassDescriptor` (4 campos + `Initialize`) | Ganha `Methods: ClassMethods?` |
| Revisão (2), corpo de `ClassRegistry.new` | Ganha `SetClassMethods` entre `SetClassChain` e `Initialize` |
| Revisão (2), "`Runtime.Instance.NewBase` sai da superfície pública" | Vale igual para `SetClassMethods`: `init.luau` não reexporta |
| Desenho original, `Instance.luau` — mensagens de erro | Família de acesso a membro passa a inglês/formato Roblox; o resto de `Instance.luau` fica em português |

### Fidelidade vs. pragmatismo (entradas novas)

- **Método de classe é imutável e indistinguível de método herdado** — fiel ao real (pergunta 2 da pesquisa: nenhuma distinção conhecida). Fecha a lacuna em que o script do usuário podia fazer `workspace.Raycast = nil`.
- **Ler membro desconhecido devolve `nil` em vez de errar — DIVERGÊNCIA CONHECIDA E ACEITA nesta fase.** O Roblox real erra (`"X is not a valid member of Y"`, confirmado com boa evidência convergente, não com documentação oficial). Não é omissão: é impossibilidade estrutural enquanto não houver schema por classe (tabela Lua não guarda `nil`, e propriedade de tipo Instance tem default `nil` legítimo). Prazo: entra junto com a primeira classe real de `services` (task-runtime-018). **Precisa estar comentada no ponto exato do fallback de `__index`, citando o arquivo da pesquisa** — o `revisor-runtime` cobra isso.
- **Escrever nome desconhecido cria propriedade nova em silêncio — mesma divergência, mesma causa, mesmo prazo.** Comentar no ponto exato do fallback de `__newindex`.
- **Mensagem de erro ao escrever sobre método/evento é do LuauBench, não do Roblox.** A pesquisa não conseguiu a string real e a inferência estrutural dela é enganosa para este caso. Aproximação de boa-fé declarada, nunca apresentada como fidelidade byte-a-byte.
- **Colisão entre método de classe e a superfície fixa de `Instance` erra no load** em vez de deixar um dos dois vencer. Não há caso real conhecido no dump; se aparecer, volta ao arquiteto.

### Riscos e decisões

- **Reabrir `Instance.luau` (24/24, três revisões).** Risco real, medido antes de decidir e não estimado: o spec só acessa `ClassName`/`Name`/`Parent`/sinais/métodos pela metatable, testa propriedade genérica por `Get/SetPropertyRaw` (fora das metametades) e não casa texto de erro. Blast radius do patch: **um** campo em `Internal`, uma função de módulo, ~16 linhas nas duas metametades, três mensagens reescritas. `Signal`/`Scheduler`/`Integration`/`Sandbox` não tocam acesso a membro além de `Parent`/`Name`. **Se algum dos 24 precisar mudar, o patch está errado — parar e voltar ao arquiteto** (mesma cláusula da revisão de `ThreadBroker`).
- **`ClassRegistry.luau` acabou de sair de `review` (task-runtime-013 fechou como `done` durante a escrita desta seção).** Dependência satisfeita, task-runtime-016 pode ser despachada; o que continua valendo é a exclusão mútua de território — nenhum outro agente toca `Instance.luau`/`ClassRegistry.luau` enquanto ela estiver `in-progress`. Este é o **terceiro** patch em `ClassRegistry.luau` na mesma sessão; se um quarto aparecer antes de `services` existir, isso é sinal de que o contrato está sendo descoberto por revisão em vez de desenhado, e vale parar para revisar o `ClassDescriptor` inteiro de uma vez com o usuário.
- **`DataModel.new()` (task-runtime-005) cria a raiz fora do `ClassRegistry`**, logo nasce sem `classMethods` **e** sem schema — modo leniente. Some junto com a decisão de cadeia que aquela tarefa já precisa tomar (registrar `DataModel` no registry resolve os dois de uma vez). Anotado lá, não deixado implícito.
- **`table.freeze`/`table.isfrozen` são Luau padrão**, disponíveis no Lune — mas o `coder` deve confirmar na prática antes de apoiar a validação neles; se não estiverem, a validação vira só a varredura memoizada, sem a garantia de congelamento, e isso vira nota de fidelidade.

### O que deliberadamente NÃO fazer agora

- **Não** implementar erro em leitura/escrita de membro desconhecido (impossível sem schema; ver acima).
- **Não** adicionar `Properties`/`SetClassSchema`/`PropertyDescriptor` ao código — só ao desenho, até task-runtime-017 confirmar o modelo do dump.
- **Não** traduzir/alterar mensagens fora de `__index`/`__newindex` (`setParent`, `getInternal`) — backlog, não escopo.
- **Não** expor `SetClassMethods` em `src/runtime/init.luau`.
- **Não** dar a cada instância a própria cópia da tabela de métodos — uma tabela congelada por classe, referência compartilhada.
- **Não** reescrever `Instance.luau`/`ClassRegistry.luau`: são dois patches cirúrgicos sobre arquivos que passam nos próprios testes.
