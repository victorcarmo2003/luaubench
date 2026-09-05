# Pesquisa: sobrescrever método de Instance / ler membro inexistente no Roblox real

Tarefa: `task-runtime-014`. Pendência aberta em `.claude/agents-memory/arquiteto-runtime-2026-09-04.md`, seção "Revisão pós-integração 2026-09-04 (2)", subseção "Pendência adjacente".

## Contexto da busca (importante para calibrar confiança)

O comportamento exato de `__index`/`__newindex` de uma `Instance` real do Roblox é **implementado em C++ fechado** (motor do Roblox, não open-source) e **não é documentado em prosa** em nenhuma das três fontes primárias que o projeto pede:

- `create.roblox.com/docs/reference/engine/classes/Instance` — verificado (fetch direto): lista propriedades/métodos/eventos com assinatura, mas **não descreve** o que acontece ao ler/escrever um membro inválido, nem menciona `__index`/`__newindex`/mensagens de erro.
- `create.roblox.com/docs/luau/metatables` — verificado (fetch direto): fala de metatables em geral e de GC de `Instance` fraco, mas **não** entra em como o Instance real usa `__index`/`__newindex`/`__namecall` nem em erros de atribuição.
- `Full-API-Dump.json` / README do `MaximumADHD/Roblox-Client-Tracker` — verificado (fetch direto do README): documenta só a existência do dump completo (classes/enums, campo `Default`), **não documenta comportamento de runtime** (erro de leitura/escrita), nem explica como a herança (`Superclass`) se reflete em acesso por script.

Ou seja: nenhuma das três fontes-fonte-primária do projeto cobre isso — é esperado, dado que é comportamento de engine fechada, não de formato de dado. Diante disso, a fonte prática disponível é: (a) o blog de engenharia oficial da Roblox sobre a implementação Lua/C++ (fonte primária, mas de 2017, sobre mecanismo, não sobre mensagens de erro), e (b) um volume grande e consistente de relatos no Developer Forum (**secundário, nunca fórum como fonte de "verdade" isolada, mas aqui uso a convergência de dezenas de threads independentes ao longo de anos como evidência de comportamento estável, não como opinião de um post só** — marcado explicitamente onde uso isso).

## 1. Atribuir sobre um método existente (`workspace.Raycast = nil`, `game.GetService = print`): erra, é ignorado, ou funciona?

**Resposta curta:** quase certamente erra (nunca funciona de verdade, nunca é ignorado silenciosamente) — mas a mensagem **exata** para este caso específico (nome que existe como método, não como propriedade) **não foi confirmada** nesta sessão.

**Fatos verificados**
- Instância real do Roblox é **UserData em C++, não uma tabela Lua** — leitura/escrita de membro passa por metamétodos implementados nativamente e conectados a um sistema de reflection (`__index` para propriedade/método, `__namecall` especificamente adicionado para chamada de método). Fonte: blog oficial de engenharia da Roblox, "Optimizing the Lua/C++ Interoperability" (about.roblox.com/newsroom/2017/05/optimizing-lua-c-interoperability) — **fonte primária oficial**, mas de 2017 e focado em otimização de chamada, não documenta o texto de erro de atribuição.
- Atribuir a um **nome que não existe como membro nenhum** da classe (nem propriedade, nem método, nem evento) erra com o mesmo formato usado na leitura: `"<Nome> is not a valid member of <ClassName>"` — corroborado por relato de desenvolvedor descrevendo que `Workspace.Part1 = Instance.new("Part")` erra em vez de criar um filho (fonte agregadora de terceiros, `copyprogramming.com`, **marcado como pista, não fonte primária** — mas consistente com o padrão abaixo).
- Atribuir a uma **propriedade real, mas somente-leitura** (ex.: `DriverSeat.Occupant`, `Animator...Speed`) produz uma mensagem **diferente**: `"Unable to assign property <Nome>. Property is read only"` — corroborado por múltiplos threads independentes do Developer Forum reportando exatamente essa string para propriedades diferentes (`Occupant`, `Speed`), ao longo de anos diferentes. Fonte: devforum.roblox.com/t/unable-to-assign-property-occupant-property-is-read-only/2421493 e devforum.roblox.com/t/unable-to-assign-property-speed-property-is-read-only/2852919 — **secundário (fórum), mas convergente e específico o bastante (duas propriedades distintas, mesma frase exata) para tratar como padrão real, não coincidência**.
- O próprio API Dump classifica cada membro por `MemberType` (`Property` / `Function` / `Event` / `Callback`) — ou seja, a distinção "isto é uma propriedade vs. isto é uma função" é estrutural no sistema de reflection que a Roblox usa, o mesmo sistema que decide se uma atribuição é válida. Isso sustenta a inferência abaixo, mas o dump em si (conferido acima) não descreve o comportamento de erro.

