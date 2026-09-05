# Pesquisa: membro vs. filho, `Instance.new` inválido, `Hidden`, `Source`, `RenderStepped`

Tarefa: `task-services-006`. Pendências abertas por `arquiteto-services-2026-09-05.md`, seção "Pendências para o pesquisador". Fonte primária: `Full-API-Dump.json` do commit fixado `28360dea4b90b35dc3fe9f829baae64fb6c50e75` (baixado nesta sessão, 8 006 149 bytes — bate com o tamanho já registrado no lock), `create.roblox.com/docs` (via GitHub `Roblox/creator-docs`, mais confiável que o site renderizado), e DevForum como pista/corroboração, nunca como única fonte.

**Resumo executivo (para quem só quer o veredito):**

| # | Pergunta | Veredito | Contradiz o desenho atual? |
|---|---|---|---|
| 1a | Membro vence filho em colisão? | **SIM, confirmado por fonte oficial.** | Não — confirma `task-runtime-021`. |
| 1b | Escrever num nome que é filho | Erra (mesma família "is not a valid member of"), por inferência forte, não citação direta. | Não. |
| 2 | Mensagem de `Instance.new` inválido/NotCreatable | Mesma família `Unable to create an Instance of type "X"` nos dois casos — alta confiança, não é um único teste lado-a-lado. | Não. |
| 3 | `Hidden` sem `NotScriptable` acessível por script? | **SIM, confirmado por 3 fontes independentes.** | Não — confirma a leitura do gerador. |
| 4a | `script.Source` num Script comum | **Erra com mensagem de CAPABILITY, não "is not a valid member of", nunca string vazia.** E o dump mostra `Security: None` + `Capabilities: PluginOrOpenCloud` — **não** `PluginSecurity` como o desenho assumiu. | **SIM — corrige uma premissa factual errada do desenho.** |
| 4b | `RunService.RenderStepped` no servidor real | **Erra ao conectar** em produção real (RCC); só não erra por causa de um **bug reconhecido do Studio** (ambiente de teste local). | **SIM — o desenho atual ("existe e nunca dispara") não é o comportamento do servidor real; é o comportamento do bug do Studio.** |

Achado extra não pedido, mas decorrente direto da pergunta 4a: **o filtro do gerador (Decisão 3) não olha o campo `Capabilities` do dump, só `Security` + tags — isso é uma lacuna real, não só para `Source`.** Ver seção própria no fim.

---

## 1. Ordem membro vs. filho em `__index`/`__newindex`

**Resposta curta:** confirmado por documentação oficial: propriedade/método/evento sempre vence filho em caso de colisão de nome via notação de ponto. Sem colisão, a notação de ponto resolve para o filho (uso básico e universal do ecossistema, mas sem uma frase oficial isolada dizendo isso — é o pressuposto de todo tutorial oficial). Escrita sobre nome de filho: erra, por inferência forte a partir do comportamento já confirmado para "escrever em não-membro" (pesquisa anterior), não por citação direta desse cenário específico.

**Fatos verificados**
- Fonte primária oficial, citação literal do campo `description` do membro `FindFirstChild` da classe `Instance`, arquivo `content/en-us/reference/engine/classes/Instance.yaml` do repositório `Roblox/creator-docs` (espelha `create.roblox.com/docs/reference/engine/classes/Instance`):
  > "Sometimes the `Name` of an object is the same as that of a property of its `Parent`. When using the dot operator, properties take precedence over children if they share a name."
  Acompanhado de um exemplo com um `Folder` chamado `"Color"` como filho de uma `Part` que também tem a propriedade `Part.Color`: `part.Color` devolve o valor `Color3` da propriedade, não o `Folder`.
