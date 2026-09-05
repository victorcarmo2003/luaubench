# Pesquisa — comportamento de `ServiceProvider:GetService` no Roblox real (2026-09-05)

Re-confirmação solicitada para task-runtime-029 (mudança de assinatura `DataModel:GetService` de `Instance` para `Instance?` no LuauBench). Pesquisa anterior de mesma data não deixou arquivo — este é o registro.

## Fontes primárias consultadas

- **Documentação oficial atual**, buscada ao vivo via `curl` em 2026-09-05 (bypass de sumarização por modelo, texto bruto):
  `https://create.roblox.com/docs/en-us/reference/engine/classes/ServiceProvider.md`
  (`last_updated: 2026-09-03T23:49:25Z` no frontmatter do próprio arquivo — é a versão vigente hoje).
- **DevForum, thread original (2018)**, JSON bruto da API do Discourse (bypass de sumarização):
  `https://devforum.roblox.com/t/getservice-returns-nil-if-the-service-name-doesnt-exist-but-is-a-name-used-elsewhere-in-roblox-instead-of-erroring/189063.json`
  — post #1 de Kampfkarren/boyned (2018-10-14T20:30:05Z), post #2 e #4 de Maximum_ADHD (engine reverse-engineer, mantenedor do Roblox-Client-Tracker que o LuauBench usa como fonte do dump).
- Pastebin linkado por Maximum_ADHD (`DeepStrings` do client watch dele) — consultado mas não conclusivo para os nomes exatos "Frame"/"Folder" (ver Incerto).

## 1. `game:GetService("Frmae")` (nome que não é classe nenhuma) — ERRA

**Resposta:** sim, lança erro. String exata confirmada no JSON bruto do post original (Roblox Output, formato `HH:MM:SS.mmm - <mensagem>`):

```
'Doge' is not a valid Service name
```

Aspas simples em volta do nome, "Service" com S maiúsculo, "name" minúsculo, sem prefixo `GetService:`. Generalizando para o caso pedido: `'Frmae' is not a valid Service name`.

**Confiança: alta** para a string em si (fonte primária, texto bruto, sem resumo de modelo). **Confiança média** para persistência exata até a build 0.737.0.7371584 pinada pelo LuauBench — esta string é detalhe de implementação do engine C++, não faz parte do API Dump (Dump não documenta strings de erro internas), então não há como confirmar contra o dump pinado. Não encontrei fonte datada entre 2018 e 2026 que mostre a string mudou; a doc oficial atual (2026-09-03) não contradiz.

## 2. `game:GetService("Folder"/"Part"/"Frame")` (classe real, sem tag Service) — RETORNA NIL, NÃO ERRA

**Resposta:** retorna `nil` silenciosamente. Esta é a pergunta mais crítica e a evidência é forte:

- Doc oficial atual (texto bruto, 2026-09-03): *"This function will return `nil` if the className parameter is an existing class, but the class is not a service."*
- Teste empírico reproduzido no devforum (2018, post original): `game:GetService("Motor")`, `("Part")`, `("TweenPosition")`, `("Vector3")` → todos `nil`.
- Maximum_ADHD (post #2): comportamento é "deliberado" segundo o código-fonte do engine, não é bug.
- Mecanismo real (não é "checa se é Service"): a função checa se o nome existe **em qualquer lugar** do Roblox (qualquer classe, propriedade etc.), não se é especificamente uma Service. Por isso qualquer ClassName real do dump — incluindo `Folder` e `Frame`, que existem como classe mas não têm a tag `Service` — cai em "existe, mas não é Service" → `nil`.

**Confiança: alta.** Fonte oficial atual + teste empírico + confirmação de quem faz engenharia reversa do engine convergem. Ressalva: os testes de 2018 usaram `Motor`/`Part`/`TweenPosition`/`Vector3`, não literalmente `Folder`/`Frame` — não achei teste publicado com essas duas strings exatas. A generalização para `Folder`/`Frame` vem da doc oficial ("an existing class", sem exceção por classe), não de um teste direto com esses nomes. Ainda assim, não há indício de exceção.

## 3. Outros casos além dos 3 mapeados — nenhum adicional encontrado

Não encontrei fonte confirmando comportamento diferente para: Service que existe só no cliente, erro por security context em servidor, `GetService("")`, `GetService(nil)` ou tipo errado. Pela documentação, o único caminho de erro documentado além do "nome inválido" é: *"If you attempt to fetch a service that is present under another Object, an error will be thrown stating that the 'singleton serviceName already exists'."* (texto oficial, bruto).

**Confiança: média-baixa** por ausência de evidência (não confirmei positivamente que NÃO existe caso extra — só não encontrei um). `GetService(nil)`/tipo errado provavelmente cai no erro padrão de checagem de argumento do Luau/Roblox (`invalid argument #1 (string expected, got nil)`), mas isso é inferência por padrão comum de outras APIs do Roblox, **não confirmado especificamente para GetService**.

## 4. Alias / nome legado — NÃO existe; só o ClassName exato funciona

Doc oficial (texto bruto): *"This is the only way to create some services, and can also be used for services that have unusual names, e.g. RunService's name is 'Run Service'."* — ou seja, a propriedade `Name` de `RunService` é `"Run Service"` (com espaço), mas `GetService` exige o `ClassName` (`"RunService"`), nunca o `Name`. Não há alias documentado nem encontrado em fonte nenhuma — `game:GetService("Workspace")` funciona porque `Workspace` já É o ClassName.

**Confiança: alta** (fonte oficial, bruta, direta).

## Incerto

- String exata de `GetService(nil)` / `GetService(123)` / `GetService("")` — não confirmado, apenas inferência por padrão geral do Roblox.
- Se `Folder`/`Frame` especificamente (não só `Part`/`Motor`/`Vector3`) foram testados por alguém e publicados — não encontrado.
- Se existe alguma Service com tag `Service` no dump que erra por causa de client/server context em vez de simplesmente não existir na instância `game` daquele contexto — não encontrado, tratado como não existente até prova em contrário.
