# Pesquisa: modelo de membro do Roblox API Dump (task-runtime-017)

**Fonte primária inspecionada:** `Full-API-Dump.json` real, baixado nesta sessão de
`https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json`
(repositório tem uma única branch, `roblox`, sem pastas por versão — é um snapshot rolante com histórico via `git log`).

- Commit inspecionado: `28360dea4b90b35dc3fe9f829baae64fb6c50e75`, mensagem `"0.737.0.7371584 (JSON)"`, autor "Roblox Client Tracker", data `2026-09-03T00:16:47Z`.
- `version-guid.txt` no mesmo commit: `version-9fe94fb0e9d84c25`.
- **`Full-API-Dump.json` é gerado pelo próprio Roblox Studio**, não por ferramenta de terceiro: confirmado pelo `README.md` do repositório — `RobloxStudioBeta.exe -FullAPI Full-API-Dump.json` ("mais completo que o dump normal, inclui todas as classes/enums omitidos e chaves extras como `Default` em algumas propriedades"). Isso é fonte oficial de primeira mão, não inferência de terceiro.
- Todas as afirmações abaixo vêm de inspeção programática (Python) do JSON real, script descartável em `C:\Users\hakor\AppData\Local\Temp\claude\...\scratchpad\Full-API-Dump.json` (não faz parte do repositório do projeto — é só o arquivo baixado para esta pesquisa; **não fica fixado/versionado por esta tarefa**, a fixação de versão do dump para o projeto é decisão separada, ainda em aberto conforme `.claude/rules/03-services-api-dump.md:6`).
- **Nenhuma parte deste relatório vem de memória/suposição sobre o formato — tudo foi contado/verificado direto no JSON baixado.**

---

## Resposta curta

`Scriptability` **não existe** neste dump (0 ocorrências em 4038 `Property`). O modelo real de escrituralidade é **três sinais independentes** por `Property`: `Security: {Read, Write}` (nível de identidade exigido), a tag `"ReadOnly"` (nunca gravável, por ninguém, independente de segurança) e a tag `"NotScriptable"` (invisível para *qualquer* script Luau, independente de segurança) — **não colapsa num único booleano sem perda**. `Default` é **sempre uma string** no JSON (nunca número/bool/objeto nativo), com 5 valores-sentinela documentando "sem valor real disponível"; para propriedade tipo `Instance` o valor é **sempre** um desses sentinelas — nunca um valor de instância serializado — então `nil` é a tradução correta. `MemberType` tem **exatamente** 4 valores (`Property`/`Function`/`Event`/`Callback`), nunca mais de um por (classe, nome). O dump **redeclara membro de mesmo nome já declarado num ancestral**, com casos reais de assinatura diferente da versão herdada — achatamento "mais específico vence" de task-runtime-016/018 tem colisão legítima real, não hipotética. `Security` muda o que um `Script` comum alcança: valor diferente de `"None"` em `Read`/`Write` é inacessível a um script de jogo normal (identidade `GameScript`/`LocalGui`).

**Recomendação de `PropertyDescriptor`** (arquiteto decide, ver seção própria abaixo): não usar `ReadOnly: boolean` sozinho. Usar dois booleanos — `Writable` e `Readable` (ou aceitar a divergência de fase e nunca representar propriedade não-`None`/`NotScriptable` no schema, o que é razoável dado que LuauBench não simula identidade/segurança nenhuma hoje).

---

## Fatos verificados

### Q1 — Escrituralidade: `Scriptability` não existe; é `Security` + `Tags`

- **`Scriptability` tem zero ocorrências** em todo o dump (varredura completa dos 4038 membros `Property`). Fonte: `Full-API-Dump.json`, commit acima.
- O que existe de fato, em **todo** membro `Property` (100% dos 4038 têm o campo):
  ```json
  "Security": { "Read": "None", "Write": "None" }
  ```
  Valores observados de `Security.Read`/`Security.Write` (contagem real): `"None"` (2828 Read / 2769 Write), `"RobloxScriptSecurity"` (672/681), `"RobloxSecurity"` (300/301), `"PluginSecurity"` (223/260), `"LocalUserSecurity"` (14/15), `"NotAccessibleSecurity"` (1/12).
  Para `Function`/`Event`/`Callback`, `Security` é uma **string única** (não `{Read,Write}`) — ex.: `"Instance.AddTag"` tem `"Security": "None"`. Confirmado por varredura de tipo: 100% dos 4363 membros não-`Property` têm `Security` como `str`.
