# Sandboxing de globals em chunks Luau dentro do Lune

**Resposta curta:** Sim, existe suporte nativo do Lune. A biblioteca padrão `@lune/luau` expõe `luau.load(source, loadOptions)`, e `loadOptions.environment` é uma tabela de ambiente customizada aplicada ao chunk carregado — o equivalente funcional de `loadstring` + `setfenv` do Lua 5.1. `loadOptions.injectGlobals` (default `true`) controla se os globals padrão do Lune são copiados para dentro desse ambiente customizado; para isolar de verdade (ex.: impedir que o script do usuário veja `require`, `fs`, `process`), a Sandbox.luau da task-runtime-006 deve chamar com `injectGlobals = false` e montar manualmente a tabela de globals permitida (as APIs simuladas de Roblox: `game`, `workspace`, `print`, `wait`, etc.). `getfenv`/`setfenv` **não estão disponíveis** como globals dentro de scripts Luau (nem no Lune, nem no Luau em geral) — não é um caminho viável.

## Fatos verificados

**1. `luau.load` — fonte primária: código Rust, não apenas docs**
- Assinatura pública em Luau (arquivo de tipos): `function luau.load(source: string, loadOptions: LoadOptions?): (...any) -> ...any` — `crates/lune-std-luau/types.d.luau`, lido diretamente do repositório em `main` (commit `7f1849c`, 2026-07-03; release estável mais recente: `v0.10.5`). URL: https://github.com/lune-org/lune/blob/main/crates/lune-std-luau/types.d.luau
- `LoadOptions` (mesma fonte, linhas 34-39):
  ```luau
  export type LoadOptions = {
      debugName: string?,
      environment: { [string]: any }?,
      injectGlobals: boolean?,
      codegenEnabled: boolean?,
  }
  ```
- Comentário oficial de doc no mesmo arquivo (linha 30): *"`environment` - A custom environment to load the chunk in. Setting a custom environment will deoptimize the chunk and forcefully disable codegen. Defaults to the global environment."*
- Implementação Rust real, `crates/lune-std-luau/src/lib.rs` (função `load_source`, li o arquivo inteiro):
  ```rust
  fn load_source(
      lua: &Lua,
      (source, options): (LuaString, LuauLoadOptions),
  ) -> LuaResult<LuaFunction> {
      let mut chunk = lua
          .load(source.as_bytes().to_vec())
          .set_name(options.debug_name);
      let env_changed = options.environment.is_some();

      if let Some(custom_environment) = options.environment {
          let environment = lua.create_table()?;

          if options.inject_globals {
              for pair in lua.globals().pairs() {
                  let (key, value): (LuaValue, LuaValue) = pair?;
                  environment.set(key, value)?;
              }
              if let Some(global_metatable) = lua.globals().metatable() {
                  environment.set_metatable(Some(global_metatable))?;
              }
          } else if let Some(custom_metatable) = custom_environment.metatable() {
              environment.set_metatable(Some(custom_metatable))?;
          }

          for pair in custom_environment.pairs() {
              let (key, value): (LuaValue, LuaValue) = pair?;
              environment.set(key, value)?;
          }

          chunk = chunk.set_environment(environment);
      }

      lua.enable_jit(options.codegen_enabled && !env_changed);
      let function = chunk.into_function()?;
      lua.enable_jit(/* restore previous JIT state */);

      Ok(function)
  }
  ```
  Ou seja: quando `environment` é passado, o Lune monta uma tabela nova; se `inject_globals = true`, copia todos os globals atuais do Lune (`_G`, `print`, `require`, `warn`, `_VERSION`, mais as bibliotecas base do Luau) para dentro dela antes de sobrepor as chaves da tabela custom; se `inject_globals = false`, **só** as chaves que você mesmo colocou em `environment` existem ali (mais o metatable custom, se houver). O chunk é então ligado a essa tabela via `Chunk::set_environment` (API do `mlua`, não é `setfenv` do Luau em si) antes de virar função.
