# `cli` — Arquitetura

Data: 2026-09-05. Território novo, do zero — `src/cli/` não existe em disco. Desenhado sobre `runtime` (20 tarefas, fechado) e `services` leva 1 (7 tarefas, fechada).

Insumos que este desenho consome e **não repete**:
- `.claude/agents-memory/arquiteto-runtime-2026-09-04.md` — contrato de `runtime` + as quatro revisões pós-integração.
- `.claude/agents-memory/arquiteto-services-2026-09-05.md` — contrato de `services`, sequência de bootstrap de 8 passos, regra de idioma dos erros.
- `.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md` — schema do `.project.json`, tabela extensão→ClassName, sourcemap, resolução de `$path`, projetos aninhados. **Nada disso é repesquisado aqui.**
- Leitura direta, nesta sessão, do código real já em disco: `src/runtime/init.luau`, `src/runtime/Sandbox.luau`, `src/runtime/Scheduler.luau` (assinaturas), `src/runtime/DataModel.luau` (assinaturas), `src/services/init.luau`.
- Inspeção direta dos typedefs do Lune 0.10.5 instalados (`~/.lune/.typedefs/0.10.5/`) — marcado abaixo como **[verificado 09-05c]**.

---

## Propósito

Transformar um projeto Rojo em disco num `DataModel` simulado vivo e executar o código do usuário dentro dele, sem que `cli` conheça o nome de nenhuma classe do Roblox e sem duplicar nenhuma decisão de segurança que já vive no `Sandbox` do `runtime`.

---

## Fatos externos fixados nesta sessão

Nenhum item abaixo é de memória. Todos vêm de leitura direta dos typedefs do Lune 0.10.5 instalado por Rokit (`rokit.toml`: `lune-org/lune@0.10.5`).

| Fato | Valor | Consequência de desenho |
|---|---|---|
| `serde.EncodeDecodeFormat` | `"json" \| "jsonc" \| "yaml" \| "toml"` **[verificado 09-05c]** | JSONC do `.project.json` sai de graça; `luaubench.toml` (se um dia existir) também |
| `serde.decode(format, s): any` | devolve `any` **[verificado 09-05c]** | fronteira externa — exige um módulo de narrowing (`JsonValue.luau`), regra 01 |
| `fs` de Lune 0.10.5 | `readFile`, `readDir`, `writeFile`, `writeDir`, `removeFile`, `removeDir`, `metadata`, `isFile`, `isDir`, `move`, `copy` — **e nada mais** **[verificado 09-05c]** | **NÃO existe observador de filesystem.** Decisão 9 |
| `process` | `args: {string}`, `cwd: string`, `env`, `os`, `arch`, `exit(code)`, `exec`, `create` **[verificado 09-05c]** | argv e exit code resolvidos sem nada novo |
| `stdio` | `write`, `ewrite`, `color(Color)`, `style(Style)`, `format`, `readLine` **[verificado 09-05c]** | stdout/stderr separados + cor; **não há detecção de TTY** → Decisão 7 |
| `luau.load(source, LoadOptions): (...any) -> ...any` | devolve a função do chunk **[verificado 09-05c]** | `Sandbox.Load` é viável (Decisão 5) |
| Whitelist atual de globals do `Sandbox` | `task, coroutine, math, string, table, os{clock,time}, bit32, utf8, typeof, tostring, tonumber, pcall, xpcall, assert, select, pairs, ipairs, next, print, warn, error` | **falta `setmetatable`** e toda a família `raw*` → Decisão 12, bloqueio real |
| `Sandbox.Run` | `chunk()` — descarta o valor de retorno, roda em thread própria via `Scheduler:Spawn` | não serve para `require` → Decisão 5 |
| `Services` exporta | `Bootstrap`, `new`, `IsKnownClass`, `IsSimulatedClass`, `GetDumpVersion` | **falta saber se uma classe é Service** → Decisão 4 |

---

## Decisão 1 — Ler o `.project.json` direto em Luau; **não** invocar o binário `rojo`

**Decidido: `cli` implementa o parser e o walk do filesystem em Luau. `rojo` nunca é executado, nem é procurado no PATH.**

Quatro razões, em ordem de peso:

1. **O sourcemap não carrega `$properties` nem `$attributes`.** O nó real do sourcemap é exatamente `{name, className, filePaths, children}` (pesquisa, seção 6) — não existe campo de propriedade. O pedido de materializar `$properties` seria **impossível** por esse caminho. Isso sozinho encerra a discussão.
2. **Invariante 3 do projeto.** "Runtime é o Lune. Nenhuma dependência de binário externo além do que o Lune já provê entra sem essa decisão ser revisitada explicitamente com o usuário." Exigir `rojo` no PATH é exatamente isso. E a distribuição é `rokit add victorcarmo2003/luaubench` — que instala o LuauBench, não o Rojo. "O usuário provavelmente tem rojo" não é contrato.
3. **Fragilidade de flag.** Sem `--include-non-scripts` o sourcemap **descarta silenciosamente** toda instância sem script descendente (pesquisa, "Limites e pegadinhas"). Depender de uma flag de um binário de versão desconhecida é um modo de falha silencioso, que é a categoria que a regra 00 mais combate.
4. **Custo baixo.** `serde.decode("jsonc", ...)` entrega a árvore JSON; `fs.readDir`/`fs.isDir`/`fs.isFile` fazem o walk; a tabela de extensão→ClassName tem ~15 entradas já confirmadas por pesquisa. É trabalho finito e testável.

**Rejeitado explicitamente:** aceitar um sourcemap pré-gerado via `--sourcemap <arquivo>` como entrada alternativa. Seria um segundo caminho de código estritamente mais fraco (sem `$properties`, sem `$attributes`, sem meta files), com o dobro da superfície de bug e metade da fidelidade. Se um dia entrar, entra como otimização de watch mode, nunca como fonte primária.

**Consequência declarada:** `cli` reimplementa a semântica do Rojo e pode divergir dela quando o Rojo evoluir. Mitigação: a tabela de regras vive num módulo de dados isolado (`SyncRules.luau`) com a versão do Rojo de referência (v7.7.0) no cabeçalho, e toda divergência conhecida está na seção "Fidelidade vs. pragmatismo".

---

## Decisão 2 — JSONC sempre, e um módulo de narrowing entre `serde` e o resto

`serde.decode("jsonc", ...)` **[verificado 09-05c]** aceita JSON estrito como subconjunto. Decisão: **decodificar sempre com `"jsonc"`**, tanto para `.project.json` quanto para `.project.jsonc` e para meta files. Isso reproduz o comportamento real do Rojo (que não ramifica por extensão — pesquisa, seção 1) sem nenhum custo.

`serde.decode` devolve `any`, e regra 01 proíbe `any` no nosso código. Toda a decodificação passa por **um único ponto**, `src/cli/JsonValue.luau`, que:

- converte `unknown` num `JsonValue` tagged (`JsonNull | boolean | number | string | JsonArray | JsonObject`);
- oferece acessores que **carregam o caminho** (`tree.ReplicatedStorage.$path`) e produzem a mensagem de erro certa em vez de um `attempt to index nil`;
- é o único lugar do território com um cast de fronteira, comentado (mesmo precedente do cast de `LoadOptions.environment` já presente em `Sandbox.luau`).

Isso é o que transforma a exigência da regra 04 — *"erro claro apontando o campo problemático, nunca stack trace cru do parser"* — de intenção em mecanismo.

---

## Decisão 3 — Separar **planejar** de **materializar**

O núcleo do desenho. Ler o projeto e andar o filesystem produz um **`InstancePlan`: uma árvore de dados pura, sem nenhuma dependência de `runtime` ou `services`**. Só depois esse plano é materializado em Instances reais.

Por quê, concretamente:

- **Falha antes de mutar.** Um `.project.json` com erro é rejeitado com *todos* os problemas listados de uma vez, com nenhuma Instance criada — em vez de morrer no meio da árvore deixando um `DataModel` meio construído.
- **Testável sem DataModel.** `TreePlanner` se testa com fixtures em disco e asserções sobre uma tabela, sem `Scheduler`, sem `Bootstrap`, sem `ClassRegistry`.
- **Watch mode fica trivial depois.** Diferença entre plano antigo e novo é comparação de tabela; sem essa separação, watch mode exigiria reler o mundo inteiro para saber o que mudou.
- **Diagnóstico completo.** Cada nó carrega o `NodePath` e o `FilePath` de origem, então qualquer erro posterior sabe apontar de onde a Instance veio.

