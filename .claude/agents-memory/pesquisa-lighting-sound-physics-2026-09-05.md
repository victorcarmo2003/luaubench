# Pesquisa — Lighting / SoundService / PhysicsService (grupo 4 de prioridade)

Data: 2026-09-05
Dump fixado: commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75` de `MaximumADHD/Roblox-Client-Tracker`, arquivo local `D:\UserData\Documents\GitHub\luaubench\.cache\api-dump\28360dea4b90b35dc3fe9f829baae64fb6c50e75.json` (também existe uma cópia `28360dea.json` idêntica em bytes — mesmo dump, nome curto).

Fontes usadas, por ordem de confiança:
1. `Full-API-Dump.json` fixado (fonte primária de superfície — Seção A e a maior parte da B).
2. `Roblox/creator-docs` no GitHub (`content/en-us/reference/engine/classes/{Lighting,SoundService,PhysicsService,WorldRoot}.yaml` e `content/en-us/workspace/collisions.md`), branch `main`, lido em 2026-09-05 — é o texto-fonte por trás de `create.roblox.com/docs`, mais completo que a página renderizada.
3. DevForum (comunidade + 1 anúncio oficial de staff Roblox) — marcado explicitamente como tal, nunca tratado como fonte primária de comportamento.

**Bug no script de extração corrigido durante a pesquisa:** `Capabilities` no dump tem formato diferente por tipo de membro — `Property` usa `{Read: [...], Write: [...]}`, mas `Function`/`Event`/`Callback` usa array plano (`["Audio","InternalTest"]`). Um filtro que trata só o formato de objeto deixa passar membros com `InternalTest` (ex.: `SoundService:SetInputDevice` quase escapou do filtro). Vale avisar `coder-services` se o gerador for reaproveitar lógica de filtro parecida.

---

## A) Superfície do dump

### Lighting
`Superclass: Instance` · `Tags: ["NotCreatable", "Service"]` · 30 membros no dump.

Sobrevivem ao filtro (Security.Read == None, sem `NotScriptable`, sem `InternalTest`/`PluginOrOpenCloud`/`RemoteCommand` em Capabilities): **28** — 20 Property, 7 Function, 1 Event.

**Property (20):** `Ambient`, `Brightness`, `ClockTime` (tag `NotReplicated`), `ColorShift_Bottom`, `ColorShift_Top`, `EnvironmentDiffuseScale`, `EnvironmentSpecularScale`, `ExposureCompensation`, `FogColor`, `FogEnd`, `FogStart`, `GeographicLatitude`, `GlobalShadows`, `LightingStyle` (Write=`RobloxScriptSecurity` — legível por script comum, **não gravável**), `OutdoorAmbient`, `Outlines` (tag `Deprecated`), `PrioritizeLightingQuality` (Write=`RobloxScriptSecurity`, mesma situação de `LightingStyle`), `ShadowColor` (tags `NotReplicated`+`Deprecated`), `ShadowSoftness`, `TimeOfDay`.

**Function (7):** `GetMinutesAfterMidnight`, `GetMoonDirection`, `GetMoonPhase`, `GetSunDirection`, `SetMinutesAfterMidnight`, `getMinutesAfterMidnight` (alias minúsculo, tag `Deprecated`, aponta para o correto via `PreferredDescriptorName`), `setMinutesAfterMidnight` (idem).

**Event (1):** `LightingChanged(skyChanged: bool)`.

Rejeitados (2): `ExtendLightRangeTo120` (Property, `NotScriptable`), `Technology` (Property, `Security.Read = RobloxScriptSecurity`).

### SoundService
`Superclass: Instance` · `Tags: ["NotCreatable", "Service"]` · 48 membros no dump.

Sobrevivem: **17** — 13 Property, 4 Function, 0 Event.

**Property (13):** `AcousticSimulationEnabled`, `AmbientReverb`, `CharacterSoundsUseNewApi` (Write=`PluginSecurity` — só Studio/plugin escreve, script lê), `DiffractionEnabled`, `DistanceFactor`, `DopplerScale`, `ListenerCFrame`, `ListenerObject`, `ListenerType`, `OcclusionEnabled`, `RespectFilteringEnabled`, `ReverbEnabled`, `RolloffScale`.

**Function (4):** `GetListener`, `GetMixerTime`, `PlayLocalSound`, `SetListener`. (`SetInputDevice` foi excluído corretamente — `Capabilities` inclui `InternalTest`.)

**Event: nenhum sobrevive** — `AudioInstanceAdded`, `DeviceListChanged`, etc. são todos `RobloxScriptSecurity`/`RobloxSecurity`.

Rejeitados (31): majoritariamente `RobloxScriptSecurity` (device enumeration, recording, `InsertAsset`, `SetSoundEnabled` etc.), `VolumetricAudio` (`NotScriptable`), `DefaultListenerLocation` (`PluginSecurity` no Read), `SetInputDevice` (`InternalTest`).

### PhysicsService
`Superclass: Instance` · `Tags: ["NotCreatable", "Service"]` · 18 membros no dump.

Sobrevivem: **15** — 0 Property, 15 Function, 0 Event.

**Function (15):** `CollisionGroupContainsPart` (tag `Deprecated`), `CollisionGroupSetCollidable`, `CollisionGroupsAreCollidable`, `CreateCollisionGroup` (tag `Deprecated`), `GetCollisionGroupId` (tag `Deprecated`), `GetCollisionGroupName` (tag `Deprecated`), `GetCollisionGroups` (tag `Deprecated`), `GetMaxCollisionGroups`, `GetRegisteredCollisionGroups`, `IsCollisionGroupRegistered`, `RegisterCollisionGroup`, `RemoveCollisionGroup` (tag `Deprecated`), `RenameCollisionGroup`, `SetPartCollisionGroup` (tag `Deprecated`), `UnregisterCollisionGroup`.

Rejeitados (3): `IkSolve`/`LocalIkSolve` (`RobloxScriptSecurity`/`LocalUserSecurity`), `CollisionGroupCollidableChanged` (Event, `RobloxSecurity`).

**Nenhum Property sobrevive em PhysicsService** — a classe não tem propriedade scriptável nenhuma, só métodos.

Importante: apenas os 6 métodos marcados `Deprecated` acima carregam a tag formal no dump. Os outros 9 (`RegisterCollisionGroup`, `UnregisterCollisionGroup`, `CollisionGroupSetCollidable`, `CollisionGroupsAreCollidable`, `RenameCollisionGroup`, `IsCollisionGroupRegistered`, `GetRegisteredCollisionGroups`, `GetMaxCollisionGroups`) **não têm `Tags: ["Deprecated"]`** mas o texto de documentação (`deprecation_message` no YAML da creator-docs) diz "superseded by `Class.WorldRoot:<Método>()` which should be used for all new work" — ver seção B7 abaixo, é o achado mais importante desta pesquisa.

---

## B) Comportamento acoplado

### B1 — ClockTime / TimeOfDay / Get·SetMinutesAfterMidnight: mesma view, confirmado oficialmente

Fonte: `Lighting.yaml` (creator-docs), campos `description` de `Lighting.ClockTime`, `Lighting.TimeOfDay` e `Lighting:SetMinutesAfterMidnight`.

- **São três vistas do mesmo estado.** Citação direta do doc de `ClockTime`: *"Changing `TimeOfDay` or using `SetMinutesAfterMidnight()` will also change this property."* E de `TimeOfDay`: *"Changing `ClockTime` or using `SetMinutesAfterMidnight()` will also change this property."*
- Escrever `ClockTime = 14.5` **muda `TimeOfDay`** (e vice-versa).
- Formato de leitura do dump: default é `"14:00:00"` (string, `HH:MM:SS`, dois dígitos). Exemplo oficial de **escrita** aceita formato mais curto: `Lighting.TimeOfDay = "11:00"` e `"21:30"` (sem segundos) — ou seja, entrada aceita `H:MM`/`HH:MM`/`HH:MM:SS`, mas não confirmei se a leitura de volta sempre normaliza para `HH:MM:SS` com zero-padding em horas de um dígito (ex.: escrever `"9:00"` e ler de volta — **não confirmado** se retorna `"09:00:00"` ou `"9:00:00"`).
- `GetMinutesAfterMidnight()`: retorna minutos desde meia-noite, description diz *"nearly identical to `ClockTime` multiplied by 60"* — ou seja, não é garantida igualdade exata (arredondamento interno), e o valor retornado é sempre o minuto-do-dia atual (não necessariamente igual ao último valor passado para `SetMinutesAfterMidnight`, que aceita >1440 min).
- `SetMinutesAfterMidnight(minutes)`: doc confirma explicitamente **wrap** — *"It also allows values greater than 24 hours that correspond to times in the next day."* Não documenta o que ocorre com `minutes` negativo — **não confirmado** (inferência razoável: também wrap via módulo, mas sem fonte).
- Valores fora de alcance escritos diretamente em `ClockTime`/`TimeOfDay` (fora de `SetMinutesAfterMidnight`): comportamento de wrap não é confirmado explicitamente pela doc atual para esse caminho de entrada — só é confirmado para `SetMinutesAfterMidnight`. Inferência (não fonte primária): como as três são a mesma variável de estado, plausível que sigam a mesma regra, mas não achei o texto confirmando para escrita direta de `ClockTime`.
- **Achado de bug antigo (comunidade, DevForum 2017, thread [TimeOfDay modified with high values can cause unclear error](https://devforum.roblox.com/t/timeofday-modified-with-high-values-can-cause-unclear-error/57674)):** escrever `TimeOfDay = "0:0:65536"` (componente ≥ 65536, aparentemente limite de `unsigned short`) lança erro `"bad lexical cast: source type value could not be interpreted as target"` em vez de wrap/clamp. **Não confirmado se ainda reproduz na engine atual** — reporte tem quase 9 anos.

### B2 — LightingChanged

Fonte: `Lighting.yaml`, description completa do evento.

- Dispara quando **uma propriedade de `Lighting` muda OU um `Sky` é adicionado/removido** de `Lighting`.
- Argumento: `skyChanged: boolean` — citação: *"`true` when a `Sky` is added or removed, or when a Sky property other than `SkyboxOrientation` changes. `false` for Lighting property changes, Atmosphere property changes, and SkyboxOrientation changes."*
- **NÃO dispara para todas as propriedades.** Exceções documentadas explicitamente: `GlobalShadows` **não** dispara o evento; `FogColor`, `FogStart`, `FogEnd` **não** disparam o evento. Para esses casos a doc recomenda `Object.Changed`/`GetPropertyChangedSignal` em vez de `LightingChanged`.
- Isso é uma pegadinha real para uma simulação ingênua: se o LuauBench disparar `LightingChanged` para toda propriedade indiscriminadamente, diverge do Roblox real em pelo menos 4 propriedades conhecidas (`GlobalShadows`, `FogColor`, `FogStart`, `FogEnd`).

### B3 — GetSunDirection / GetMoonDirection: fórmula não é pública

- Doc oficial descreve só o contrato (`Vector3` a partir de `(0,0,0)`, continua apontando abaixo do horizonte após "pôr") — **nenhuma fórmula publicada** envolvendo `GeographicLatitude`/`ClockTime`.
- `GetMoonPhase()`: doc confirma que **sempre retorna `0.75`** — não há forma de mudar a fase da lua, método já vem com nota de "não deveria ser usado" apesar de não ter tag `Deprecated` no dump.
- Recomendação para o arquiteto: como não há fórmula pública, a via correta pelas regras do projeto é um stub simplificado e documentado (ex.: aproximação senoidal com `ClockTime`, ou retorno de um vetor fixo/direção "acima"), nunca fingir exatidão. `GetMoonPhase` pode ser um caso trivial: sempre `0.75`, comportamento 100% fiel e documentado.

### B4 — PlayLocalSound: client-only

- Doc oficial (`SoundService.yaml`) **não afirma explicitamente** que lança erro no servidor — só descreve o efeito ("heard only by the client calling this method").
- Comunidade (múltiplas threads DevForum) relata consistentemente que chamar no servidor lança algo como **`"SoundService:PlayLocalSound only works on a client."`** — não encontrei a string exata verbatim citada em uma fonte primária (só paráfrases em threads), então trato a string como **aproximada, não 100% confirmada caractere-a-caractere**. O comportamento em si (erro em contexto de servidor) tem consenso forte da comunidade.
- Nenhuma tag no dump indica isso (Security = `None` para servidor e cliente igualmente) — é uma restrição de `RunContext` que o dump não modela, então **não dá pra derivar isso só do dump**; é conhecimento de comportamento teria que vir de doc/comunidade/teste real.

### B5 — SetListener / GetListener

Fonte: `SoundService.yaml`.

- `SetListener(listenerType: Enum.ListenerType, listener: Tuple)`: segundo argumento depende do primeiro — `BasePart` para `ObjectPosition`/`ObjectCFrame`, `CFrame` para `ListenerType.CFrame`, `nil` para `ListenerType.Camera`.
- `GetListener()` retorna tupla `(listenerType, listenerValue)` — para `Camera` o segundo valor não é retornado (só o tipo); para `CFrame`/`ObjectPosition`/`ObjectCFrame` retorna o valor setado.
- **Padrão de fábrica confirmado: `ListenerType.Camera`**, ou seja, ouvinte é `Workspace.CurrentCamera` até alguém chamar `SetListener`.

### B6 — Write-protection em runtime

- **Não encontrei nenhuma das cinco propriedades (`RespectFilteringEnabled`, `AmbientReverb`, `DistanceFactor`, `DopplerScale`, `RolloffScale`) com `Security.Write` diferente de `None` no dump** — todas com `{"Read":"None","Write":"None"}`, ou seja, **sem restrição formal de escrita em runtime**, ao contrário do padrão real que existe em outras propriedades do Roblox (ex.: `LightingStyle`/`PrioritizeLightingQuality` em `Lighting`, que têm `Write: RobloxScriptSecurity` — essas sim são só-leitura para script comum).
- **Discrepância encontrada entre dump e doc para `RespectFilteringEnabled`:** o dump lista `Default: "false"`, mas a doc oficial (`SoundService.yaml`) diz *"Default is `true`, meaning filtering is enabled."* Não resolvi essa contradição — **sinalizo para decisão do arquiteto/usuário** qual valor usar como default simulado (a doc textual tende a refletir o comportamento real de runtime pretendido; o campo `Default` do dump às vezes reflete o valor "cru" do engine antes de qualquer inicialização de place). Recomendo tratar como **não confirmado** até testar em Studio real ou perguntar ao usuário, e documentar a escolha explicitamente no código.
- `CharacterSoundsUseNewApi` tem `Write: PluginSecurity` — só Studio/plugin escreve; script comum só lê.

### B7 — PhysicsService: achado principal — API duplicada e "superseded" por `WorldRoot`

Este é o ponto mais importante da pesquisa e vai além do que foi pedido literalmente (só `PhysicsService`), mas afeta diretamente a modelagem.

- **Confirmado no dump:** a classe `WorldRoot` (superclasse de `Workspace`, `Tags: ["NotCreatable"]`) tem sua **própria cópia scriptável** dos mesmos métodos: `RegisterCollisionGroup`, `UnregisterCollisionGroup`, `CollisionGroupSetCollidable`, `CollisionGroupsAreCollidable`, `GetRegisteredCollisionGroups`, `GetMaxCollisionGroups`, `IsCollisionGroupRegistered`, `RenameCollisionGroup` (`Security: None`, mesmas assinaturas) — mais uma property `CollisionGroupData` (Hidden/NotScriptable/RobloxSecurity, estado interno) e um evento `CollisionGroupCollidableChanged` (Hidden/RobloxSecurity, não scriptável).
- **Confirmado via creator-docs (`PhysicsService.yaml`):** todos os métodos de `PhysicsService` relacionados a collision group (exceto os já com tag `Deprecated` formal) têm `deprecation_message` dizendo, palavra por palavra: *"This method has been superseded by `Class.WorldRoot:<Método>()` which should be used for all new work."* — isso vale para `RegisterCollisionGroup`, `UnregisterCollisionGroup`, `CollisionGroupSetCollidable`, `CollisionGroupsAreCollidable`, `RenameCollisionGroup`, `IsCollisionGroupRegistered`. Ou seja: **não tem `Tags: ["Deprecated"]` no dump, mas a documentação já trata como sucedido/legado.**
- **Confirmado via `WorldRoot.yaml`:** a descrição de `WorldRoot:RegisterCollisionGroup` diz literalmente *"Registers a new collision group **in this world** with the given name"* — ou seja, o registro é **escopado por instância de `WorldRoot`** (cada `Workspace`/`WorldModel` tem seu próprio registro), não mais um registro único global como o modelo mental de `PhysicsService` sugere.
- **Confirmado no dump (evidência independente, não é só o resumo do DevForum):** existe `WorldModel.UseWorkspaceCollisionGroups` (`Property`, `bool`, `Default: "false"`, `Security: None/None`) — uma flag de opt-in para um `WorldModel` herdar os grupos de colisão do `Workspace` em vez de manter registro próprio. Isso corrobora de forma independente (via dump, não só prosa) que o modelo é per-`WorldRoot`.
- **DevForum (anúncio oficial de staff Roblox, não fonte primária de dump — tratar como comunidade/anúncio, li o conteúdo resumido, não o texto bruto verbatim):** thread "[Expanding WorldModel Simulation Capabilities: Support for Collision Groups](https://devforum.roblox.com/t/expanding-worldmodel-simulation-capabilities-support-for-collision-groups/4848541)" (muito recente, ~3 dias antes desta pesquisa) diz que chamadas existentes a `PhysicsService` **"automatically forward to `Workspace`"** para manter compatibilidade retroativa, e que `PhysicsService` "is now deprecated" em favor de `WorldRoot`. **Recomendo tratar a parte "automatically forward to Workspace" como plausível e consistente com o resto (dá pra inferir isso do texto do próprio creator-docs), mas não recomendo citar a frase exata como 100% verbatim** — veio de um resumo de fetch, não da leitura do HTML bruto da thread.
- **Implicação de arquitetura (para o `arquiteto` decidir, não decisão minha):** se o LuauBench quiser fidelidade real, o estado "grupos de colisão registrados" deveria morar no `WorldRoot` (ou seja, em `Workspace`, e potencialmente em qualquer `WorldModel` simulado), com `PhysicsService:RegisterCollisionGroup` implementado como um alias fino que delega para o `Workspace` do `DataModel` — não como um registro global independente dentro do módulo `PhysicsService`. Uma simulação ingênua que colocasse o registro só dentro de `PhysicsService` divergiria do comportamento real assim que o usuário testasse com múltiplos `WorldModel`s (streaming/paralelo) ou lesse `Workspace:GetRegisteredCollisionGroups()` depois de chamar `PhysicsService:RegisterCollisionGroup()`.

### Semântica dos métodos de PhysicsService (confirmada via `PhysicsService.yaml`)

- `GetMaxCollisionGroups()` → **32**, citação direta: *"This value is currently 32."*
- **Grupo `"Default"` pré-registrado:** confirmado via `collisions.md` — *"The editor includes one Default collision group which cannot be renamed or deleted. All BaseParts automatically belong to this default group unless assigned to another group."*
- **Registrar nome duplicado:** **não documentado** em nenhuma das fontes checadas (nem `PhysicsService.yaml` nem `collisions.md` nem `WorldRoot.yaml` mencionam esse caso). Marco como **não confirmado** — decisão de comportamento (erro silencioso, no-op, ou lançar erro) fica para o arquiteto decidir e documentar como extensão/interpretação do LuauBench, já que a fonte oficial não cobre.
- **Nome reservado `"Default"`:** `RegisterCollisionGroup` — doc diz só *"The name cannot be `Default`"* (não especifica se lança erro ou é no-op; a redação sugere restrição ativa, provável erro, mas não citou "throw" explicitamente para este método como fez para outros). `UnregisterCollisionGroup`/`RemoveCollisionGroup`: **lança erro** explicitamente se nome for `"Default"` ou se chamado do cliente. `RenameCollisionGroup`: lança erro runtime se nome inválido/vazio em qualquer um dos dois argumentos, ou se chamado do cliente.
- **Nome inválido (vazio, etc.):** `UnregisterCollisionGroup`/`RemoveCollisionGroup` — *"If an invalid name is provided, this method will not do anything"* (no-op silencioso, não erro). `RenameCollisionGroup` — nome inválido/vazio **lança erro** (comportamento oposto ao de Unregister!). `RegisterCollisionGroup` — não documentado além da restrição de `"Default"`.
- **Consultar grupo inexistente:** `CollisionGroupsAreCollidable(a, b)` com grupo(s) não registrado(s) → **retorna `true`** (não erro) — citação: *"the default collision mask collides with all groups."* `CollisionGroupSetCollidable(a, b, ...)` com grupo não registrado → **lança erro** (comportamento diferente do "Are" — "Set" erra, "Are" retorna true). `IsCollisionGroupRegistered(name)` → `false` para não registrado, nunca erro (é a função recomendada pela doc para checar antes de chamar as que erram).
- **Replicação servidor→cliente:** não encontrei confirmação explícita de que o registro de grupos replica automaticamente do servidor para clientes via essas APIs — o que está confirmado é que `UnregisterCollisionGroup`/`RemoveCollisionGroup`/`RenameCollisionGroup` **lançam erro se chamados do cliente** (ou seja, são efetivamente só-servidor / `RegisterCollisionGroup` não tem essa nota explícita de restrição de lado, mas por analogia com as demais operações de escrita do mesmo grupo de API, é razoável assumir server-only também — **não 100% confirmado para `RegisterCollisionGroup` e `CollisionGroupSetCollidable` especificamente**, só para Unregister/Remove/Rename). Leitura (`GetRegisteredCollisionGroups`, `IsCollisionGroupRegistered`, `CollisionGroupsAreCollidable`, `GetMaxCollisionGroups`) não tem nenhuma restrição de lado documentada — presumivelmente utilizável em ambos.
- **Colidibilidade padrão entre dois grupos recém-criados:** **colidem por padrão** — confirmado via `collisions.md`: *"Under default configuration, objects in all groups collide with each other."*

### B8 — PhysicsService: métodos só-servidor?

Ver B7 acima: confirmado explicitamente para `UnregisterCollisionGroup`/`RemoveCollisionGroup` (erro no cliente) e `RenameCollisionGroup` (erro no cliente). **Não confirmado** para `RegisterCollisionGroup`, `CollisionGroupSetCollidable`, `SetPartCollisionGroup` — a doc não menciona restrição de lado para esses três, apesar de serem operações de escrita semelhantes. Tratar como incerto e não assumir simetria.

### B9 — Colidibilidade padrão

Respondido em B7: **sim, colidem por padrão** (config padrão = todos os grupos colidem entre si).

---

## C) O que um script de lógica pura realmente tocaria

Sinal usado: descrição das APIs + contagem aproximada de uso real via `gh api search/code` (proxy fraco, mas direcional) em 2026-09-05:

| Busca | Resultados (proxy) |
|---|---|
| `PhysicsService:RegisterCollisionGroup language:Lua` | 212 |
| `SoundService:PlayLocalSound language:Lua` | 135 |
| `Lighting.ClockTime language:Lua` | 2144 (mas maioria é script de day/night **visual**, não lógica pura) |
| `SetMinutesAfterMidnight language:Lua` | 150 |

**Prioridade sugerida para o `arquiteto`:**

1. **`PhysicsService` (`RegisterCollisionGroup`/`UnregisterCollisionGroup`/`CollisionGroupSetCollidable`/`CollisionGroupsAreCollidable`/`IsCollisionGroupRegistered`/`GetRegisteredCollisionGroups`/`GetMaxCollisionGroups`) é a que mais vale a pena simular com comportamento real.** É comum em bootstrap de servidor de projetos reais (registrar grupos "Players"/"Projectiles"/"Enemies" uma vez no `ServerScriptService`, checar `IsCollisionGroupRegistered` antes de registrar de novo em hot-reload) — é lógica de inicialização de gameplay, não depende de render/física real para fazer sentido testar fora do Studio. `RenameCollisionGroup`/`CollisionGroupContainsPart`(deprecated)/`SetPartCollisionGroup` são bem menos comuns em scripts de lógica pura (mexem com `BasePart`, que não existe de verdade sem física real).
2. **`Lighting.ClockTime`/`TimeOfDay`/`Get·SetMinutesAfterMidnight`** — usados quando um projeto guarda/sincroniza um ciclo dia/noite como parte do estado do mundo (às vezes até persistido via DataStore junto com o resto do save), então há caso de uso de "lógica pura" real, mas é minoritário frente ao uso puramente visual. Vale simular a coerência ClockTime/TimeOfDay/Minutes (B1) porque é barato e evita um bug de fidelidade óbvio; o resto das properties de `Lighting` (Ambient, Brightness, Fog*, ColorShift_*, EnvironmentDiffuse/SpecularScale, ShadowSoftness, GlobalShadows, Outlines) é dado morto do ponto de vista de um data manager — só precisa existir, ler/escrever e (seletivamente, ver B2) disparar `LightingChanged`.
3. **`SoundService` é a menos relevante para lógica pura.** `PlayLocalSound`/`SetListener`/`GetListener` são 100% sobre reprodução de áudio real — um data manager/ProfileStore nunca chama isso. Justifica ser stub-que-erra (`PlayLocalSound` no "servidor simulado" lançando o erro documentado pela comunidade) e as properties (`AmbientReverb`, `DistanceFactor`, `DopplerScale`, `RolloffScale`, `RespectFilteringEnabled`, etc.) como dado morto simples, sem comportamento acoplado — não há evento (`SoundService` não sobrevive nenhum Event ao filtro) e não há necessidade de coerência entre propriedades como existe em `Lighting`.

---

## Lista de "NÃO CONFIRMADO" (resumo para referência rápida)

- Formato exato de zero-padding de `TimeOfDay` para horas de um dígito ao ler de volta após escrita curta (`"9:00"` → `"09:00:00"` ou `"9:00:00"`?).
- Comportamento de wrap/clamp/erro ao escrever `ClockTime`/`TimeOfDay` diretamente com valor fora de alcance (só confirmado para `SetMinutesAfterMidnight`, e só para valores positivos >24h).
- Se o bug de `"bad lexical cast"` para componentes ≥65536 em `TimeOfDay` ainda reproduz na engine atual (fonte de 2017).
- String de erro exata (verbatim) de `PlayLocalSound` chamado no servidor — comportamento confirmado pela comunidade, string é paráfrase.
- Motivo da discrepância `RespectFilteringEnabled` default `false` (dump) vs `true` (doc) — precisa decisão explícita de qual usar.
- Se registrar um nome de collision group duplicado gera erro, no-op, ou substitui — não documentado em nenhuma fonte checada.
- Se `RegisterCollisionGroup`, `CollisionGroupSetCollidable` e `SetPartCollisionGroup` são também restritos a servidor (só confirmado para Unregister/Remove/Rename).
- Redação exata ("automatically forward to Workspace") do anúncio de DevForum sobre `PhysicsService` sendo encaminhado para `Workspace` — vem de resumo de fetch, não do HTML bruto da thread.