- Confirma exatamente a hipótese de `task-runtime-021`/Decisão 4 do arquiteto: **"membro sempre vence filho"** — não é hipótese, é documentação oficial.
- A mesma seção documenta o motivo de `FindFirstChild` existir: é o caminho explícito para pegar o filho quando há colisão (`FindFirstChild` ~20% mais lento que o operador de ponto, ~8x mais lento que guardar referência direta — números citados na própria doc, não relevantes para o LuauBench mas confirmam que a citação é real e não paráfrase).
- Não há, na doc oficial, uma frase isolada dizendo "sem colisão, o ponto resolve para o filho" — mas isso é o pressuposto ativo de toda a documentação de tutorial oficial (`create.roblox.com/docs/tutorials/fundamentals/...`), que usa `workspace.Baseplate`, `script.Parent`, etc. como idioma básico sem ressalva, e é universalmente descrito assim por qualquer fonte de terceiros consultada (nenhuma divergência encontrada).

**Exemplo mínimo (Luau, comportamento real do Roblox)**
```lua
local part = Instance.new("Part")
local colorFolder = Instance.new("Folder")
colorFolder.Name = "Color"
colorFolder.Parent = part

print(part.Color)             --> Color3 (a PROPRIEDADE), nunca o Folder
print(part:FindFirstChild("Color"))  --> o Folder
```

**Limites e pegadinhas**
- Escrita: não encontrei um relato citando literalmente o resultado de `rs.Modules = 1` quando `Modules` é um filho e não é membro. A pesquisa anterior desta sessão (`pesquisa-instance-member-access-2026-09-04.md`) já confirmou, por convergência de múltiplos threads do DevForum ao longo de anos, que escrever num nome que **não é membro nenhum** (nem propriedade, nem método, nem evento) erra com a família `"<Nome> is not a valid member of <ClassName>"`. Como a atribuição de propriedade no Roblox real nunca consulta a lista de filhos (são estruturas internas completamente separadas — reflection em C++ para propriedades, lista de instâncias-filho para hierarquia), a inferência de que **escrever sobre um nome de filho cai na mesma família de erro, sem criar propriedade nem substituir o filho**, é forte, mas continua sendo inferência, não uma citação direta desse cenário exato.
- A ordem exata que `task-runtime-021`/Decisão 4 do arquiteto propõe (membro checado nos passos 5/6, filho só no passo 7, escrita nunca olha filho) está agora **confirmada como correta pela fonte primária**, não apenas plausível.

**Incerto**
- String exata do erro ao escrever num nome que é filho (assumido como sendo a mesma família "is not a valid member of" usada para leitura — nunca confirmado literalmente para este cenário específico).

---

## 2. String exata de `Instance.new` para classe inexistente vs. `NotCreatable`

**Resposta curta:** alta confiança de que é a **mesma mensagem** `Unable to create an Instance of type "X"` nos dois casos — por convergência de múltiplas causas de falha diferentes produzindo o mesmo formato, não por um teste único e autoritativo comparando os dois casos lado a lado.

**Fatos verificados**
- Citação literal de erro real, classe que **existe no motor mas foi bloqueada para criação direta** (não é um simples `NotCreatable` do dump, é uma mudança de API mais recente, mas o mecanismo de recusa é o mesmo: `Instance.new` recusa e usa este formato): `"Unable to create an Instance of type 'EditableMesh'"` e `"Unable to create an Instance of type 'EditableImage'"` — devforum.roblox.com/t/unable-to-create-an-instance-of-type-editablemesh/3275604, devforum.roblox.com/t/editable-instances-uncreatable/3227053 (ambos com citação de mensagem de erro real reportada por desenvolvedores).
- Citação literal de um **engine bug de 2015** em que uma classe **perfeitamente normal e sempre-criável** (`Folder`) também produziu a mesma frase: `"Unable to create instance of type 'Folder'"` — devforum.roblox.com/t/unable-to-create-instance-of-type-folder/13812. Isso é a evidência mais forte encontrada: mostra que o motor usa **um único formato de mensagem genérico**, disparado por um único ponto de código sempre que `Instance.new` falha em produzir uma instância, **independente da causa raiz** (classe não-criável, classe inexistente, falha interna).
- Não encontrei citação literal de erro para um nome de classe **totalmente inventado/typo** (ex.: `"Frmae"`) — é um cenário raro o bastante (ninguém erra e depois posta no fórum "olha que chato, deu esse erro" para um typo óbvio) para não ter registro direto, ao contrário do caso "não consigo criar classe conhecida mas bloqueada", que gera threads de suporte.

