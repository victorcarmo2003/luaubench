# Testador — primeira rodada real contra Roblox-Games (2026-09-05)

Nota de continuidade: esta rodada foi retomada depois de uma queda de processo no meio da
execução original. O trabalho abaixo é o que foi de fato executado e verificado nesta sessão
(não há achado reaproveitado de uma tentativa anterior que não tenha sido re-confirmado aqui).

## Escopo

Primeira vez que `luaubench run` (pipeline completo: `ProjectFile` → `TreePlanner` →
`TreeMaterializer` → `ScriptRunner`) roda contra projetos Roblox reais do usuário, não fixtures
sintéticas. Território: `tests/scenarios/` (escrita), read-only em `src/**` e em
`C:\Users\hakor\Documents\Roblox-Games`.

## Levantamento inicial (os 17 projetos com `.project.json`)

| Projeto | Arquivos .lua/.luau | Tamanho em disco |
|---|---|---|
| AnimeFallen | 1013 | 16M |
| BLOXIA | 473 | 4.9M |
| BallBrawl | 595 | 4.6M |
| CodeBreaker | 916 | 13M |
| Frozen_Faithless | 1041 | 12M |
| Hide-or-Hit | 688 | 13M |
| LaunchLuckyBlock | 454 | 290M (assets grandes) |
| Modux | 601 | 5.1M |
| PLANE | 1064 | 46M |
| **Panic - CHESSS** | **30** | **846K** |
| RunningSmth | 982 | 12M |
| SquishObby | 635 | 8.6M |
| Story_Game | 433 | 2.9M |
| **TheGame** | **310** | **3.3M** |
| **Tiktok** | **3** | **80K** |
| Tower Defense - Bloxia | 462 | 4.8M |
| Towers | (não capturado no scan, ver nota) | — |

Escolhidos os 3 menores/mais autocontidos para a primeira rodada: **Tiktok** (projeto Rojo
"default" gerado por `rojo init`), **Panic - CHESSS** (jogo de xadrez real, framework próprio
Modux, ~30 arquivos), **TheGame** (310 arquivos, para ver comportamento numa árvore maior).

## Como cada projeto foi rodado

Comando real, processo real (não chamada in-process a `RunCommand.Execute`):

```
lune run src/cli/main.luau run "<caminho>" --no-color --timeout 5
```

Reproduzível via `tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` (roda os 3
projetos via `process.exec`, com asserts sobre `ExitCode`/stdout/stderr reais — rodado com
sucesso nesta sessão, 3/3 passando, caracterizando o comportamento ATUAL, ver seção "Bug grave"
abaixo para o porquê os asserts documentam um bug em vez de um sucesso).

## Achado principal — BUG GRAVE confirmado (território `cli`)

**Todos os 3 projetos reais testados falham em `TreePlanner.Plan` com
`[plan/missing-class-name]` no nó `StarterPlayer.StarterPlayerScripts`, ANTES de qualquer script
do usuário rodar.** Saída real (Tiktok, `--no-color`):

```
error: [plan/missing-class-name] Instance "tree.StarterPlayer.StarterPlayerScripts" is missing
some required information. One of the following must be true: - "$className" must be set,
- "$path" must be set to an existing file or folder, or - the instance must be a known service,
like ReplicatedStorage. (node: tree.StarterPlayer.StarterPlayerScripts, file: .../default.project.json)
```

Idêntico (mesmo `node`/mesma mensagem) em **Panic - CHESSS** e **TheGame**.

### Por que isso não é peculiaridade dos 3 escolhidos

`grep -l "StarterPlayerScripts" */default.project.json` nos 17 projetos reais do usuário retorna
**17/17** — todo projeto que popula `StarterPlayerScripts` (ou seja, todo projeto com
LocalScript de cliente — praticamente qualquer jogo Roblox real) usa o mesmo padrão:

```json
"StarterPlayer": {
  "StarterPlayerScripts": {
    "Client": { "$path": "src/client" }
  }
}
```

— sem `$className` explícito em `StarterPlayerScripts`. Confirmado por amostragem (TheGame,
BLOXIA, AnimeFallen) que nenhum declara `$className` ali. Isso é o padrão gerado pelo próprio
`rojo init` (visto de forma mais pura no projeto "Tiktok", que é literalmente o template default
do Rojo).

### Causa raiz (leitura de código, não execução — para orientar `coder-cli`/`pesquisador`)

