# Formato do `.project.json` e do sourcemap do Rojo

**Versão verificada:** código-fonte do branch `master` de `rojo-rbx/rojo`, baixado em 2026-09-05, comparado com o CHANGELOG — corresponde à release `v7.7.0` (publicada 2026-07-01, é a "latest release" via GitHub API). As mudanças em `Unreleased` acima do `v7.7.0` são apenas correções de path no Windows, não mudam o schema. Ou seja: **os fatos abaixo valem para Rojo v7.7.0**, e são tirados do código-fonte real (`.rs`), não de paráfrase — quando uma informação veio só de um resumo de doc (não do código), isso está marcado.

## Resposta curta

O parser do `cli` precisa reproduzir: (1) o `Project`/`ProjectNode` do `project.rs` (campos exatos abaixo, com **erro se houver campo desconhecido no nível raiz** — isso quebra a sugestão de `.claude/rules/04-cli-rokit.md` de usar um campo `"luaubench": {...}` no topo do `.project.json`, ver "Limites e pegadinhas"); (2) o algoritmo de resolução de `ClassName` de `snapshot_project.rs` (ordem: `$className` explícito > classe inferida do `$path` > inferência de Service pelo nome quando o pai é `DataModel`); (3) a tabela de `sync_rule` (extensão → Middleware) de `snapshot_middleware/mod.rs`; (4) que `rojo sourcemap` **sem `--include-non-scripts` só inclui `Script`/`LocalScript`/`ModuleScript`** — se o `cli` do LuauBench for popular o `DataModel` inteiro a partir do sourcemap, precisa rodar com essa flag ou vai perder toda instância não-script (Folders, Models, Values etc.) silenciosamente.

## Fatos verificados

### 1. Schema do `.project.json` (struct `Project`, `src/project.rs`)

- Fonte: `#[serde(deny_unknown_fields, rename_all = "camelCase")] pub struct Project` — código-fonte, `rojo-rbx/rojo@master/src/project.rs` linha 60-144.
- Campos de topo confirmados (nome serializado em camelCase, campo Rust entre parênteses):
  - `name: Option<String>` — se ausente, Rojo deriva do nome do arquivo/pasta (`default.project.json` → nome da pasta).
  - `tree: ProjectNode` — obrigatório.
  - `servePort` (`serve_port: Option<u16>`)
  - `servePlaceIds` (`serve_place_ids: Option<HashSet<u64>>`)
  - `blockedPlaceIds` (`blocked_place_ids: Option<HashSet<u64>>`) — não estava nas docs, só no código.
  - `placeId` (`place_id: Option<u64>`)
  - `gameId` (`game_id: Option<u64>`)
  - `serveAddress` (`serve_address: Option<IpAddr>`)
  - `serveAllowedHosts` (`serve_allowed_hosts: Vec<String>`, default `[]`) — campo recente, não estava na doc antiga.
  - `emitLegacyScripts` (`emit_legacy_scripts: Option<bool>`) — default efetivo `true` até a v8 (função `emit_legacy_scripts_default()` em `util.rs` retorna `Some(true)`, com comentário "TEMP function until rojo 8.0").
  - `globIgnorePaths` (`glob_ignore_paths: Vec<IgnorableGlob>`, default `[]`) — globs relativos à pasta do `.project.json`.
  - `syncbackRules` (`syncback_rules: Option<SyncbackRules>`) — usado só pelo comando `rojo syncback` (Studio → disco), não relevante pro `cli` do LuauBench.
  - `syncRules` (`sync_rules: Vec<SyncRule>`, default `[]`) — permite o usuário mapear globs customizados para um Middleware (extensão do sistema de extensão-para-tipo, ver seção 3).
  - `$schema` (campo `schema: Option<String>`) — convenção JSON Schema, ignorado na prática.
  - `file_location` — `#[serde(skip)]`, não vem do JSON; é preenchido pelo próprio Rojo com o path do arquivo carregado.