- Tags observadas em `Property` (contagem real, só tags-string): `NotReplicated` 1099, `Hidden` 926, `NotScriptable` 536, `ReadOnly` 503, `Deprecated` 157, `WriteOnly` 9, `NotBrowsable` 7. As quatro tags citadas na pergunta (`ReadOnly`, `NotScriptable`, `Deprecated`, `Hidden`) **existem de verdade** no dump atual.
- **Os três sinais são independentes, não redutíveis um ao outro** (prova empírica):
  - De 503 membros com tag `ReadOnly`, **349 têm `Security = {Read:"None", Write:"None"}`** — ou seja, "somente leitura" não é implicado por segurança nenhuma; é um sinal à parte que diz "isto nunca é gravável, mesmo com identidade máxima". Exemplo concreto — `Object.ClassName`:
    ```json
    {"Category":"Data","Default":"__api_dump_class_not_creatable__","MemberType":"Property",
     "Name":"ClassName","Security":{"Read":"None","Write":"None"},
     "Serialization":{"CanLoad":false,"CanSave":false},
     "Tags":["ReadOnly","NotReplicated"],"ThreadSafety":"ReadSafe",
     "ValueType":{"Category":"Primitive","Name":"string"}}
    ```
    (Nota: `ClassName` **não está declarado em `Instance`**, está em `Object`, a superclasse raiz de `Instance` — `Instance.Superclass == "Object"`, `Object.Superclass == "<<<ROOT>>>"`.)
  - De 536 membros com tag `NotScriptable`, **249 também têm `Security = {None, None}`** — ou seja, "invisível para script" não é implicado por segurança nenhuma; um membro pode ter segurança totalmente aberta e ainda assim ser um campo interno nunca refletido para Luau. Exemplo com segurança elevada E `NotScriptable` junto: `EditableImage.ImageData` → `Security: {Read:"RobloxSecurity", Write:"RobloxSecurity"}`, `Tags: ["Hidden","NotReplicated","NotScriptable"]`.
  - `WriteOnly` (9 ocorrências) é raro e aparece em propriedades legadas/internas (`BasePart.siz`, `Part.shap`, `Terrain.ClusterGrid*`, `HopperBin.Command`) — todas com `Security:{None,None}`, `Serialization:{CanLoad:true,CanSave:false}`. Confirma que existe de fato um estado "gravável mas não legível de volta", que um `ReadOnly: boolean` também não representa.
- **Conclusão factual**: para saber se um `Script` comum (identidade sem segurança elevada) pode ler/escrever um membro, é preciso checar os **três** independentemente: `NotScriptable` (exclui de qualquer script), `Security.Read`/`Security.Write` (exclui de script sem identidade elevada), `ReadOnly` (exclui escrita para qualquer um). Um booleano só cobre 1 desses 3 eixos.

### Q2 — `Default`: sempre string, sentinelas para "sem valor real", `nil` verdadeiro para `Instance`

