# Pesquisa — `PreRender` no servidor, capabilities reservadas e texto de erro do `RenderStepped`

`task-services-007`. Três pendências abertas em `.claude/agents-memory/arquiteto-services-2026-09-05.md`, seção "Revisão pós-pesquisa 2026-09-05 — Capabilities e RenderStepped", subseção final "Pendências novas para o pesquisador". Não implementei nada — só pesquisa.

Fontes usadas: `Full-API-Dump.json` do commit fixado `28360dea` (reaproveitado de `.cache/api-dump/28360dea.json`, 8 006 149 bytes — bate com o tamanho já registrado pelo arquiteto, não rebaixei), `raw.githubusercontent.com/Roblox/creator-docs` (`RunService.yaml`), `create.roblox.com/docs` (páginas renderizadas), DevForum (pista/corroboração, nunca fonte primária), e o repositório comunitário `Pseudoreality/Roblox-Identities` (secundário — não é doc oficial nem dump, mas é detalhado e bateu ponto a ponto com o dump e com uma citação ao vivo; tratado abaixo explicitamente como fonte secundária, nunca como confirmação sozinha).

---

## 1. `RunService.PreRender` conectado do lado servidor: erra ou "existe e nunca dispara"?

**Resposta curta: não confirmado por citação ao vivo de erro real, mas a doc oficial dá evidência direta e mais forte do que a que já sustentou a decisão de `RenderStepped` — recomendo migrar `PreRender` para `RejectingSignal` também, e digo por quê a evidência é assimétrica em relação a `BindToRenderStep`.**

### Fatos verificados

- No dump fixado `28360dea`, `RenderStepped` e `PreRender` são **idênticos** nos quatro eixos que o gerador olha: `Security: None`, `Capabilities: ["Basic"]`, sem `Tags`. O dump **não tem como resolver esta pergunta** — a restrição client/server não está codificada em nenhum campo dele, é comportamento de engine fora do que o dump expõe.
- `creator-docs` (`content/en-us/reference/engine/classes/RunService.yaml`, `main`, conferido nesta sessão), campo `description` do evento `PreRender`, citação **verbatim**:
  > "The `PreRender` event (replacement for `Class.RunService.RenderStepped|RenderStepped`) fires every frame, prior to the frame being rendered. [...] As `PreRender` is client-side, it can only be used in a `Class.LocalScript`, in a `Class.ModuleScript` required by a `Class.LocalScript`, or in a `Class.Script` with `Class.BaseScript.RunContext|RunContext` set to `Enum.RunContext.Client`."
- Em contraste, o `description` **atual** de `RenderStepped` no mesmo arquivo **não tem mais nenhum texto de restrição** — só "Fires every frame, prior to the frame being rendered." + uma "Migration Note" apontando para `PreRender`. A frase de restrição migrou de local, documentacionalmente.
- `BindToRenderStep` tem frase quase idêntica na doc ("As it is linked to the client's rendering process, `BindToRenderStep()` can only be called on the client.") — mas uma citação de DevForum antiga (thread `bindtorenderstep-doesnt-work-on-a-server-side-script-during-online-game-play`, id `182636`) reporta que, em jogo publicado real (não Studio), chamar isso do servidor **falha silenciosamente, sem erro** ("does NOT work when in a script on the server's side when playing online, and gives no errors"). Ou seja: a mesma frase de doc ("client-side, só pode em X") **não** implica sozinha um erro forte — precisa checar o mecanismo, não só o texto.
- Já para `RenderStepped` especificamente (não `BindToRenderStep`), a thread `renderstepped-does-not-error-when-connected-to-on-the-server` (DevForum, "Studio Bugs", 14/set/2024, autor cita RCC como o comportamento esperado de referência) mostra que `:Connect()` **erra em produção real (RCC)** mas não erra em Studio (bug reconhecido de Studio, ticket interno aberto por staff `thirdtakeonit` nessa mesma thread) — isso é consistente com e reforça a decisão B já tomada pelo arquiteto (RCC é a fonte de verdade, não Studio).

