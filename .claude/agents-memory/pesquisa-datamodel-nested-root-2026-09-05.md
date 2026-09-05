# Pesquisa — `$className: "DataModel"` fora da raiz do plano inteiro (task-cli-022)

Pesquisa pontual para a lacuna registrada na **Decisão 16** de `arquiteto-cli-2026-09-05.md`
(seção "Lacuna conhecida que a Decisão 16 não fecha"), referente a `task-cli-019`/`task-cli-020`.

## Resposta curta

**O Rojo real não valida a posição de `DataModel` em lugar nenhum do próprio parsing/snapshot do
projeto.** Não existe "erro nomeado" pra imitar — nem para raiz de projeto aninhado, nem para
qualquer outra posição não-raiz. `$className: "DataModel"` é tratado, na resolução de classe de
`snapshot_project_node`, exatamente como qualquer outra string de classe: se `$path` resolve a
`Folder`, o `$className` explícito vence, sem diagnóstico algum — mesmo comportamento em qualquer
posição da árvore. A falha (quando existe) acontece **fora** do Rojo: no motor real do Roblox
(via o plugin, tentando `Instance.new("DataModel")`, que o dump confirma como `NotCreatable`), não
no código de carregamento de projeto do Rojo.

**Implicação pra LuauBench:** se `coder-cli` for fechar essa lacuna, a mensagem/diagnóstico não é
uma mirror de nenhuma mensagem real do Rojo (porque ela não existe) — é uma validação **original do
LuauBench**, justificada pelo próprio API Dump (`DataModel` tem `Tags: ["NotCreatable"]`), adiantando
pra fase de `Plan` um erro que hoje só aparece tarde, na fase de `Materialize`. Isso é consistente
com a regra 01 (mensagem de erro com contexto) e com o contrato de `services`/`runtime` ("classe
abstrata do dump não é instanciável diretamente") — não é inventar comportamento de `.project.json`
que o Rojo não define (regra 04), porque não estamos adicionando campo nenhum, só adiantando uma
checagem de instanciabilidade que o dump já dita.

## Fatos verificados

Fonte: código-fonte real do Rojo, clone raso de `https://github.com/rojo-rbx/rojo.git`,
branch `master`, commit `a30a8ecd0f757a23c7d5be5f91e8a4d55d87b8fc` (2026-07-05), pesquisado em
2026-09-05 — mesma técnica das pesquisas anteriores (`pesquisa-formato-projeto-rojo-2026-09-05.md`,
correção de `task-cli-013`).

- **Toda a ocorrência da string `"DataModel"` em `.rs` no repo inteiro** (`grep -rn "DataModel"
  --include="*.rs" .`, excluindo `target/`) se resume a 4 pontos, nenhum deles uma checagem de
  posição:
  1. `src/snapshot_middleware/project.rs:682` — `infer_class_name`: se `parent_class == "DataModel"`
     e o nome do filho bate com uma classe com tag `Service` no `rbx_reflection_database`, infere
     a classe do filho como esse Service. É inferência de **filhos** de um `DataModel`, não uma
     validação sobre o próprio nó `DataModel`.
  2. `src/cli/build.rs:189` (comentário) — ao exportar `.rbxlx` (`OutputKind::Rbxlx`), usa
     `root_instance.children()` em vez de `[root_id]` porque "*Place files don't contain an entry
     for the DataModel, but our WeakDom representation does*". Só olha pro **único root** da árvore
     inteira construída pela sessão — não é uma checagem de "é isso um DataModel legal aqui".
  3. `src/cli/upload.rs:52` — `match root.class.as_str() { "DataModel" => root.children().to_vec(),
     _ => vec![root.referent()] }`. Mesmo padrão do build.rs: decide o que subir pro Open Cloud
     baseado na classe do **root da sessão inteira** (`tree.inner().root()`), não uma validação de
     posição em nós internos.
  4. `tests/tests/serve.rs:659` e `tests/tests/syncback.rs:68` — fixtures de teste que usam
     `"$className": "DataModel"` exatamente como esperado: **na raiz do `tree` do
     `default.project.json` de teste**. Não exercitam o caso de `DataModel` fora da raiz.

- **A função que resolve `$className`/`$path`/inferência é uma só, chamada identicamente pra
  qualquer nó da árvore, raiz ou não, projeto de topo ou aninhado — `snapshot_project_node`**
  (`src/snapshot_middleware/project.rs:92-219`). Ela não recebe nenhum parâmetro tipo `isRoot` ou
  `isOutermostRoot`. O único parâmetro relacionado é `parent_class: Option<&str>`, usado só pra
  inferência de serviços (achado 1 acima).

- **`snapshot_project` (`project.rs:30-90`) — chamada tanto pro projeto de topo quanto pra qualquer
  projeto aninhado referenciado via `$path`** — é despachada genericamente por
  `src/snapshot_middleware/mod.rs:249` (`Middleware::Project => snapshot_project(context, vfs, path,
  name)`), o mesmo branch de dispatch tanto pro arquivo de projeto passado a `rojo serve`/`build`
  quanto pra um `.project.json` aninhado encontrado seguindo um `$path`. E o corpo de
  `snapshot_project` (linha 65) sempre chama:

  ```rust
  snapshot_project_node(&context, path, project_name, &project.tree, vfs, None)
  ```

  — **`parent_class` é literal `None`, hardcoded, idêntico pra topo e pra aninhado.** Não existe
  nenhum jeito de `snapshot_project_node` saber, olhando pros seus parâmetros, se está processando
  a raiz do projeto mais externo ou a raiz de um projeto aninhado três níveis abaixo. É exatamente o
  mesmo código, com o mesmo argumento.

- **A resolução de classe em si (`project.rs:145-188`)** — quando `node.class_name = Some("DataModel")`
  e o `$path` resolve a um `Folder` (pasta sem `init.*`, o cenário do achado do revisor), cai no
  braço:

  ```rust
  (Some(project), Some(path), _, _) => {
      if path == "Folder" {
          project
      } else {
          bail!( /* "ClassName for Instance ... was specified in both ..." */ )
      }
  }
  ```

  `path == "Folder"` → retorna `project` = `"DataModel"`. **Sem `bail!`, sem warning, sem log —
  em qualquer posição da árvore.** É indistinguível de usar `$className: "Model"` na mesma posição.

- **API Dump oficial pinado do LuauBench confirma por que a falha real deveria acontecer, e onde**:
  `.cache/api-dump/28360dea4b90b35dc3fe9f829baae64fb6c50e75.json` (commit fixado em
  `tools/api-dump.lock.json`, `robloxVersion: 0.737.0.7371584`) — classe `DataModel`:
  ```json
  { "Name": "DataModel", "Superclass": "ServiceProvider", "Tags": ["NotCreatable"] }
  ```
  `NotCreatable` é a mesma tag que já impede `Instance.new("DataModel")` no LuauBench hoje (linha
  com o resto das classes abstratas tipo `Instance`/`PVInstance` — ver Regra 02: "Classe abstrata do
  dump ... não é instanciável diretamente"). No Roblox real, é o **motor** (via o plugin do Rojo
  tentando efetivamente instanciar) que rejeitaria isso — não o Rojo em si.

## Exemplo mínimo (reprodução do achado, formato Rojo real)

```jsonc
// default.project.json (projeto ANINHADO, referenciado por $path de outro projeto)
{
  "name": "nested",
  "tree": {
    "$className": "DataModel",   // <- não é a raiz do lugar inteiro
    "$path": "pasta-sem-init"    // <- pasta comum, sem init.lua/init.server.lua/etc → class_name_from_path = "Folder"
  }
}
```
Resultado no Rojo real: **nenhum erro no `rojo serve`/`build`/`sourcemap`.** A árvore recebe um nó
com `ClassName = "DataModel"` na posição onde o projeto aninhado foi montado. O que acontece depois
(no Studio, via plugin, ou num `rojo build` de place) está fora do escopo do parsing de projeto.

## Limites e pegadinhas

- Esta pesquisa cobre só o **carregamento de projeto** (`snapshot_middleware/project.rs` +
  dispatch em `mod.rs`). Não fui atrás de código de `rbx_dom_weak`/`rbx_reflection` pra confirmar
  se existe alguma validação de `NotCreatable` em outro lugar do pipeline do Rojo (ex: no
  `rojo build` ao serializar) — os dois únicos usos de `"DataModel"` em `cli/build.rs` e
  `cli/upload.rs` são sobre o **root único da sessão inteira**, não uma varredura de todos os nós
  buscando classes inválidas. Não encontrei nenhuma chamada tipo `descriptor.tags.contains(&ClassTag::NotCreatable)`
  fora de `project.rs:688` (que é sobre `Service`, não `NotCreatable`), então a hipótese mais provável
  é que o Rojo real **nunca** valida "essa classe pode estar aqui" de forma geral — mas isso é
  inferência por ausência de grep, não uma prova de negativa.
- **Achado que extrapola o escopo original do pedido, sinalizando pro arquiteto/planejador**: como
  não existe "checagem especial de posição pra DataModel" nem no Rojo real nem — até onde os
  Decisão 15/16 desenharam — no LuauBench hoje fora da raiz de topo, a lacuna da task-cli-022 é na
  prática um caso particular de um problema mais genérico: **qualquer classe `NotCreatable`/abstrata
  do dump alcançada via `$className` + `$path`-que-resolve-a-`Folder` passa pelo `Plan` sem
  diagnóstico**, porque a guarda `plan/class-name-conflict` só dispara quando `pathClassName ~=
  "Folder"` (Decisão 16), nunca quando é `Folder`. `DataModel` só é o exemplo que apareceu porque é
  a classe abstrata mais comum de aparecer por engano num `.project.json`; o mesmo bug bate em
  `$className: "Instance"` ou `$className: "PVInstance"` com `$path` de pasta sem `init.*`. Vale o
  arquiteto decidir se a correção é "checagem especial pra `DataModel` fora da raiz de topo" (escopo
  estreito, como a task original propôs) ou "checagem geral de instanciabilidade no `Plan`, usando o
  mesmo `IsSimulatedClass`/tabela de classes abstratas que `services` já expõe" (escopo mais largo,
  fecha a família inteira do bug de uma vez). Não decidi isso sozinho — é decisão de arquitetura,
  não de pesquisa.