- **`deny_unknown_fields` está ativo no nível raiz.** Qualquer chave extra em `.project.json` (ex.: `"luaubench": {...}`) faz o `rojo` real (`serve`/`build`/`sourcemap`) **falhar o parse com erro**, não ignora silenciosamente.
- Extensão de arquivo: `.project.json` ou `.project.jsonc` (`Project::is_project_file`). O parser (`json::from_slice`) é chamado igual para as duas extensões — suporta comentários `//`, `/* */` e vírgula sobrando (testado no arquivo `test project_with_jsonc_features`, que literalmente usa comentários e trailing commas). Como `load_from_slice` não ramifica por extensão, isso indica que o parser tolera sintaxe JSONC mesmo num arquivo `.project.json` puro — mas o teste oficial só cobre a extensão `.jsonc` explicitamente, então trato o caso `.project.json` com comentário como **inferência forte, não 100% confirmada por teste dedicado**.
- Nome do projeto default: `DEFAULT_PROJECT_NAMES = ["default.project.json", "default.project.jsonc"]` — é o nome que `rojo build`/`serve`/`cli` do LuauBench devem procurar quando o usuário passa um diretório em vez de um arquivo específico.

### 2. Schema do nó da árvore (`ProjectNode`, mesmo arquivo, linha 369-432)

Campos confirmados (todos com `skip_serializing_if` quando ausentes, **sem `deny_unknown_fields`** nesse struct):

- `$className` (`class_name: Option<Ustr>`) — obrigatório se `$path` não for setado; não pode ser setado junto com `$path` a menos que o path resolva pra um `Folder` (ver algoritmo na seção 4).
- `$path` (`path: Option<PathNode>`) — `PathNode` é um enum `untagged`: ou uma string (`"src"`, path obrigatório) ou um objeto `{"optional": "src"}` (path opcional — se o arquivo não existir, o nó é simplesmente omitido em vez de dar erro). Confirmado por teste (`path_node_required`, `path_node_optional`).
- `$properties` (`properties: BTreeMap<Ustr, UnresolvedValue>`)
- `$attributes` (`attributes: BTreeMap<String, UnresolvedValue>`)
- `$id` (`id: Option<String>`) — id pra referenciar essa Instance de outra propriedade do tipo `Ref` (referent). Não documentado na página de docs que consultei, só existe no código.
- `$ignoreUnknownInstances` (`ignore_unknown_instances: Option<bool>`) — default `true` se `$path` não setado, `false` se `$path` setado (doc-comment explícito no código).
- **Filhos nomeados**: `children: BTreeMap<String, ProjectNode>` com `#[serde(flatten)]` — ou seja, **qualquer chave que não seja `$className`/`$id`/`$properties`/`$attributes`/`$ignoreUnknownInstances`/`$path` é tratada como filho**, cujo nome é a própria chave e cujo valor precisa ser um `ProjectNode` válido.
- Chaves começando com `$` que não são reconhecidas só geram um **warning de log** ("Keys starting with '$' are reserved by Rojo to ensure forward compatibility"), não erro — mas isso é reservado pro próprio Rojo evoluir, não é uma extensão seguro pra terceiros (ver "Limites e pegadinhas").

Formato de `$properties`/`$attributes` (via `UnresolvedValue`, `src/resolution.rs`, enum `untagged`):
- Forma "ambígua" (mais comum, resolvida contra o banco de reflection do Roblox por classe+propriedade): booleano literal, string literal, array de strings (`Tags`), número único (`Int32`/`Int64`/`Float32`/`Float64`), array de 2 números (`Vector2`), array de 3 números (`Vector3` ou `Color3`), array de 4 números, array de 12 números (`CFrame`: posição xyz + matriz de rotação 3x3), objeto de `Attributes`/`Font`/`MaterialColors`, ou string que casa com um nome de item de `Enum` (ex.: `"Material": "Plastic"`).
- Forma "totalmente qualificada": o `Variant` serializado diretamente (formato usado internamente por `rbx_dom_weak`/rbxlx) — usado quando a forma ambígua não seria suficiente.

### 3. Convenção de arquivo → `ClassName` sem `$className` explícito

Fonte: `src/snapshot_middleware/mod.rs`, função `default_sync_rules()` (linha 419-444) e `get_dir_middleware()` (linha 110-150) — tabela literal do código:

**Arquivos** (regras testadas em ordem, primeira que casa vence):
| Padrão | Middleware/Classe resultante |
|---|---|
| `*.server.lua` / `*.server.luau` | `Script` |
| `*.client.lua` / `*.client.luau` | `LocalScript` |
| `*.plugin.lua` / `*.plugin.luau` | script de plugin (`PluginScript` middleware) |
| `*.lua` / `*.luau` (sobra) | `ModuleScript` |
| `*.project.json` / `*.project.jsonc` | projeto aninhado (ver seção 4) |
| `*.model.json` / `*.model.jsonc` | modelo custom (formato JSON próprio do Rojo p/ descrever instâncias/hierarquia) |
| `*.json` (exceto `*.meta.json`) / `*.jsonc` (exceto `*.meta.jsonc`) | `ModuleScript` que retorna o JSON decodificado como tabela Luau |
| `*.toml` | `ModuleScript` que retorna o TOML decodificado |
| `*.csv` | `LocalizationTable` |
| `*.txt` | `StringValue` |
| `*.rbxmx` | modelo Roblox XML |
| `*.rbxm` | modelo Roblox binário |
| `*.yml` / `*.yaml` | `ModuleScript` (via Middleware `Yaml`) |

**Diretórios** (`get_dir_middleware`, ordem de prioridade **fixa, comentada como "não pode mudar por compatibilidade"**):
1. `default.project.json` ou `default.project.jsonc` dentro da pasta → **a pasta inteira vira um projeto Rojo aninhado** (prioridade máxima, checado antes de qualquer `init.*`).
2. `init.luau` / `init.lua` → a pasta vira `ModuleScript` (arquivo é o corpo, subpastas/arquivos viram filhos).
3. `init.server.luau` / `init.server.lua` → `Script`.
4. `init.client.luau` / `init.client.lua` → `LocalScript`.
5. `init.plugin.lua` / `init.plugin.luau` → script de plugin.
6. `init.csv` → `LocalizationTable`.
7. Nenhum dos acima → `Folder` simples com o nome da pasta.

**Meta files** (`src/snapshot_middleware/meta_file.rs`, structs `AdjacentMetadata` e `DirectoryMetadata`):
- `<nome>.meta.json` (ou `.jsonc`) ao lado de um arquivo (`hello.lua` + `hello.meta.json`): seta `id`, `ignoreUnknownInstances`, `properties`, `attributes` pra Instance resultante — **sem `className`** (o tipo já veio da extensão do arquivo).
- `init.meta.json` (ou `.jsonc`) **dentro** de uma pasta: mesmos campos, **mais `className`** — só pode sobrescrever a classe se a instância resultante for um `Folder` puro (senão erro).

### 4. Algoritmo de resolução de `ClassName` (o "como children nomeados aparecem")

Fonte: `src/snapshot_middleware/project.rs`, função `snapshot_project_node` (linha 92-233) — lido literalmente do código, não é paráfrase.

- Para cada nó, calcula três candidatos: `node.class_name` (explícito), `class_name_from_path` (resultado de rodar `snapshot_from_vfs` no `$path`), `class_name_from_inference` (`infer_class_name(nome, parent_class)`).
- `infer_class_name`: **só entra em ação se `parent_class == "DataModel"`** — nesse caso, olha o banco de reflection oficial do Roblox e, se existir uma classe com esse nome marcada com a tag `ClassTag::Service` (ex.: `ReplicatedStorage`, `ServerScriptService`, `Workspace`), infere essa classe. **Confirma diretamente a pergunta 1**: um filho nomeado do nó raiz do `tree` que bate com o nome de um Service real do Roblox vira aquele Service automaticamente, sem precisar de `$className`.
- **A raiz da árvore (`project.tree`) é chamada com `parent_class = None`** (`snapshot_project_node(..., &project.tree, vfs, None)`) — ou seja, **a raiz NÃO tem inferência automática de `DataModel`**. Se a raiz não tiver `$path`, ela precisa de `$className` explícito (por convenção do ecossistema, `"DataModel"`, mas isso é convenção de quem escreve o projeto, não algo que o Rojo injeta sozinho).
- Ordem de precedência quando há conflito: `$className` explícito > classe do `$path` > inferência de Service — **exceto** quando `$className` E `$path` estão setados ao mesmo tempo: só é permitido se a classe resolvida pelo `$path` for `Folder` (senão erro "$className foi especificado tanto no projeto quanto no filesystem"). Da mesma forma, se `$path` resolve a `Folder` e há inferência de Service disponível, a inferência de Service vence (uma pasta chamada `ReplicatedStorage` sob a raiz vira o Service, não um Folder genérico).
- Mensagem de erro literal quando nada resolve o `ClassName` (útil pra replicar no LuauBench com fidelidade de UX): `"Instance \"{nome}\" is missing some required information. One of the following must be true: - $className must be set... - $path must be set... - The instance must be a known service, like ReplicatedStorage"`.
- `$path` do tipo `{"optional": "..."}` que não resolve a nada (arquivo ausente) e sem outra fonte de classe → o nó inteiro é omitido (`Ok(None)`), não é erro.