### Por que a assimetria importa

`PreRender`/`RenderStepped` são eventos (`:Connect()`), `BindToRenderStep` é um método que registra um callback por nome — mecanismos de enforcement diferentes na engine. A evidência de que `:Connect()` erra em RCC é sólida para `RenderStepped`; não tenho uma citação ao vivo do `:Connect()` de `PreRender` especificamente, mas a doc oficial usa a mesma gramática de restrição ("client-side, only usable in...") e `PreRender` é estruturalmente o mesmo tipo de membro (`Event`) que `RenderStepped`, não um método tipo `BindToRenderStep`. Por analogia estrutural + doc oficial explícita (mais forte que os bug trackers de 2014-2024 que sustentam `RenderStepped` hoje), recomendo tratar `PreRender` igual a `RenderStepped` (`RejectingSignal`) — mas isso é **inferência documentada, não confirmação empírica**. Se o arquiteto quiser o padrão conservador ("nunca errar sem evidência direta"), a alternativa é manter `PreRender` como está até haver uma citação ao vivo do `:Connect()` no servidor.

### Incerto

- Nenhuma citação ao vivo (DevForum, bug tracker) de alguém conectando `PreRender:Connect()` num script de servidor e reportando o resultado exato (erro vs. silêncio). Busquei especificamente por isso e não achei.
- Um tópico de 2021–2025 (`prerender-does-not-work`, comentário de nov/2025: "We are in 2025 and the problem is still here") indica que os "eventos novos" (`PreRender`/`PreSimulation`/`PreAnimation`/`PostSimulation`) tiveram histórico de rollout por feature flag incompleto para alguns usuários — não é sobre client/server, é sobre o evento não disparar em alguns clientes mesmo no contexto certo. Tangencial, mas mostra que testar isso ao vivo hoje pode dar resultado inconsistente dependendo da build.

---

## 2. `InternalTest` e `RemoteCommand` bloqueiam um script comum não-sandboxed?

**Resposta curta: sim para os dois. `InternalTest` tem citação de erro real ao vivo (fecha o critério sozinho, conforme o texto da task). `RemoteCommand` não tem citação de "lacking capability" ao vivo, mas tem evidência direta do dump + explicação secundária detalhada e consistente — mantenho os dois na lista `reserved`.**

### `InternalTest` — CONFIRMADO por citação real

- DevForum, thread "What is 'Misprediction' rbx event in RunService?" (`devforum.roblox.com/t/what-is-misprediction-rbx-event-in-runservice/4319943`), post de **31/jan/2026** por um usuário comum (`DificultyX`, não é staff), erro **verbatim** (confirmado por duas buscas independentes do mesmo tópico, inclusive via o endpoint `.json` do Discourse, que devolveu o texto cru dos posts):
  > "The current thread cannot connect 'Misprediction' (lacking capability InternalTest)"
- Resposta de outro usuário (`ridwan`) na mesma thread: "InternalTest is a ScriptCapability used by ROBLOX engineers. It was introduced in 2025." — coerente com o mecanismo.
- **Discrepância a registrar**: o dump fixado `28360dea` declara `RunService.Misprediction` com `Capabilities: ["Basic", "PluginOrOpenCloud"]` (verifiquei direto no JSON nesta sessão) — **não** menciona `InternalTest`. O erro ao vivo de 2026 cita `InternalTest` como a capability faltante, não `PluginOrOpenCloud`. Duas explicações possíveis, não distinguidas por esta pesquisa: (a) o requisito real de `Misprediction` mudou depois do commit do dump e passou a exigir `InternalTest` também (dump desatualizado nesse membro específico); (b) o erro reporta só a *primeira* capability faltante de uma lista maior que o próprio dump não capturou por completo. **Não muda a conclusão prática** (`Misprediction` já saía do schema por `PluginOrOpenCloud` de qualquer forma, que já está em `reserved`), mas é um sinal de que o dump pode divergir da imposição ao vivo em membros específicos — vale uma nota de cautela geral, não uma correção pontual.

