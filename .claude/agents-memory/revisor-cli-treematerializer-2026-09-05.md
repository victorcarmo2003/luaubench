# Revisão — task-cli-004 (TreeMaterializer.luau)

Data: 2026-09-05. Território: `src/cli/`. Revisão read-only, tudo reproduzido pelo próprio revisor (nenhum número aceito do self-report do coder sem reexecução independente).

## Arquivos revisados

- `src/cli/TreeMaterializer.luau` (novo)
- `src/cli/TreeMaterializer.spec.luau` (novo)
- `src/cli/fixtures/tree-materializer/basic/*` (novo: `default.project.json`, `server/Main.server.lua`, `shared/Modules/Foo.lua`)
- `src/cli/fixtures/tree-materializer/properties/default.project.json` (novo)
- `src/cli/Messages.luau` (diff — só adição, 6 funções novas no fim do arquivo)
- Leitura cruzada: `src/cli/TreePlanner.luau` (ordenação `table.sort`, `planProjectTree`/`planChildrenOf`), `src/runtime/DataModel.luau` (mensagem PT-BR de `GetService`), `src/services/init.luau` (`IsServiceClass`/`IsSimulatedClass`/`GetSimulatedServiceClasses`/`GetDumpVersion`), `src/services/generated/Manifest.luau`, `src/services/generated/classes/Instance.luau` (schema de `archivable`/`className`).
- `git status --short -- src/cli`: confirma escopo exato — só `Messages.luau` modificado + os 3 itens novos acima. Nenhum outro arquivo do território tocado.

## Verificação reproduzida (não aceita do relato)

1. **Testes rodados por mim, `lune run` em cada spec individualmente:**
   - `src/cli/*.spec.luau` (9 arquivos): 13+7+8+10+17+28+8+17+5 = **113/113**.
   - `src/runtime/*.spec.luau` (8 arquivos): 29+12+63+9+20+16+7+6 = **162/162**.
   - `src/services/*.spec.luau` + `src/services/behavior/*.spec.luau` (9 arquivos): 9+3+14+5+16+4+8+11+3 = **73/73**.
   - Números batem exatamente com o self-report (113/162/73), confirmados por execução própria, não por leitura do relato.