- **100% dos 4038 membros `Property` têm a chave `Default`, e o valor é sempre `str`** (nunca número, bool ou objeto — verificado por `type()` em todos). O dump serializa cada tipo à mão como texto: bool → `"true"`/`"false"` (ex.: `Animator.PreferLodEnabled` = `"true"`), número → string decimal (`Humanoid.MaxHealth` = `"100"`, `Humanoid.WalkSpeed` = `"16"`), `Vector3`/`Color3` → CSV (`Attachment.Position` = `"0, 0, 0"`, `Fire.Color` = `"0.92549, 0.545098, 0.27451"`), `ColorSequence`/`NumberSequence` → lista de keypoints separada por espaço (`Beam.Transparency` = `"0 0.5 0 1 0.5 0 "`), `Enum` → nome do item (`Part.Shape` = `"Block"`, tipo `PartType`).
- **5 strings-sentinela** cobrem os casos sem valor amostrável de verdade (contagem exata sobre 4038 propriedades):
  | Sentinela | Ocorrências | Situação observada |
  |---|---|---|
  | `__api_dump_class_not_creatable__` | 718 | classe abstrata/não instanciável (ex.: toda propriedade de `BasePart`, `Instance`) |
  | `__api_dump_skipped_class__` | 542 | classe pulada pelo processo de dump |
  | `__api_dump_no_string_value__` | 310 | valor não serializável como string — **é exatamente o caso de propriedade tipo `Instance`** |
  | `__api_dump_failed_to_create_class__` | 18 | tentativa de instanciar a classe falhou |
  | `__api_dump_write_only_property__` | 7 | propriedade `WriteOnly`, não dá pra ler de volta pra amostrar |
  Essas 5 strings **não são API oficial documentada por nome** — são inferidas pelo padrão de nome (prefixo `__api_dump_`) e pela correlação estatística com o contexto (classe abstrata, tipo Instance, tag WriteOnly). O *mecanismo* (Studio tenta instanciar a classe e ler a propriedade de volta para amostrar um `Default` real) é inferência de engenharia razoável a partir do texto do README ("Default values on some properties"), **não confirmada por documentação de cada sentinela individualmente**.
- **Propriedade tipo `Instance` — confirmado com os três exemplos pedidos**:
  ```json
  // ObjectValue.Value
  {"Default":"__api_dump_no_string_value__","MemberType":"Property","Name":"Value",
   "ValueType":{"Category":"Class","Name":"Instance"}, ...}
  // Humanoid.SeatPart
  {"Default":"__api_dump_no_string_value__","MemberType":"Property","Name":"SeatPart",
   "Tags":["ReadOnly","NotReplicated"],"ValueType":{"Category":"Class","Name":"BasePart"}, ...}
  // Model.PrimaryPart
  {"Default":"__api_dump_no_string_value__","MemberType":"Property","Name":"PrimaryPart",
   "ValueType":{"Category":"Class","Name":"BasePart"}, ...}
  ```
  **100% das propriedades com `ValueType.Category == "Class"` têm `Default` igual a um dos 5 sentinelas** (nunca um valor "de verdade") — verificado por varredura completa. A tradução correta para o `PropertyDescriptor` é `Default = nil` sempre que `ValueType.Category == "Class"`, e é isso — não dá pra distinguir "de fato nulo no Roblox real" de "o gerador do dump não conseguiu amostrar", mas para propriedade tipo Instance as duas coisas coincidem sempre (nunca existe outro valor possível).

### Q3 — `MemberType`: exatamente 4 valores, nunca mais de um por (classe, nome)

- Contagem exata: `Property` 4038, `Function` 3258, `Event` 1087, `Callback` 18. Nenhum quinto valor.
- **Nenhuma classe tem duas declarações do mesmo `Name`** (verificado: zero duplicatas intra-classe em nome de membro, contando os 4 tipos juntos).
- **27 nomes** aparecem com `MemberType` diferente **entre classes diferentes** (ex.: `Move` é `Function` em `Humanoid` mas `Event` em outra classe, `OnInvoke` é `Function` em algum lugar e `Callback` em `BindableFunction`) — isso é esperado e não é ambiguidade dentro de uma classe, é coincidência de nome entre hierarquias não relacionadas.

### Q4 — Sim, o dump redeclara membro de nome já existente num ancestral, com assinatura real diferente

Achado direto e o mais importante para o achatamento de task-runtime-016/018: **19 pares (classe, ancestral) com nome de membro sobreposto**, verificados percorrendo a cadeia de `Superclass` de cada uma das 916 classes contra os nomes de membro de cada ancestral real. Exemplos citados com o JSON completo dos dois lados:

- **`BoolValue.Changed` vs `Object.Changed`** (e o mesmo padrão em `IntValue`, `NumberValue`, `ObjectValue`, `StringValue`, `Vector3Value`, `CFrameValue`, `Color3Value`, `BrickColorValue`, `RayValue`, `DoubleConstrainedValue`, `IntConstrainedValue` — 11 classes `*Value`, todas redeclarando `Changed`):
  ```json
  // Object.Changed (genérico, herdado por default)
  {"MemberType":"Event","Name":"Changed","Parameters":[{"Name":"property","Type":{"Category":"Primitive","Name":"string"}}]}
  // BoolValue.Changed (redeclarado, assinatura DIFERENTE)
  {"MemberType":"Event","Name":"Changed","Parameters":[{"Name":"value","Type":{"Category":"Primitive","Name":"bool"}}]}
  // ObjectValue.Changed (redeclarado, tipo do parâmetro é a própria classe do Value)
  {"MemberType":"Event","Name":"Changed","Parameters":[{"Name":"value","Type":{"Category":"Class","Name":"Instance"}}]}
  ```
  Isto é uma colisão **real e com tipo de parâmetro genuinamente diferente**, não cosmética — `Object.Changed(property: string)` vs `BoolValue.Changed(value: bool)` têm até nome de parâmetro diferente.
