# Pesquisa — `lune build` e `require()` multi-arquivo em binário standalone

Data: 2026-09-07. Lune pinado no projeto: `0.10.5` (`rokit.toml:7`, confirmado).

## Pergunta 1 — `lune build` suporta `require()` relativo entre arquivos?

**Resposta curta: NÃO. Confirmado tanto pela documentação/changelog oficial quanto lendo o código-fonte real do comando `build` na tag `v0.10.5`.** `lune build` compila e embute **só o bytecode do arquivo de entrada único**. Não existe nenhuma flag em `lune build --help` (`input`, `--output`, `--target` são os únicos parâmetros) para resolver grafo de `require` — e a funcionalidade de rastrear/agrupar requires está **literalmente um TODO não implementado** no próprio código do Lune 0.10.5.

### Fatos verificados (fonte primária)

- **CHANGELOG oficial, entrada da versão `0.8.0` (14 jan 2024)**, quando `lune build` foi introduzido — texto ainda válido, nenhuma entrada posterior (`0.8.1` até `0.10.5`, li o changelog inteiro) revoga isso:
  > "To compile scripts that use `require` and reference multiple files, a bundler such as [darklua](https://github.com/seaofvoices/darklua) should preferrably be used. You may also distribute files alongside the standalone binary, they will still be able to be `require`-d. **This limitation will be lifted in the future and Lune will automatically bundle any referenced scripts.**"
  — https://github.com/lune-org/lune/blob/main/CHANGELOG.md (linha 591 no snapshot lido)

- **Código-fonte real, tag `v0.10.5`** (a mesma versão pinada no `rokit.toml` do projeto):
  - `crates/lune/src/cli/build/mod.rs`, linhas 68-73 — o comando `build` só lê o arquivo de entrada isolado:
    ```rust
    // Try to read the given input file
    // FUTURE: We should try and resolve a full require file graph using the input
    // path here instead, see the notes in the `standalone` module for more details
    let source_code = fs::read(&self.input)
        .await
        .context("failed to read input file")?;
    ```
  - `crates/lune/src/standalone/tracer.rs` — o arquivo **inteiro** é um stub vazio, não implementado:
    ```rust
    /*
        TODO: Implement tracing of requires here

        Rough steps / outline:

        1. Create a new tracer struct using a main entrypoint script path
        2. Some kind of discovery mechanism that goes through all require chains (failing on recursive ones)
           ...
        3. ???
        4. Profit
    */
    ```
  - `crates/lune/src/standalone/metadata.rs`, `create_env_patched_bin` — compila **só** o `script_contents` recebido (um único blob) e anexa esse bytecode ao final do binário base do Lune, com um marcador mágico (`cr3sc3nt`). Não há nenhum mecanismo de empacotar múltiplos arquivos.
  - `crates/lune/src/standalone/mod.rs`, função `run` — em runtime, o binário standalone só carrega esse blob único e o executa como `rt.run_custom("STANDALONE", meta.bytecode)`. É exatamente o `Script 'STANDALONE', Line 24` que aparece no stack trace do usuário.

- **Causa raiz exata do crash** (nova descoberta, não estava no changelog): a mensagem `require is not supported in this context` **não é do Lune** — vem direto do binding Luau do `mlua` (crate Rust que o Lune usa como runtime Luau, confirmado por `use mlua::Compiler as LuaCompiler;` em `standalone/metadata.rs`). Código-fonte de `mlua-rs/mlua`, `src/luau/require.rs`, função `find_current_file` (dentro de `create_require_function`):
  ```rust
  unsafe extern "C-unwind" fn find_current_file(state: *mut ffi::lua_State) -> c_int {
      let mut ar: ffi::lua_Debug = mem::zeroed();
      for level in 2.. {
          if ffi::lua_getinfo(state, level, cstr!("s"), &mut ar) == 0 {
              ffi::luaL_error(state, cstr!("require is not supported in this context"));
          }
          if CStr::from_ptr(ar.what) != c"C" {
              break;
          }
      }
      ffi::lua_pushstring(state, ar.source);
      1
  }
  ```
  Esse mecanismo sobe a pilha de chamadas Lua procurando o frame Lua real de quem chamou `require`, para resolver o path relativo. Quando `lune run` executa um script normal, ele passa pelo sistema de require-by-string com um chunk devidamente registrado. Quando `lune build` gera o binário, o script vira um chunk sintético chamado `"STANDALONE"` executado via `rt.run_custom(...)` — fora do caminho normal de carregamento de arquivo — e por isso o `require()` já falha na primeira chamada, mesmo relativa e mesmo no próprio arquivo de entrada. Isso bate 100% com o stack trace relatado: `proxyrequire` → `__mlua_require, Line 13` → `STANDALONE, Line 24`.
  - Fonte: `gh search code` (autenticado) localizou a string exata em `mlua-rs/mlua:src/luau/require.rs` e `luau-lang/luau:Require/src/RequireImpl.cpp`. Conteúdo lido via `gh api repos/mlua-rs/mlua/contents/src/luau/require.rs`.