`src/cli/TreePlanner.luau:596` e `:921` só ativam a inferência de "known service" quando
`parentClassName == "DataModel"`. `src/services/generated/Manifest.luau:749` confirma
`StarterPlayerScripts` tem `IsService = false` (fiel ao dump real — não é uma Service
`GetService()`-ável) — então mesmo que a guarda `parentClassName == "DataModel"` fosse
relaxada, a checagem `options.IsServiceClass(name)` ainda devolveria `false` para
`StarterPlayerScripts`. Ou seja, **relaxar só o `parentClassName` não resolve** — Rojo real usa
um mecanismo diferente de "Service por nome" pra esse caso.

### Confirmado contra o Rojo real, não suposição

Rodei o binário real (`rojo 7.7.0`, via `rokit` já instalado no projeto Tiktok):

```
cd Roblox-Games/Tiktok && rojo sourcemap default.project.json --include-non-scripts -o <tmp>
```

Saída fresca (gerada nesta sessão, não um `sourcemap.json` obsoleto que já estava no repo do
usuário — validei os dois e batem, mas o que conta é o fresco):

```json
{"name":"StarterPlayerScripts","className":"StarterPlayerScripts","children":[
  {"name":"Client","className":"LocalScript","filePaths":["src/client/init.client.luau"]}
]}
```

O Rojo real resolve `StarterPlayerScripts` como filho de `StarterPlayer` **sem** `$className`
explícito, com sucesso. Isso **contradiz** a leitura registrada em
`.claude/agents-memory/pesquisa-formato-projeto-rojo-2026-09-05.md` (linha 90-91: "infer_class_name
só entra em ação se parent_class == DataModel"). Duas hipóteses, nenhuma confirmada por mim
(fora do meu papel — é para `pesquisador` decidir):
1. A pesquisa original estava incompleta para este caso específico (Rojo pode ter uma segunda via
   de inferência para filhos fixos e conhecidos de uma classe — `StarterPlayerScripts`/
   `StarterCharacterScripts` são os dois únicos filhos fixos de `StarterPlayer` no Roblox real).
2. Comportamento mudou entre a versão do código-fonte pesquisada e o binário Rojo 7.7.0 testado
   aqui.

**Recomendação**: antes de `coder-cli` tentar corrigir `TreePlanner.luau`, `pesquisador` precisa
revisitar especificamente "como Rojo resolve ClassName de filhos fixos conhecidos (ex.:
StarterPlayerScripts/StarterCharacterScripts) que não têm a tag `Service`" — não é um simples
relaxamento de `parentClassName == "DataModel"`.

### Impacto

Bloqueia o pipeline **inteiro** — nenhum script chega a rodar — para praticamente qualquer
projeto Roblox real com a estrutura padrão. É a lacuna de maior impacto encontrada nesta rodada,
maior que qualquer Service ou value-type faltante (que são esperados e já documentados como
divergência conhecida).

## Outros achados (por projeto)

### Tiktok (projeto Rojo "default")
- Além do bug acima: `$properties` com array (`Ambient`/`Position`/`Color`/`Size` — todos
  Vector3/Color3, ainda não simulados) vira **warning** `plan/non-primitive-property`, citando o
  campo exato, nunca erro nem valor inventado. Comportamento correto e gracioso — bate a
  expectativa da regra 00 ("nunca inventa, nunca falha silenciosamente"). **Padrão coberto com
  sucesso.**
- `SoundService` (não coberto pela wave 1 de `services`) está no `.project.json` mas só com
  `$properties`, nunca chega a ser instanciado/verificado nesta rodada porque o pipeline já erra
  antes em `StarterPlayerScripts` — não dá pra confirmar se bloquearia depois.

### Panic - CHESSS (jogo de xadrez real, framework Modux)
- Mesmo bug acima, sem achado incidental adicional.
- Por leitura de código (não executado — pipeline nunca chegou lá): `src/shared/Chess/Network.luau`
  chama `Instance.new("RemoteEvent")`/`Instance.new("RemoteFunction")` dentro de
  `Network.setup()`, chamado logo na primeira linha de `src/server/init.server.luau`. `RemoteEvent`
  não está nas 24 classes cobertas — seria a PRÓXIMA parede assim que a primeira for corrigida
  (mensagem esperada: `[LuauBench] RemoteEvent exists in the Roblox API Dump (...) but is not
  simulated by LuauBench yet`). Também usa `game:GetService("Players")` +
  `Players.PlayerRemoving:Connect` + `Players:GetPlayerByUserId` — ambos cobertos hoje
  (`Players` está na leva 1). Vale re-testar quando a StarterPlayerScripts for corrigida.