**Exemplo mínimo**
```lua
local ok, err = pcall(function() return Instance.new("Frmae") end) -- typo proposital
print(ok, err) -- esperado: false, "Unable to create an Instance of type \"Frmae\"" (não confirmado literalmente, ver Incerto)
```

**Limites e pegadinhas**
- A convergência (3 causas de falha diferentes → mesmo formato de mensagem) é evidência indireta forte, mas continua sendo inferência de padrão, não uma fonte que testou e comparou os dois casos da pergunta lado a lado e declarou "são idênticas, byte a byte".
- Recomendo manter a mensagem do LuauBench como está hoje no desenho (`Unable to create an Instance of type "X"` para os dois casos), mantendo o comentário no código de que a string exata não foi confirmada byte-a-byte para o caso específico de nome completamente inexistente — a aproximação de boa-fé já prevista é a decisão correta.

**Incerto**
- String literal exata para nome de classe que nunca existiu no dump/motor (typo puro). Só há confirmação indireta via convergência de outras causas de falha usando o mesmo formato.

---

## 3. Tag `Hidden` sem `NotScriptable`: acessível por um Script comum?

**Resposta curta: SIM, acessível.** `Hidden` controla só a visibilidade na janela de propriedades do Studio — não tem nenhuma relação com o que um script pode ler/escrever. Confirmado por três fontes independentes que convergem exatamente para a leitura que o gerador já assumiu.

**Fatos verificados**
- **Fonte comunitária de longa data (Anaminus, autor de ferramentas de referência do ecossistema Roblox desde 2014, JSON schema do formato de dump legado)**: `Hidden`: *"Whether the property is visible in the Studio's property panel."* — github.com/Anaminus/roblox-bug-tracker, `issues/345/api-dump-schema.json` (baixado e inspecionado literalmente nesta sessão). Contraste explícito com `NotScriptable`, que é o campo que de fato bloqueia acesso via script (confirmado no mesmo schema e em outras fontes abaixo).
- **Biblioteca comunitária ativa e usada pelo ecossistema (`cxmeel/dump-parser`, Wally package)**: código-fonte real (`src/Filter.lua`, baixado e inspecionado nesta sessão) define:
  ```lua
  local Scriptable: T.GenericFilter<T.Item> = Invert(HasTags("NotScriptable"))
  ```
  ou seja, o filtro "posso usar isso em script" verifica **apenas** a tag `NotScriptable` — `Hidden` nunca entra nessa checagem. O README da própria lib documenta o filtro de "propriedades seguras de usar" como `Invert(Deprecated) + HasSecurity("None") + Scriptable` — de novo, sem `Hidden`.
- **Inspeção direta do `Full-API-Dump.json` fixado (commit `28360dea`, feita nesta sessão)**: exemplo concreto de propriedade com `Hidden` e **sem** `NotScriptable`, `Security` totalmente aberta e `Capabilities` não-restritiva:
  ```json
  // Attachment.Position
  {"Tags": ["Hidden", "NotReplicated"], "Security": {"Read": "None", "Write": "None"},
   "Capabilities": {"Read": ["Basic"]}, "ValueType": {"Category": "DataType", "Name": "Vector3"}}
  ```
  `Attachment.Position` é uma propriedade comum, usada em scripts reais o tempo todo — confirma que `Hidden` sozinho nunca impediu acesso via script. Contei 81 propriedades no dump com esse mesmo padrão (`Hidden` presente, `NotScriptable` ausente, `Security` totalmente aberta) numa amostra rápida, sem esgotar as 926 citadas no desenho do arquiteto.
  Por contraste, quando uma propriedade `Hidden` **é** de fato bloqueada para script, o bloqueio vem sempre de outro campo junto (`NotScriptable` e/ou `Security` elevada) — nunca de `Hidden` sozinho. Exemplo: `EditableImage.ImageData` tem `Tags: ["Hidden", "NotReplicated", "NotScriptable"]` — o bloqueio real é `NotScriptable`, `Hidden` é redundante ali.

**Exemplo mínimo**
```lua
local attachment = Instance.new("Attachment")
print(attachment.Position) --> Vector3.new(0, 0, 0), funciona normalmente
-- Position tem a tag Hidden no dump (some do Property window do Studio),
-- mas isso nunca impediu o script de ler/escrever.
```