```luau
export type PlanPropertyValue = boolean | number | string

export type PlanNode = {
    Name: string,
    ClassName: string,                          -- já resolvido (Decisão 4)
    IsServiceRoot: boolean,                     -- true => materializar via game:GetService
    Source: string?,                            -- conteúdo do arquivo, p/ Script/LocalScript/ModuleScript
    SourcePath: string?,                        -- caminho absoluto em disco (diagnóstico + watch futuro)
    Properties: { [string]: PlanPropertyValue },
    Children: { PlanNode },
    NodePath: string,                           -- "tree.ReplicatedStorage.Modules" (diagnóstico)
}

export type InstancePlan = {
    ProjectName: string,
    ProjectPath: string,        -- caminho absoluto do .project.json raiz
    RootClassName: string,      -- precisa ser "DataModel" para `luaubench run`
    Roots: { PlanNode },        -- filhos diretos da raiz
    Diagnostics: { Diagnostics.Diagnostic },
}
```

---

## Decisão 4 — Resolução de `ClassName` e a lacuna em `services`

Ordem de precedência (idêntica ao Rojo — pesquisa, seção 4):

1. `$className` explícito;
2. classe inferida do `$path` (via `SyncRules`);
3. inferência de Service — **só quando o pai é o `DataModel`**;
4. nada resolve → erro nomeando o nó, na família da mensagem real do Rojo.

Conflito `$className` + `$path`: só é legal se o `$path` resolver para `Folder` (senão erro). `$path` que resolve para `Folder` sob a raiz com nome de Service → **a inferência de Service vence** (pasta chamada `ReplicatedStorage` vira o Service, não um Folder).

### A lacuna: `cli` não tem como perguntar "isto é um Service?"

`Services` exporta hoje `IsKnownClass` / `IsSimulatedClass` / `GetDumpVersion` / `new` / `Bootstrap`. **Nenhuma responde se uma classe carrega a tag `Service` do dump** — e o `Manifest.luau` gerado tem exatamente esse campo (`ManifestEntry.IsService`). `cli` não pode abrir `generated/Manifest.luau` (regra 03: registro central, `cli` só requer `require("../services")`).

**Decisão: duas funções novas em `src/services/init.luau`** (tarefa de `coder-services`, pequena, leitura pura do manifesto):

```luau
-- Tag `Service` do dump, para as 916 classes do manifesto. PURA — só lê `generated/Manifest.luau`,
-- não toca em ClassRegistry nem em Context: é SEGURA de chamar ANTES de `Services.Bootstrap`.
-- É o que permite a `cli` reproduzir a inferência de Service do Rojo sem conhecer nome de classe.
function Services.IsServiceClass(className: string): boolean

-- Classes com `IsService == true` E `Covered == true` — as Services que este build simula de
-- verdade. `cli` faz `game:GetService(x)` para cada uma no bootstrap, de modo que o acesso por
-- ponto (`game.ReplicatedStorage`) funcione como no Roblox real mesmo para Service que o
-- `.project.json` não declara. Ordem determinística (ordenada por nome).
function Services.GetSimulatedServiceClasses(): { string }
```

`GetSimulatedServiceClasses` também resolve um problema que passaria despercebido: no Roblox **todo Service existe sempre**. Um projeto cujo `.project.json` não declara `ReplicatedStorage` ainda assim tem `game.ReplicatedStorage` funcionando. Sem pré-criar, o `__index` de `DataModel` (leniente) devolveria `nil` — divergência silenciosa, a categoria proibida pela regra 00. Pré-criar via lista vinda de `services` mantém zero nome de classe dentro de `cli`.

**Serviço com nome diferente da classe na raiz** (`"MinhaCoisa": {"$className": "Workspace"}`): o Rojo permite; o LuauBench **erra claro**, porque `DataModel:GetService` é dono da nomeação do singleton (`Name == ClassName`) e criar um segundo `Workspace` por fora quebraria a identidade do serviço. Divergência declarada.

---

## Decisão 5 — Carregamento de script, `require`, e a segunda lacuna (agora em `runtime`)

### O `Source` vai por `SetPropertyRaw`

`Script.Source`/`ModuleScript.Source` estão **fora do schema** (capability `PluginOrOpenCloud` — desenho de `services`, revisão A.4), e `Get/SetPropertyRaw` **nunca consultam o schema** (Decisão 6.2 de `services`). Então:

```luau
Runtime.Instance.SetPropertyRaw(instance, "Source", sourceText)   -- cli grava
local raw = Runtime.Instance.GetPropertyRaw(instance, "Source")   -- cli lê de volta (unknown)
```

É exatamente o canal que o desenho de `services` já reservou para isto. Um script do usuário continua sem conseguir ler `script.Source` — fiel ao Roblox.

### `Sandbox.Run` não serve para `ModuleScript`

Lido no código real: `Sandbox.Run` faz `scheduler:Spawn(entry)` e, dentro, `chunk()` — **descarta o valor de retorno e roda numa thread separada**. As duas coisas são incompatíveis com `require`, que precisa (a) do valor de retorno e (b) de rodar **na thread chamadora**, para que um `task.wait()` no topo do módulo suspenda quem pediu, e para que o erro do módulo suba até o `pcall` do script que chamou.

Três saídas foram consideradas:

| Alternativa | Veredito |
|---|---|
| `cli` chama `luau.load` por conta própria | **Rejeitada.** Duplicaria a whitelist de globals — a superfície de segurança passaria a ter duas definições, em dois territórios. Regra 00 é frontal sobre isso. |
| `Sandbox.Run` ganhar um `onResult` | **Rejeitada.** Continuaria em thread separada; não resolve a semântica síncrona de `require`, só o valor. |
| **`Sandbox.Load`: compila e devolve o chunk, sem criar thread** | **Adotada.** |

**Decisão: tarefa nova de `coder-runtime` (`task-runtime-025`)**, em `src/runtime/Sandbox.luau`:

```luau
export type SandboxChunkOptions = {
    scriptName: string,
    source: string,
    scheduler: Scheduler,
    extraGlobals: SandboxGlobals?,
    onOutput: (record: OutputRecord) -> (),
}

-- Compila `source` com EXATAMENTE a mesma `buildEnvironment` que `Sandbox.Run` usa (a MESMA
-- função, nunca uma segunda cópia da whitelist) e devolve a função do chunk SEM criar thread e
-- SEM chamá-la. Quem chama decide quando invocar; invocar na thread corrente é o que preserva a
-- semântica síncrona de `require`.
--
-- NÃO registra thread em `ownThreads` e NÃO se inscreve em `ThreadError`: um erro dentro do chunk
-- propaga para quem chamou -- que é justamente o que faz `pcall(require, m)` funcionar no script
-- do usuário. Se ninguém tratar, o erro sobe até a thread do Script que originou a cadeia, que JÁ
-- é `ownThread` do `Sandbox.Run` dele -- reportada lá, uma vez só.
function Sandbox.Load(options: SandboxChunkOptions): () -> ...unknown
```

Um único cast de fronteira no retorno de `luau.load` (`(...any) -> ...any`), comentado — mesmo precedente do cast de `environment` já presente no arquivo.

### `require` simulado (`src/cli/ModuleLoader.luau`)

```luau
export type ModuleLoader = {
    Require: (self: ModuleLoader, target: unknown) -> unknown,
    -- `target` é `unknown` de propósito: vem do script do usuário, que pode passar QUALQUER coisa.
}
```

Semântica:

- **cache por identidade de Instance**, `{ [Runtime.Instance]: CacheEntry }`;
- **carregando em outra thread** → o segundo requerente espera. Implementado com `Runtime.Signal.new()` (já público) por módulo em voo: `:Wait()` de dentro de uma thread gerida roteia pelo `ThreadBroker`, então funciona sem nada novo;
- **carregando na mesma thread** → ciclo → erro `Requested module was required recursively` (família Roblox, inglês, sem prefixo — **aproximação de boa-fé, string não confirmada byte-a-byte**, mesmo protocolo da mensagem de `Instance.new`);
- **módulo não retorna exatamente um valor** → erro `Module code did not return exactly one value` (mesma marcação de aproximação);
- **`target` não é `ModuleScript`** → `Attempted to call require with invalid argument(s).` (idem);
- **`target` é número (asset id)** → `[LuauBench] require by asset id is not supported (LuauBench runs offline)` — **prefixo obrigatório**: não tem contraparte no Roblox real (lá funcionaria), e a razão é a regra 00 local-first. Idioma dos erros conforme a Decisão 5 do desenho de `services`.

Cada módulo é carregado com o seu **próprio** `extraGlobals` (`script` = o `ModuleScript`), montado por `ScriptEnvironment`. Como o Lune **copia** a tabela `environment` no `luau.load`, não há vazamento entre módulos.

---

## Decisão 6 — Convenção arquivo→ClassName (`src/cli/SyncRules.luau`)

Dados puros, sem I/O, testáveis sozinhos. Cabeçalho registra "Rojo v7.7.0, pesquisa de 2026-09-05".

**Arquivos** — primeira regra que casa vence (ordem é significativa: `.server.lua` casa antes de `.lua`):

| Padrão | Leva 1 | Resultado |
|---|---|---|
| `*.server.lua` / `*.server.luau` | ✅ | `Script` |
| `*.client.lua` / `*.client.luau` | ✅ | `LocalScript` |
| `*.lua` / `*.luau` | ✅ | `ModuleScript` |
| `*.project.json` / `*.project.jsonc` | ✅ | projeto Rojo aninhado (Decisão 8) |
| `*.meta.json` / `*.meta.jsonc` | ✅ | **não é Instance** — metadado do irmão (Decisão 7) |
| `*.plugin.lua` / `*.plugin.luau` | ❌ | reconhecido, **diagnóstico de warning**, nó omitido |
| `*.model.json` / `*.model.jsonc` | ❌ | idem (formato não confirmado — pesquisa, "Incerto") |
| `*.json` / `*.jsonc` (fora de `*.meta.*`) | ❌ | idem (viraria `ModuleScript` que retorna tabela — precisa de um chunk sintético) |
| `*.toml`, `*.yml`, `*.yaml` | ❌ | idem |
| `*.csv` | ❌ | idem (`LocalizationTable` não está na leva 1 de `services`) |
| `*.txt` | ❌ | idem (`StringValue` não está na leva 1) |
| `*.rbxm` / `*.rbxmx` | ❌ | idem |
| qualquer outra extensão | — | ignorado em silêncio (é o que o Rojo faz) |

**Diretórios** — ordem de prioridade **fixa** (pesquisa: comentada no código do Rojo como imutável por compatibilidade):

1. `default.project.json` / `.jsonc` dentro → projeto aninhado (**vence tudo**, inclusive `init.*`)
2. `init.luau` / `init.lua` → `ModuleScript`
3. `init.server.luau` / `init.server.lua` → `Script`
4. `init.client.luau` / `init.client.lua` → `LocalScript`
5. `init.plugin.*` → warning, tratado como (7)
6. `init.csv` → warning, tratado como (7)
7. nenhum dos acima → `Folder`

**A regra dura do "não suportado":** nunca omitir em silêncio. Todo arquivo reconhecido pela tabela mas fora da leva 1 gera um `Diagnostic{Severity="warning"}` com o caminho real, e o sumário final do `run` lista quantos foram. Um `.json` que sumisse calado viraria um `require` falhando dez minutos depois sem explicação — exatamente o modo de falha que a regra 03 proíbe.

---

## Decisão 7 — `$properties`, `$attributes` e meta files

### `$properties` vai pelo caminho público de escrita, **não** por `SetPropertyRaw`

`SetPropertyRaw` ignora o schema. Se `cli` escrevesse `$properties` por ele, um typo do usuário (`"Gravty": 10`) gravaria uma propriedade fantasma que o script depois **não conseguiria ler** (o `__index` estrito erraria "Gravty is not a valid member of Workspace") — erro no lugar errado, dez passos depois da causa.

**Decisão: escrever pela via pública, deixar o `__newindex` do `runtime` fazer o enforcement, e traduzir a falha em diagnóstico de projeto.**

```luau
-- Cast de fronteira único e comentado: `Runtime.Instance` é um tipo de campos nomeados, e aqui a
-- chave vem do .project.json (string dinâmica). A escrita continua passando pelo __newindex real
-- -- é justamente ele que valida contra o ClassSchema e devolve a mensagem da família Roblox.
local writable = (instance :: unknown) :: { [string]: unknown }
local ok, err = pcall(function() writable[key] = value end)
```

Falha → `Diagnostic{Severity="error"}` citando `NodePath`, o nome da propriedade e a mensagem do motor. Isso é fiel: o próprio Rojo erra em propriedade inexistente (resolução contra o reflection database).

### Valores não-primitivos: **warning e pula**, nunca erro, nunca mentira

`$properties` no Rojo aceita a forma ambígua: array de 3 números = `Vector3`/`Color3`, string = nome de `EnumItem`, etc. O LuauBench **não tem tipos de valor nem `Enum`** (leva 3 de `services`). Três opções, e por que a escolhida:

- gravar a tabela crua (`{0,0,0}`) → **mentira**: `lighting.Ambient` deixaria de ser `nil` e passaria a ser um array, e `typeof` diria "table". Rejeitado.
- erro duro → recusaria um `.project.json` perfeitamente válido só porque o LuauBench é incompleto. Falha por comissão — o lado caro, mesmo princípio da Decisão 3 de `services`. Rejeitado.
- **warning + pula** → a propriedade fica com o default do schema (`nil` para `DataType`/`Enum`, que é a divergência **já declarada** de `services`), e o usuário sabe exatamente qual propriedade de qual nó não foi aplicada. **Adotado.**

Aceitos na leva 1: `boolean`, `number`, `string`. Um `string` continua ambíguo (pode ser um `EnumItem` no Rojo real) — nesta fase é gravado como string, e isso está na tabela de fidelidade.

### `$attributes`

`Instance:SetAttribute` existe no dump mas **não é simulado** (`ClassBuilder` instala o stub `[LuauBench] ... not simulated yet`). Então `cli` valida a forma e emite **warning listando os atributos não aplicados**. Nunca ignora calado.

### Meta files

- `<nome>.meta.json` ao lado de um arquivo → aplica `properties` (mesmas regras acima). `id` / `ignoreUnknownInstances` → warning de não suportado.
- `init.meta.json` dentro de uma pasta → o mesmo, **mais `className`**, que só pode sobrescrever quando a pasta resolveu para `Folder` puro (idêntico ao Rojo; senão, erro).

---

## Decisão 8 — `$path`, paths opcionais e projetos aninhados

- `$path` é resolvido **relativo à pasta do `.project.json` que define aquele nó** (pesquisa, seção 5). Num projeto aninhado, relativo à pasta **dele**, não à do pai. `cli` carrega o path do projeto corrente em todo o walk — não há variável global de "raiz".
- `PathNode` string (obrigatório) ausente em disco → **erro** nomeando o nó, o campo e o caminho absoluto tentado.
- `PathNode` `{"optional": "..."}` ausente → nó omitido, **sem erro** (semântica do Rojo), com `Diagnostic{Severity="info"}` visível só em `--verbose`.
- **Projeto aninhado** (`default.project.json` numa pasta alcançada, ou `$path` apontando para um `*.project.json`): recursão do mesmo parser. Proteção de ciclo obrigatória — conjunto de caminhos absolutos de projeto no ramo corrente; ciclo → erro listando a cadeia. É a única recursão não-limitada do território.

---

## Decisão 9 — Watch mode: **fora da leva 1, e por um motivo técnico duro**

Não é priorização. **`@lune/fs` da versão 0.10.5 — a fixada em `rokit.toml` — não tem API de observação de filesystem** (verificado nos typedefs instalados: `readFile`, `readDir`, `writeFile`, `writeDir`, `removeFile`, `removeDir`, `metadata`, `isFile`, `isDir`, `move`, `copy`, e nada mais) **[verificado 09-05c]**.

A regra 04 diz: *"Reagir a mudança de arquivo do projeto do usuário via observador de filesystem do Lune, nunca por polling em intervalo."* Ela pressupõe uma capacidade que o runtime fixado não oferece. As três saídas reais:

1. **atualizar o Lune** — mexe na invariante 4 (build/distribuição) e precisa de confirmação de que uma versão mais nova expõe watcher;
2. **binário externo de watch** — viola a invariante 3;
3. **polling** — viola a regra 04 como escrita.

Nenhuma das três é decisão de arquiteto sozinho: **é decisão do usuário.** Registrada como tal, com pesquisa dedicada (`task-cli-007`) para levantar os fatos antes da conversa.

Efeito prático na leva 1: `luaubench run --watch` **é reconhecido** e responde com o motivo real, não com "flag desconhecida":

```
--watch ainda não é suportado: o Lune 0.10.5 (versão fixada em rokit.toml) não expõe
observador de filesystem, e o LuauBench não faz polling (.claude/rules/04-cli-rokit.md).
```

Nota de desenho para quando entrar: `ClassRegistry` não tem reset e `Services.Register()` é idempotente por guarda local — reexecutar **no mesmo processo** exige `DataModel` novo + cache de módulos novo (os dois são fáceis: o `DataModel` é criado por `cli`, e o cache de `require` vive no `ModuleLoader` de `cli`), mas o `ClassRegistry` persiste. Isso está certo (classes não mudam) e já foi antecipado no desenho de `services` ("Riscos", último item).

---

## Decisão 10 — `luaubench.toml`: **não criar agora**

Levantei o que a leva 1 precisaria configurar: ponto de entrada, quais contêineres executam `Script`, globs ignorados, timeout. **Todos têm default sensato ou já viram flag.** Criar um formato de configuração antes de existir um ajuste que precise dele produz superfície de compatibilidade de graça — e um arquivo que o usuário precisa aprender sem ganhar nada.

**Decisão: nenhum arquivo de configuração próprio na leva 1.** O que fica **reservado e registrado**, para ninguém inventar outra coisa depois:

- nome: **`luaubench.toml`**, na raiz do projeto do usuário, ao lado do `.project.json`;
- formato: TOML, lido com `serde.decode("toml", ...)` **[verificado 09-05c]** — zero dependência nova;
- **nunca dentro do `.project.json`**: o struct raiz do Rojo usa `deny_unknown_fields`, então um campo `"luaubench"` no topo **quebra `rojo serve`/`build` de verdade**, e dentro de um nó viraria uma Instance fantasma chamada "luaubench" (pesquisa, "Limites e pegadinhas"; regra 04 já corrigida).

---

## Decisão 11 — O que executa, em que ordem, e o que só é carregado

O LuauBench se apresenta como **servidor** (`RunService:IsServer() == true`, `IsStudio() == false`, `RenderStepped` recusa conexão) — decisão já tomada e já declarada no desenho de `services`. `cli` é coerente com ela:

```luau
export type RunPolicy = {
    ServerScriptContainers: { string },   -- default: {"ServerScriptService", "Workspace"}
    RunLocalScripts: boolean,             -- default: false
}
```

- **`Script`** roda se (a) é descendente de um contêiner de `ServerScriptContainers` **e** (b) `Enabled ~= false`. `Script` em `ReplicatedStorage`/`ServerStorage`/`StarterGui`/`StarterPack`/`Lighting` é **carregado mas não executado** — fiel ao Roblox.
- **`LocalScript`** nunca executa. É carregado, o `Source` fica disponível, e o sumário final diz quantos foram (`N LocalScript não executado — LuauBench roda como servidor`). Honesto e acionável, nunca silencioso.
- **`ModuleScript`** nunca executa sozinho — só via `require` (Decisão 5). É exatamente a semântica real.
- **Ordem:** determinística — profundidade primeiro, contêineres na ordem de `ServerScriptContainers`, irmãos por nome. O Roblox real **não garante ordem**; determinismo é melhor que arbitrário para depurar, e a divergência (não é a ordem do Roblox, é *uma* ordem estável) está declarada. O desenho do `runtime` já previa que essa escolha seria de `cli`.
- **Início real:** `Scheduler:Spawn` roda a função **até o primeiro yield** antes de devolver. Logo o script N+1 só é spawnado depois que o N cedeu ou terminou — o que é próximo do comportamento real, e está documentado.

A lista `ServerScriptContainers` é uma **aproximação declarada**, pendente de `pesquisador` (`task-cli-007`).

---

## Decisão 12 — A whitelist de globals do `Sandbox` está incompleta para o caso de uso

Achado do desenho, não da implementação. A whitelist atual (lida no código) **não tem `setmetatable`**. Nem `getmetatable`, `rawget`, `rawset`, `rawequal`, `rawlen`, `buffer`, `wait`, `spawn`, `delay`, `tick`, `time`.

Isso não é um detalhe: **todo módulo OOP do ecossistema Roblox usa `setmetatable`** — ProfileStore, state managers, class patterns, proxytables. É literalmente o alvo declarado do projeto no `CLAUDE.md`. Um `cli` perfeito rodando sobre a whitelist atual falha no primeiro `ProfileStore.new`.

`cli` **poderia** injetar via `extraGlobals` — e **não deve**: a whitelist é a superfície de segurança do sandbox, e a regra 00 é explícita sobre ela ser uma decisão do runtime. Injetar de `cli` criaria duas definições do que um script do usuário enxerga, em dois territórios.

**Decisão: tarefa nova de `coder-runtime` (`task-runtime-026`) — completar a whitelist.** Adições, cada uma justificada como "existe no ambiente Roblox real **e** não concede acesso ao host":

| Global | Justificativa |
|---|---|
| `setmetatable`, `getmetatable`, `rawget`, `rawset`, `rawequal`, `rawlen`, `newproxy` | Luau puro, zero acesso a host. Bloqueio real do caso de uso central. |
| `buffer` | biblioteca padrão do Luau, presente no Roblox moderno |
| `os.date`, `os.difftime` (somando ao `os` restrito atual) | o `os` do Roblox tem `time`/`date`/`clock`/`difftime`. `getenv`/`exit`/`remove`/`rename`/`tmpname` **continuam fora** — esses sim vazam o host |
| `wait`, `spawn`, `delay`, `tick`, `time` | globais depreciados mas onipresentes em código real; **precisam rotear pelo `Scheduler`**, igual a `task.*` — por isso vivem no `runtime`, não em `cli`. Comentar como depreciados |
| `unpack` | **confirmar antes** (`task-cli-007`): o Luau pode não manter o alias global |
| `debug` | **deliberadamente fora desta leva** — precisa de análise própria (o que `debug.info`/`traceback` revelam de caminho do host dentro de um chunk sandboxed) |

`_G` e `shared` **não** entram na whitelist: são **estado por execução** compartilhado entre os scripts de um mesmo run, não constantes. Quem cria a tabela e injeta em todo `extraGlobals` é `cli` — é o dono do ciclo de vida do run.

### Globais de valor não simulados: erro nomeado, nunca `nil`

`Vector3`, `CFrame`, `Color3`, `Enum` e companhia são leva 3 de `services`. Deixá-los ausentes produz `attempt to index nil with 'new'` — inútil. **Decisão: `src/cli/UnsimulatedGlobals.luau`** monta, para cada nome de uma lista explícita, uma tabela cujo `__index` erra:

```
[LuauBench] Vector3 is not simulated by LuauBench yet (planned: value-types wave)
```

Extensão do LuauBench **fora do namespace de qualquer classe real** (regra 00 permite exatamente isso, em módulo próprio). É a mesma disciplina da regra 03 — "nunca stub silencioso que finge funcionar". Lista da leva 1: `Vector3`, `Vector2`, `CFrame`, `Color3`, `UDim`, `UDim2`, `Rect`, `Region3`, `Ray`, `NumberRange`, `NumberSequence`, `ColorSequence`, `BrickColor`, `TweenInfo`, `PhysicalProperties`, `Faces`, `Axes`, `Random`, `DateTime`, `Font`, `RaycastParams`, `OverlapParams`, `Enum`.

---

## Decisão 13 — Formato do output e idioma

`OutputRecord{level, message, scriptName, line, timestamp}` chega de `Sandbox` e vira terminal.