- Defaults confirmados em `crates/lune-std-luau/src/options.rs` (struct `LuauLoadOptions::default()`): `debug_name = "luau.load(...)"`, `environment = None`, `inject_globals = true`, `codegen_enabled = false`.

**2. `getfenv`/`setfenv` não existem como globals utilizáveis em Luau**
- No próprio VM de referência do Luau (`luau-lang/luau`, `VM/src/lbaselib.cpp`, branch `master`), as funções `luaB_getfenv` e `luaB_setfenv` **estão implementadas no C++** mas **não estão registradas** no array `base_funcs[]` que a `luaopen_base` expõe como globals. Ou seja, mesmo que o código exista no binário, não há um global `getfenv`/`setfenv` chamável a partir de um script Luau — chamar `getfenv()` resulta em "attempt to call a nil value". Fonte: https://github.com/luau-lang/luau/blob/master/VM/src/lbaselib.cpp
- Isso é consistente com o RFC oficial do Luau, "Deprecate getfenv/setfenv" (https://rfcs.luau.org/deprecate-getfenv-setfenv.html): a linguagem mantém as funções por compat binária, mas o objetivo declarado é desencorajar/eliminar seu uso; o RFC também confirma que a estratégia de sandboxing "oficial" do Luau é outra: dar a cada script sua própria tabela de globals que faz `__index` para a tabela de globals embutida (builtin), em vez de mutação de fenv em tempo de execução.
- Não confirmei (e é improvável) que o Lune registre `getfenv`/`setfenv` por conta própria — `crates/lune-std/src/globals/mod.rs` só expõe `g_table` (`_G`), `print`, `require`, `version` (`_VERSION`) e `warn` como globals extras; nada relacionado a fenv.

**3. Mecanismo nativo de sandbox do Luau (nível VM/C API) — e como o próprio Lune já o usa**
- O runtime de referência do Luau expõe, em `VM/include/lualib.h`:
  ```c
  LUALIB_API void luaL_sandbox(lua_State* L);
  LUALIB_API void luaL_sandboxthread(lua_State* L);
  ```
  Fonte: https://github.com/luau-lang/luau/blob/master/VM/include/lualib.h
  Guia oficial (https://luau.org/sandbox/): `luaL_sandbox` marca as bibliotecas builtin e a tabela global como readonly (e ativa "safeenv"); `luaL_sandboxthread` troca a tabela de ambiente de uma thread específica por uma nova tabela que escreve localmente e usa `__index` para ler do ambiente global do chamador (ou seja, um sandbox por-thread com fallback de leitura).
  Isso são funções de **API C**, não chamáveis a partir de um script Luau — só o host (aqui, o binário Lune, escrito em Rust) pode invocá-las.
- O binding Rust `mlua` (que o Lune usa, feature `luau`) expõe isso como `Lua::sandbox(&self, enabled: bool) -> Result<()>` (wrapper de `luaL_sandbox`) e `Thread::sandbox(&self) -> Result<()>` (wrapper de `luaL_sandboxthread`). Fontes: https://docs.rs/mlua/latest/mlua/struct.Lua.html e https://docs.rs/mlua/latest/mlua/struct.Thread.html
- **O próprio Lune já chama isso no boot do runtime.** Em `crates/lune/src/rt/runtime.rs` (li o arquivo, `Runtime::new()`), depois de injetar todos os globals padrão:
  ```rust
  // Sandbox the Luau VM and make it go zooooooooom
  lua.sandbox(true)?;

  // _G table needs to be injected again after sandboxing,
  // otherwise it will be read-only and completely unusable
  ```
  Ou seja: o estado Lua raiz do Lune já roda em modo sandbox nativo do Luau (globals/bibliotecas readonly) antes mesmo de qualquer script do usuário rodar. Isso é ortogonal ao mecanismo de `luau.load({environment=...})`: o sandbox nativo protege o ambiente global do processo Lune contra mutação; `luau.load` com `environment` custom é o que dá a **um chunk específico** um conjunto diferente (mais restrito) de globals.
  `Thread::sandbox()` (por-thread, ligado a `luaL_sandboxthread`) não aparece usado em nenhum lugar do código do Lune que percorri — não está exposto para scripts Luau via nenhuma std lib do Lune. Não confirmado que exista uma forma de acioná-lo a partir de Luau puro sem escrever um binding Rust próprio.

## Exemplo mínimo

```luau
local luau = require("@lune/luau")

-- Ambiente restrito: só enxerga print (a própria função print do host,
-- passada explicitamente) e um "game" fake. NÃO tem require, _G, string, etc.
local restrictedEnv = {
    print = print,
    game = fakeGameGlobal, -- construído pela Sandbox.luau
}

local userChunk = luau.load(userSourceCode, {
    debugName = "UserScript",
    environment = restrictedEnv,
    injectGlobals = false, -- crítico: sem isso, todos os globals do Lune (incl. require) vazam pro chunk
})

local ok, err = pcall(userChunk)
```

## Limites e pegadinhas

- `injectGlobals` default é `true`. Se a Sandbox.luau esquecer de setar `false` explicitamente, o chunk do usuário herda **todos** os globals atuais do Lune, incluindo `require` — que dá acesso a `require("@lune/process")`, `require("@lune/fs")` etc., quebrando o isolamento. Confirmar esse valor é o ponto mais fácil de errar.
- Setar `environment` força `codegenEnabled` efetivo para `false` (o código do Lune desliga o JIT quando `env_changed = true`, independente do valor pedido pelo caller) — custo de performance conhecido e documentado, não um bug.
- `require` dentro do ambiente restrito, se você optar por incluí-lo para permitir módulos do usuário, ainda resolve caminhos via o resolver padrão do Lune (`crates/lune-std/src/require/`) — não constatei (não pesquisei a fundo) se dá pra restringir `require` a um subdiretório sandboxed sem reimplementar a função. Marcar como não confirmado se isso vier a importar para a task.
- A tabela `environment` passada por você é **copiada** chave-a-chave para dentro de uma tabela nova criada pelo Lune (não é a sua tabela por referência) — então mutação posterior da tabela original que você passou não afeta o chunk já carregado. Isso está explícito no corpo de `load_source` acima.
- `luaL_sandboxthread`/`Thread::sandbox()` seria, em tese, um mecanismo mais "nativo" e talvez mais barato para isolar globals por execução, mas **não está exposto por nenhuma std lib do Lune para scripts Luau** — só é acionável escrevendo Rust. Para a Sandbox.luau (que presumivelmente é código Luau, não um crate Rust novo), `luau.load` com `environment`/`injectGlobals` é o único mecanismo real e alcançável a partir de dentro do processo Lune sem sair de Luau puro.

## Incerto

- Não confirmei se existe alguma forma, só em Luau (sem escrever Rust), de acionar `luaL_sandboxthread` via `@lune/luau` ou qualquer outra std lib — pesquisei o texto completo de `crates/lune-std-luau/src/lib.rs` e `types.d.luau` e não há tal exposição hoje (commit `7f1849c`, 2026-07-03). Se isso for necessário, provavelmente exige um crate Rust customizado que envolve o Lune, o que foge do escopo de "chunk Luau restrito" da pergunta.
- Não verifiquei em profundidade o comportamento de `require()` dentro de um ambiente restrito quanto a possíveis vazamentos (ex.: `debug.info` para inspecionar upvalues do chamador, ou userdata compartilhado que dá acesso indireto a objetos privilegiados). Isso é uma preocupação de design de sandbox mais ampla, não só do mecanismo de globals, e vale uma passada extra do arquiteto/revisor de runtime antes de fechar o design da Sandbox.luau.