**Limites e pegadinhas**
- A leitura do gerador do LuauBench ("Hidden esconde do Property window do Studio, não do script") está **certa**, com confiança alta (3 fontes convergentes, incluindo inspeção direta do próprio dump fixado). Recomendo ao arquiteto **fechar** essa pendência como confirmada, sem mudar a Decisão 3.

**Incerto**
- Nenhuma fonte oficial da Roblox (create.roblox.com) documenta `Hidden` explicitamente — a confirmação vem de ferramentas/schemas comunitários de longa data + inspeção direta do dump, nunca de uma frase da Roblox em si. Tratando como confirmado dado o grau de convergência, mas registrando que não é uma fonte "oficial Roblox" no sentido estrito.

---

## 4. `script.Source` e `RunService.RenderStepped` no servidor

### 4a. `script.Source` lido de um Script comum

**Resposta curta:** **erra com uma mensagem de capability**, não com "is not a valid member of" e nunca devolve string vazia silenciosamente. E a premissa do desenho do arquiteto ("`Source` é `PluginSecurity` no dump") **está incorreta para o commit fixado** — o dump mostra `Security: None` e o bloqueio real vem do campo `Capabilities`, não do `Security` legado.

**Fatos verificados**
- **Inspeção direta do dump fixado (commit `28360dea`, feita nesta sessão)** — `Script.Source` (redeclarado identicamente em `ModuleScript.Source`; não existe em `LuaSourceContainer`/`BaseScript`):
  ```json
  {"MemberType": "Property", "Name": "Source", "Default": "",
   "Security": {"Read": "None", "Write": "None"},
   "Capabilities": {"Read": ["PluginOrOpenCloud"], "Write": ["PluginOrOpenCloud"]},
   "ValueType": {"Category": "DataType", "Name": "ProtectedString"}}
  ```
  `Security` é `None`/`None` — **não** `PluginSecurity**. O eixo que de fato bloqueia é `Capabilities`, um campo separado que a Decisão 3 do arquiteto não verifica.
- **Citação literal de erro real, de um script comum tentando ler `.Source` numa experiência publicada** (thread "Counting total lines of a code during runtime", devforum.roblox.com/t/counting-total-lines-of-a-code-during-runtime/4106643):
  > "The current thread cannot read 'Source' (lacking capability PluginOrOpenCloud)"
  Confirma exatamente o formato já catalogado pela pesquisa anterior (`pesquisa-api-dump-membros-2026-09-04.md`, Q5) para a família de erro de `Capabilities` — mas agora com a citação específica para `Source`, não só um exemplo genérico.
- Isso é uma **terceira família de erro**, distinta de "is not a valid member of" (membro realmente inexistente) e de "Unable to assign property... read only" (propriedade real mas somente-leitura). Nenhuma das três opções literais da pergunta original ("erra como not a valid member", "erra por capability", "string vazia") — a resposta certa é a do meio, mas com o formato exato agora confirmado por citação direta.

**Exemplo mínimo**
```lua
-- Script comum de servidor, rodando de verdade (não plugin, não OpenCloud):
local s = script
print(s.Source) --> erro real: "The current thread cannot read 'Source' (lacking capability PluginOrOpenCloud)"
```

**Limites e pegadinhas — achado que volta para o arquiteto**
- A frase do desenho (`arquiteto-services-2026-09-05.md`, seção "Contrato services → cli"): *"Script.Source é PluginSecurity no dump, logo excluída do schema pela Decisão 3"* está **factualmente errada** para o commit fixado `28360dea` — `Security` é `None`, o bloqueio é via `Capabilities`. A CONCLUSÃO prática (excluir `Source` do schema, `cli` usa `Get/SetPropertyRaw`) continua **correta** — só a justificativa/fonte está errada e precisa ser corrigida no texto do desenho.
- **Mais importante: a Decisão 3 do gerador (filtro de emissão de schema) só olha `Security.{Read,Write}` e as tags (`NotScriptable`/`ReadOnly`/`WriteOnly`) — nunca `Capabilities`.** Isso significa que, do jeito que a regra está desenhada hoje, `Source` **entraria** no schema como propriedade normal legível/gravável (porque `Security` mostra `None` e não há `NotScriptable`), o que é o comportamento **errado**. Ver seção "Achado extra" abaixo para o tamanho do problema além de `Source`.

**Incerto**
- Nada incerto na resposta central — a citação de erro é literal e específica para `Source`.

### 4b. `RunService.RenderStepped` no servidor real

**Resposta curta:** num **servidor de produção real (RCC)**, conectar (`:Connect()`) em `RunService.RenderStepped` **erra**. O comportamento "existe e nunca dispara" (o que o desenho atual do LuauBench assumiu) é, na verdade, um **bug reconhecido do Studio** (ambiente de teste local), não o comportamento real de produção.

**Fatos verificados**
- **Inspeção direta do dump fixado**: `RunService.RenderStepped` tem `Security: "None"`, `Capabilities: ["Basic"]`, **sem nenhuma Tag**. Ou seja, **o dump não tem absolutamente nenhum sinal** de que esse membro é restrito a cliente — a restrição client/server é aplicada por lógica de `RunContext` embutida no motor, invisível no dump. Isso confirma na prática a regra 03 do projeto ("o dump dá o 'o quê', nunca o 'como'") exatamente para este caso.
- **Bug report do DevForum (Studio Bugs, recente)**, "RenderStepped does not error when connected to on the server" (devforum.roblox.com/t/renderstepped-does-not-error-when-connected-to-on-the-server/3158569), citação literal do autor:
  > "When connecting to `RenderStepped` on the server in a local studio test, it will connect as if it was any other event."
  > "I expect it to error in a similar way to when `RenderStepped` is connected to on RCC [Roblox Cloud Compute — servidor dedicado real]."
  Resposta de funcionário da Roblox (`thirdtakeonit`): "Thanks for the report! I filed a ticket in our internal database." — tratado como bug real, não comportamento pretendido do Studio.
  Comentário de outro usuário: "This is expected, since RenderStepped can be used for studio plugins." — explica por que o **Studio** especificamente não erra (a VM de servidor do Studio compartilha alguma infraestrutura com plugins), mas não contradiz que o **RCC real erra**.
- **Texto de erro histórico, confirmado em múltiplos relatos independentes ao longo de anos, incluindo issues do próprio bug tracker da Roblox**: `"RenderStepped event can only be used from local scripts"` — github.com/Anaminus/roblox-bug-tracker/issues/636, /issues/365; github.com/ROBLOX/Studio-Tools/issues/14. É a mensagem real usada pelo motor para recusar a conexão fora de um contexto de cliente.

**Exemplo mínimo (comportamento real esperado em produção)**
```lua
-- Script de SERVIDOR rodando em produção real (RCC), não em Studio:
game:GetService("RunService").RenderStepped:Connect(function() end)
-- esperado: erro "RenderStepped event can only be used from local scripts" (ou variante), NÃO uma conexão silenciosa
```

**Limites e pegadinhas — achado que volta para o arquiteto**
- O desenho atual (`arquiteto-services-2026-09-05.md`, tabela "Fidelidade vs. pragmatismo"): *"RunService.RenderStepped — Existe no schema e nunca dispara... Aliasar para Heartbeat foi rejeitado."* — essa decisão **reproduz o comportamento do BUG do Studio, não o comportamento do Roblox real de produção**, que é justamente o que a regra 00 pede para não fazer silenciosamente ("fidelidade de comportamento com o Roblox real é o objetivo").
- Como o LuauBench já decidiu deliberadamente se apresentar como **servidor rodando** (`RunService:IsServer() == true`, mesma seção do desenho), a opção mais fiel ao Roblox real é **fazer `RunService.RenderStepped:Connect()` errar** no LuauBench (mensagem própria, já que a exata do motor não é 100% garantida, mas a família está bem documentada), em vez de deixar existir silenciosamente sem nunca disparar. Isso é uma recomendação de mudança de decisão, não uma implementação — volta para o arquiteto decidir.
- Nuance a registrar se o arquiteto preferir manter a decisão atual mesmo assim: ela reproduziria fielmente o **Studio**, não a **produção real** — precisa virar uma divergência **declarada** explicitamente (qual dos dois ambientes reais o LuauBench está imitando), não deixar implícito que é "o Roblox real" sem qualificar.

**Incerto**
- A string de erro exata usada **hoje** (2026) pelo motor não foi recolhida de um teste ao vivo desta sessão — a citação `"RenderStepped event can only be used from local scripts"` vem de relatos de anos diferentes (2014–2024), então é possível que o texto tenha mudado de leve ao longo do tempo (ex.: podendo ter migrado para o formato mais novo de `Capabilities`, já que o dump mostra `Capabilities: ["Basic"]` sem nada de especial — o que sugere que a restrição realmente não passa pelo sistema de Capabilities, reforçando que é RunContext hardcoded, mas o texto exato da mensagem atual não foi verificado ao vivo).

---

## Achado extra (não pedido, decorrente direto de 4a): `Capabilities` é um eixo que a Decisão 3 do gerador ignora

Ao investigar `Source`, rodei uma varredura no dump fixado procurando por propriedades com `Security: {None, None}` (portanto "abertas" pela regra de filtro atual) mas com um `Capabilities` restritivo — ou seja, candidatas a serem incluídas erradamente no schema pela Decisão 3 como está escrita hoje.

**Números brutos (contagem ingênua, ver ressalva abaixo):** 1833 de 4038 propriedades (~45%) no dump inteiro têm `Security` totalmente aberto mas `Capabilities` com algum nome além de `"Basic"`. Nas 23 classes da leva 1, isso aparece em 68 propriedades — incluindo, por exemplo, `Workspace.Gravity`, `Lighting.Ambient`, `Players.RespawnTime`, `StarterPlayer.CameraMode`.

**Ressalva importante, confirmada via documentação oficial (`Roblox/creator-docs`, `content/en-us/scripting/capabilities.md`):**
> "Rather than the default 'all-or-nothing system,' you can set a script to only be able to access certain categories..."

Isso confirma que **por padrão** (sem o script sandboxing opt-in, que é um recurso novo e não usado pela maioria dos jogos), um script comum **tem todas as capabilities** — é um sistema "tudo ou nada" que só vira granular se o desenvolvedor ligar explicitamente o sandboxing por script. Ou seja: **a contagem de 1833/68 acima superestima muito o problema real** — `Workspace.Gravity` (`Capabilities: {Write: ["Basic","Physics"]}`) é acessível normalmente por qualquer script comum (é literalmente uma das propriedades mais usadas do Roblox), porque `Physics` não é uma capability negada por padrão, é só uma categoria que existiria para um script explicitamente sandboxed.

O que **parece** ser diferente — nomes de capability que soam como identidade fixa do motor, não como categoria de sandboxing opcional, e que aparecem em erros reais mesmo para scripts comuns não-sandboxed: `PluginOrOpenCloud` (confirmado via citação de erro real para `Source`), `Plugin` e `RobloxScript` (confirmados via múltiplas citações de erro reais em contextos não relacionados a sandboxing do usuário). No dump da leva 1, os candidatos que seguem esse padrão de "nome de identidade reservada", não "categoria de sandboxing": `Script.Source`/`ModuleScript.Source` (`PluginOrOpenCloud`), `BaseScript.LinkedSource`/`ModuleScript.LinkedSource` (`LoadUnownedAsset`), `Instance.Capabilities`/`Instance.Sandboxed` (`CapabilityControl`), `RunService.FrameNumber` (`InternalTest`).

**Recomendação para o arquiteto:** a Decisão 3 precisa de uma terceira checagem além de `Security`+tags: excluir do schema qualquer membro cujo `Capabilities.Read`/`Capabilities.Write` contenha um nome da família "identidade reservada" (`Plugin`, `PluginOrOpenCloud`, `RobloxScript`, `RobloxEngine`, `CapabilityControl`, `LoadUnownedAsset`, `InternalTest`, e possivelmente outros da mesma família ainda não catalogados) — **mas não tratar qualquer nome fora de `"Basic"` como restritivo**, isso excluiria incorretamente propriedades de uso comum como `Workspace.Gravity`. Não tenho, nesta sessão, uma lista fechada e 100% confirmada de quais nomes de capability são "identidade reservada" vs. "categoria de sandboxing opcional" — recomendo uma pesquisa dedicada e pequena antes do gerador rodar de verdade sobre a leva 1, focada em enumerar essa lista a partir de `create.roblox.com/docs/scripting/capabilities` (a doc lista as categorias, só não indica claramente quais são concedidas por padrão) e de mais alguns exemplos de erro reais como o de `Source`.

---

## Fontes consultadas (resumo)

- `Full-API-Dump.json`, commit `28360dea4b90b35dc3fe9f829baae64fb6c50e75` — baixado e inspecionado diretamente nesta sessão (tamanho conferido: 8 006 149 bytes, bate com o lock já registrado). Fonte primária para tudo que é estrutura do dump.
- `github.com/Roblox/creator-docs`, `content/en-us/reference/engine/classes/Instance.yaml` — fonte primária oficial, citação literal da seção `FindFirstChild` (pergunta 1).
- `github.com/Roblox/creator-docs`, `content/en-us/scripting/capabilities.md` — fonte primária oficial, citação sobre o sistema "all-or-nothing" (achado extra da pergunta 4a).
- `github.com/Anaminus/roblox-bug-tracker`, `issues/345/api-dump-schema.json` — fonte comunitária de longa data (autor de ferramentas de referência do ecossistema desde 2014), citação literal da definição de `Hidden` (pergunta 3).
- `github.com/cxmeel/dump-parser`, `src/Filter.lua` — biblioteca comunitária ativa, código-fonte real inspecionado (pergunta 3).
- DevForum (múltiplos threads citados inline, sempre como corroboração de padrão convergente ou citação de erro real, nunca como fonte isolada de "verdade"): perguntas 2, 4a, 4b.
- `github.com/Anaminus/roblox-bug-tracker` (issues #636, #365) e `github.com/ROBLOX/Studio-Tools` (issue #14) — bug trackers reais da comunidade/Roblox, citação da mensagem de erro de `RenderStepped` (pergunta 4b).

## Recomendação final consolidada para o arquiteto

1. **Pergunta 1 (membro vs. filho): fechar como confirmada.** `task-runtime-021` está correta como desenhada; nenhuma mudança necessária.
2. **Pergunta 2 (mensagem de `Instance.new`): fechar como aproximação de boa-fé de alta confiança.** Manter como está, manter o comentário de "não confirmado byte-a-byte".
3. **Pergunta 3 (`Hidden`): fechar como confirmada.** A inclusão de `Hidden` no schema (Decisão 3) está correta; nenhuma mudança necessária.
4. **Pergunta 4a (`Source`): dois pontos de ação.**
   - Corrigir o texto do desenho: `Security` de `Source` é `None`, não `PluginSecurity` — quem bloqueia é `Capabilities`. A conclusão prática (fora do schema, `cli` usa `Get/SetPropertyRaw`) continua certa.
   - **Decisão 3 do gerador precisa de uma terceira checagem para `Capabilities` com identidade reservada** (não qualquer capability fora de `"Basic"`) — ver "Achado extra". Recomendo uma pesquisa pequena e focada antes de rodar o gerador de verdade, ou uma lista inicial conservadora (`Plugin`, `PluginOrOpenCloud`, `RobloxScript`, `RobloxEngine`, `CapabilityControl`, `LoadUnownedAsset`, `InternalTest`) com o gerador reportando no relatório qualquer capability desconhecida encontrada, para revisão manual.
5. **Pergunta 4b (`RenderStepped`): recomendo mudar a decisão.** "Existe e nunca dispara" reproduz um bug do Studio, não o Roblox real de produção. Recomendo `RunService.RenderStepped:Connect()` errar no LuauBench (fiel ao RCC real), com string própria documentada como aproximação — ou, se o arquiteto preferir manter o comportamento atual por simplicidade, declarar explicitamente que está imitando o Studio (ambiente de teste), não o servidor de produção real, para não violar a regra 00 silenciosamente.
