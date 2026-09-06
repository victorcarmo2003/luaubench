# Revisão — task-services-022 (HttpService sub-leva A + registro de MessagingService no gerador)

Data: 2026-09-06. Revisor: `revisor-services` (read-only). Metodologia: nenhuma alegação do coder foi aceita sem reprodução direta — toda claim abaixo foi checada rodando código, não lendo relatório.

## O que foi verificado, e como

1. **Suíte completa de `src/services/` + `tools/`**: rodei `lune run` em cada um dos 27 arquivos `.spec.luau` do território (listagem via glob, não a lista do coder). Resultado: **337/337, 0 falhas, 27/27 arquivos**. Bate exatamente com a alegação (`HttpService.spec` 21/21, `MessagingService.spec` 11/11, `Index.spec` 14/14, `generate-services.spec` 19/19).

2. **`game:GetService("MessagingService")`/`("HttpService")` via caminho real**: escrevi um script próprio (`_revisor_verify1.luau`, fora de `src/`, apagado ao final) chamando `Services.Register()` + `Services.Bootstrap()` + `game:GetService(...)` — sem tocar nenhum spec do coder. Ambos devolvem instância (`ClassName` correto). Fiz também um round-trip `SubscribeAsync`/`PublishAsync` via `GetService` puro: entregou a mensagem (eco local fiel).

3. **Detecção de ciclo em `JSONEncode`**: reproduzi eu mesmo (`_revisor_verify2.luau`): auto-referência (`t.self = t`) erra com "cyclic reference"; ciclo mútuo de dois níveis (`a.b = b; b.a = a`) também erra; duas referências IRMÃS não-cíclicas à mesma subtabela **não** erram (prova que não é falso positivo por overengineering). Bate exatamente com o spec e com a alegação.

4. **Round-trip JSON e JSON inválido**: `JSONEncode`/`JSONDecode` fazem round-trip correto; `JSONDecode("{not valid json")` erra (nunca `nil`), mensagem retraduzida ("Unable to parse JSON: ...").

5. **`UrlEncode` contra o exemplo oficial**: confirmei eu mesmo lendo `.claude/agents-memory/pesquisa-http-messaging-2026-09-05.md` linha 94 (fonte independente do código do coder): `"https://www.roblox.com/discover#/"` → `"https%3A%2F%2Fwww%2Eroblox%2Ecom%2Fdiscover%23%2F"`. Rodei a função de verdade — bate caractere a caractere.

6. **`GenerateGUID`**: com/sem chaves, formato `8-4-4-4-12` hex minúsculo confirmado por regex, funciona com `HttpEnabled == false` (não chama `assertHttpEnabled`).

7. **`HttpEnabled`**: lê `false` por padrão; escrever por dentro do schema (`httpService.HttpEnabled = true`) erra "Property is read only" — é `ReadOnly` **gerado pelo schema** (`Security.Write = LocalUserSecurity`), sem `Behavior` explícito nenhum — confirmei lendo `generated/classes/HttpService.luau` (`ReadOnly = true` no `Schema`) e rodando a escrita real.

8. **`GetAsync`/`PostAsync`/`RequestAsync`**: erram "Http requests are not enabled..." com `HttpEnabled == false`. Forcei `HttpEnabled = true` via `Runtime.Instance.SetPropertyRaw` (a mesma via de engenharia que a spec usa) e confirmei que a mensagem **muda** para `[LuauBench] HttpService:GetAsync() ... not simulated by LuauBench yet (see task-services-026)` — prova concreta de que a checagem lê a propriedade de verdade via `GetPropertyRaw`, não é hardcoded.

9. **`grep "@lune/net"` em `HttpService.luau`**: só aparece dentro de um comentário (linha 9, explicando a ausência); nenhum `require("@lune/net")` real.

10. **`MessagingService.spec.luau` — padrão antigo removido de verdade**: `git diff` mostra a remoção literal de `local ClassBuilder = require("../ClassBuilder")`, da construção manual de `Types.GeneratedClass` e da chamada `Runtime.ClassRegistry.Register(ClassBuilder.Build(...))`, substituídos por `Services.Register()` + `game:GetService("MessagingService")`. Não é comentário — é código removido/substituído.

11. **`--!strict`/sem `any`**: todos os arquivos tocados (produção e teste) começam com `--!strict`; grep por `\bany\b` não encontrou uso real (só menções em comentário "nunca `any`").

12. **Território limpo**: `git status` mostra só `src/services/**`, `tools/coverage.luau`, `tools/generate-services.spec.luau`, `.claude/tasks.json`. `src/cli/TreeMaterializer.spec.luau` modificado pertence ao agente concorrente `task-cli-027` (nota de concorrência confirmada — nada de `services` vazou pra lá, e nada de `cli`/`runtime`/`valuetypes` foi tocado por este coder). Diffs de `generated/Index.luau`/`Manifest.luau` são exatamente as 2 linhas esperadas (adicionar `HttpService`/`MessagingService`), nada mais mudou — prova de regeneração limpa, não edição manual.

13. **Fatos do dump confirmados por fonte independente** (`.cache/api-dump/28360dea....json`, não o texto do coder): `JSONDecode(input: string): Variant` (ReturnType `{Category: "Group", Name: "Variant"}`); `HttpService`/`MessagingService` ambas `["NotCreatable", "Service", ...]`, `Superclass: "Instance"` — bate com `IsAbstract=true`/`IsService=true`/`Superclass="Instance"` nos arquivos gerados.

## Achados