### `RemoteCommand` — sem citação "lacking capability" ao vivo, mas fechado por evidência direta + secundária

- Busquei especificamente por `"lacking capability RemoteCommand"` (DevForum e geral) e não achei nenhuma ocorrência real — os resultados foram todos ruído (SSH `RemoteCommand`, ferramentas não relacionadas).
- Evidência direta do dump `28360dea` (conferida nesta sessão): `RemoteCommandService` tem `Tags: ["NotCreatable", "Service"]` e quatro métodos com **`Security: None` mas `Capabilities: ["RemoteCommand"]`** (`GetExecutingPlayer`, `GetReceivedUpdateSignal`, `GetStoppingSignal`, `SendUpdate`) — exatamente o padrão "só a capability bloqueia, `Security` sozinho deixaria passar" que a Decisão A.3 do arquiteto identificou como o caso que precisa do eixo novo. Os demais membros do serviço são `RobloxScriptSecurity`/`RobloxSecurity` (já bloqueados por `Security`, `Tags: ["Hidden"]` na maioria dos eventos) — a família de nomes (`CommandSentFromStudio`, `UpdateSentFromRcc`, `OneshotCommandResultFromRcc`) deixa claro que é um canal de controle Studio↔RCC, não algo que um script de jogo comum chamaria.
- Fonte **secundária, não oficial** (`github.com/Pseudoreality/Roblox-Identities`, repositório comunitário de documentação de identidades/capabilities — tratado aqui só como corroboração, nunca como prova sozinha): o arquivo `Capabilities/59 - RemoteCommand.md` diz que a capability é "granted to `GameScript` when executed by `RemoteCommandService.ExecuteCommand`, `RemoteCommandService.ExecuteCommandAsync`, and `ExecutedRemoteCommand.RunMoreCode`" — ou seja, um `Script`/`LocalScript` comum rodando do jeito normal **não** tem `RemoteCommand`; só tem se estiver executando especificamente dentro do mecanismo de Remote Command. O mesmo arquivo cita a família de erro específica desse eixo (**diferente** da família genérica "lacking capability"): `"x can only be called from within an executed command"`. O arquivo `Identities/02 - GameScript.md` do mesmo repositório confirma: `RemoteCommand` só está disponível "if executed via `RemoteCommandService` or `ExecutedRemoteCommand:RunMoreCode()`", e `InternalTest` só "if `FFlagDebugLocalPluginsElevatedForInternal` is true and Internal Permission is enabled" (flag interna, normalmente desligada — explica por que o `DificultyX` de 2026 tomou o erro).
- **Conclusão prática**: mantenho `RemoteCommand` na lista `reserved` de `tools/capabilities.lock.json`. O critério do texto da task ("uma citação com qualquer um dos dois fecha") já está satisfeito por `InternalTest` sozinho; `RemoteCommand` fica sustentado por evidência direta do dump + fonte secundária convergente, não por citação `"lacking capability"` ao vivo — differença que registro explicitamente porque a fonte secundária sugere que o erro real para esse eixo pode ter texto **diferente** da família `"lacking capability X"` (ver acima).

### Incerto

- Não achei citação `"lacking capability RemoteCommand"` ao vivo. Se aparecer uma no futuro, confirma com o mesmo padrão do restante; se o texto real for a família `"can only be called from within an executed command"` citada pela fonte secundária, isso é uma família de erro distinta que vale documentar separadamente se o LuauBench algum dia precisar simular a mensagem exata (não é o caso agora — o gerador só usa isso para decidir inclusão/exclusão, não para reproduzir a string).
- `Pseudoreality/Roblox-Identities` é comunitário, não citei nada dele como fato isolado — só onde bateu com dump e/ou citação ao vivo independente.

---

## 3. Texto atual (2026) da recusa de `RenderStepped` conectado no servidor

**Resposta curta: não confirmado ao vivo. Nenhuma fonte de 2025/2026 encontrada cita o texto exato de um erro real de servidor. A string de bug trackers de 2014–2024 continua sendo a melhor pista disponível, e há um motivo novo para desconfiar que ela pode ter mudado de família.**