### 5. Resolução de `$path` e projetos aninhados

- `$path` é resolvido **relativo à pasta que contém o `.project.json` que define aquele nó** — código: `project_folder = project_path.parent().unwrap()`; `if path.is_relative() { project_folder.join(path) }`. Isso é literal do doc-comment de `Project::file_location`: "Relative paths in the project should be considered relative to the parent of this field, also given by `Project::folder_location`".
- **Projetos aninhados**: quando o Rojo, varrendo uma árvore (inclusive uma pasta alcançada via `$path` de outro projeto), encontra uma pasta contendo `default.project.json`/`default.project.jsonc`, essa pasta é tratada como projeto Rojo próprio — os `$path` **dentro desse projeto aninhado são relativos à pasta dele mesmo**, não à raiz do projeto pai. Essa detecção acontece em `get_dir_middleware` e tem prioridade sobre **todas** as convenções de `init.*`.
- Não existe um mecanismo diferente de "múltiplos `.project.json` por Service" além desse: é exatamente aninhamento de projeto dentro de projeto via `$path` apontando pra uma pasta que por acaso contém um `default.project.json`.

### 6. Formato do sourcemap (`rojo sourcemap`, `src/cli/sourcemap.rs`)

Struct real (linha 30-43):
```rust
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SourcemapNode<'a> {
    name: &'a str,
    class_name: Ustr,
    file_paths: Vec<Cow<'a, Path>>, // omitido no JSON se vazio
    children: Vec<SourcemapNode<'a>>, // omitido no JSON se vazio
}
```
JSON resultante: `{"name": "...", "className": "...", "filePaths": [...], "children": [...]}`, recursivo, raiz = instância raiz do projeto.

Flags e comportamento confirmados:
- `rojo sourcemap <project>` — path do projeto é opcional (default: diretório atual).
- `--output <arquivo>` — se omitido, imprime no stdout.
- `--include-non-scripts` (default `false`!) — **por padrão o sourcemap só inclui nós que são `Script`/`LocalScript`/`ModuleScript` ou que têm algum descendente que seja** (`filter_non_scripts`, checado recursivamente: um nó sem filhos relevantes e que não é ele mesmo um script é podado da árvore). Isso é crítico: sem essa flag, Folders/Models/Values/Parts que não contêm script nenhum **desaparecem inteiramente do sourcemap**.
- `--absolute` (default `false`) — paths relativos à pasta do projeto por padrão (`pathdiff::diff_paths(val, project_dir)`); com a flag, usa `path::absolute()`.
- `--watch` — reobserva e reescreve o sourcemap quando o VFS detecta mudança relevante (via `patch_set_affects_sourcemap`), não é polling.
- `filePaths` só lista arquivos que existem de fato no disco no momento (`.filter(|path| path.is_file())`) dentre os `relevant_paths` da instância — ou seja, pode ter mais de um path por nó (ex.: script + seu `.meta.json`), ou zero (instância sem arquivo próprio, ex. Service inferido sem `$path`).

## Exemplo mínimo

`.project.json` típico (baseado na semântica confirmada acima):
```jsonc
{
  "name": "MyGame",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      // vira o Service real por inferência de nome, mesmo sem $className
      "$path": "src/shared"
    },
    "ServerScriptService": {
      "$path": "src/server"
    }
  }
}
```

Saída de `rojo sourcemap default.project.json --include-non-scripts` (formato confirmado):
```json
{
  "name": "MyGame",
  "className": "DataModel",
  "children": [
    {
      "name": "ReplicatedStorage",
      "className": "ReplicatedStorage",
      "children": [
        { "name": "Foo", "className": "ModuleScript", "filePaths": ["src/shared/Foo.luau"] }
      ]
    }
  ]
}
```