```
ServerScriptService.Main: hello world
warn  ServerScriptService.Main: cache miss
error ServerScriptService.Main:12: attempt to index nil with 'Foo'
```

- **`print` → stdout (`stdio.write`); `warn` e `error` → stderr (`stdio.ewrite`).** É o comportamento correto de CLI e o que permite `luaubench run > saida.txt` funcionar.
- **Cor** via `stdio.color` (amarelo/vermelho). O Lune 0.10.5 **não expõe detecção de TTY** **[verificado 09-05c]**, então: cor ligada por padrão, desligada por `--no-color` **e** pela variável de ambiente `NO_COLOR` (padrão de facto; `process.env` está disponível).
- **Sem coluna de timestamp** na leva 1. `OutputRecord.timestamp` é `os.time()` (resolução de segundo), inútil como a coluna de milissegundos do Studio, e uma coluna de segundos só rouba largura. Fica para uma flag `--timestamps`.
- **Reatribuição de linha (só em `cli`):** um erro dentro de um `ModuleScript` chega com `record.line == nil` e a `message` contendo `[string "ReplicatedStorage.Modules.Combat"]:12: ...` — porque o `splitErrorMessage` do `Sandbox` procura o marcador do script **de fora**. O `OutputFormatter` faz uma segunda passada sobre esse padrão e renderiza atribuindo ao módulo que de fato errou, citando o script que originou a cadeia. **Isso vive em `cli` de propósito** — é apresentação, e mantém `runtime` intocado.
- **`scriptName`** = `instance:GetFullName()` (dá `ServerScriptService.Main`, a nomenclatura do Studio). Se vier com prefixo `DataModel.`, `cli` remove — uma linha, comentada.

### Idioma: uma decisão que fica marcada para o usuário

Duas vozes distintas, e a separação precisa ser explícita porque é nova:

- **Erro/saída vindo do script do usuário: repassado literalmente, nunca traduzido.** É a voz do motor e das strings do próprio usuário. As famílias de mensagem do Roblox e os `[LuauBench]` já são inglês, por decisão fechada no desenho de `services`.
- **Diagnósticos do próprio CLI** (`.project.json` inválido, flag desconhecida, arquivo não suportado): **recomendo inglês**, porque (a) o LuauBench é publicado no Rokit para o ecossistema Roblox, (b) misturar um erro de projeto em pt-BR com um erro de motor em inglês na mesma tela é pior que qualquer das duas opções sozinha, (c) a regra 00 fixa código/identificadores/commits em inglês e a linha *"Resposta ao usuário: português"* está entre bullets sobre artefatos de agente, não sobre produto publicado.

**É a única ambiguidade real de regra neste desenho, e não a resolvo sozinho.** Mitigação de engenharia: **todas as strings voltadas ao usuário vivem em `src/cli/Messages.luau`** — trocar o idioma inteiro é editar um arquivo, nunca uma refatoração. A decisão pode ser revertida a custo ~zero depois que o usuário se pronunciar.

---

## Decisão 14 — Campos do `.project.json`: aceitar, avisar ou recusar

`cli` **espelha o `deny_unknown_fields` do Rojo no nível raiz**: chave desconhecida no topo é **erro**, nomeando a chave e listando as válidas. Aceitar calado deixaria `"tre"` em vez de `"tree"` passar como projeto vazio — e é o mecanismo que garante, na prática, que ninguém tente enfiar `"luaubench": {...}` ali.

| Campo | Leva 1 |
|---|---|
| `tree` | **obrigatório**; ausente → erro nomeando o campo |
| `name` | usado como `Name` do `DataModel`; ausente → derivado do nome do arquivo/pasta, igual ao Rojo |
| `$schema` | aceito e ignorado (convenção JSON Schema) |
| `servePort`, `serveAddress`, `serveAllowedHosts`, `servePlaceIds`, `blockedPlaceIds`, `placeId`, `gameId`, `syncbackRules` | aceitos e ignorados — só fazem sentido para `serve`/`syncback`. Documentado no código, **sem** warning (não afetam a execução) |
| `emitLegacyScripts` | aceito; `false` → **warning**: o LuauBench não modela `RunContext`, então o mapeamento `.server.lua`→`Script` não muda e o comportamento pode divergir |
| `globIgnorePaths` | aceito; se não-vazio → **warning** de não suportado, listando os globs. Ignorar calado faria o LuauBench carregar arquivos que o usuário excluiu |
| `syncRules` | aceito; se não-vazio → **warning** de não suportado. Mudaria o mapeamento arquivo→classe; aplicar parcialmente seria pior que não aplicar |
| `$id` (nó) | aceito; **warning** (alvos de `Ref` dependem de tipos de valor, leva 3) |
| `$ignoreUnknownInstances` (nó) | aceito e ignorado **sem warning** — é semântica de sincronização bidirecional, sem significado numa carga somente-leitura. Documentado no código |

Raiz com `$className` diferente de `DataModel` (projeto de modelo/pacote) → erro dedicado e claro: `luaubench run` executa place projects; um projeto cuja raiz é `Model` não tem `game`. É um caso comum e merece mensagem própria, não um erro genérico de classe.

---

## Módulos

Todos em `src/cli/`. Território exclusivo de `coder-cli`.

- **`main.luau`** — executável. Lê `process.args`, chama `Cli.Main`, chama `process.exit(code)`. Nada mais. Requer `./` (estilo diretório) — ver "gotcha do `require`" abaixo.
  - Depende de: `./` (init), `@lune/process`.

- **`init.luau`** — API pública programática. Existe para que `tests/scenarios/` (território do `testador`) rode um projeto de ponta a ponta **sem** disparar processo.
  ```luau
  export type MainResult = { ExitCode: number, ErrorCount: number, WarningCount: number }
  function Cli.Main(argv: { string }): MainResult
  function Cli.RunProject(options: RunCommand.RunOptions): MainResult
  ```
  - **Gotcha do `require` (já documentado em `runtime/init.luau` e `services/init.luau`, vale igual aqui):** carregado estilo diretório, o chunk é identificado por `src/cli`, o que desloca a base dos `require` relativos escritos **dentro** deste arquivo em um nível. Aqui dentro: `./cli/Args`, `./cli/RunCommand`, `./runtime`, `./services`. De **fora** de `src/cli/` (qualquer módulo com nome normal): `require("../runtime")`, `require("../services")`, o caminho óbvio.

- **`Messages.luau`** — todas as strings voltadas ao usuário, em um lugar (Decisão 13). Sem lógica.

- **`Args.luau`** — argv → comando + flags.
  ```luau
  export type Command =
      { Kind: "run", ProjectPath: string?, Timeout: number?, NoColor: boolean, Verbose: boolean }
      | { Kind: "version" } | { Kind: "help" }
      | { Kind: "error", Message: string }
  function Args.Parse(argv: { string }): Command
  ```
  Reconhece `--watch` e devolve o motivo real (Decisão 9). Depende de: `Messages`.

- **`Diagnostics.luau`** — coleta e renderização de problemas de projeto.
  ```luau
  export type Severity = "error" | "warning" | "info"
  export type Diagnostic = {
      Severity: Severity, Code: string, Message: string,
      ProjectPath: string?, NodePath: string?, FilePath: string?, Field: string?,
  }
  export type Bag = {
      Add: (self: Bag, diagnostic: Diagnostic) -> (),
      All: (self: Bag) -> { Diagnostic },
      CountOf: (self: Bag, severity: Severity) -> number,
      HasErrors: (self: Bag) -> boolean,
  }
  function Diagnostics.newBag(): Bag
  function Diagnostics.Render(diagnostic: Diagnostic, useColor: boolean): string
  ```
  `Code` é um identificador estável (`project/unknown-field`, `sync/unsupported-extension`, `property/not-a-member`) — dá para o usuário pesquisar e para o teste asserir sem casar texto.

- **`JsonValue.luau`** — narrowing de `unknown` (a saída `any` de `serde`) para JSON tipado, com acessores que carregam o caminho (Decisão 2).
  ```luau
  export type JsonValue = nil | boolean | number | string | { JsonValue } | { [string]: JsonValue }
  function JsonValue.Decode(text: string, sourcePath: string): (JsonValue?, Diagnostics.Diagnostic?)
  function JsonValue.AsObject(value: JsonValue, path: string): ({ [string]: JsonValue }?, Diagnostics.Diagnostic?)
  function JsonValue.AsString(value: JsonValue, path: string): (string?, Diagnostics.Diagnostic?)
  -- ... AsBoolean / AsNumber / AsArray, mesmo formato
  ```
  Único lugar do território com cast de fronteira sobre a saída de `serde`.