### Fatos verificados

- Busquei repetidamente (`"RenderStepped" "can only be used from local scripts"`, variações com `2025`/`2026`, `"lacking capability"` + `RenderStepped`, threads específicas de 2024-2025 sobre o assunto) e **nenhuma** citação ao vivo de 2025/2026 traz o texto exato de um erro de servidor real (RCC) para `RenderStepped`. As únicas ocorrências da frase `"RenderStepped event can only be used from local scripts"` continuam sendo as três já citadas no relatório anterior do pesquisador (`Anaminus/roblox-bug-tracker` #636 e #365, `ROBLOX/Studio-Tools` #14 — todas de 2014-2015).
- A thread de 14/set/2024 (`renderstepped-does-not-error-when-connected-to-on-the-server`) **confirma que o erro acontece em RCC** (o autor usa RCC como a referência do comportamento esperado, em contraste com o bug de Studio), mas **não cita o texto** do erro — só descreve que ele existe.
- Achado novo relevante: a doc oficial (`RunService.yaml`, `main`) **removeu** o texto de restrição da descrição de `RenderStepped` e moveu para `PreRender` (ver seção 1). Isso é uma mudança de *documentação*, não necessariamente de *mensagem de erro em runtime* — mas é coerente com a hipótese de que a família de erro pode ter migrado do formato antigo em inglês solto ("X event can only be used from local scripts") para o formato novo de capability introduzido por volta de 2024-2025 ("The current thread cannot connect 'X' (lacking capability Y)"), já confirmado ao vivo para `Misprediction` (seção 2). Não encontrei nenhuma citação que confirme ou descarte isso para `RenderStepped` especificamente — é uma hipótese, não um fato.

### Recomendação

Manter a string atual (`"RenderStepped event can only be used from local scripts"`) com o comentário de "aproximação de boa-fé" já existente, **sem** trocar para o formato de capability — não há evidência de qual dos dois formatos é o real hoje, e trocar por suposição seria o mesmo erro que a Decisão 3 evita para o eixo de capabilities. Se o `testador`/`cli` algum dia rodar um smoke test contra um servidor Roblox real publicado, essa é a única forma de fechar esta pendência — pesquisa documental não chega lá.

### Incerto

- Texto exato vivo em 2025/2026, para `RenderStepped` especificamente, não confirmado.
- Se a família migrou para o formato de capability, não confirmado.

---

## Recomendações consolidadas para o arquiteto

1. **`PreRender`**: evidência documental oficial (não só inferência) aponta para tratar igual a `RenderStepped` (`RejectingSignal`) — mas não é confirmação empírica de erro ao vivo. Decisão de risco a tomar explicitamente: doc diz "client-side only" com a mesma força que já usamos para `BindToRenderStep` (que na prática falha silencioso, não erra) — a analogia estrutural (`Event`/`:Connect()` como `RenderStepped`, não método como `BindToRenderStep`) é o argumento a favor de errar; a ausência de citação ao vivo é o argumento contra.
2. **`tools/capabilities.lock.json`**: nenhuma mudança na lista `reserved` (`InternalTest`, `PluginOrOpenCloud`, `RemoteCommand`) — os três continuam corretamente fora do que um script comum detém. `InternalTest` agora tem citação real; `RemoteCommand` continua sustentado por dump + fonte secundária, não por citação `"lacking capability"` ao vivo.
3. **Nota de cautela nova, não bloqueante**: o dump fixado `28360dea` pode já estar levemente desatualizado em relação à imposição de capability ao vivo em membros específicos (caso `Misprediction`/`InternalTest`, seção 2). Não é motivo para reabrir o congelamento de versão (regra `03-services-api-dump.md`), só um registro de que "dump diz X" e "produção real exige X" podem divergir pontualmente — o comentário de código para membros excluídos por capability já devia dizer "conforme o dump fixado", e isso reforça que essa relativização é a correta.
4. **Texto de erro de `RenderStepped`**: sem mudança — manter a string atual como aproximação de boa-fé, comentada como não verificada ao vivo em 2026.
