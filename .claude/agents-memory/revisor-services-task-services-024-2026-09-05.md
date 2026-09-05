# Revisão — task-services-024 (`Lighting`: ClockTime/TimeOfDay/minutos + LightingChanged + GetMoonPhase)

Data: 2026-09-05. Escopo: `src/services/behavior/Lighting.luau`, `Lighting.spec.luau`, `Index.luau`, `Index.spec.luau`. Read-only, tudo reproduzido pelo revisor (não aceito self-report).

## Evidência reproduzida

- `lune run src/services/behavior/Lighting.spec.luau` → **14/14 PASS** (rodei eu mesmo).
- `lune run src/services/behavior/Index.spec.luau` → **5/5 PASS** (rodei eu mesmo).
- Suíte completa `src/services/**` (13 specs, 115 testes somados) → **todos PASS**, zero regressão.
- Sondas independentes escritas por mim (arquivo temporário na raiz do repo, apagado ao final, `git status` confirma território limpo):
  - 3 direções de sincronia (ClockTime→TimeOfDay/minutos, TimeOfDay→ClockTime/minutos, SetMinutesAfterMidnight→ambos) — confirmadas corretas.
  - Wrap positivo (`SetMinutesAfterMidnight(1500)`→1h, `ClockTime=25`→1h) — confirmado, bate com os testes oficiais.
  - Wrap **negativo** (não coberto pelos specs oficiais): `SetMinutesAfterMidnight(-10)` → `ClockTime=23.833...`, `TimeOfDay="23:50:00"`; `ClockTime = -1` → `23`/`"23:00:00"`. Bate com a decisão documentada no cabeçalho (wrap por analogia, módulo Lua nunca negativo).
  - `TimeOfDay = "5:30"` (forma curta, hora de 1 dígito) → `"05:30:00"`/`ClockTime=5.5`. Correto.
  - `LightingChanged`: os 4 casos de exclusão (`GlobalShadows`/`FogColor`/`FogStart`/`FogEnd`) testados individualmente no spec oficial — confirmei lendo o teste, todos os 4 casos são checados separadamente (não é 1 caso genérico).
  - `GetMoonPhase()` == `0.75` sempre, inclusive após mudar `ClockTime` — confirmado.
  - `GetSunDirection`/`GetMoonDirection` erram com prefixo `[LuauBench]` (stub do `ClassBuilder`, sem `Methods` próprio) — confirmado lendo o código e o spec.
  - Lista de exclusão do `LightingChanged` deriva de `LightingGenerated.Schema` (`Kind == "Property"`), não é lista solta — confirmei lendo `generated/classes/Lighting.luau` (20 properties + 1 event, bate exatamente com a pesquisa: `ClockTime`/`TimeOfDay` inclusos, `LightingChanged` como Event fica fora por construção). As 4 exclusões batem literalmente com a citação verbatim da pesquisa (seção B2).
  - `--!strict` presente e zero `any` nos 4 arquivos (`grep` confirmou).
  - `git status`/`git diff --stat`: só os 4 arquivos esperados tocados (`Index.luau` modificado, `Index.spec.luau` modificado, `Lighting.luau`/`Lighting.spec.luau` novos) + `src/valuetypes/types/CFrame.luau` não relacionado (trabalho concorrente do `coder-valuetypes`, já avisado na nota de concorrência).
  - Divergência de zero-padding/wrap não confirmados está documentada explicitamente no cabeçalho de `Lighting.luau` (linhas 37-49), não só no relatório do agente.
  - Registro discoverable: confirmei em `src/services/init.luau:276` (`local behavior = BehaviorIndex[className]`) — lookup genérico por nome, nenhum `if ClassName == "Lighting"` em lugar nenhum.

## Achado — MÉDIO (reentrância / contagem de `LightingChanged`)