### BAIXO — tipo de retorno gerado de `JSONDecode` é mais estreito que a realidade (herdado, não introduzido nesta tarefa)
`src/services/generated/classes/HttpService.luau:22`: `JSONDecode` está tipado `(self, input: string) -> { [string]: unknown }`, mas o dump diz `ReturnType = Variant` (`Category: "Group", Name: "Variant"`) — ou seja, o retorno real pode ser array, string, número ou bool, não só dicionário. A implementação em `Methods.JSONDecode` já devolve `unknown` (correto); só o TIPO PÚBLICO exportado mente.
**Causa raiz**: `tools/generate-services.luau`, função `luauReturnType` (código PRÉ-EXISTENTE, não tocado por task-services-022) — o branch `Category == "Group"` só distingue `"Tuple"`/`"Array"`; qualquer outro nome (`"Variant"`, `"Dictionary"`, etc.) cai no mesmo `else` e vira `{ [string]: unknown }`. Confirmei que esse mesmo padrão já existe em classes aprovadas em tarefas anteriores (`GlobalDataStore.SetAsync`, `DataStoreKeyInfo.GetMetadata`, `Instance.GetAttributes`, etc.) — não é uma regressão desta tarefa, é uma simplificação sistêmica já aceita no gerador.
**Cenário de falha**: um script faz `local arr = httpService:JSONDecode('[1,2,3]')` e tenta `arr[1]` — no Luau, o tipo declarado `{ [string]: unknown }` não expressaria isso corretamente para quem depende de checagem estática (embora em runtime funcione, porque é só `unknown` por trás).
**Correção sugerida**: separar `"Variant"` de `"Dictionary"` em `luauReturnType`, emitindo `unknown` para `"Variant"` (mais honesto que uma forma de dicionário fixa). Fora do escopo desta tarefa — registrar como tarefa própria contra `tools/generate-services.luau`.

### BAIXO — nível de `error(..., 2)` nos helpers de validação aponta pra dentro do módulo de `services`, não pro script do usuário (padrão sistêmico pré-existente)
Reproduzi: `httpService:GetAsync(...)` com `HttpEnabled=false` erra citando `src\services\behavior\HttpService:331` (linha de `assertHttpEnabled` dentro do módulo), não a linha do script que chamou `GetAsync`. `assertHttpEnabled`/`assertValidTopic`/`assertValidMessage` usam nível 2 (culpa quem chamou a função de validação, não quem chamou o método público). O comentário do próprio código admite que é "mesma convenção já em uso" por `GlobalDataStore.luau`/`MessagingService.luau` — não é uma escolha nova desta tarefa, é consistência com o que já existe.
Regra 01 pede "linha do script do usuário quando disponível" — este padrão sistemicamente não entrega isso para NENHUM `Methods.*` do território, não só `HttpService`. Não é bloqueante para task-services-022 especificamente (mudar só aqui criaria inconsistência com o resto do território); registrar como possível ação futura de higiene sobre TODO o território `services`, não uma pendência desta tarefa.

### Avaliação das 3 divergências declaradas (pedido explícito do despacho)
1. **Ciclo em `JSONEncode` corrigido à mão** (detecção própria antes de delegar a `serde.encode`): decisão CORRETA. `serde.encode` do Lune omite a chave cíclica em silêncio — deixar isso passaria uma divergência SILENCIOSA (dado mudando de forma sem erro), exatamente o que a regra 00 proíbe. Reproduzi e confirmei que a implementação não gera falso positivo em referência compartilhada não-cíclica (diamond/DAG).
2. **`inf`/`NaN` → `null` do `serde`, NÃO corrigido, só declarado**: decisão CORRETA e já pré-aprovada pelo próprio arquiteto na tabela L2.2.5 ("declarada em vez de silenciada"). Corrigir exigiria um encoder JSON autoral, fora do escopo explícito da tarefa ("JSON sobre `@lune/serde`"). Reproduzi: `JSONEncode({x = 1/0})` devolve `{"x":null}`.
3. **Tabela vazia `{}` → objeto `"{}"`, não array `"[]"`, NÃO corrigido, só declarado**: mesma lógica do item 2, achado novo desta tarefa mas tratado com a mesma disciplina (declarar, não silenciar, não overengenheirar um encoder próprio pra um caso de baixo impacto). Reproduzi: `JSONEncode({})` devolve `"{}"`.

Nenhuma das 3 é um problema de julgamento — são exatamente as decisões que a regra 00 e a arquitetura da leva pedem.

## Não encontrado / não aplicável
- Nenhuma superfície de API inventada fora do dump — toda propriedade/método novo bate com `.cache/api-dump/28360dea....json` (`HttpEnabled`, `JSONEncode`, `JSONDecode`, `UrlEncode`, `GenerateGUID`, `GetAsync`, `PostAsync`, `RequestAsync`, `GetSecret`, `CreateWebStreamClient`, `PublishAsync`, `SubscribeAsync`) — confirmado por leitura direta do dump cacheado, não por confiança no relatório do coder.
- Nenhuma chamada de rede real (`@lune/net`) em `HttpService.luau`.
- Nenhum stub silencioso — `GetSecret`/`CreateWebStreamClient` erram alto via `ClassBuilder`, testado.
- `--!strict`/zero `any` real em todos os arquivos tocados.
- Território limpo (fora do que pertence ao agente concorrente de `cli`).

## Veredito

**APROVADO**

Todos os itens do acceptance de task-services-022 foram reproduzidos independentemente (não só lidos do relatório do coder), incluindo os pontos "críticos" pedidos (GetService real de MessagingService, detecção de ciclo com auto-referência E ciclo mútuo, mudança de mensagem de erro ao forçar HttpEnabled via SetPropertyRaw). As duas ressalvas (BAIXO) são limitações sistêmicas pré-existentes do gerador/convenção de erro do território, não introduzidas por esta tarefa, e não afetam o acceptance declarado.
