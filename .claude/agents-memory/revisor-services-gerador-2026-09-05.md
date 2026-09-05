# revisor-services — task-services-002 — Gerador dev-time (tools/generate-services.luau)

Data: 2026-09-05. Território revisado: `tools/generate-services.luau`, `tools/generate-services.spec.luau`,
`tools/api-dump.lock.json`, `tools/capabilities.lock.json`, `tools/coverage.luau`,
`src/services/generated/{Manifest,Index}.luau` + `src/services/generated/classes/*.luau` (24 arquivos).

**Metodologia**: nenhum número do coder foi aceito de olho. Rodei o gerador eu mesmo (lune 0.10.5),
reimplementei de forma independente (Node.js) a lógica de classificação de 4 eixos contra o
`Full-API-Dump.json` real em cache, e testei os 3 caminhos de abort corrompendo os arquivos de lock
eu mesmo (com backup/restauração, estado final limpo confirmado por `git status`).

## Verificações obrigatórias — todas reproduzidas por mim

1. **Idempotência** — `rm -rf src/services/generated && lune run tools/generate-services` duas vezes
   seguidas: `md5sum` dos 26 arquivos IDÊNTICO nas duas rodadas, e o texto do relatório impresso
   IDÊNTICO (`diff` limpo). Uma terceira rodada após os testes de abort (restaurando os locks)
   também produziu relatório idêntico ao original.

2. **3 caminhos de abort testados por mim, do zero** (não apenas lidos no código):
   - (a) `sha256` do lock corrompido para `deadbeef...` → abort com mensagem nomeando o arquivo de
     cache, o hash calculado e o esperado, `exit 1`. Restaurado.
   - (b) `Version` do dump forçada para `2` (cópia do dump real com `"Version": 1` → `"Version": 2`,
     lock temporariamente apontado para essa cópia com `sizeBytes`/`sha256` recalculados) → abort
     `"esquema do dump (campo Version) é 2, esperado 1"`, `exit 1`. Restaurado.
   - (c) Removi `"Environment"` de `grantable` em `tools/capabilities.lock.json` (sem adicionar a
     `reserved`) → abort nomeando exatamente `'Environment'` e listando os 32 membros afetados
     (`Lighting.Ambient`, `Lighting.Brightness`, ..., `Workspace.AirDensity`,
     `Workspace.AirTurbulenceIntensity`), `exit 1`. Restaurado, regerado, relatório voltou idêntico
     ao original.

3. **Números exatos, recontados de forma independente**:
   - `Manifest.luau`: **916 entradas** — confirmado por `grep -cE` direto no arquivo (não pela suíte
     do coder), e pelo relatório do próprio gerador.
   - Fecho: **24 classes** (as 20 de `coverage.luau` + `WorldRoot`/`Model`/`PVInstance`/
     `BasePlayerGui` puxadas por herança) — confirmado pela saída do gerador e por `ls
     src/services/generated/classes | wc -l`.
   - Eixo `Capabilities` exclui **exatamente 4** membros de schema na leva: `Script.Source`,
     `ModuleScript.Source`, `RunService.Misprediction`, `RunService.FrameNumber` — reproduzido por
     um script Node independente que reimplementa a tabela A.4 inteira (não o código do gerador)
     contra o dump bruto em cache, varrendo as 24 classes do fecho + o fold de `Object`. Resultado
     bate 100% com o gerador.
   - Métodos: **143 mantidos, 60 excluídos por Security, 0 por capability reservada** — confirmado
     pelo mesmo script independente, E por contagem manual classe a classe (`RunService`
     declared=28/kept=11/excluded=17; `Workspace` declared=18/kept=7/excluded=11; `WorldRoot`
     declared=38/kept=27/excluded=11; `Players` declared=36/kept=24/excluded=12) — todos batem com
     as notas do board em `task-services-003`/`004`.
   - `Lighting`/`Players`/`StarterPlayer` com schema **completo**: listei TODOS os membros excluídos
     dessas 3 classes por Security/Tags (não por Capability) — `Lighting.ExtendLightRangeTo120`/
     `Technology`; ~19 membros de `Players` (todos `Hidden`/`RobloxSecurity`/`LocalUserSecurity`/
     `NotScriptable`); ~24 de `StarterPlayer` (idem) — zero exclusão pelo eixo Capabilities nas três,
     confirmando que a leitura ingênua "capability != Basic é restritiva" não foi implementada.

4. **Amostragem de vazamento de `NotScriptable`/`Security.Read ~= "None"`** — script independente
   rodado contra **12 classes** (mais que o mínimo de 3 pedido): `Workspace`, `WorldRoot`, `Instance`,
   `Model`, `PVInstance`, `RunService`, `ReplicatedStorage`, `Script`, `ModuleScript`, `Folder`,
   `BaseScript`, `LuaSourceContainer` — **zero violações** em todas.