**Não confirmado**
- A mensagem literal exata produzida ao atribuir a um nome que **existe como `Function`/`Event`/`Callback`** (não como `Property`) — ex.: `workspace.Raycast = nil`. Busquei ativamente por um relato de alguém reproduzindo esse cenário específico (é raro: ninguém tenta isso por acidente, ao contrário de "propriedade somente-leitura", que é erro comum de iniciante) e não encontrei um thread do Developer Forum, post técnico ou documentação oficial com essa string literal.
- Minha melhor inferência, **não verificada empiricamente nesta sessão**: como `Function`/`Event`/`Callback` não têm "Setter" no sistema de reflection (só `Property` tem), o caminho de atribuição provavelmente trata esses nomes como se não existissem *para fins de escrita* — ou seja, cai na mesma família `"<Nome> is not a valid member of <ClassName>"` em vez da família "Property is read only". Mas isso é dedução a partir do mecanismo descrito no blog de 2017 + na estrutura do dump, **não uma citação de mensagem real**. Se o `arquiteto`/`revisor-runtime` precisar da string exata para replicar byte-a-byte, isso exige teste direto no Roblox Studio real (fora do alcance deste agente, que é read-only e sem acesso a Studio).

## 2. O comportamento é igual para método herdado de `Instance` (`GetChildren`) e para método específico da classe (`Raycast`)?

**Resposta curta:** não há nenhuma fonte, oficial ou de terceiros, que descreva ou sugira qualquer distinção de comportamento entre os dois — e a própria estrutura do sistema de reflection (dump com `Superclass`, resolvido por quem consome o dump ao "achatar" a cadeia de herança) implica que não existe distinção observável do lado do script.

**Fatos verificados**
- `Full-API-Dump.json` modela herança via campo `Superclass` por classe — um membro definido em `Instance` não é redeclarado em `Workspace`; quem lê o dump (o próprio motor da Roblox, ou o gerador de `services` do LuauBench) precisa subir a cadeia para saber que `Workspace` também tem `GetChildren`. Isso é estrutural do formato (conferido no README do `Roblox-Client-Tracker`, embora o README não descreva comportamento de runtime, só a existência do dump completo).
- Na prática de uso (amplamente e uniformemente relatado em qualquer script Roblox real, sem exceção conhecida em nenhum dos threads varridos nesta pesquisa), `objeto:GetChildren()` e `objeto:Raycast(...)` são chamados com sintaxe idêntica (`:`), nenhum thread de troubleshooting jamais atribui um erro diferente a "método herdado" vs "método próprio da classe" — os erros de "not a valid member" aparecem por classe errada (`Touched` não existe em `Model`), nunca por "existe mas é herdado, então funciona diferente".

**Não confirmado**
- Não existe uma declaração explícita, oficial ou de terceiros, dizendo literalmente "não há diferença entre método herdado e método próprio para leitura/escrita". É ausência de evidência de diferença, não confirmação positiva de igualdade por uma fonte que tenha testado os dois lados de propósito.

## 3. Ler propriedade inexistente numa Instance real: erra ou devolve `nil`?

**Resposta curta: erra.** Nunca devolve `nil` silenciosamente. Isto está fortemente confirmado (não pela documentação oficial, que não cobre isso, mas pela convergência maciça e consistente de relatos independentes no Developer Forum, ao longo de vários anos, para dezenas de nomes de propriedade/classe diferentes — comportamento tratado como conhecimento comum e estável da comunidade Roblox, não uma opinião isolada).