`src/services/behavior/Lighting.luau:239-273`
**Problema:** uma única escrita lógica em `ClockTime`/`TimeOfDay` dispara `LightingChanged` **mais de uma vez** — 2x para escrita de `ClockTime`/`TimeOfDay` já em forma canônica, **3x** quando `TimeOfDay` é escrito em forma curta não-canônica (ex.: `"9:05"`), porque a resincronia reescreve a própria `TimeOfDay` (raw → canônica) e depois `ClockTime`, cada `SetPropertyRaw` sendo um `Changed` genuíno que o handler conta para `LightingChanged`.

**Reproduzido por mim:**
```
dynamic.ClockTime = 6         -> LightingChanged dispara 2x
dynamic.TimeOfDay = "9:05"    -> Changed dispara 3x (ClockTime, TimeOfDay, TimeOfDay) -> LightingChanged 3x
```

**Cenário de falha:** um script real que conecta `LightingChanged:Connect(...)` esperando uma chamada por atribuição lógica (padrão comum: `local n = 0; lighting.LightingChanged:Connect(function() n += 1 end)`) vê `n` incrementar 2-3x para uma única linha de código do usuário — divergência de contagem de evento, sem ter fonte que confirme se o Roblox real (onde as três vistas são literalmente o mesmo estado interno, não 3 propriedades logicamente independentes) dispara `LightingChanged` mais de uma vez para o mesmo tipo de escrita.

**Por que não é GRAVE/ALTO:** é uma aproximação **declarada** no cabeçalho (linhas 261-268: "uma única escrita de ClockTime pode disparar LightingChanged mais de uma vez... Aproximação aceita: cada Changed genuíno gera um LightingChanged, sem deduplicar"), não uma divergência silenciosa, e não há API inventada. O texto do comentário cobre genericamente "mais de uma vez" (tecnicamente cobre o caso 3x também), mas não registra o multiplicador exato nem que ele VARIA (2x vs 3x) conforme a forma de entrada.

**Correção sugerida:** (a) apertar o teste "LightingChanged dispara para ClockTime" — hoje só assere `fireCount >= 1`, o que aceitaria silenciosamente uma regressão futura para 4x, 5x etc.; travar no valor exato observado (2) e adicionar um teste equivalente para escrita curta de `TimeOfDay` (3). (b) opcionalmente, registrar no relatório desta tarefa (não só no código) que o multiplicador é 2x/3x, não "mais de uma vez" genérico, para o `pesquisador` ter algo concreto pra confirmar contra o Roblox real depois. Nenhuma das duas é bloqueante.

## Sem achados adicionais

Verifiquei especificamente e não encontrei problema em: fidelidade ao dump (nenhuma propriedade/evento/método inventado — os 20 Property + 1 Event + 7 Function batem exatamente com a pesquisa e o `generated/classes/Lighting.luau`), tipos reais vs. simplificados (fora de escopo desta task — `Vector3`/`CFrame` não entram aqui de propósito, decisão do arquiteto), herança (Lighting não reimplementa nada de `Instance`), stubs de `GetSunDirection`/`GetMoonDirection`/aliases deprecated (erram alto, não fingem funcionar), contrato com `runtime` (só `Instance.Changed`/`GetPropertyRaw`/`SetPropertyRaw`, API de engenharia já estabelecida por `RunService.luau`), registro central discoverable, `--!strict`/sem `any`, ausência de loop infinito (estruturalmente impossível — a flag `syncing` limita a recursão a no máximo 2 níveis, o cascateamento de `LightingChanged` é uma ação terminal, não recursiva).

## Veredito

**APROVADO COM RESSALVAS** — o único achado é MÉDIO (contagem de `LightingChanged` maior que 1 por escrita acoplada, documentada de forma genérica mas não com o multiplicador exato, e sub-testada com `>= 1` em vez de um valor travado). Não bloqueia merge; recomendo endereçar o teste apertado (`fireCount == 2`/`== 3` conforme o caso) numa tarefa de acompanhamento ou nesta mesma antes de fechar, e citar o multiplicador exato no relatório da task para o `pesquisador` confirmar contra o Roblox real quando conveniente.