5. **Cabeçalho "ARQUIVO GERADO — NÃO EDITAR À MÃO" + commit + versão** — confirmado em `Workspace`,
   `Instance`, `WorldRoot`, `Folder`, `Script`, `Manifest.luau`, `Index.luau` (7 arquivos, mais que o
   mínimo de 5 pedido).

6. **`Index.luau` usa requires literais** — lido o arquivo inteiro: 24 linhas `["X"] =
   require("./classes/X") :: Types.GeneratedClass`, nenhuma construção dinâmica por string/
   concatenação em tempo de execução.

7. **`--!strict` + zero `any` real** — nenhum arquivo de `tools/*.luau` ou
   `src/services/generated/**` sem `--!strict` na primeira linha; toda ocorrência da palavra `any`
   nesses arquivos está dentro de comentário (`nunca any`, `regra 01`), nunca em código. `luau-lsp
   analyze --platform=standard` limpo (zero diagnósticos) em `tools/generate-services.luau`,
   `tools/generate-services.spec.luau` e nos 26 arquivos gerados (rodei `lune setup` para popular os
   typedefs, que estavam vazios no ambiente antes desta revisão).

8. **`.cache/` não commitado, dump não commitado** — `.gitignore` já tinha `.cache/` (não duplicado
   pelo coder); `git status` mostra só `src/services/generated/`, `tools/` como novos e
   `.claude/tasks.json` modificado (pré-existente); `git check-ignore` confirma `.cache/api-dump/*`
   ignorado.

## As duas correções do coder — julgadas

1. **Colisão com `function` (palavra reservada do Luau)** em `RunService:BindToRenderStep`/
   `:BindToSimulation` (parâmetro chamado literalmente `function` no dump real) — a lista
   `LUAU_KEYWORDS` + sufixo `_` (`function_`) é uma correção correta e mínima, confirmada no arquivo
   gerado (`RunService.luau:25-26`) e validada pelo `luau-lsp analyze` limpo. Não introduz problema
   novo: é só o nome do parâmetro no TIPO exportado (documentação de assinatura), não afeta
   `MethodNames`/despacho em runtime.
2. **Não-dobra de `Object.GetPropertyChangedSignal`/`IsA`/`isA` em `Instance.MethodNames`** —
   verificado que `Instance` declara 39 `Function` próprias no dump, 1 excluída por Security
   (`GetDebugId`, `PluginSecurity`), sobrando exatamente 38 — bate com os 38 nomes realmente emitidos
   em `Instance.luau`. `IsA`/`GetPropertyChangedSignal`/`isA` (de `Object`) ficam de fora e aparecem
   no relatório do gerador como gap declarado (nunca inventados nem implementados silenciosamente).
   Decisão correta e consistente com o resto do design (o SCHEMA dobra Property/Event de `Object`,
   as `Function` de `Object` não são dobradas — assimetria deliberada, documentada no código).

## Observação (não é achado, informativa)

`Instance.Schema` dobra `ChildAdded`/`ChildRemoved`/`AncestryChanged`/`Destroying`/`Changed` de
`Object` como `Kind = "Event"` (exigido e testado pelo próprio `generate-services.spec.luau`). Isso
faz `ClassRegistry.new` (task-runtime-018/022, território de `runtime`) semear um `Signal.new()`
extra para esses 5 nomes a cada instanciação, além do Signal fixo nativo que `Instance.luau` já
mantém internamente (`internal.childAdded`, `internal.changed`, ...). Confirmei em
`src/runtime/Instance.luau` que os sinais fixos são resolvidos no passo 2 do `__index`, ANTES do
schema (passo 5/6) — então o Signal seedado pelo schema para esses 5 nomes é morto/nunca observado
pelo script do usuário, só um desperdício de alocação. Não é um bug de `services`: é consequência
direta e testada da Decisão 1 (dobrar Object em Instance) + Decisão 6 (semear Signal por evento) do
próprio desenho do arquiteto. Sinalizo para quem eventualmente perfilar custo de instanciação, não
como correção pendente.

## Território e regressão

- Nenhum arquivo fora de `tools/` e `src/services/generated/` foi tocado por esta tarefa —
  `src/services/{Types,ClassBuilder,Context,init}.luau` já existiam (commit `6eca82f`, task-services-001)
  e não aparecem como modificados no `git status`.
- `lune run tools/generate-services.spec.luau` → **10/10 passou** (rodei eu mesmo via Lune real, não
  só a reimplementação em Node).

## Veredito

```
## Veredito
APROVADO
```

Nenhum achado GRAVE ou ALTO. Todos os números do relatório do coder foram reproduzidos de forma
independente (rodando o gerador do zero, reimplementando a lógica de classificação em separado, e
testando os 3 caminhos de abort eu mesmo) e bateram exatamente. A única observação registrada acima
é informativa, não bloqueante, e decorre de uma decisão já tomada e testada pelo arquiteto — não uma
falha desta tarefa.
