# Pesquisa — TweenService / TweenBase / Tween / TweenInfo (para desenho do arquiteto)

**Dump fixado:** commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75` de `MaximumADHD/Roblox-Client-Tracker`
(`0.737.0.7371584`), lido de `.cache/api-dump/28360dea4b90b35dc3fe9f829baae64fb6c50e75.json` (8 006 149 bytes,
já em cache — não baixei de novo). Filtro do projeto aplicado é o **real**, lido de
`tools/generate-services.luau` (`classifySchemaMember`/`classifyMethodMember`, linhas ~402-487) +
`tools/capabilities.lock.json` (`grantable`/`reserved`), não um filtro inventado por mim.

---

## A) Superfície do dump

### `TweenService`
- `Superclass: "Instance"`. `Tags: ["NotCreatable", "Service"]`.
- Cadeia de herança: `TweenService → Instance → Object → <<<ROOT>>>` (no LuauBench, `Instance` já é a raiz simulada — ver `ClassBuilder.luau`).
- 3 `Members`, todos `MemberType: Function`, todos `Security: "None"`, todos `Capabilities: ["Basic"]` (sem `Tags`):

| Nome | Parâmetros | ReturnType |
|---|---|---|
| `Create` | `instance: Class<Instance>`, `tweenInfo: DataType<TweenInfo>`, `propertyTable: Group<Dictionary>` | `Class<Tween>` |
| `GetValue` | `alpha: float`, `easingStyle: Enum<EasingStyle>`, `easingDirection: Enum<EasingDirection>` | `float` |
| `SmoothDamp` | `current: Variant`, `target: Variant`, `velocity: Variant`, `smoothTime: float`, `maxSpeed: float?`, `dt: float?` | `(Variant, Variant)` |

`GetValue`/`SmoothDamp` têm `SimulationAccess: true` (campo extra do dump, não usado pelo filtro do projeto).

### `TweenBase`
- `Superclass: "Instance"`. `Tags: ["NotCreatable", "NotBrowsable"]` (abstrata, nunca instanciável — coerente com a doc: só existe como base de `Tween`).
- Cadeia: `TweenBase → Instance → Object → <<<ROOT>>>`.
- 5 `Members`:

| Nome | Tipo | Security | Tags | Capabilities | Detalhe |
|---|---|---|---|---|---|
| `PlaybackState` | Property, `ValueType: Enum<PlaybackState>` | `{Read:"None", Write:"None"}` | `["ReadOnly","NotReplicated"]` | (ausente) | `Default: "__api_dump_class_not_creatable__"` (sentinela — classe abstrata) |
| `Cancel` | Function, sem parâmetros | `"None"` | (ausente) | (ausente) | retorno `null` |
| `Pause` | Function, sem parâmetros | `"None"` | (ausente) | (ausente) | retorno `null` |
| `Play` | Function, sem parâmetros | `"None"` | (ausente) | (ausente) | retorno `null` |
| `Completed` | Event, `playbackState: Enum<PlaybackState>` | `"None"` | (ausente) | (ausente) | — |

### `Tween`
- `Superclass: "TweenBase"`. `Tags`: ausente (classe concreta).
- Cadeia: `Tween → TweenBase → Instance → Object → <<<ROOT>>>`.
- 2 `Members`, ambos `Property`, `Security: {Read:"None", Write:"None"}`, `Tags: ["ReadOnly","NotReplicated"]`, `Capabilities: {Read:["Basic"]}`:

| Nome | ValueType | `Default` (string bruta do dump) |
|---|---|---|
| `Instance` | `Class<Instance>` | `"__api_dump_no_string_value__"` (sentinela — propriedade tipo Instance nunca tem default serializável) |
| `TweenInfo` | `DataType<TweenInfo>` | `"Time:1 DelayTime:0 RepeatCount:0 Reverses:False EasingDirection:Out EasingStyle:Quad"` |

O `Default` de `Tween.TweenInfo` é uma prova direta, no próprio dump, dos defaults oficiais de `TweenInfo` — bate 1:1 com a doc oficial (seção B).

### Filtro do projeto — nenhum membro é excluído

Apliquei `classifySchemaMember`/`classifyMethodMember` (código real de `tools/generate-services.luau`) aos 10 membros das 3 classes:

- `TweenService.Create/GetValue/SmoothDamp`: `Security: "None"`, sem `NotScriptable`/`WriteOnly`, `Capabilities: ["Basic"]` → `Basic` está em `grantable` (`tools/capabilities.lock.json`) → **incluído** nos 3.
- `TweenBase.PlaybackState`: `Security.Read == "None"`, sem `NotScriptable`, tag `ReadOnly` → **incluído, ReadOnly = true**.
- `TweenBase.Cancel/Pause/Play`: `Security: "None"`, sem `Capabilities` → **incluídos**.
- `TweenBase.Completed`: `Security: "None"`, `MemberType: "Event"` → **incluído, ReadOnly = true** (passo 6 do classificador).
- `Tween.Instance`/`Tween.TweenInfo`: `Security.Read == "None"`, tag `ReadOnly`, `Capabilities.Read: ["Basic"]` (`Basic` é `grantable`, não `reserved`) → **incluídos, ReadOnly = true**.

**Nenhum dos 10 membros cai em `reserved` (`InternalTest`/`PluginOrOpenCloud`/`RemoteCommand`) nem tem `Security` elevado nem `NotScriptable`/`WriteOnly`.** `TweenService`/`TweenBase`/`Tween` entram no schema **inteiros**, sem exclusão — resultado do código real do gerador, não de suposição.

---

## B) `TweenInfo`

**Fato do dump:** `TweenInfo` **não existe** como `Class` nem como `Enum` no `Full-API-Dump.json` (top-level só tem `Classes`, `Enums`, `Version` — confirmado varrendo as chaves). Ele só aparece **2 vezes** no dump inteiro, sempre como `{"Category": "DataType", "Name": "TweenInfo"}` — um tipo referenciado (parâmetro de `TweenService:Create`, tipo de `Tween.TweenInfo`), nunca definido. Isso é o padrão normal do dump para todo `DataType` (`Vector3`, `CFrame`, `Color3`, etc. também não têm sua própria estrutura de campos no dump) — **não é lacuna deste dump em particular**, é a fonte errada para essa pergunta. Confirmação via fonte oficial abaixo.

**Fonte oficial:** `create.roblox.com/docs/reference/engine/datatypes/TweenInfo` (conferida nesta sessão via fetch).

| Campo | Tipo | Default oficial |
|---|---|---|
| `Time` | `number` | `1` |
| `EasingStyle` | `Enum.EasingStyle` | `Enum.EasingStyle.Quad` |
| `EasingDirection` | `Enum.EasingDirection` | `Enum.EasingDirection.Out` |
| `RepeatCount` | `number` | `0` |
| `Reverses` | `boolean` | `false` |
| `DelayTime` | `number` | `0` |

**Ordem dos parâmetros de `TweenInfo.new`** (citação da doc oficial):
```
TweenInfo.new(time: number, easingStyle: Enum.EasingStyle, easingDirection: Enum.EasingDirection, repeatCount: number, reverses: boolean, delayTime: number)
```
Todos os 6 parâmetros são opcionais, cada um com o default da tabela acima, **nessa ordem exata**.

**Cruzamento com o dump (seção A):** `Tween.TweenInfo.Default = "Time:1 DelayTime:0 RepeatCount:0 Reverses:False EasingDirection:Out EasingStyle:Quad"` — os 6 valores batem exatamente com a tabela acima (a ordem alfabética da string é só como o dump serializa o struct, não a ordem do construtor — a ordem do construtor é a da doc).

---

## C) Enums (valores exatos do dump fixado `28360dea`)

**`Enum.EasingStyle`** (11 itens):
`Linear=0, Sine=1, Back=2, Quad=3, Quart=4, Quint=5, Bounce=6, Elastic=7, Exponential=8, Circular=9, Cubic=10`

**`Enum.EasingDirection`** (3 itens):
`In=0, Out=1, InOut=2`

**`Enum.PlaybackState`** (6 itens):
`Begin=0, Delayed=1, Playing=2, Paused=3, Completed=4, Cancelled=5`

Nenhum item tem `Tags` (nenhum `Deprecated`).

---

## D) Semântica real, com fonte

### D1 — `Create()`: propriedade inexistente / tipo errado / read-only

**Confirmado por citações reais (DevForum), 3 famílias de erro, todas com prefixo `TweenService:Create` — ou seja, a própria mensagem indica que a validação acontece DENTRO de `Create()`, não em `Play()`:**

1. Propriedade que não existe na instância:
   > `TweenService:Create no property named 'Position' for object 'UI'`
   (fonte: devforum.roblox.com/t/tweenservicecreate-no-property-named-position-for-object-ui/2764614)
2. Tipo do valor não bate com o tipo real da propriedade:
   > `TweenService:Create property named 'Size' cannot be tweened due to type mismatch (property is a 'Vector3', but given type is 'double')`
   > `TweenService:Create property named 'Material' cannot be tweened due to type mismatch (property is a 'int', but given type is 'token')`
   (fontes: devforum.roblox.com/t/tweenservicecreate-property-named-size/1620835 e .../tweenservicecreate-property-named-material.../3163468)
3. Propriedade de tipo que NUNCA é tweenável (ex.: `NumberSequence`, `ColorSequence`), independente do valor dado:
   > `TweenService:Create property named 'Transparency' on object 'Beam' is not a data type that can be tweened`
   (fonte: devforum.roblox.com/t/tweenservicecreate-property-named-transparency-on-object-beam-is-not-a-data-type-that-can-be-tweened/148063 — thread confirma explicitamente: "The error triggers at :Create() time")

**Read-only:** **NÃO CONFIRMADO.** Busquei especificamente por uma citação viva de erro para propriedade read-only e não achei nenhuma. É razoável supor (por analogia com as 3 famílias acima, todas prefixadas `TweenService:Create`) que também erra em `Create()`, mas não tenho o texto exato — não invente essa string no código, trate como "erro genérico não confirmado" se o comportamento for implementado.

**Conclusão prática:** todas as validações de `propertyTable` (existência, tipo, "é tweenável") acontecem em `Create()`, de forma síncrona — nunca em `Play()`. Isso é confirmado pelo próprio texto do erro (prefixo `TweenService:Create`), não só por inferência de fórum.

### D2 — Tipos tweenáveis: lista fechada, oficial

**Fonte primária:** `raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/TweenService.yaml` (campo `description`, citação verbatim):

> "`Tweens` can be used on any object with compatible property types, including: number, boolean, `CFrame`, `Rect`, `Color3`, `UDim`, `UDim2`, `Vector2`, `Vector2int16`, `Vector3`, `EnumItem`."

Lista **fechada** — 11 tipos. `string`, `Instance`, `NumberSequence`, `ColorSequence`, `BrickColor` **não estão na lista** → tentar tweenar propriedade desses tipos cai na família de erro D1.3 ("is not a data type that can be tweened") se a propriedade em si for desse tipo, ou D1.2 (type mismatch) se o VALOR dado for de um tipo incompatível com uma propriedade que É tweenável.

**Nota de cautela:** uma busca (WebSearch, não fonte primária) mencionou `Vector3int16` na lista — **não confirmei isso na doc oficial** (a citação verbatim do YAML acima não inclui `Vector3int16`). Fico com a lista da fonte oficial; marco `Vector3int16` como NÃO CONFIRMADO/possivelmente incorreto.

### D3 — `Play()`/`Pause()`/`Cancel()`

**Fontes:** `creator-docs` YAML de `TweenBase` (fetch nesta sessão) + DevForum "Has Tween:Cancel() behaviour been changed?" (thread confirma comportamento atual).

- **`Cancel()`**: para o tween e **reseta as variáveis internas de progresso** (tempo decorrido volta a 0). **NÃO reverte o valor da propriedade** — a propriedade fica congelada no valor que tinha no instante do cancelamento (confirmado por consenso de DevForum, citação: "if you cancel a tween halfway through its animation, the properties do not reset to their original values... it only resets the tween variables, not the properties").
- **`Play()` depois de `Cancel()`**: reinicia do zero (usa a duração cheia de novo, `PlaybackState` volta a `Begin`/`Delayed`/`Playing`), **não** retoma de onde parou. Diferença explícita documentada em relação a `Pause()`.
- **`Pause()`**: suspende a execução preservando o progresso atual; `Play()` depois de `Pause()` **retoma do ponto onde parou** (não reinicia).
- Chamar `Play()` num `Tween` cuja propriedade-alvo já está sendo tweenada por outro `Tween` **cancela o tween anterior** (doc oficial, `TweenService.yaml`: "If two tweens attempt to modify the same property, the initial tween will be cancelled and overwritten by the most recent tween").

### D4 — `Completed`: argumento e quando dispara

**Fonte:** dump (`Completed(playbackState: Enum<PlaybackState>)`) + doc oficial `TweenBase` + DevForum "TweenBase Completed event odd behavior" (citação de explicação da causa raiz de um bug reportado, não staff, mas consistente com o dump/doc).

- Dispara com **um argumento**: `playbackState: Enum.PlaybackState`.
- **Dispara em `Cancel()`** — com o argumento `Enum.PlaybackState.Cancelled` (confirmado: doc oficial de `TweenBase` diz que `Completed` "fires when the tween finishes, passing an Enum.PlaybackState value"; e a thread confirma na prática que cancelar um tween — inclusive por sobrescrita implícita ao criar outro tween na mesma propriedade — dispara `Completed` com `Cancelled`).
- **Dispara em conclusão normal** com `Enum.PlaybackState.Completed`.
- **NÃO dispara em `Pause()`** (doc oficial `TweenBase`, citação direta: "calling Pause() does not fire this event").

### D5 — `RepeatCount = -1` + `Reverses = true` — interação com `Completed`

- `RepeatCount < 0` → **loop infinito** (doc oficial e uso corrente confirmam; recomendação oficial para parar é chamar `:Cancel()`).
- **`Completed` NUNCA dispara** enquanto o tween está em loop infinito — só dispara se/quando `Cancel()` for chamado (aí dispara com `Cancelled`, nunca com `Completed`, já que a repetição infinita por definição nunca "termina naturalmente"). Confirmado por convergência de múltiplas threads DevForum + a semântica do enum (`Completed`/`Cancelled` são os dois únicos estados terminais possíveis de `PlaybackState`, e o infinito nunca alcança o primeiro).
- **Semântica de `RepeatCount` em geral** (não pedido explicitamente, mas necessário pra não implementar errado): `RepeatCount` é o número de repetições **depois** da primeira execução — `RepeatCount = 0` (default) toca uma vez; `RepeatCount = 1` toca DUAS vezes no total. Confirmado por `github.com/dphfox/Fusion/issues/172` (issue relatando exatamente esse off-by-one ao portar a semântica: "a RepeatCount of 1 or above... represents additional repetitions beyond the initial play"; duração total real = `Time * (RepeatCount + 1)` quando não-infinito). `Reverses = true` faz cada ciclo tocar ida+volta (não documentado com detalhe fino de timing na doc oficial consultada — o efeito visual é conhecido, mas a fórmula exata de duração por ciclo com `Reverses` não foi confirmada por citação numérica).

### D6 — Passo do frame / servidor

- **NÃO CONFIRMADO em detalhe de engine.** Não achei citação oficial ou de engenheiro Roblox especificando exatamente em que fase do frame (`Heartbeat`/`Stepped`/`RenderStepped`/interno) `TweenService` atualiza a propriedade, nem no client nem no servidor. As buscas só trazem discussão de terceiros sem fonte primária.
- **`TweenService` FUNCIONA no servidor** — sim, confirmado indiretamente: a comunidade só precisa de módulos como "TweenService V2" para RESOLVER o problema de a interpolação no servidor não ficar visualmente suave para os clientes (rede/replicação de propriedade, não porque o Tween "não roda"). Ou seja, `TweenService:Create` + `:Play()` num `Script` de servidor **executa e interpola de fato** a propriedade no servidor — a ressalva real é que a MUDANÇA DE PROPRIEDADE por frame é replicada aos clientes pelo mecanismo de replicação normal do Roblox (que não é por-frame para todo tipo de propriedade), então o resultado visual no cliente pode não ficar suave — isso é um problema de REDE, não de "TweenService não roda no servidor". Fonte: múltiplas threads DevForum e o próprio README de `Steadyon/TweenServiceV2` ("this... helps to efficiently replicate movement between server and client... running tweens clientside"), que só faz sentido como solução se o problema original for replicação, não execução.
- **Implicação para o LuauBench:** como o runtime não tem replicação real nem render, a divergência relevante a documentar no código é: (a) qual "tick" do scheduler do LuauBench vai avançar o alpha do tween (decisão do arquiteto, não tem uma resposta "correta" única do Roblox real para copiar, já que não é documentado publicamente); (b) sem cliente/servidor real, não há problema de replicação a simular — mas isso PRECISA ser documentado como divergência deliberada (regra 00), não herdado silenciosamente.

### D7 — `GetValue(alpha, easingStyle, easingDirection)` e fórmulas de easing

- **Retorno confirmado** (dump + doc oficial): `float`, alpha de entrada é **restringido/clampado entre 0 e 1** (doc oficial, citação: "input values constrained between 0 and 1").
- **Fórmulas exatas: NÃO é possível reproduzir numericamente com garantia de fidelidade total.** A fonte mais direta encontrada — um dev que fez uma reimplementação Luau pura de `TweenService` (`devforum.roblox.com/t/tweenserviceluau-pure-luau-tweenservice-reimplementation/3005452`) — declara **explicitamente**:
  > "None of the functions are 100% accurate to the original TweenService; most are accurate to two decimal places."
  E atribui a diferença em parte a `TweenService` usar precisão de ponto flutuante single (float) internamente enquanto Luau usa double.
- Formas conhecidas (não citação de engenheiro Roblox, é conhecimento padrão de easing — mesma família usada por quase toda reimplementação, incluindo a citada acima, que se baseia em Robert Penner's Easing Functions / easings.net): `Linear(t) = t`; `Quad Out(t) = 1-(1-t)^2` (bate com um resultado de busca: "Quad is y=2*x-x^2 for Out... x^2 for In", equivalente); as demais (`Sine`, `Back`, `Cubic`, `Quart`, `Quint`, `Bounce`, `Elastic`, `Exponential`, `Circular`) seguem as fórmulas-padrão de Penner/easings.net, mas **nenhuma fonte encontrada confirma que a implementação em C++ da Roblox usa exatamente essas constantes** (ex.: `Back` tem uma constante de overshoot arbitrária que varia entre bibliotecas).
- **Conclusão prática para o LuauBench:** implementar `GetValue` com as fórmulas-padrão de Penner é a melhor aproximação disponível hoje, mas **precisa ser documentado no código como aproximação, não fidelidade exata** (regra 00, "divergência é sempre declarada") — a própria comunidade que tentou reproduzir bateu o mesmo teto de precisão.

### D8 — Instância destruída (`Destroy()`) no meio do tween

- **NÃO derruba nem lança erro.** Confirmado por convergência de múltiplas threads DevForum ("Tween affects part after destroyed", "About tween destroy", "How do I stop an object tweening when it is destroyed?"): o `Tween` **continua rodando sem erro**, mesmo sem nada de visível para atualizar — não há exceção nem parada automática. A prática recomendada pela comunidade é `tween:Cancel()` explícito antes de `Destroy()`, ou tratar limpeza no handler de `Completed`. **Não achei confirmação oficial (doc/staff) desse comportamento** — é conclusão por convergência de múltiplos relatos de usuário, não citação de fonte primária Roblox; trato como "muito provável, não 100% oficial".

---

## Incerto (resumo)

- Mensagem exata de erro para propriedade **read-only** em `Create()` — não encontrada.
- Fase exata do frame (`Heartbeat`/interno) em que `TweenService` atualiza a propriedade, no cliente e no servidor — não documentado publicamente.
- Fórmulas matemáticas exatas (constantes internas) de cada `EasingStyle` — comunidade confirma que reproduções abertas chegam a ~2 casas decimais, não 100%.
- Timing exato de duração por ciclo quando `Reverses = true` combinado com `RepeatCount` finito (efeito qualitativo confirmado, fórmula numérica de duração não).
- Comportamento de `Destroy()` do alvo durante o tween — só convergência de relatos de usuário, sem citação de doc/staff oficial.
- `Vector3int16` como tipo tweenável — mencionado por uma busca secundária, **não confirmado** na doc oficial (`TweenService.yaml` não o lista).