- `default.project.json` deste projeto também declara um `SoundService` com `$properties`
  (`RespectFilteringEnabled`) — mesma situação do Tiktok, não verificável ainda.

### TheGame (310 arquivos, projeto maior)
- Mesmo bug acima.
- Performance: planejar a árvore inteira (310 arquivos `.lua`/`.luau`, todos lidos do disco)
  levou **2.5s** (medido com `time`, processo real) — nenhum sinal de lentidão exponencial nesta
  escala. Não é um teste de carga rigoroso (uma amostra, um projeto), mas é dado real.
- Achado incidental, NÃO bug do LuauBench: `$path` para `ReplicatedStorage.Packages` e
  `ServerScriptService.ServerPackages` aponta para pastas que não existem neste checkout (Wally
  não rodou / dependências não instaladas) — vira erro `plan/required-path-not-found`, citando o
  caminho absoluto resolvido. Mensagem clara, mesmo padrão de qualidade do achado principal.

## Checklist do pedido original

1. **Experiência real de rodar**: comando funciona, lê o projeto, dá erro claro e acionável em
   TODOS os 3 casos. Nenhum crash cru, nenhum stack trace do Lune vazando, nenhuma mensagem
   confusa (confirmado por assert explícito no cenário: nenhuma ocorrência de `stack traceback`
   nem `attempt to index nil` no stderr de nenhum dos 3 processos reais).
2. **Onde cada projeto bate a primeira parede**: os 3 batem no MESMO lugar —
   `TreePlanner.Plan`, nó `StarterPlayer.StarterPlayerScripts`, `[plan/missing-class-name]` — ver
   seção principal acima. Isso é o mapa de prioridade mais claro possível: é a ÚNICA coisa que
   precisa ser corrigida pra que qualquer um dos 17 projetos reais avance para a próxima parede
   (Services/value-types faltantes, aí sim variando projeto a projeto).
3. **Script/trecho que roda com sucesso até o fim ou até ponto significativo**: nenhum dos 3
   chegou a executar nenhum script de usuário nesta rodada — todos pararam na fase de
   planejamento (antes do passo 7 do pipeline, `Sandbox.Run`). Isso é uma limitação real desta
   rodada, não uma alegação de sucesso: a base de execução (scheduler/require/OOP) já tem
   cobertura de sucesso demonstrada pelos cenários sintéticos existentes
   (`tests/scenarios/*.scenario.luau` pré-existentes, ex. `metatable-oop-class-hierarchy`,
   `thirdparty-signal-scheduler-integration`) — só não foi re-confirmada contra código real
   porque nenhum projeto real passou da fase de plan.
4. **Crash real do LuauBench**: nenhum encontrado. Os 3 processos terminaram com `ExitCode 2`
   (erro de projeto, conforme a família de exit codes documentada em `src/cli/init.luau`),
   diagnóstico estruturado, sem travar (TheGame confirmado em 2.5s, os outros dois ainda mais
   rápidos). O achado do item 2 é um BUG DE FIDELIDADE (comportamento diverge do Rojo real), não
   um crash — mas é grave o suficiente pra bloquear tudo, daí a classificação GRAVE mesmo sem
   ser um crash literal.
5. **Falso positivo de segurança (sandbox)**: NÃO TESTÁVEL nesta rodada — nenhum script de
   usuário real chegou a rodar (todos os 3 pararam antes do `Sandbox.Run`). Fica como pendência
   explícita para a próxima rodada, assim que o bug do item 2 for corrigido (ou usando um projeto
   sintético/fixture que não dependa de `StarterPlayerScripts` populado, se alguém quiser
   adiantar esse teste especificamente antes do fix).

## Cenário criado

`tests/scenarios/real-roblox-games-pipeline-smoke.scenario.luau` — roda os 3 projetos reais via
`process.exec("lune", {"run", "src/cli/main.luau", "run", <path>, ...})`, 3/3 passando hoje
(caracterizando o bug atual). Cabeçalho do arquivo documenta que os asserts precisarão ser
atualizados quando `TreePlanner.luau` for corrigido (o comportamento esperado depois do fix é a
pipeline avançar, não mais parar em `plan/missing-class-name`).