## Se a resposta virar código (pra `coder-cli` não precisar rep-esquisar)

Não existe mensagem real do Rojo pra imitar — a mensagem é 100% original do LuauBench. Sugestão de
condição e texto (arquiteto/planejador decide o nome final do diagnóstico e se generaliza pra além
de `DataModel`, ver seção anterior):

- **Onde**: mesmo arquivo/função da Decisão 16, `src/cli/TreePlanner.luau`, na guarda de
  `resolveCore` que hoje só cobre `pathClassName ~= "Folder"`. Precisa de um braço NOVO, separado do
  existente (não reescrever a condição existente — ela já está correta pro caso não-Folder):
  ```
  se explicitClassName == "DataModel" (ou: se explicitClassName é NotCreatable/abstrata no dump,
    caso o arquiteto opte por generalizar) e pathClassName == "Folder" e NOT isOutermostRoot
    (mesmo campo PlanContext.OutermostProjectFilePath da Decisão 16)
  então: novo diagnóstico plan/<nome-a-definir>, ex. "DataModel só é válido como a raiz do projeto
    mais externo; aqui ele está em <NodePath>, dentro de <caminho do projeto aninhado ou não>."
  ```
- **Precisa cobrir também a raiz de topo com pasta sem `init.*`?** Não — pela tabela da Decisão 16,
  esse caso (`Raiz (qualquer) DataModel + $path de pasta sem init.*`) **já passa hoje** e deve
  continuar passando quando é de fato a raiz do plano inteiro (é a forma legítima de um projeto Rojo
  raiz sem arquivo de entrada — pasta comum). O novo diagnóstico só dispara quando
  `NOT isOutermostRoot`.
- **Teste**: fixture novo em `src/cli/fixtures/tree-planner/`, projeto externo com um nó cujo
  `$path` aponta pra uma pasta com `default.project.json` próprio, e esse projeto aninhado com
  `{"$className":"DataModel","$path":"pasta-sem-init"}` (pasta sem `init.*`) na raiz. Mais um teste
  confirmando que a raiz de topo com o mesmo padrão continua passando sem diagnóstico (regressão da
  Decisão 15/16).