- **`SyncRules.luau`** — a tabela da Decisão 6. Dados puros, sem I/O.
  ```luau
  export type FileKind = "Script" | "LocalScript" | "ModuleScript" | "NestedProject" | "MetaFile" | "Unsupported"
  export type DirKind  = "NestedProject" | "ModuleScript" | "Script" | "LocalScript" | "Folder" | "Unsupported"
  function SyncRules.ClassifyFile(fileName: string): (FileKind, string)  -- (kind, nome da Instance sem extensão)
  function SyncRules.ClassifyDir(dirName: string, entries: { string }): (DirKind, string?)  -- (kind, arquivo init)
  ```

- **`ProjectFile.luau`** — localizar, ler e validar o `.project.json` (Decisões 2 e 14).
  ```luau
  export type PathNode = { Kind: "required", Path: string } | { Kind: "optional", Path: string }
  export type ProjectNode = {
      ClassName: string?, Path: PathNode?,
      Properties: { [string]: JsonValue.JsonValue },
      Attributes: { [string]: JsonValue.JsonValue },
      Children: { [string]: ProjectNode },
      NodePath: string,
  }
  export type Project = {
      Name: string?, Tree: ProjectNode, FilePath: string, FolderPath: string,
      EmitLegacyScripts: boolean, GlobIgnorePaths: { string }, HasSyncRules: boolean,
  }
  function ProjectFile.Locate(pathArg: string?, cwd: string): (string?, Diagnostics.Diagnostic?)
  function ProjectFile.Read(filePath: string, bag: Diagnostics.Bag): Project?
  ```
  `Locate`: caminho de arquivo → usa direto; caminho de diretório (ou ausente → `process.cwd`) → procura `default.project.json` e depois `default.project.jsonc` (os `DEFAULT_PROJECT_NAMES` reais do Rojo).

- **`TreePlanner.luau`** — `Project` + filesystem → `InstancePlan` (Decisões 3, 4, 6, 7, 8). **Não requer `runtime` nem `services`**; recebe `IsServiceClass` injetada.
  ```luau
  export type PlanOptions = { IsServiceClass: (className: string) -> boolean }
  function TreePlanner.Plan(project: ProjectFile.Project, options: PlanOptions, bag: Diagnostics.Bag): InstancePlan?
  ```
  É o módulo maior do território e o de maior valor de teste — toda a semântica do Rojo mora aqui, e nada dela precisa de um `DataModel` para ser verificada.

- **`TreeMaterializer.luau`** — `InstancePlan` → `DataModel` real.
  ```luau
  export type MaterializedScript = { Instance: Runtime.Instance, Node: TreePlanner.PlanNode, FullName: string }
  export type MaterializedTree = { Game: Runtime.DataModel, Scripts: { MaterializedScript } }
  function TreeMaterializer.Materialize(plan: InstancePlan, game: Runtime.DataModel, bag: Diagnostics.Bag): MaterializedTree
  ```
  - Service (`IsServiceRoot`) → `game:GetService(ClassName)`; resto → `Services.new(ClassName, Name)`; hierarquia por `.Parent`.
  - `Source` por `Runtime.Instance.SetPropertyRaw`; `$properties` pela via pública com `pcall` (Decisão 7).
  - Devolve a lista de scripts **na ordem determinística do plano** — `ScriptRunner` não precisa reandar a árvore.

- **`UnsimulatedGlobals.luau`** — os globais de valor que erram nomeando a lacuna (Decisão 12).
  ```luau
  function UnsimulatedGlobals.Build(): { [string]: unknown }
  ```

- **`ScriptEnvironment.luau`** — monta o `extraGlobals` de **uma** Instance de script.
  ```luau
  export type EnvironmentContext = {
      Game: Runtime.DataModel, Workspace: Runtime.Instance,
      GlobalTable: { [string]: unknown },   -- `_G`, um por execução
      SharedTable: { [string]: unknown },   -- `shared`, um por execução -- CORREÇÃO 2026-09-05 (task-cli-007): tabela SEPARADA de `_G` no Roblox real, nunca a mesma referência
      Require: (target: unknown) -> unknown,
  }
  function ScriptEnvironment.Build(context: EnvironmentContext, scriptInstance: Runtime.Instance): Runtime.SandboxGlobals
  ```
  Produz `game`, `workspace`, `script`, `Instance = { new = Services.new }`, `require`, `_G`, `shared`, mais `UnsimulatedGlobals`. É o **único** lugar de `cli` que decide o que o script enxerga além da whitelist do `runtime`.

- **`ModuleLoader.luau`** — o `require` simulado (Decisão 5). Depende de `Runtime.Sandbox.Load` (`task-runtime-025`).

- **`ScriptRunner.luau`** — política de execução e disparo (Decisão 11).
  ```luau
  export type RunPolicy = { ServerScriptContainers: { string }, RunLocalScripts: boolean }
  export type RunSummary = { Executed: number, SkippedLocalScripts: number, SkippedByContainer: number, SkippedDisabled: number }
  function ScriptRunner.Run(tree: TreeMaterializer.MaterializedTree, context: RunContext): RunSummary
  ```

- **`OutputFormatter.luau`** — `OutputRecord` → terminal (Decisão 13).
  ```luau
  export type Formatter = {
      Emit: (self: Formatter, record: Runtime.OutputRecord) -> (),
      ErrorCount: (self: Formatter) -> number,
  }
  function OutputFormatter.new(useColor: boolean): Formatter
  ```
  Conta erros — é a fonte do exit code 1.

- **`RunCommand.luau`** — orquestra o pipeline inteiro (abaixo).
  ```luau
  export type RunOptions = { ProjectPath: string?, Cwd: string, Timeout: number?, UseColor: boolean, Verbose: boolean }
  function RunCommand.Execute(options: RunOptions): Cli.MainResult
  ```

- **`fixtures/`** — projetos Rojo mínimos para os specs de `coder-cli`. Ficam **dentro** do território para não colidir com `tests/scenarios/`, que é do `testador` (regra 05). Nota de tooling: a pasta pode precisar de exclusão no `luau-lsp analyze` — um fixture que simula código de usuário nem sempre é `--!strict`-limpo, e isso é o ponto dele.

---

## Pipeline do `luaubench run [caminho]`

```
 1. Args.Parse(process.args)                          -> Command
 2. ProjectFile.Locate(caminho, process.cwd)          -> caminho absoluto do .project.json
 3. ProjectFile.Read(path, bag)                       -> Project (campos de topo validados)
 4. TreePlanner.Plan(project, {IsServiceClass = Services.IsServiceClass}, bag)  -> InstancePlan
        (lê o filesystem; NENHUMA Instance criada ainda)
 5. bag:HasErrors()  ->  imprime TODOS os diagnósticos e sai (exit 2)
 6. scheduler = Runtime.Scheduler.new();  game = Runtime.DataModel.new()
 7. Services.Bootstrap({ scheduler = scheduler, dataModel = game })
 8. para cada c em Services.GetSimulatedServiceClasses(): game:GetService(c)
 9. TreeMaterializer.Materialize(plan, game, bag)     -> MaterializedTree
10. ScriptRunner.Run(tree, ctx)                       -> um Sandbox.Run por Script elegível
11. scheduler:Run(shouldContinue)                      -- shouldContinue = deadline de --timeout
12. imprime sumário (warnings, LocalScripts não executados, erros) e devolve o exit code
```

**Passos 4 e 7 na ordem certa.** `Services.IsServiceClass` é leitura pura do manifesto e **é segura antes de `Bootstrap`** — precisa estar escrito no código de `services`, não subentendido. Planejar antes de registrar dá a propriedade mais valiosa do pipeline: um projeto inválido é recusado com o mundo inteiro ainda não construído.

**Exit codes:** `0` sucesso; `1` o script do usuário levantou ao menos um erro não tratado; `2` erro de projeto ou de uso (argumento inválido, `.project.json` ausente/inválido, raiz não-`DataModel`).

