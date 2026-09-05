# coder-services — task-services-002 — Gerador dev-time

Data: 2026-09-05. Território: `tools/generate-services.luau`, `tools/api-dump.lock.json`,
`tools/coverage.luau`, `tools/capabilities.lock.json`, `src/services/generated/**`. Nenhum arquivo
fora desse território foi tocado (confirmado via `git status`: só `.claude/tasks.json` aparece
modificado, pré-existente, não tocado por mim).

## Arquivos

Criados:
- `tools/api-dump.lock.json` — lock do dump (commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75`,
  versão Roblox `0.737.0.7371584`, `sizeBytes=8006149`, `sha256` **já preenchido** (não deixei o
  placeholder `"<preenchido pelo gerador..."`) — ver seção "Decisão: sha256 pré-preenchido" abaixo.
- `tools/capabilities.lock.json` — `grantable` (41 nomes, seção A.5 do desenho, copiados
  verbatim) + `reserved` (`InternalTest`, `PluginOrOpenCloud`, `RemoteCommand`).
- `tools/coverage.luau` — as 20 classes-alvo da leva 1, literalmente as do board (sem
  WorldRoot/Model/PVInstance/BasePlayerGui).
- `tools/generate-services.luau` (1086 linhas) — o gerador.
- `tools/generate-services.spec.luau` (182 linhas, 10 testes) — verifica a SAÍDA já gerada (não
  roda o gerador; roda depois dele).
- `src/services/generated/Manifest.luau`, `src/services/generated/Index.luau`,
  `src/services/generated/classes/<24 arquivos>.luau` — saída, 100% sobrescrita a cada execução.

## Pipeline implementado (bate com a Decisão 1/2/3 + revisão pós-pesquisa)

1. Lê `tools/api-dump.lock.json` + `tools/capabilities.lock.json`.
2. `.cache/api-dump/<commit-completo>.json` — baixa via `net.request` se ausente; valida
   `sizeBytes`+`sha256` (via `serde.hash("sha256", ...)`) contra o lock; **aborta** (mensagem +
   `process.exit(1)`) se divergir. Testado de verdade: corrompi o cache local (bytes extras) e
   confirmei abort com a mensagem certa antes de restaurar.
3. `serde.decode`, valida `Version == 1` — testado de verdade (fabriquei um JSON minúsculo com
   `Version=2`, apontei o lock pra ele por um instante, confirmei abort, restaurei o lock original).
4. Fecho de superclasses a partir de `tools/coverage.luau`, parando em `"Instance"` e ignorando
   `"Object"`/`"<<<ROOT>>>"` — resultado: **24 classes** (as 20 do coverage + `WorldRoot`, `Model`,
   `PVInstance`, `BasePlayerGui`, puxadas por herança, confirmadas ausentes de `coverage.luau`).
5. Pré-validação de capability: varre TODO membro do fecho (Property/Event/Callback/Function,
   Read+Write) e aborta ANTES de escrever qualquer arquivo se algum nome não estiver em
   `grantable ∪ reserved` — testado de verdade (removi `"Environment"` de `grantable`, confirmei que
   o abort lista `Environment` e os ~30 membros afetados de `Lighting`/`Workspace`, restaurei o
   lock).
6. Classificação de schema (tabela A.4, 8 passos, primeiro casamento vence) e de `MethodNames`
   (passos 1-3, aplicados também a `Function` — o buraco da regra antiga).
7. `Default` parseado por `ValueType.Category`: sentinela `__api_dump_*` (encontrei 5 variantes
   reais no dump: `__api_dump_no_string_value__`, `__api_dump_skipped_class__`,
   `__api_dump_failed_to_create_class__`, `__api_dump_class_not_creatable__`,
   `__api_dump_write_only_property__` — todas tratadas pelo mesmo `string.match("^__api_dump")`,
   não uma lista fechada de strings exatas) → `nil`; `Primitive` não-sentinela → valor Luau real;
   `Enum`/`DataType`/`Class` → `nil` sempre (mesmo quando o dump traz um valor real não-sentinela,
   ex.: `AccessoryDescription.AccessoryType = "Unknown"` — fora do fecho desta leva, mas confirmei
   que a regra dispara certo caso apareça).
8. Emite `Manifest.luau` (916), `classes/<X>.luau` (24) e `Index.luau` (requires literais).
9. Imprime relatório (deprecated, defaults não representáveis por classe, membros de Object/Instance
   não cobertos por `runtime/Instance.luau`, funções de Object não dobradas, classes vazias).

## Números exatos confirmados (pedidos explicitamente pela tarefa)

Rodando `lune run tools/generate-services` contra o dump real:

- **Manifest.luau: 916 entradas** (confirmado por teste automatizado).
- **Fecho: 24 classes** (20 do coverage + WorldRoot/Model/PVInstance/BasePlayerGui por herança).
- **Eixo Capabilities exclui EXATAMENTE 4 membros de schema na leva 1**: `Script.Source`,
  `ModuleScript.Source`, `RunService.Misprediction` (Event), `RunService.FrameNumber` — os mesmos
  4 citados no board, byte-a-byte.
- **143 métodos emitidos no total** no fecho, **60 excluídos por Security**, **0 por capability**
  reservada — bate exato com o board (contribuições maiores: RunService 17 excluídos de 28,
  WorldRoot 11 de 38, Workspace 11 de 18, Players 12 de 36 — todas conferidas).
- **Lighting/Players/StarterPlayer com schema COMPLETO**: zero exclusão pelo eixo Capabilities nas
  três (só exclusões por Security, que são legítimas — ex.: `Lighting` tem 2 propriedades
  `RobloxSecurity`). Prova direta e testada: `Lighting.Ambient` (`Capabilities.Read=["Environment"]`),
  `Players.PlayerAdded` (`Capabilities=["Players"]`), `StarterPlayer.AutoJumpEnabled`
  (`Capabilities.Read=["Players"]`, `Default=true` real) sobrevivem no schema — se a regra ingênua
  "capability != Basic é restritiva" tivesse sido implementada, as três classes teriam sido
  praticamente zeradas.
- **Idempotência confirmada rodando duas vezes**: apaguei `src/services/generated/` do zero, rodei
  o gerador duas vezes seguidas, comparei `md5sum` de todos os 26 arquivos (idênticos) E o texto do
  relatório impresso (idêntico). Também testado via `git add -A` + segunda rodada +
  `git diff --stat`: zero diferença nos arquivos gerados (só `.claude/tasks.json`, que não é meu).

## Achados/decisões durante a implementação (não estavam 100% no desenho)

1. **`Object.GetPropertyChangedSignal`/`IsA`/`isA` NÃO são dobradas em `Instance.MethodNames`** —
   só o SCHEMA (`Property`/`Event`) de Object é dobrado em Instance, nunca as `Function`. Descobri
   isso batendo a conta: dobrar as 3 funções de Object dava 146 métodos totais (146/60/0), 3 a mais
   que o "143" pedido pelo board. O board também cita "Instance 38 de 39" (em task-services-003) —
   39 é exatamente o total de `Function` que `Instance` declara SOZINHA no dump, sem a Object. Then
   confirmei: 146-3=143 bate exato. `IsA` já é nativo (precedência de `runtime/Instance.luau`, então
   dobrá-la seria morto mesmo); `GetPropertyChangedSignal`/`isA` (deprecated) ficam de fora e
   aparecem no relatório final como gap declarado, nunca implementados nem inventados.
2. **Palavra reservada `function` como nome de parâmetro do dump**: `RunService:BindToRenderStep`
   e `:BindToSimulation` têm um parâmetro literalmente chamado `function` no dump real — gerar
   `function: unknown` no tipo público quebraria a compilação. Adicionei uma lista de palavras
   reservadas do Luau e sufixo `_` em colisão (`function_`). Achado ao rodar pela primeira vez, não
   hipotético — luau-lsp não pegou isso (é sintaticamente inválido, não um erro de tipo, então
   `luau-lsp analyze` reportaria parse error, o que me fez olhar o arquivo manualmente).
3. **Toda chave de membro (schema e tipo público) usa colchetes (`["Nome"] = ...`)**, nunca
   `.Nome` — o dump real tem nomes com espaço (`PVInstance."Pivot Offset"`,
   `StarterPlayer."LoadCharacterLayeredClothing "` com espaço à direita, ambos felizmente excluídos
   por `NotScriptable` nesta leva, mas o gerador não depende disso: a forma em colchetes é sempre
   válida independente do nome).
4. **`string.format("%q", ...)` para todo literal de string emitido** — escapa qualquer conteúdo
   com segurança (a mesma razão do ponto 3).
5. **Campos/métodos que `runtime/Instance.luau` já cobre nativamente não são redeclarados no TIPO
   público exportado** (`export type X = Runtime.Instance & {...}`) — só no VALOR de
   `Generated.Schema`/`MethodNames` (necessário para o achatamento do `ClassRegistry`). Lista
   hardcoded em `NATIVE_COVERED_BY_RUNTIME_INSTANCE` (21 nomes: 3 campos fixos, 5 sinais fixos, 13
   métodos base) — precisa ficar em sincronia manual se `runtime/Instance.luau` mudar; documentado
   no código e aqui como risco de manutenção aceito.
6. **`abort()` não é tipada `-> never`** — luau-lsp 1.69.0 reporta "Not all codepaths in this
   function return 'never'" mesmo com `process.exit` (tipado `-> never` no typedef do Lune) como
   último statement. Documentei o achado no código; toda função que precisa de exaustividade depois
   de `abort(...)` tem um `return` explícito logo depois (nunca depende de inferência de fluxo).
   Em runtime não muda nada — `process.exit` encerra o processo de verdade.
7. **`sha256`/`sizeBytes` do lock já vêm preenchidos**, não deixei o placeholder do desenho
   ("`<preenchido pelo gerador na primeira execução>`"): já tinha os dois valores verificados por
   inspeção direta nesta sessão (`sha256sum` real + `serde.hash("sha256", ...)` batendo). O gerador
   só LÊ e VALIDA o lock, nunca escreve nele — mais simples e mais seguro pra idempotência (um
   gerador que reescreve um arquivo committado a cada rodada é uma fonte de diff espúrio).

## Testes rodados (resultado real, não assumido)

- `lune run tools/generate-services` — roda de ponta a ponta, exit 0, relatório não vazio.
- `lune run tools/generate-services.spec.luau` — **10/10 passou**, cobrindo os números exatos acima
  mais o congelamento (`table.freeze`) de todo `Generated.Schema`.
- Idempotência: 2 rodadas limpas, `md5sum` de 26 arquivos idêntico + relatório idêntico + `git diff
  --stat` limpo.
- 3 caminhos de abort testados DE VERDADE (não só lidos no código): sha256/sizeBytes divergente,
  `Version ~= 1`, capability desconhecida (nomeando a capability E os membros afetados) — todos
  restaurados ao estado original depois.
- `luau-lsp analyze --platform=standard` limpo (exit 0, zero diagnósticos) em: `tools/generate-
  services.luau`, `tools/generate-services.spec.luau`, e nos 26 arquivos gerados
  (`Manifest.luau`, `Index.luau`, `classes/*.luau`) — zero ocorrência real de `any` (só dentro de
  comentários, nunca em código).
- Carregamento real via Lune (não só análise estática) dos arquivos gerados: `require` de
  `Workspace`, `Instance`, `Index`, `Manifest` a partir de um script de fora de `src/`, todos
  carregam e os dados batem.
- Corrigidos DURANTE a verificação (não ficaram para o revisor achar): parâmetro `function`
  colidindo com palavra reservada (quebraria compilação), variável morta `methodTypeLines`,
  `abort()` mal tipada, um `:: any` que tinha entrado no spec.

## Superfície NÃO coberta por esta tarefa (fica para task-services-003+)

- `src/services/behavior/**`, `src/services/init.luau` (registro real via `ClassRegistry`,
  `Services.Register()` iterando `Index.luau`) — território de task-services-003/004/005, que eu
  não toquei.
- Comportamento das classes (o "como") — o gerador só emite o "o quê" (regra 03). Nenhum
  `Initialize` é gerado, como o desenho exige.
- `Vector3`/`CFrame`/`Enum`/`DataType` reais — todos os `Default`/tipos dessas categorias são
  `nil`/`unknown` nesta fase, documentado no código e no relatório impresso pelo gerador (contagem
  por classe).

## Fidelidade / divergências declaradas

- Tipo público exportado por classe (`export type X = Runtime.Instance & {...}`) usa `unknown` para
  toda `ValueType` que não seja `Primitive` (Enum/DataType/Class) e para parâmetro/retorno de método
  fora de `Primitive` — nunca uma aproximação solta (ex.: nunca finjo `Runtime.Instance?` para uma
  propriedade `Class` só porque "faz sentido"; fica `unknown`, documentado no cabeçalho de cada
  arquivo gerado).
- Retorno de método `Group`/`Tuple` vira `...unknown`; `Array` vira `{ unknown }`;
  `Dictionary`/`Map` vira `{ [string]: unknown }` — aproximação declarada (o dump não enumera os
  elementos de uma tupla), comentada no código (`luauReturnType`).
- `.cache/` já estava no `.gitignore` (confirmado, não duplicado). `Full-API-Dump.json` não é
  committado — só os 916 bytes-de-resumo do Manifest e os 24 arquivos de classe.