## Limites e pegadinhas

- **Achado crítico pra `.claude/rules/04-cli-rokit.md`**: a regra sugere um campo namespaced `"luaubench": {...}` dentro do `.project.json`. Isso **quebra o parser real do Rojo** no nível raiz, porque `Project` usa `#[serde(deny_unknown_fields)]` — um `.project.json` com esse campo extra passa a dar erro em `rojo serve`/`build`/`sourcemap` de verdade. Dentro de um nó da árvore (`ProjectNode`) não há `deny_unknown_fields`, mas qualquer chave desconhecida é interpretada como **filho/Instance** (via `#[serde(flatten)]` em `children`), não como metadado livre — colocar `"luaubench": {...}` dentro de um nó criaria uma Instance fake chamada "luaubench" na árvore real do projeto (visível no Studio/build real), o que também não é o que se quer. **Recomendação pro `arquiteto`/`coder-cli`: não estender o `.project.json` diretamente — usar um arquivo separado (ex. `luaubench.toml` ou `.luaubench.json` ao lado do `.project.json`) para configuração própria do LuauBench.** Isso não é opinião minha isolada — é consequência direta e verificada do schema real.
- `rojo sourcemap` sem `--include-non-scripts` **descarta silenciosamente** qualquer instância sem script descendente. Se o `cli` do LuauBench for usar o sourcemap (em vez de reimplementar o walk do `.project.json`) pra montar o `DataModel`, **precisa passar `--include-non-scripts`**, ou perde Folders/Models/Values inteiros sem aviso.
- A inferência de Service (`infer_class_name`) depende do **banco de reflection oficial do Roblox rodando dentro do próprio Rojo** (`rbx_reflection_database`), não do `Full-API-Dump.json` que o LuauBench já usa — são fontes diferentes (ambas oficiais/derivadas da Roblox, mas dumps/formatos distintos). O `cli` do LuauBench precisa checar a tag `Service` no `Full-API-Dump.json` (campo `Tags` da classe) pra replicar esse comportamento, já que não vai embarcar o crate Rust `rbx_reflection_database`.
- `emitLegacyScripts` (default `true` até Rojo v8) controla se `.server.lua`/`.client.lua` viram `Script`/`LocalScript` (modo legado) ou `Script` com `RunContext` apropriado (modo novo) — o `cli` do LuauBench precisa decidir qual comportamento default replicar; hoje o default real do Rojo ainda é o modo legado.
- `$path` opcional (`{"optional": "..."}`) faz o nó inteiro sumir se o arquivo não existir — silencioso por design do Rojo, não é bug.
- `.project.jsonc`/comentários: suporte a JSONC é real e confirmado por teste automatizado do Rojo, mas o teste só cobre explicitamente a extensão `.jsonc`; não achei teste que comprove comentário dentro de um arquivo com extensão `.project.json` pura (mesmo o código sugerindo que funcionaria igual).

## Incerto

- Se comentários JSONC funcionam também dentro de um arquivo literalmente nomeado `algo.project.json` (extensão sem o `c`) — o código não ramifica por extensão, então provavelmente sim, mas não achei teste dedicado a esse caso específico. Tratar como "provável, não 100% confirmado".
- Formato exato do "custom model" (`*.model.json`) — não abri o middleware `json_model.rs`; só confirmei que existe e que é diferente do `.json` genérico (que vira `ModuleScript`). Se o `cli` do LuauBench for suportar `.model.json`, isso precisa de uma pesquisa própria antes de implementar.
- Formato exato de `SyncRule` (o item de `syncRules` no `.project.json`, que deixa o usuário mapear glob → Middleware customizado) — só vi o uso (`sync_rule!` macro, `context.get_user_sync_rule`), não o struct JSON-facing completo (`src/snapshot.rs`, tipo `SyncRule`). Se for prioridade pro LuauBench suportar `syncRules` customizado, precisa de mais uma leitura de fonte antes de implementar.
- `PluginScript`/scripts de plugin (`*.plugin.lua`) — não confirmei qual `ClassName` real do Roblox isso produz (é `Script` com algum `RunContext`/propriedade específica, ou uma classe própria) — baixa prioridade pro LuauBench (plugins de Studio não fazem sentido fora do Studio), mas fica marcado como não confirmado.