### Conclusão da pergunta 1

`lune build` em `0.10.5` só suporta um **único arquivo autocontido, sem `require()` de arquivo local nenhum** (nem relativo, nem por diretório/`init.luau`). `src/cli/main.luau` fazendo `require("./")` — ou qualquer outro `require` relativo — nunca vai funcionar dentro do binário standalone gerado por essa versão do Lune, ponto.

## Pergunta 2 — solução padrão do ecossistema

**Resposta curta: bundlar com `darklua` antes de rodar `lune build`, usando o `require_mode: "luau"` (não `"path"`) — é o modo que a própria documentação do darklua diz ser "the require mode used by the Lune runtime".** Isso é exatamente o que a nota do CHANGELOG do Lune recomenda, e é o único caminho hoje (a "flag" nativa do `lune build` para isso não existe — não foi "perdida" pelo usuário, não existe mesmo).

### Fatos verificados

- **darklua tem um comando de bundling real**, não é só um formatter/minifier. Fonte primária: `site/content/docs/bundle/index.md` do repositório `seaofvoices/darklua` (branch `main`, lido via raw GitHub):
  > "Darklua is capable of bundling Lua code: it will start from a given file and attempt to merge every require into a single file."

  Config mínima:
  ```json5
  {
    bundle: {
      require_mode: "path",
    },
  }
  ```
  Comando:
  ```sh
  darklua process entry-point.lua bundled.lua
  ```
  ("Given the `entry-point.lua`, darklua will recursively follow the requires and inline the code into a single `bundled.lua` file.")

- **Existem 2 modos de require para bundling: `path` e `luau`** — e para o caso do LuauBench (que usa exatamente a semântica de `require` do Lune: relativo com `./`/`../`, `@self` dentro de `init.luau`, potencialmente `.luaurc`), o modo certo é `"luau"`, não `"path"` (a hipótese do pedido original citava `"path"`, mas a doc oficial do darklua diz o contrário). Fonte: `https://darklua.com/docs/luau-require-mode/`:
  > "Luau require mode is intended for resolving content using Luau module paths [...] and is the require mode used by the [Lune runtime]." Exemplo: `require("@self/module")`.

  Config completa do modo luau (da própria doc):
  ```json5
  {
    name: "luau",
    aliases: {
      "@pkg": "./Packages",
      images: "./assets/image-links.json",
    },
    use_luau_configuration: true,
  }
  ```
  `use_luau_configuration: true` (default) faz o darklua procurar `.luaurc` automaticamente para resolver aliases adicionais — coerente com o jeito que Lune já resolve requires.

- **Como excluir os `require("@lune/...")` do bundle** (built-ins do Lune não devem ser inlinados — eles não são arquivo local):
  ```json5
  {
    bundle: {
      require_mode: "luau",
      excludes: ["@lune/**"],
    },
  }
  ```
  Fonte: mesma página `bundle/index.md`, seção "Excludes".

- **Aviso oficial importante**: "it is important that each module do not have any side effects at require-time, as the order of those side effects may not be preserved in the bundled code." — relevante porque módulos do LuauBench que registram algo em um registro central no top-level (ex: `services` se registrando globalmente ao ser `require`-ado) podem ter ordem de side-effect alterada pelo bundling. Vale revisar se algum módulo do projeto depende de ordem de `require` para side-effect antes de adotar bundling.

- **Licença e distribuição do darklua**: MIT (`LICENSE.txt` do repo, citado na doc de bundling via exemplo do próprio `Cargo.toml` do darklua: `license = "MIT"`). Instalável via Rokit: `rokit add seaofvoices/darklua` (confirmado no `README.md` do repo `seaofvoices/darklua`) — ou seja, se o projeto decidir adotar, encaixa no canal de distribuição que o LuauBench já usa (Rokit), não introduz um gerenciador de pacote novo.