**Fatos verificados**
- Formato da mensagem, confirmado por citação direta de thread real: `"HumanoidRootPart is not a valid member of Model \"Workspace.<username>\""` — fonte: devforum.roblox.com/t/handling-is-not-a-valid-member-of-error/2169313 (fetch direto, citação verbatim extraída do thread).
- O mesmo formato aparece de forma consistente para: eventos acessados com nome errado (`"Connect is not a valid member of RBXScriptSignal"`, devforum.roblox.com/t/connect-is-not-a-valid-member-of-rbxscriptsignal/1423193), evento chamado no objeto errado (`"Touched is not a valid member of Model"`, devforum.roblox.com/t/touched-is-not-a-valid-member-of-model/2432274), propriedade em classe errada (`"BoolValue is not a valid member of Workspace \"Workspace\""`, devforum.roblox.com/t/boolvalue-is-not-a-valid-member-of-workspace/767214), entre múltiplos outros exemplos independentes.
- Isso é tratado universalmente pela comunidade como diferença fundamental de Roblox Instance vs. tabela Lua comum: tabela Lua devolve `nil` para chave desconhecida; Instance real **erra**.

**Consequência direta para o desenho do LuauBench (não é pergunta da pesquisa, mas decorre diretamente do fato acima):**
O `InstanceMeta.__index` atual do LuauBench cai em `data.properties[key]` para qualquer chave desconhecida — isso devolve `nil` para uma propriedade que não existe, o que **já diverge do Roblox real independentemente de qualquer método entrar em jogo**. Essa divergência existe hoje, antes mesmo de `services` escrever a primeira classe.

## Recomendação para o `arquiteto` (não implementado, decisão é do arquiteto)

1. **Sim, construir algo como `Instance.SetClassMethods`** — tabela separada de métodos, consultada por `__index` **antes** de `properties`, e protegida por `__newindex` (erro ao tentar escrever, nunca silêncio). O mecanismo deve ser **único**, sem distinguir método herdado de `Instance` vs. método da classe concreta — não há fonte (nem inferência plausível) que sustente tratamento diferente entre os dois (pergunta 2), então uma tabela única de métodos resolvida no momento de `Initialize`/registro cobre ambos os casos igualmente.
2. **A pergunta maior e mais cara é a da pergunta 3, não a do método**: o fallback de `__index` para `properties[key]` já diverge do real para *qualquer* propriedade inexistente, não só para método. Corrigir só a proteção de método (pergunta 1) sem tratar leitura de membro desconhecido deixa a divergência maior (silêncio em vez de erro) sem resolver. Recomendo que o arquiteto decida as duas coisas juntas: `__index` deveria, no fallback final (depois de checar propriedade conhecida, método e criança), **erro** em vez de `nil` — replicando a família `"%s is not a valid member of %s"` (formato confirmado na pergunta 3), documentando explicitamente que o LuauBench está aproximando o texto exato (que não é público) e não replicando byte-a-byte a mensagem do motor fechado da Roblox — isso é divergência declarada, exigida pela regra 2 do projeto (`.claude/CLAUDE.md`), não silenciosa.
3. **Para escrita sobre método** (pergunta 1): já que a mensagem exata do Roblox real não está confirmada, recomendo ao arquiteto decidir uma mensagem própria do LuauBench (ex.: reaproveitar o mesmo formato `"%s is not a valid member of %s"` usado para leitura, já que é a família mais provável por dedução estrutural) e **documentar no código que a mensagem exata do Roblox real para este caso específico não foi confirmada** — não apresentar como fidelidade byte-a-byte.
4. Esta pesquisa não teve como confirmar a string exata sem acesso a um Roblox Studio real rodando o teste ao vivo — se byte-a-byte importar para algum teste de fidelidade automatizado, é um teste que só pode ser resolvido rodando o cenário real no Studio (fora do escopo de um agente read-only sem esse acesso), não por mais busca textual.

## Fontes consultadas (resumo)

- create.roblox.com/docs/reference/engine/classes/Instance — oficial, verificado, não cobre o comportamento perguntado.
- create.roblox.com/docs/luau/metatables — oficial, verificado, não cobre o comportamento perguntado.
- github.com/MaximumADHD/Roblox-Client-Tracker (README) — oficial (fonte de dado do projeto), verificado, não cobre comportamento de runtime.
- about.roblox.com/newsroom/2017/05/optimizing-lua-c-interoperability — oficial (blog de engenharia Roblox), 2017, confirma mecanismo (UserData + `__namecall`), não confirma mensagens de erro.
- Developer Forum (múltiplos threads, listados inline acima) — secundário/comunidade, usado só pela convergência entre relatos independentes; nunca como fonte isolada.
- Blog técnico de terceiros `atrexus.github.io/posts/roblox-reflection-part1` — **não consultado com sucesso** (404 ao buscar diretamente e via wayback machine, indisponível para fetch nesta sessão); mencionado aqui só para registrar que foi tentado e falhou, não deve ser citado como fonte.
