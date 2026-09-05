# Pesquisa `task-cli-007` — `lune build`/bundling, watcher de filesystem, contêineres de `Script`, mensagens de `require`, globais do Roblox

Data: 2026-09-05. Fontes consultadas: código-fonte real de `lune-org/lune` (branch `main` e tag `v0.10.5`, via `gh api`), `CHANGELOG.md` oficial do Lune, issue tracker oficial do Lune, repositório oficial `Roblox/creator-docs` (YAML/Markdown fonte de `create.roblox.com/docs`), DevForum como pista (marcado explicitamente onde usado).

---

## 1. `lune build` — embute múltiplos arquivos ou exige arquivo único?

**Resposta curta:** `lune build` **NÃO embute o grafo de `require`**. Ele lê e compila **só o arquivo de entrada** em bytecode e o grava dentro de uma cópia do binário do interpretador Lune. Se `main.luau` faz `require` de outros módulos (o caso do LuauBench: `src/cli/main.luau` → `src/cli/init.luau` → `src/runtime` + `src/services` + resto de `src/cli/`), **o repositório precisa de um passo de bundle** (ex: darklua) antes do `lune build`, ou o release deixa de ser um único executável de verdade.

**Fatos verificados**
- Código-fonte real, `crates/lune/src/cli/build/mod.rs`, idêntico em `main` e na tag `v0.10.5` (branches divergem em zero linhas neste arquivo) — [github.com/lune-org/lune/blob/main/crates/lune/src/cli/build/mod.rs](https://github.com/lune-org/lune/blob/main/crates/lune/src/cli/build/mod.rs), lido em 2026-09-05: `BuildCommand::run` faz `fs::read(&self.input)` — só o arquivo passado como argumento — com o comentário no próprio código:
  ```
  // Try to read the given input file
  // FUTURE: We should try and resolve a full require file graph using the input
  // path here instead, see the notes in the `standalone` module for more details
  ```
- `crates/lune/src/standalone/tracer.rs` (idêntico em `main` e `v0.10.5`) é um **stub vazio** — só um bloco de comentário `TODO: Implement tracing of requires here` com um esboço de passos futuros, zero código funcional. `crates/lune/src/standalone/mod.rs` declara o módulo (`pub(crate) mod tracer;`) mas não o invoca em lugar nenhum do pipeline de build/execução standalone.
- `CHANGELOG.md` oficial, versão `0.8.0` (14 de janeiro de 2024, que introduziu o comando) — [github.com/lune-org/lune/blob/main/CHANGELOG.md](https://github.com/lune-org/lune/blob/main/CHANGELOG.md), citação literal:
  > "To compile scripts that use `require` and reference multiple files, a bundler such as [darklua](https://github.com/seaofvoices/darklua) should preferrably be used. You may also distribute files alongside the standalone binary, they will still be able to be `require`-d. **This limitation will be lifted in the future and Lune will automatically bundle any referenced scripts.**"
- Essa promessa de "no futuro" segue **não cumprida quase 2 anos depois** — o `tracer.rs` de `main` (checado hoje, 2026-09-05) continua exatamente no mesmo estado de esboço não implementado.

**Exemplo mínimo**
```sh
# invocação exata, do CHANGELOG 0.8.0
lune build my_cool_script.luau
# Windows -> my_cool_script.exe
# macOS/Linux -> my_cool_script (sem extensão)

# com flags (0.8.4+)
lune build src/cli/main.luau --output luaubench --target windows-x86_64
```

**Limites e pegadinhas**
- "Distribuir arquivos ao lado do binário" significa que, em runtime, `require` continua lendo do **disco**, relativo ao arquivo — ou seja, sem bundle prévio, o release do LuauBench vira um `.zip` com o `.exe` + a árvore inteira de módulos `.luau`, o oposto de "executável standalone" que a regra 04/invariante 4 descreve.
- **Consequência direta para o board:** `src/cli/main.luau` hoje faz `require` de `./cli/*`, `../runtime`, `../services` (múltiplos arquivos). Release via Rokit vai exigir uma de duas saídas, **decisão do usuário antes de qualquer tarefa de release**:
  1. Rodar `darklua bundle` (ferramenta de **build-time/CI**, não entra no processo do LuauBench em runtime — não fere a invariante 3, que é sobre binário externo em tempo de execução) para produzir um único `.luau` antes do `lune build`;
  2. Mudar a distribuição para "pasta" (exe + módulos), o que muda o manifesto compatível com Rokit e o fluxo `rokit add`.
- `darklua` ainda é uma peça nova no pipeline (dependência de build, não de runtime) — precisa aparecer documentada explicitamente (CI, README) mesmo não violando invariante nenhuma.

**Incerto**
- Não executei `lune build` nem `darklua bundle` empiricamente nesta sessão (ambiente de pesquisa é read-only, sem Lune instalado aqui) — a confirmação é 100% leitura de código-fonte oficial + changelog oficial, não teste de execução.

---

## 2. Watcher de filesystem no Lune

**Resposta curta:** **Ausência confirmada** em 0.10.5 **e** na branch `main` atual (nenhuma mudança). Existe um issue oficial aberto desde 2023 pedindo a feature, **sem implementação, sem branch de trabalho, sem prazo comprometido por mantenedor**. As três saídas já levantadas pelo arquiteto (atualizar Lune / binário externo / polling) continuam sendo as únicas possíveis — nada nesta pesquisa muda isso, só reforça que não há sinal de mudança iminente.

**Fatos verificados**
- Código-fonte real, `crates/lune-std-fs/src/lib.rs` (branch `main`, 2026-09-05) registra exatamente 11 funções: `readFile`, `readDir`, `writeFile`, `writeDir`, `removeFile`, `removeDir`, `metadata`, `isFile`, `isDir`, `move`, `copy` — nenhuma outra, nem em `main` nem em `v0.10.5` (mesma lista já levantada localmente nos typedefs instalados).
- `crates/lune-std-fs/types.d.luau` (branch `main`) — mesmas 11 assinaturas, sem `watch`.
- Diretório `crates/lune-std-fs/src/` só tem `copy.rs`, `metadata.rs`, `options.rs`, `lib.rs` — ausência **estrutural** (nem um arquivo `watch.rs` esboçado), diferente do caso de `lune build` onde ao menos existe um stub (`tracer.rs`).
- Issue oficial **[lune-org/lune#63 "Add an API for watching for file changes"](https://github.com/lune-org/lune/issues/63)**, aberta em 2023-07-08, **status: open**, última atividade 2024-12-16 (quase 3 anos sem fechamento). Corpo do issue é uma proposta de API explicitamente "subject to change":
  ```lua
  fs.watch(rootPath: string, patternOrOptions: string | FsWatchOptions, ...)
  ```
  com nota do próprio autor: "filesystem watching is notoriously tricky and we would want this to work across all platforms that Lune currently supports [...] it might also be worth re-evaluating some other APIs". Dois comentários de usuários da comunidade pedindo a feature (2024-09, 2024-12), nenhuma resposta de mantenedor.
- Repositório não tem `ROADMAP.md` (só `README.md` na raiz) — não há compromisso público de prazo em lugar nenhum do repo.

**Limites e pegadinhas**
- Encontrei um fork de terceiros (`0x5eal/lune-fs-watch`) — é experimento pessoal não vinculado ao upstream oficial, não conta como fonte confirmatória nem como caminho de instalação suportado.
- Nada nesta pesquisa resolve a tensão regra 04 (proíbe polling) vs. ausência real de watcher — é exatamente a decisão que precisa ir para o usuário, com estes fatos como insumo.

**Incerto**
- Impossível prever se/quando `fs.watch` será implementado — não há RFC, branch de trabalho nem menção em PR aberto.

---

## 3. Quais contêineres executam `Script` (RunContext Legacy) no servidor real

**Resposta curta:** **Confirmado por fonte oficial**, o desenho do arquiteto está correto: **`Workspace` e `ServerScriptService`** são os únicos contêineres onde um `Script` com `RunContext = Legacy` (o default) executa automaticamente no servidor.

**Fatos verificados**
- Fonte primária oficial (repositório que alimenta `create.roblox.com/docs`): `Roblox/creator-docs`, `content/en-us/scripting/locations.md` — [github.com/Roblox/creator-docs/blob/main/content/en-us/scripting/locations.md](https://github.com/Roblox/creator-docs/blob/main/content/en-us/scripting/locations.md), citação literal:
  > "When you create a `Class.Script`, its default run context is `Legacy`, meaning that it a) is a server-side script and b) only runs if it is in a server container, such as `Class.Workspace` or `Class.ServerScriptService`."
- Mesma fonte, tabela de locations embutida (`content/en-us/includes/engine-comparisons/script-locations.md`), linha `ServerStorage`:
  > "Scripts do not run from this location, but you can store server-side `ModuleScripts` here."
  — confirma explicitamente que `ServerStorage`, apesar de ser server-side, **não** é contêiner de execução.
- A mesma tabela confirma que `ReplicatedFirst`/`ReplicatedStorage` só rodam `Script` com `RunContext = Client` (não Legacy) e que os `Starter*`/`StarterGui`/`StarterPack` só rodam `LocalScript`.

**Limites e pegadinhas**
- A frase oficial usa "such as", tecnicamente não-exaustiva por construção gramatical — mas a tabela de locations cobre **todos** os contêineres padrão do Explorer e nenhum outro aparece como executando `Script` Legacy, então a lista de 2 é exaustiva na prática para os contêineres padrão.
- Um `Script` com `RunContext = Server` (configuração explícita, não o default Legacy) também roda em `ReplicatedStorage` — irrelevante para o `RunPolicy` da leva 1 do LuauBench, que modela exatamente o caso Legacy/default.

**Incerto:** nada — dupla confirmação de fonte primária (texto + tabela), sem contradição.

---

## 4. Mensagens reais de `require`

**Resposta curta:** As três strings já usadas no desenho como "aproximação de boa-fé" **batem com o texto relatado de forma consistente na comunidade**, mas **não encontrei confirmação em documentação oficial** — o mecanismo de `require` do Roblox é fechado (closed-source), `create.roblox.com` não documenta as strings de erro literalmente. Tratar como **não confirmado por fonte primária**, porém de confiança alta (repetição idêntica e independente ao longo de anos).

**Fatos verificados (fonte: DevForum, comunidade — marcado como pista, não fonte primária)**
- `"Requested module was required recursively"` — usado como título literal de pelo menos 4 threads distintas do DevForum (ex: [t/1292666](https://devforum.roblox.com/t/requested-module-was-required-recursively/1292666), [t/2947916](https://devforum.roblox.com/t/recursive-module-requiring-workaround/2947916)), o que sugere cópia exata da mensagem real (usuários normalmente colam a saída do Output literalmente no título).
- `"Module code did not return exactly one value"` — título literal de ao menos 7 threads distintas (ex: [t/1526973](https://devforum.roblox.com/t/module-code-did-not-return-exactly-one-value/1526973), [t/2667034](https://devforum.roblox.com/t/how-do-i-fix-module-code-did-not-return-exactly-one-value/2667034)).
- `"Attempted to call require with invalid argument(s)."` — título literal (com o ponto final) de ao menos 5 threads (ex: [t/729867](https://devforum.roblox.com/t/attempted-to-call-require-with-invalid-arguments/729867)).
- Post de compilação da comunidade — [devforum.roblox.com/t/most-require-errors-and-their-meanings-and-how-they-occur/2998009](https://devforum.roblox.com/t/most-require-errors-and-their-meanings-and-how-they-occur/2998009) — lista as três acima e mais sete relacionadas fora do escopo da leva 1 (`"Requested module experienced an error while loading"`, `"...while setting Instance parents"`, mensagens de asset id, `"Cannot require a non-RobloxScript module from a RobloxScript"`, `"Requested module has already been destroyed"`).

**Limites e pegadinhas**
- `create.roblox.com` não documenta strings de erro do `require` em lugar nenhum da referência oficial checada (página do global `require`, `Global.LuaGlobals.require`) — não há página de "mensagens de erro" oficial para comparar.
- O texto exato pode variar entre versões do engine sem anúncio formal — tratar como aproximação estável de longo prazo (as mesmas strings aparecem em threads de 2019 a 2025), não como contrato imutável.

**Incerto:** as três strings não têm confirmação de fonte primária (código-fonte do motor Roblox é fechado); mantidas como estão no desenho, com o mesmo selo de "aproximação de boa-fé" já usado.

---

## 5. Ambiente global do Roblox real

**Resposta curta:**
- **`unpack`**: confirmado que **ainda existe** como global, **não depreciado** na documentação oficial atual. Pode entrar em `task-runtime-026` sem ressalva de depreciação.
- **`shared` e `_G`**: são **tabelas separadas**, não a mesma. Confirmado estruturalmente (duas entradas distintas em duas páginas de referência oficiais diferentes, sem nenhuma nota de equivalência) e reforçado por teste empírico relatado na comunidade.
- **`tick`/`time`**: confirmado que **NÃO estão marcados como depreciados** na documentação oficial atual (contrário à crença comum). **`elapsedTime`** está marcado `Deprecated`. `spawn`/`delay`/`wait` também estão `Deprecated`, com `deprecation_message` apontando para `task.spawn()`/`task.delay()`/`task.wait()`.

**Fatos verificados**
- Fonte primária oficial, `Roblox/creator-docs`, `content/en-us/reference/engine/globals/LuaGlobals.yaml` (fonte YAML que gera `create.roblox.com/docs/reference/engine/globals/LuaGlobals`):
  - `unpack`: `tags: []` (sem `Deprecated`), descrição funcional completa com exemplo de código (`print(unpack(t))`).
  - `_G`: `tags: []`, descrição: "A table that is shared between all scripts of the same context level."
- Mesma fonte oficial, `content/en-us/reference/engine/globals/RobloxGlobals.yaml`:
  - `shared`: `tags: []`, descrição: "A table shared between all code running at the same execution context level."
  - `tick` (linha 265): `tags: []` — **sem** `Deprecated`.
  - `time` (linha 289): `tags: []` — **sem** `Deprecated`.
  - `elapsedTime` (linha 143): `tags: [Deprecated]`.
  - `spawn` (linha 215): `tags: [Deprecated]`, `deprecation_message`: "This method has been superseded by `Library.task.spawn()` and should not be used for future work."
  - `delay` (linha 88): `tags: [Deprecated]`, mesma fórmula apontando para `task.delay()`.
  - `wait` (linha 371): `tags: [Deprecated]`, mesma fórmula apontando para `task.wait()`.
- DevForum (comunidade, pista): relato com teste empírico mostrando que `shared.Test = 'Test'` não aparece em `_G.Test` — [devforum.roblox.com/t/shared-vs-g-whats-the-difference/174035](https://devforum.roblox.com/t/shared-vs-g-whats-the-difference/174035) — corrobora a leitura estrutural dos dois YAMLs oficiais.

**Limites e pegadinhas**
- As descrições de `_G` e `shared` usam quase o mesmo texto ("context level" / "execution context level") — **mesmo escopo de compartilhamento**, mas são **tabelas diferentes**. Isso é relevante para a Decisão 12/`ScriptEnvironment.Build` do desenho de `cli`: hoje o desenho propõe "uma tabela por execução, compartilhada entre os scripts do run" para os dois (`_G`/`shared`, mesma `SharedTable`). Isso é uma **divergência real** do Roblox (lá, escrever em `shared` não aparece em `_G`) — recomendo tratar como divergência declarada explicitamente no código (comentário) OU, a custo baixo, usar duas tabelas separadas desde já (mesma implementação, só duplicar a referência em vez de reaproveitar uma).
- Não encontrei nenhuma frase oficial em prosa dizendo literalmente "`_G` e `shared` são tabelas diferentes" — a conclusão vem da estrutura da documentação (duas entradas oficiais distintas, sem cross-reference) + teste empírico de comunidade, não de uma declaração direta da Roblox.

**Incerto**
- Não há declaração oficial explícita de equivalência ou não-equivalência entre `_G`/`shared` — tratado como confirmado para fins de decisão de fidelidade (evidência combinada forte), mas registrando a proveniência (estrutural + comunidade, não prosa oficial direta).