2. **Grep próprio, `src/cli` inteiro** (não só o arquivo novo): `NewEngineInstance(` (com parêntese) — zero ocorrências fora do texto do cabeçalho/spec que citam o nome em prosa. `any` real (padrões `: any`, `:: any`, `<any>`, `as any`) — zero ocorrências fora de uma linha de prosa em `JsonValue.luau` que explica por que `any` é evitado.
3. **`luau-lsp analyze --platform=standard`** rodado por mim em `TreeMaterializer.luau` e `TreeMaterializer.spec.luau` isoladamente: exit 0, zero diagnóstico. Rodado sobre todos os `.luau` de topo de `src/cli/`: só os dois `TypeError: Unknown require` já documentados em `init.spec.luau` (bug de tooling conhecido, não deste território) — exatamente o que o self-report alegava, nada novo.
4. **Fixture `basic`** (`ReplicatedStorage/Modules/Foo` via `$path`, `ServerScriptService` via `$path`): rodei o teste real (não apenas li) — `game.ReplicatedStorage.Modules.Foo` resolve por acesso de ponto encadeado, comparado por identidade (`==`) contra o objeto achado por `FindFirstChild`. `Source` do `Main.server.lua` é comparado byte a byte contra o conteúdo real do arquivo (lido de novo no teste, não hardcoded) via `GetPropertyRaw`, e uma segunda tentativa de leitura via `__index` normal (`mainScriptDot["Source"]`) falha com `pcall` — confirma invisibilidade ao script.
5. **Fixture `properties`**: `archivable: false` aplicado pela via pública de verdade (schema real de `Instance.luau` confirma `["archivable"] = { Kind = "Property", ReadOnly = false }`); `"Gravty": 10` (nome inexistente) e `"className": "Hacked"` (schema real confirma `ReadOnly = true`) viram dois `Diagnostic` distintos com `Code = "materialize/invalid-property"`, citando `NodePath`/`Field`/mensagem do motor (`"is not a valid member of"` e `"is read only"`, ambos confirmados como as mensagens reais de `Instance.luau:662` e `:727`) — nó `BadProps` continua existindo, `ClassName` nunca foi sobrescrito.
6. **Extensão do coder (Service do dump não coberto → erro amigável)**: HÁ teste cobrindo isso de verdade — `Services.IsServiceClass("Teams")` e `not Services.IsSimulatedClass("Teams")` confirmados por *sanity check* dentro do próprio teste E por leitura direta do manifesto gerado (`grep '["Teams"]' Manifest.luau` → `IsService = true, Covered = false`). O teste roda um `InstancePlan` manual com `IsServiceRoot=true`/`ClassName="Teams"` e confirma `Diagnostic{Code="materialize/service-not-simulated"}` com prefixo `[LuauBench]` e família `"not simulated"` — nunca a mensagem em português de `DataModel.GetService` (que eu confirmei ser literalmente `"GetService: '{className}' está registrada mas não é um Service..."` / `"classe '{className}' não registrada em ClassRegistry"`, lendo `DataModel.luau:74` e `:82`). **Não há lacuna aqui** — ao contrário do que a instrução antecipava, o caso está coberto por teste real, não por suposição.
7. **Ordem determinística de `Scripts`**: confirmei por leitura de código, não só pelo teste passar — `TreePlanner.luau:1048` (`table.sort(order)`) roda dentro de `planChildrenOf`, e `planProjectTree` (linha 1136) chama a MESMA função para os filhos da raiz — ou seja, `plan.Roots` já sai ordenado alfabeticamente pela mesma rotina que ordena `PlanNode.Children` em qualquer nível. `TreeMaterializer.materializeNode` visita em pré-ordem (nó, depois `for _, child in node.Children`) sem reordenar nada. Para o fixture `basic`, isso dá `Roots = [ReplicatedStorage, ServerScriptService]` (R < S) e a lista final `Scripts = [Foo, Main]`, exatamente o que o teste assere.
8. **`pcall` nunca engole erro em silêncio**: os dois pontos de `pcall` do módulo (`Services.new` em `createInstance`, escrita de `$properties` em `applyProperties`) sempre viram `bag:Add({Severity="error", ...})` citando `tostring(err)`/`tostring(resultOrError)` no `Message`. Não há nenhum `pcall` cujo branch de falha seja descartado.
9. **Raiz não-DataModel / Service com nome divergente**: ambos geram `Diagnostic` dedicado (`materialize/root-not-datamodel`, `materialize/service-name-mismatch`), e ambas as mensagens vêm de `Messages.luau` (`MaterializeRootNotDataModel`, `MaterializeServiceNameMismatch`) — conferido que **nenhuma** string literal user-facing aparece inline em `TreeMaterializer.luau` (todo `Message = ...` é uma chamada a `Messages.Materialize*`). `git diff -- src/cli/Messages.luau` confirma que a mudança é puramente aditiva (6 funções novas no fim, zero linha removida/alterada) — não quebra nenhuma mensagem existente de `TreePlanner`/`ProjectFile`/`Args`.
10. **`--!strict`**: presente na primeira linha de `TreeMaterializer.luau` e `TreeMaterializer.spec.luau`. Os dois arquivos `.lua` do fixture `basic` (`Main.server.lua`, `Foo.lua`) simulam código de usuário e não precisam de `--!strict` (mesma exceção documentada no desenho do arquiteto para `fixtures/`), e de fato não têm.

## Achados