---

## Contrato entre territórios

### `runtime` → `cli` (tudo que `cli` consome; nada mais)

```luau
local Runtime = require("../runtime")

Runtime.Scheduler.new(): Scheduler
Runtime.DataModel.new(): DataModel                       -- + :GetService(className)
Runtime.ClassRegistry.new(className, name): Instance     -- não usado na leva 1 (cli usa Services.new)
Runtime.Instance.GetPropertyRaw(instance, name): unknown -- ler Source
Runtime.Instance.SetPropertyRaw(instance, name, value)   -- gravar Source
Runtime.Signal.new<T...>(): FireableSignal<T...>         -- espera de módulo em voo no ModuleLoader
Runtime.Sandbox.Run(options): SandboxResult              -- Script/LocalScript
Runtime.Sandbox.Load(options): () -> ...unknown          -- NOVO (task-runtime-025): ModuleScript/require
-- tipos: Instance, DataModel, Scheduler, SandboxOptions, SandboxGlobals, OutputRecord, OutputLevel
```

`cli` **nunca** chama `Runtime.ClassRegistry.NewEngineInstance` — está escrito no cabeçalho de `runtime/init.luau` como lista fechada, e a razão é exatamente esta: `$className` vem do arquivo do usuário (entrada não confiável), e `NewEngineInstance` não tem a guarda de `NotCreatable`.

### `services` → `cli`

```luau
local Services = require("../services")

Services.Bootstrap({ scheduler = scheduler, dataModel = game })   -- PRIMEIRO (passo 7)
Services.new(className, name): Instance                            -- extraGlobals.Instance = { new = Services.new }
Services.IsKnownClass(className): boolean
Services.IsSimulatedClass(className): boolean
Services.GetDumpVersion(): { Commit: string, Version: string }     -- `luaubench --version`
Services.IsServiceClass(className): boolean                        -- NOVO — puro, seguro pré-Bootstrap
Services.GetSimulatedServiceClasses(): { string }                  -- NOVO — puro, seguro pré-Bootstrap
```

`cli` **nunca** requer `src/services/generated/**` nem `src/services/behavior/**`, nem toca em `tools/`.

### `cli` → ninguém

`cli` é o topo. Sua superfície pública (`src/cli/init.luau`) existe só para `tests/scenarios/` (território do `testador`), que a consome como biblioteca em vez de disparar processo.

---

## Fluxo de dados

```
.project.json (disco, do usuário)
   -> serde.decode("jsonc")  ->  JsonValue.luau (narrowing + caminho do campo)
   -> ProjectFile.luau       ->  Project{Tree, FolderPath, ...}      [nenhum Runtime envolvido]
   -> TreePlanner.luau       ->  InstancePlan                        [nenhum Runtime envolvido]
        \_ SyncRules: extensão/pasta -> ClassName
        \_ fs.readDir/isFile/readFile: filhos e Source
        \_ Services.IsServiceClass: inferência de Service sob a raiz (leitura pura de manifesto)
        \_ projeto aninhado: recursão com base de path própria
   -------------------------------- fronteira: nada foi criado até aqui --------------------------------
   -> TreeMaterializer.luau
        \_ game:GetService(C)                             (Service sob a raiz)
        \_ Services.new(C, nome); inst.Parent = pai       (resto)
        \_ Runtime.Instance.SetPropertyRaw(inst,"Source") (Script/LocalScript/ModuleScript)
        \_ inst[prop] = valor via __newindex               ($properties, enforcement do schema)
   -> ScriptRunner -> Runtime.Sandbox.Run{ extraGlobals = ScriptEnvironment.Build(...) }
        \_ o script chama require(m) -> ModuleLoader -> Runtime.Sandbox.Load -> chunk() na MESMA thread
   -> scheduler:Run(shouldContinue)
   -> OutputRecord -> OutputFormatter -> stdout/stderr
```

---

## Divisão por território

| Território | O que constrói nesta leva | Contrato com o vizinho |
|---|---|---|
| `cli` (`src/cli/`) | os 15 módulos acima + fixtures | Consome só `require("../runtime")` e `require("../services")`. Nunca `generated/`/`behavior/`/`tools/`; nunca `NewEngineInstance` |
| `runtime` (`src/runtime/`) | **`task-runtime-025`**: `Sandbox.Load`. **`task-runtime-026`**: completar a whitelist de globals | Continua sem conhecer nome de classe e sem ler `.project.json`. As duas mudanças são aditivas — nenhuma assinatura existente muda |
| `services` (`src/services/`) | **`task-services-009`**: `IsServiceClass` + `GetSimulatedServiceClasses` | Leitura pura do manifesto, sem tocar `ClassRegistry`/`Context` — explicitamente segura antes de `Bootstrap` |
| `pesquisador` | **`task-cli-007`**: cinco perguntas abaixo | Read-only, roda em paralelo com tudo |

**Paralelismo real:** dentro de `cli` as tarefas são sequenciais (mesmo território, dependências reais de tipo entre os módulos). O paralelismo é *entre* territórios: na primeira leva, `coder-runtime` (025/026), `coder-services` (009) e `pesquisador` (007) rodam ao lado de `coder-cli` (001/002/003), que não depende de nenhum dos três até a task 004.

---

## Fidelidade vs. pragmatismo

Toda aproximação da leva 1, explicitamente.

| Área | Fidelidade |
|---|---|
| Schema do `.project.json` (campos de topo, `ProjectNode`, `PathNode`) | **Exato** — reproduz o `deny_unknown_fields` do Rojo v7.7.0, inclusive o erro por campo desconhecido |
| Tabela extensão→ClassName e prioridade de diretório | **Exata para o subconjunto suportado**; todo padrão fora do subconjunto vira warning nomeado, nunca omissão silenciosa |
| Resolução de `$path` (relativa ao projeto que define o nó; forma `optional`) | **Exata** |
| Projetos aninhados (`default.project.json`) | **Exato**, com proteção de ciclo que o Rojo não precisa ter |
| Inferência de Service sob a raiz | **Exata em critério** (tag `Service`), mas contra o **`Full-API-Dump.json`** e não contra o `rbx_reflection_database` que o Rojo usa. Fontes distintas, ambas oficiais — divergência possível em classe recém-adicionada |
| Service na raiz com `Name ~= ClassName` | **Divergente**: o Rojo permite, o LuauBench erra. `DataModel:GetService` é dono da nomeação do singleton |
| `$properties` primitivo (`boolean`/`number`/`string`) | Aplicado pela via pública; nome inválido ou somente-leitura **erra**, como no Rojo |
| `$properties` `Vector3`/`Color3`/`CFrame`/`EnumItem` | **Pulado com warning.** Não há tipos de valor (leva 3 de `services`); gravar a tabela crua mentiria |
| `$properties` string ambígua (pode ser `EnumItem` no Rojo) | Gravada como string. Divergência conhecida enquanto não houver `Enum` |
| `$attributes` | **Pulado com warning** — `Instance:SetAttribute` não é simulado |
| `globIgnorePaths`, `syncRules`, `$id`, `emitLegacyScripts: false` | Aceitos, **não aplicados, com warning**. Aplicar pela metade seria pior que não aplicar |
| `$ignoreUnknownInstances` | Aceito e ignorado sem warning — semântica de sincronização bidirecional, sem sentido numa carga somente-leitura |
| `Source` de Script/ModuleScript | **Exato** — vive fora do schema, via `Get/SetPropertyRaw`, e continua ilegível pelo script (como no Roblox) |
| `require` (cache, ciclo, espera de módulo em voo, yield propagado) | **Fiel na semântica.** As **mensagens** de erro são aproximação de boa-fé, marcadas como tal no código |
| `require(assetId)` | **Erra com `[LuauBench]`** — não tem contraparte (lá funciona); a razão é local-first (regra 00) |
| Quais `Script` executam | **Aproximação declarada**: descendentes de `ServerScriptService` e `Workspace`. Confirmado por `task-cli-007` contra `Roblox/creator-docs` — a lista está correta |
| `LocalScript` | **Nunca executa.** LuauBench é servidor — coerente com `IsServer()==true` e com a recusa de `RenderStepped`. Contado no sumário final |
| Ordem de execução entre Scripts | **Determinística** (profundidade primeiro, contêiner, nome). O Roblox real não garante ordem — não é "a ordem do Roblox", é *uma* ordem estável |
| `_G` / `shared` | **CORREÇÃO 2026-09-05 (`task-cli-007`)**: `_G` e `shared` são tabelas SEPARADAS no Roblox real — não usar a mesma tabela para os dois. Duas tabelas por execução, cada uma compartilhada entre os scripts do run; ambas injetadas em `extraGlobals` por `cli`, mesmo ciclo de vida de antes, só que agora `SharedTable`/`GlobalTable` são duas instâncias distintas, não uma só reaproveitada |
| `Vector3`/`CFrame`/`Color3`/`Enum`/... | **Existem como sentinela que erra nomeando a lacuna**, nunca `nil` silencioso |
| Watch mode | **Ausente**, com o motivo técnico impresso quando `--watch` é passado |
| Cor no terminal | Ligada por padrão; sem detecção de TTY no Lune 0.10.5 — `--no-color` e `NO_COLOR` cobrem o caso de pipe |
| Timestamp no output | Ausente na leva 1 (`OutputRecord.timestamp` tem resolução de segundo; o Studio mostra ms) |