- **Versão de referência do darklua nos exemplos acima**: `0.19.0` (aparece no próprio `Cargo.toml` do darklua, citado como exemplo na doc de bundling, e a doc lida é da branch `main` do repo em 2026-09-07 — não fixei uma tag específica porque a pergunta era sobre a existência/sintaxe do recurso, não uma versão pinada).

### Conclusão da pergunta 2

Não existe flag escondida em `lune build --help` — bundling **precisa** de uma ferramenta externa. `darklua` é a resposta oficial e confirmada, com `require_mode: "luau"` (não `"path"`) sendo o modo correto para a semântica de `require` que o Lune usa.

## Pergunta 3 — exemplo real de Lune + Rokit + require multi-arquivo publicado como binário standalone

**Parcialmente confirmado, sem um exemplo 1:1 perfeito.** Não achei um projeto open-source que faça exatamente "CLI Luau multi-arquivo rodada por Lune, bundlada com darklua e compilada via `lune build` para um `.exe` publicado em GitHub Release via Rokit" de ponta a ponta — o que achei:

- **`lune` + `darklua` coexistindo no toolchain via `rokit.toml`** é um padrão real e comum no ecossistema Roblox open-source:
  - `ffrostfall/BridgeNet2/rokit.toml` — `lune@0.8.9`, `darklua@0.15.0`
  - `1Axen/blink/rokit.toml` — `lune@0.10.4`, `darklua@0.17.2`
  - `Mark-Marks/roblox-project-template/rokit.toml` — `lune@0.8.9`, `darklua@0.14.0`, mais `pesde`, `rojo`, `stylua`, `selene`
  - Nesses três, porém, o uso combinado de `lune`+`darklua` que consegui confirmar (`Mark-Marks/roblox-project-template/.lune/build.luau`, lido) é para o fluxo **Roblox-side** (rodar `darklua process` sobre o código-fonte do jogo antes de `rojo build`, resolvendo aliases de path via a regra `convert_require`) — não para compilar o próprio script Lune multi-arquivo em um executável standalone via `lune build`. Ou seja, confirma que as duas ferramentas convivem bem no mesmo `rokit.toml`/pipeline, mas não é o mesmo caso de uso do LuauBench.
  - `.darklua.json` do `Mark-Marks/roblox-project-template` usa a regra `convert_require` com `sources` (aliases tipo `@pkg`, `@server`) — não a chave `bundle` — reforça que "bundle" e "convert_require" são usos distintos do darklua.

- Não encontrei nenhuma *issue*/*discussion* no `lune-org/lune` com a mensagem de erro literal do usuário (busquei via `WebSearch` e `gh search code`), mas a causa raiz que encontrei direto no código-fonte do `mlua` (pergunta 1) é uma explicação mais forte e específica do que qualquer relato de terceiro teria.

### Conclusão da pergunta 3

O padrão "instalar `lune` e `darklua` juntos via Rokit" é real e comprovado em múltiplos repositórios. O padrão específico "bundlar um script Lune multi-arquivo com darklua e depois rodar `lune build` nele" é a recomendação **oficial** do próprio Lune (pergunta 2) mas não achei um repositório de referência que faça exatamente isso de ponta a ponta para confirmar "na prática" — recomendo tratar como não confirmado por exemplo real, só por documentação oficial + leitura de código-fonte (que é uma fonte mais forte que um exemplo de terceiro, mas é bom deixar registrado que não há um projeto-espelho 100% idêntico ao caso do LuauBench).

## Incerto / não confirmado

- Não testei rodar `darklua process` de fato (proibido pelo escopo da tarefa — só pesquisa, sem instalar/rodar nada).
- Não confirmei se `use_luau_configuration: true` do darklua entende exatamente as mesmas regras de resolução de `.luaurc` que o Lune usa (aliases, múltiplos `.luaurc` aninhados) — a doc do darklua afirma compatibilidade, mas não vi teste cruzado dos dois lendo o mesmo `.luaurc`.
- Não confirmei se o "distribute files alongside the standalone binary" citado no CHANGELOG do Lune (0.8.0) ainda funciona hoje (0.10.5) para o **arquivo de entrada em si** — a leitura do código-fonte de `mlua`/`standalone/mod.rs` sugere que não funcionaria nem para isso, já que o erro ocorre na primeíssima chamada de `require` dentro do chunk sintético `STANDALONE`, independente de os arquivos existirem em disco ou não. Isso é inferência minha a partir do código lido, não uma frase explícita de alguma fonte dizendo "isso nunca funciona" — sinalizado como tal.