- **`CollectionService.AddTag` vs `Instance.AddTag`** (herdado, já que `CollectionService`'s cadeia passa por `Instance`):
  ```json
  // Instance.AddTag (método de instância — self implícito)
  {"Name":"AddTag","Parameters":[{"Name":"tag","Type":{"Category":"Primitive","Name":"string"}}]}
  // CollectionService.AddTag (redeclarado — assinatura tem um parâmetro A MAIS)
  {"Name":"AddTag","Parameters":[{"Name":"instance","Type":{"Category":"Class","Name":"Instance"}},
                                   {"Name":"tag","Type":{"Category":"Primitive","Name":"string"}}]}
  ```
- **`Workspace.BreakJoints` vs `Model.BreakJoints`**: `Model.BreakJoints()` sem parâmetro vs `Workspace.BreakJoints(objects: Instances)` com `Security: "PluginSecurity"` — assinatura e segurança diferentes.

**Conclusão**: a política "classe mais concreta sobrescreve a superclasse no achatamento" (já decidida por task-runtime-016 para `Methods`) tem pelo menos 19 casos reais no dump onde isso importa de verdade — não é hipotético. Vale também para `Properties` no schema de task-runtime-018 se o dump redeclarar propriedade (não encontrei um caso de `Property` redeclarada nesta amostra dos 19 pares — todos os 19 caem em `Event`/`Function` —, mas o mecanismo de achatamento já decidido cobre o caso genericamente).

### Q5 — `Security` muda o que um `Script` comum alcança; precisa entrar no schema (de algum jeito)

- Fonte comunitária (não oficial, mas convergente e citada como tal): [Pseudoreality/Roblox-Identities](https://github.com/Pseudoreality/Roblox-Identities) descreve 13 identidades de thread no Roblox; scripts de servidor comuns rodam como identidade `GameScript`, `LocalScript` como `LocalGui` — nenhuma das duas tem a capacidade elevada associada a `RobloxScriptSecurity`/`RobloxSecurity`/`PluginSecurity`. **Não confirmado por documentação oficial nesta sessão** — é o melhor dado disponível, marcado como origem comunitária.
- Fonte oficial parcial: [create.roblox.com/docs/scripting/capabilities](https://create.roblox.com/docs/scripting/capabilities) descreve o sistema **mais novo** de `Capabilities` (bit field, "experimental, client beta" à data da consulta), que hoje **coexiste** com o `Security` legado observado no dump — não documenta a correspondência exata entre os dois sistemas nem qual identidade um `Script` comum tem por padrão. Formato de erro **confirmado por citação oficial** quando falta uma capability (sistema novo, diferente da família "is not a valid member of"/"read only" já documentada em task-runtime-014):
  > "The current thread cannot modify 'Workspace' (lacking capability AccessOutsideWrite)"
  > "The current thread cannot call 'Clone' (lacking capability CreateInstances)"
  Isto é uma **terceira família de mensagem de erro**, distinta das duas já catalogadas por task-runtime-014/016. Só citada aqui por completude — LuauBench não simula identidade/capability nenhuma hoje, então não é urgente implementar essa família de erro.
- Achado empírico adicional (não pedido, mas relevante): **2817 dos 4038 membros `Property` (70%) já têm um campo `Capabilities`** no dump atual (ex.: `Humanoid.SeatPart` tem `"Capabilities":{"Read":["AvatarBehavior"],"Write":["AvatarBehavior"]}`), coexistindo com `Security`. Isso sugere que o campo `Security` legado pode estar em transição/deprecação de longo prazo dentro do próprio Roblox, mas **ambos estão presentes e populados hoje** no dump inspecionado — não é uma migração já concluída.
- **Conclusão prática para Q5**: sim, `Security` muda o que um `Script` comum alcança — qualquer valor de `Security.Read`/`Security.Write` diferente de `"None"` é inacessível a um script de jogo normal (por convergência entre o dado do dump — 70% dos membros têm `Security:{None,None}` — e a fonte comunitária de identidades). Precisa entrar no `PropertyDescriptor` **de algum jeito**, mas a forma exata (booleano derivado vs. string bruta) é decisão de arquitetura, não de pesquisa — ver recomendação abaixo.

---

## Achados adicionais (não pedidos, mas relevantes para o gerador de `services`)

- **`Tags` é um array de tipo misto** — na maioria das vezes só strings, mas quando um membro tem a tag `Deprecated` E um nome preferido de substituição, o array ganha um objeto (não string) no fim:
  ```json
  "Tags": ["ReadOnly", "NotReplicated", "Deprecated", {"PreferredDescriptorName": "ClassName", "ThreadSafety": "Unknown"}]
  ```
  (exemplo real: `Object.className`, o alias minúsculo legado de `ClassName`). Confirmado em **65 `Property` + 153 `Function` + 27 `Event` + 1 `Callback` + 18 tags de classe** — não é caso isolado de uma classe, é padrão geral do dump. **Pegadinha de tipagem**: `Tags: {string}` em `--!strict` quebra ao decodificar isso; o gerador precisa filtrar/normalizar (`if type(tag) == "string"`) antes de tipar como `{string}`.
- **Classe abstrata / classe de serviço são tags de classe, não campo booleano dedicado**: `Tags` no nível da classe (não da propriedade) contém `"NotCreatable"` (mapeia para `IsAbstract` do `ClassDescriptor` do LuauBench) e `"Service"` (mapeia para `IsService`) — ex.: `Workspace.Tags == ["NotCreatable", "Service"]`, `Part.Tags` **ausente** (chave não existe no objeto, não é `null`) porque `Part` é concreta e não-serviço.
- **Raiz real da hierarquia é `Object`, não `Instance`**: `Object.Superclass == "<<<ROOT>>>"` (string sentinela, não `null`/chave ausente), `Instance.Superclass == "Object"`. Se o gerador de `services`/o achatamento de `ClassRegistry` andar a cadeia até `Superclass == nil`, isso quebra — precisa parar em `"<<<ROOT>>>"` (ou em `"Object"`, se o LuauBench decidir que sua própria raiz simulada é `Instance` e não replicar `Object`, que é uma decisão de escopo do arquiteto, não desta pesquisa).
- **Chave ausente ≠ `null`**: quando uma classe não tem tags, a chave `Tags` **não existe** no objeto (não é `"Tags": null`). Mesmo padrão provavelmente vale para outras chaves opcionais do dump — o gerador precisa tratar "chave ausente" e não assumir presença com valor nulo.

---

## Recomendação de `PropertyDescriptor` (para o arquiteto decidir)

O rascunho provisório do arquiteto era:
```luau
export type PropertyDescriptor = { Default: unknown, ReadOnly: boolean }
```

Com o que foi confirmado, **um único `ReadOnly: boolean` perde informação real**: não representa (a) propriedade que nem sequer pode ser lida por um `Script` comum (`NotScriptable` ou `Security.Read ~= "None"`), nem (b) o caso raro mas real de `WriteOnly`. Duas recomendações possíveis, ambas compatíveis com o "modo estrito" já desenhado em task-runtime-018 — a escolha entre elas é de arquitetura (quanto de fidelidade ao sistema de segurança o LuauBench quer, dado que hoje não simula identidade nenhuma):

**Opção A — mais simples, meu palpite de custo/benefício para a fase atual:** o **gerador** (não o runtime) decide, no momento de emitir `ClassDescriptor.Properties`, se cada propriedade do dump é alcançável por um `Script` comum (`Security.Read == "None" and Security.Write == "None" and not NotScriptable`, aproximando "sempre existe tanto para leitura quanto escrita, já que LuauBench não distingue os dois hoje"). Se não for alcançável, **a propriedade simplesmente não entra no `ClassSchema`** daquela classe — cai no mesmo fallback leniente que task-runtime-016 já documentou para propriedade fora do schema. `PropertyDescriptor` continua com `ReadOnly: boolean`, mas agora `ReadOnly` é calculado como `Tags contém "ReadOnly"` (WriteOnly é raro o bastante — 7 casos — para tratar como fora do schema também, mesmo caminho de "não incluído"). Vantagem: schema pequeno, sem inventar terceiro estado. Desvantagem: perde fidelidade para o raro caso em que um `Script` real consegue ler mas não escrever uma propriedade *por razão de segurança* (diferente de `ReadOnly`) — teria a mesma superfície visível, então tecnicamente correto para o caso comum.

**Opção B — mais fiel, custa dois campos a mais:**
```luau
export type PropertyDescriptor = {
    Default: unknown,   -- já parseado por ValueType.Category, nunca a string bruta do dump
    Readable: boolean,  -- false se Tags contém "NotScriptable" OU Security.Read ~= "None"
    Writable: boolean,  -- false se Readable == false, OU Tags contém "ReadOnly"/"WriteOnly" tratado à parte, OU Security.Write ~= "None"
}
```
com o modo estrito de task-runtime-018 ganhando um terceiro erro (além de "not a valid member" e "read only"): ler propriedade com `Readable == false` também erra "not a valid member" (do ponto de vista de um script comum, é como se não existisse — coerente com o dump mostrando que ela nem é `NotScriptable`-visível). Isso aproxima mais o comportamento real sem implementar o sistema de `Capabilities`/identidade inteiro.

Em ambos os casos: **`Default: unknown` deve ser o valor já parseado pelo gerador** (número real, bool real, tabela `{x,y,z}` para Vector3 etc., ou `nil` para `ValueType.Category == "Class"`), nunca a string bruta do dump — o parsing por `ValueType.Category`/`ValueType.Name` é trabalho do gerador de `services`, não do `PropertyDescriptor` em si.

---

## Incerto

- **Semântica exata de cada uma das 5 strings-sentinela de `Default`** — inferida por nome + correlação estatística com o contexto (classe abstrata/tipo Instance/tag WriteOnly), não documentada campo-a-campo em nenhuma fonte oficial encontrada.
- **Identidade/segurança padrão de um `Script`/`LocalScript` comum** — a fonte usada (`Pseudoreality/Roblox-Identities`) é comunitária, não oficial; não achei confirmação equivalente em `create.roblox.com/docs`.
- **Relação exata entre o `Security` legado (visto no dump) e o `Capabilities` mais novo** (`create.roblox.com/docs/scripting/capabilities` descreve o sistema novo como "experimental, client beta" e não documenta a correspondência) — os dois campos coexistem no dump hoje (`Capabilities` presente em 70% dos `Property`), mas se um substitui o outro no motor real ou como interagem não foi confirmado.
- **Se o dump chega a redeclarar uma `Property`** (não só `Function`/`Event`) numa subclasse já declarada num ancestral — os 19 casos encontrados nesta sessão foram todos `Event`/`Function`; não posso afirmar que nunca acontece com `Property` sem uma varredura mais ampla do texto do dump procurando por padrão de nome id êntico com `ValueType` diferente entre classe e ancestral (a varredura feita já cobre isso e não achou nenhum, mas o n de 916 classes com hierarquias profundas deixa margem para um caso que a lógica de comparação de nomes simples não capturou se houver alguma diferença de capitalização não tratada).