---

## Riscos e decisões

- **A whitelist do `Sandbox` sem `setmetatable` invalida o caso de uso central.** É o risco número um. Um `cli` impecável rodando sobre a whitelist de hoje falha no primeiro módulo OOP — ProfileStore, state manager, qualquer classe. Por isso `task-runtime-026` **bloqueia** a tarefa de execução ponta a ponta (`task-cli-006`), e `revisor-cli` deve reprovar um fechamento de leva que não tenha rodado um fixture com `setmetatable`.
- **`Sandbox.Load` é pré-requisito estrito de `require`.** Sem ela, a única saída seria `cli` chamar `luau.load` por conta própria — fork da superfície de segurança, proibido pela regra 00. `task-runtime-025` bloqueia `task-cli-005`.
- **Script que trava (`while true do end` sem yield):** risco já registrado e aceito no desenho do `runtime` (o laço de `coroutine.resume` é síncrono e não há preempção). `--timeout` **não resolve esse caso** — `shouldContinue` só é consultado entre frames. Ele resolve o caso muito mais comum (`while true do task.wait() end`), e é assim que deve ser documentado: uma rede de segurança para o script que cede, não um watchdog.
- **`.project.json` inválido:** todo caminho de falha produz `Diagnostic` com `Code`/`NodePath`/`Field`, nunca um erro cru de `serde`. `TreePlanner` acumula em vez de abortar no primeiro, e o comando imprime todos antes de sair com código 2 — sem nenhuma Instance criada.
- **Recursão de projeto aninhado sem fim:** único ponto de recursão não-limitada. Proteção obrigatória por conjunto de caminhos absolutos no ramo corrente; ciclo → erro listando a cadeia.
- **Projeto enorme:** o walk lê **todo** arquivo suportado para dentro da memória (`Source`). Um projeto com milhares de módulos carrega tudo. Aceito nesta fase (é o que o Rojo também faz, e a alternativa — leitura preguiçosa no `require` — complica o plano sem ganho medido). Se aparecer como problema real, vira tarefa própria.
- **Divergência de semântica com o Rojo ao longo do tempo:** `cli` reimplementa regras de um projeto que evolui. Mitigação: `SyncRules.luau` isolado, versão de referência no cabeçalho, e `pesquisador` revalidando quando o Rojo publicar major.
- **Idioma dos diagnósticos do CLI:** única ambiguidade real de regra. Decidido inglês com justificativa, **marcado para o usuário confirmar**, e isolado em `Messages.luau` para que reverter custe um arquivo.
- **`GetFullName()` incluindo ou não o `DataModel`:** não confirmado. `cli` remove o prefixo se existir — uma linha, comentada. Risco baixo, custo de erro nulo.
- **Empacotamento Rokit não foi desenhado aqui.** `lune build` gera executável standalone, mas **se ele embute os `require` de múltiplos arquivos num único binário não foi confirmado** — se não embutir, a estrutura de `src/` precisa de um passo de bundle antes do build, o que muda a topologia do repositório. É pergunta de `task-cli-007` e **precisa estar respondida antes de qualquer tarefa de release**, não antes desta leva.

---

## Escopo da leva 1

**Entra:** parser do `.project.json` (schema completo de topo + nó), convenção arquivo→ClassName para scripts e pastas, `$path` (obrigatório e opcional), projetos aninhados, meta files, `$properties` primitivo, planejamento puro + materialização no `DataModel`, pré-criação dos Services simulados, `require` simulado com cache/ciclo/espera, execução dos `Script` elegíveis, output formatado com stdout/stderr e cor, `--timeout`/`--no-color`/`--verbose`/`--version`/`--help`, exit codes, e fixtures próprios.

**Não entra (e por quê):**

- **Watch mode** — o Lune 0.10.5 não tem observador de filesystem, e polling viola a regra 04. Decisão do usuário, não do arquiteto (Decisão 9).
- **Empacotamento Rokit / `lune build` / GitHub Release** — depende de saber se `lune build` embute `require`. Pesquisa primeiro (`task-cli-007`).
- **`luaubench.toml`** — nenhuma configuração é necessária ainda; nome e formato ficam reservados (Decisão 10).
- **`--client`** — o LuauBench é servidor por decisão fechada de `services`; um modo cliente mexe em `RunService`, `RenderStepped` e na política de `LocalScript` ao mesmo tempo. Tarefa própria.
- **`.json`/`.toml`/`.csv`/`.txt`/`.rbxm`/`.rbxmx`/`.model.json`/`.yaml`/`.plugin.*`** — reconhecidos e reportados; `LocalizationTable`/`StringValue` nem estão na leva 1 de `services`, e `.model.json` tem formato não confirmado.
- **`globIgnorePaths` e `syncRules` aplicados** — precisam de um motor de glob e de mapeamento customizado; aceitos com warning.
- **`$attributes`** — `Instance:SetAttribute` não é simulado.
- **`$id` / propriedades `Ref`** — dependem de tipos de valor (leva 3 de `services`).
- **Sourcemap como fonte de entrada** — estritamente mais fraco que o `.project.json` (Decisão 1).
- **`debug` no sandbox** — precisa de análise própria do que vaza do host.
- **Recarga incremental de módulo** — pré-requisito de watch mode, e depende dele.
- **`game:BindToClose`** — leva 2 de `services`, e é membro do `DataModel` (território de `runtime`).

---

## Pendências para o `pesquisador` (`task-cli-007`, cinco perguntas — nenhuma bloqueia o início)

1. **`lune build`**: embute os módulos `require`ados num único executável standalone, ou exige um arquivo único (bundle prévio)? Qual a invocação exata e o layout esperado? — **bloqueia qualquer tarefa de release**, não esta leva.
2. **Watcher de filesystem no Lune**: confirmar a ausência em 0.10.5 e verificar se alguma versão publicada (ou roadmap) expõe `fs.watch`/equivalente. É o insumo da conversa com o usuário sobre watch mode.
3. **Quais contêineres executam `Script` (RunContext Legacy) num servidor Roblox real** — a lista exata. Hoje o desenho assume `ServerScriptService` + `Workspace`.
4. **Mensagens reais de `require`**: (a) módulo requerido recursivamente, (b) módulo que não retorna exatamente um valor, (c) `require` com argumento inválido. As três são aproximação de boa-fé hoje.
5. **Ambiente global do Roblox real**: `unpack` ainda existe como global? `shared` e `_G` são a mesma tabela no servidor? `tick`/`time`/`elapsedTime` continuam disponíveis (mesmo depreciados)?

---

## Decisão que precisa do usuário

**Idioma dos diagnósticos do próprio CLI** (`.project.json` inválido, flag desconhecida, arquivo não suportado). Recomendação: **inglês**, pelas razões da Decisão 13. A regra 00 diz "Resposta ao usuário: português (pt-BR)" numa seção que trata de artefatos de agente, e o LuauBench é publicado no Rokit para o ecossistema Roblox, onde toda a saída de motor já é inglês. **Todas as strings ficam em `src/cli/Messages.luau`** — reverter é editar um arquivo. Não implementei a escolha como irreversível de propósito.