**[BAIXO] `src/cli/TreeMaterializer.luau:125-126` (comentário) e `:222`**
Problema: o comentário na função `applyProperties` chama o cast de `$properties` de "ÚNICO cast de fronteira deste módulo", mas existe um segundo `::` no mesmo arquivo (`local instance = resultOrError :: Runtime.Instance`, linha 222), usado para recuperar o tipo de sucesso depois de um `pcall` cujo closure foi anotado como `(): unknown`.
Cenário: quem lê só o comentário da linha 125 pode concluir, incorretamente, que só há um ponto de cast no arquivo inteiro.
Correção: não é um problema de segurança de tipo (não é `any`, segue o mesmo idioma já usado em `TreePlanner.luau:382-384` e `:714-718` — `pcall` com retorno `unknown` + cast pós-checagem de `ok`) — só ajustar a redação do comentário para "único cast de fronteira sobre uma Instance com chave dinâmica" ou similar, para não overclaim.

**[BAIXO] `src/cli/TreeMaterializer.luau` (ausência) / contrato `InstancePlan` (arquiteto-cli-2026-09-05.md, Decisão 3)**
Problema: o nó raiz do projeto (`"tree": {"$className": "DataModel", "$properties": {...}}`, se um usuário algum dia escrever isso) nunca tem seu `$properties`/`Source` propagado — `InstancePlan` só carrega `RootClassName: string` para a raiz, sem um `Properties`/`Source` correspondente; `TreePlanner.planProjectTree` (linha 1117-1138) descarta `core.Properties`/`core.Source` do nó raiz, mantendo só `core.ClassName`. `TreeMaterializer.Materialize` nunca aplica propriedade nenhuma em `game` (a própria raiz), e nenhum diagnóstico (nem warning) avisa disso.
Cenário: um `.project.json` com `$properties` no nó raiz (padrão incomum, mas legal na sintaxe do Rojo) seria silenciosamente ignorado — sem crash, mas também sem aviso, o que roça a regra 00 ("nunca omitir em silêncio").
Correção: não é uma decisão desta task — o tipo `InstancePlan` foi fixado assim pelo arquiteto (não há `RootProperties`/`RootSource` no contrato) e `TreePlanner` (task-cli-003) já descarta esses campos antes de `TreeMaterializer` sequer receber o plano; portanto não é um defeito da implementação de `task-cli-004`, e sim uma lacuna herdada do contrato. Registrar como pendência para o `arquiteto`/`planejador` avaliarem se vale a pena (impacto real provavelmente baixo: raiz de projeto Rojo raramente carrega `$properties`, já que a raiz normalmente só declara filhos).

Nenhum achado GRAVE, ALTO ou MÉDIO.

## O que foi verificado e está correto

- Raiz `RootClassName ~= "DataModel"` erra dedicado ANTES de qualquer Instance criada (código + teste confirmam: `game:FindFirstChildOfClass("Folder") == nil` depois da tentativa).
- `IsServiceRoot` → `game:GetService`, com a ordem de validação certa (`Name==ClassName` → `IsServiceClass` → `IsSimulatedClass`) evitando vazar a mensagem em português de `DataModel.GetService`.
- Resto → `Services.new` em `pcall`, defesa em profundidade contra `$className` explícito inválido/não coberto (testada com typo real, "Frmae").
- `Source` via `SetPropertyRaw`, recuperável e invisível ao script (testado com conteúdo real de arquivo, não string hardcoded).
- `$properties` pela via pública, único cast comentado, erro de nome inválido e de propriedade somente-leitura viram `Diagnostic` sem derrubar o nó nem a árvore (testado com schema real).
- Ordem de `Scripts` determinística e igual à ordenação alfabética de `TreePlanner` (confirmado por leitura do código de ordenação, não só pelo teste).
- Zero chamada a `NewEngineInstance`, zero `any` real, em todo `src/cli/` (não só no arquivo novo).
- `Messages.luau` só recebeu adições; nenhuma string user-facing solta inline em `TreeMaterializer.luau`.
- 113/162/73 testes, `luau-lsp analyze` limpo exceto o falso-positivo já documentado — todos reproduzidos por mim.
- Extensão "Service não coberto → erro amigável" tem teste real (não é lacuna).

## Veredito
APROVADO
