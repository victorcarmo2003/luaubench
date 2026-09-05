## Pesquisa — SignalBehavior (Immediate/Deferred) e WaitForChild por rename

Tarefa: `task-runtime-010`. Contexto: `.claude/agents-memory/arquiteto-runtime-2026-09-04.md`, seções "Fidelidade vs. pragmatismo (entradas novas)" e "Riscos residuais" da revisão pós-integração 2026-09-04.

---

## 1. SignalBehavior — Immediate vs Deferred

**Resposta curta:** confirmado por fonte oficial: hoje (`Default`) o comportamento efetivo em lugares/experiências já existentes ainda é `Immediate` — resume síncrono, dentro da própria pilha de quem disparou o evento. Mas `Deferred` já é o valor explicitamente aplicado por padrão em **lugares novos** (templates), é o modo **recomendado pela própria Roblox** para todo projeto, e `Default` está documentado como destinado a virar `Deferred` no futuro. A decisão do LuauBench de implementar `Immediate` bate com o comportamento real de hoje para projetos legados, mas diverge do que a Roblox recomenda e do rumo declarado da engine — isso precisa ficar dito explicitamente na nota de fidelidade, não só implícito.

**Fatos verificados** (fonte primária: `Roblox/creator-docs`, o repositório-fonte de `create.roblox.com/docs`; a renderização em `create.roblox.com/docs/scripting/events/deferred` não foi acessível diretamente por bloqueio de rede do WebFetch neste ambiente, então usei o markdown-fonte idêntico via `raw.githubusercontent.com`, mesmo conteúdo, mesmo repositório oficial):

- Descrição textual exata dos itens do enum `SignalBehavior`, de `content/en-us/reference/engine/enums/SignalBehavior.yaml` (commit mais recente do arquivo: `5d2e163e`, 2025-07-24):
  - `Default`: *"The default behavior; currently equivalent to `Immediate` but this will eventually change to `Deferred`."*
  - `Immediate`: *"Event handlers are resumed immediately when the event occurs."*
  - `Deferred`: *"All events are deferred and their handlers resumed at specific resumptions points each frame."*
  - `AncestryDeferred`: *"Equivalent to `Deferred` but only for events triggered by changes in ancestry."* — item extra não pedido pela tarefa, mas relevante: existe um modo de diferimento seletivo só para eventos de ancestralidade (`AncestryChanged` e afins), separado do `Deferred` geral.
  - Fonte: `https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/enums/SignalBehavior.yaml` (via raw.githubusercontent.com) — verificado 2026-09-04, conteúdo do commit de 2025-07-24.
- Página de conceito "Deferred Engine Events", `content/en-us/scripting/events/deferred.md` (commit mais recente: `0a2389cb`, 2026-04-13):
  - Modo `Immediate`: "se um evento dispara outro evento, o segundo handler dispara imediatamente" (dentro da mesma pilha).
  - Modo `Deferred`: "o segundo evento é colocado no fim de uma fila e roda depois"; handlers diferidos são "resumidos no próximo ponto de retomada (*resumption point*), junto com quaisquer handlers recém-disparados".
  - "Resumption points" = pontos específicos do ciclo de vida da engine onde Luau pode rodar. Lista explícita de pontos de retomada citados na página: processamento de input (`UserInputService`), `RunService.PreRender`, `wait()`/`spawn()`/`delay()` legados, `RunService.PreAnimation`, `RunService.PreSimulation`, `RunService.PostSimulation`, `task.wait()`/`task.spawn()`/`task.delay()`, `RunService.Heartbeat`, `DataModel.BindToClose`.
  - Lugares novos (template places): `SignalBehavior` **já vem setado diretamente para `Enum.SignalBehavior.Deferred` por padrão** — não é `Default`, é o valor explícito.
  - `Default` (o que lugares existentes/legados têm se ninguém tocar em `Workspace.SignalBehavior`) é hoje equivalente a `Immediate`, com mudança futura documentada para equivaler a `Deferred`.
  - Recomendação explícita da documentação: `Deferred` é a opção recomendada, citada como melhoria de performance e "correção" (correctness) da engine.
  - Fonte: `https://github.com/Roblox/creator-docs/blob/main/content/en-us/scripting/events/deferred.md` (via raw.githubusercontent.com) — verificado 2026-09-04, conteúdo do commit de 2026-04-13.
- **Diferença Wait() vs Connect():** a documentação-fonte **não distingue** os dois — o texto trata "event handlers" de forma unificada (tanto callback via `Connect` quanto a retomada de uma coroutine suspensa em `Wait`) como sujeitos às mesmas regras de resumption point sob `Deferred`. Não há seção separada nem nota de exceção para `Wait()`. Ou seja: sob `Deferred`, uma thread presa em `Event:Wait()` também só é retomada no próximo resumption point, exatamente como um callback de `Connect` — não achei, na fonte oficial, nenhuma ressalva de que `Wait()` seja tratado diferente.

**Exemplo mínimo** (o que muda na prática, conforme a doc, para um script que depende de ordem):
```luau
-- Sob Immediate: B roda dentro da pilha de A, antes de A continuar.
-- Sob Deferred: B só roda no próximo resumption point, depois que A (e tudo mais
-- na pilha atual) terminar.
signalA:Connect(function()
    signalB:Fire() -- dispara handler de B
    print("A: depois do Fire de B")
end)
```

**Limites e pegadinhas**
- `Default` não é um terceiro comportamento — é um alias que hoje resolve para `Immediate`, mas a doc avisa explicitamente que essa resolução é temporária e vai mudar. Um projeto que lê `Workspace.SignalBehavior == Enum.SignalBehavior.Default` e assume "logo é Immediate para sempre" está construindo sobre uma premissa que a própria Roblox documenta como transitória.
- Existe um quarto modo (`AncestryDeferred`) que dá granularidade fina só para eventos de ancestralidade — relevante porque o desenho do runtime já assume uma ordem específica para `AncestryChanged` (ver risco separado "Ordem exata de eventos ao reparentar" no arquivo do arquiteto); se o LuauBench algum dia migrar para `Deferred`, `AncestryDeferred` é uma variante que pode interagir com aquele risco e vale uma nota cruzada quando essa outra pendência for pesquisada.
- Não confirmei (fora de escopo desta tarefa) se há diferença de comportamento entre `RunService.Heartbeat`/`Stepped` como resumption points versus outros — a lista de resumption points foi copiada tal como está na doc, sem verificação cruzada linha a linha contra o comportamento real de cada um.

**Incerto**
- Não confirmei a data exata em que `Deferred` passou a ser o padrão de lugares novos (a doc não traz uma data, só o commit mais recente do arquivo, 2026-04-13, que pode ser só uma atualização de texto, não da mudança de comportamento em si).
- Não encontrei declaração oficial (docs ou dump) sobre quando/se `Default` efetivamente vai mudar de `Immediate` para `Deferred` para lugares já existentes — a doc só diz "eventually", sem prazo.

---

## 2. WaitForChild — resolve por rename de filho já existente?

**Resposta curta: NÃO CONFIRMADO.** Nem a documentação oficial (`create.roblox.com/docs` / `Roblox/creator-docs`) nem o Roblox API Dump descrevem o mecanismo interno de resolução de `WaitForChild` com esse nível de detalhe. A implementação atual do LuauBench (só escuta `ChildAdded`) **não pode ser confirmada nem refutada** contra fonte primária nesta pesquisa. O que existe é uma inferência razoável, apoiada em comportamento documentado de eventos adjacentes — reportada abaixo claramente separada como inferência, não fato.

**Fatos verificados**
- Descrição oficial de `Instance:WaitForChild`, de `content/en-us/reference/engine/classes/Instance.yaml` (commit mais recente do arquivo inteiro: `847353f2`, 2026-09-03 — bem recente): *"Returns the child of the Class.Instance with the given name. If the child does not exist, it will yield the current thread until it does."* Não há nenhuma cláusula sobre rename, nem sobre qual evento interno dispara a resolução.
- Descrição oficial de `Instance.ChildAdded`: *"Fires after an object is parented to this Class.Instance."* — fala especificamente de **parenting**, não de mudança de propriedade `Name` de um filho já parenteado.
- `Instance.FindFirstChild` (consultada para cruzar referência): nenhuma menção a rename ou a interação com `WaitForChild`.
- Fonte: `https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/Instance.yaml` — verificado 2026-09-04.
- Busquei também no fórum oficial (DevForum) por alguma resposta de staff da Roblox ou thread técnica definitiva sobre o mecanismo interno — **nenhuma thread encontrada contém confirmação de staff ou explicação de engenharia interna** sobre `WaitForChild` reagir (ou não) a rename. As threads revisadas (ex.: `devforum.roblox.com/t/waitforchild-just-waiting-even-though-child-is-already-there/2545410`) discutem só o caso trivial de "o filho já existe, então não há espera" — não o caso de um filho existente sob outro nome sendo renomeado enquanto alguém espera.

**Exemplo mínimo**
Não aplicável — não há comportamento confirmado para demonstrar.

**Limites e pegadinhas**
- Inferência (marcada como tal, **não fato confirmado**): a documentação separa claramente dois canais de notificação em `Instance` — mudança de hierarquia (`ChildAdded`/`ChildRemoved`, disparado por operação de parenting) e mudança de propriedade (`Changed`/`GetPropertyChangedSignal`, disparado por qualquer set de propriedade, incluindo `Name`). Renomear um filho já parenteado dispara `Changed("Name")`/`GetPropertyChangedSignal("Name")` no próprio filho — não há, na documentação, nenhuma indicação de que isso também dispare `ChildAdded` no pai (o filho não foi reparenteado, só teve uma propriedade alterada). Com base só nessa separação documentada de canais, a inferência de engenharia mais provável é que `WaitForChild`, implementado sobre o mesmo mecanismo de `ChildAdded`, **não** reagiria a um rename — mas isso é dedução, não teste contra o Roblox real nem confirmação de fonte primária ou staff.
- Se essa dedução estiver certa, a implementação atual do LuauBench (só `ChildAdded`) já bateria com o Roblox real neste ponto específico — mas o risco residual documentado pelo arquiteto continua tecnicamente correto em dizer "não coberto nem confirmado", porque esta pesquisa não elevou a inferência a fato.

**Incerto**
- Se renomear um filho já existente para o nome esperado resolve um `WaitForChild` pendente no Roblox real — **não confirmado por nenhuma fonte primária ou oficial**. Só há dedução por engenharia a partir da separação documentada entre eventos de hierarquia e eventos de propriedade.
- Se existe alguma diferença de comportamento entre client/server ou entre `Deferred`/`Immediate` para esse cenário específico de rename — não pesquisado (fora do escopo, e a pergunta 1 acima já é sobre esse eixo separadamente).
- Teste empírico direto no Roblox real (Studio) resolveria isso de forma definitiva e rápida — não foi feito nesta pesquisa porque a tarefa pede fonte documental/API Dump, não reprodução em Studio.

---

## Recomendação para o desenho do runtime

1. **Nota de fidelidade sobre `SignalBehavior` precisa mudar de redação.** O texto atual ("Escolhido `Immediate` porque... é o comportamento que os 30 testes existentes já assumem... A correspondência exata Immediate/Deferred não foi confirmada nesta sessão — pendência de pesquisador") deve ser atualizado para deixar de tratar isso como incerteza e passar a registrar como **divergência documentada e deliberada**: `Immediate` bate com o comportamento de `Default` em lugares/projetos legados hoje, mas diverge do padrão de lugares novos (`Deferred` explícito) e da recomendação oficial da Roblox. Isso não é um "não sei", é um "sei e decidi diferente por ora" — o arquivo do arquiteto já tem o gancho certo (a política de resume vive isolada em `Driver.Resume`, então migrar depois é troca localizada), só falta a frase deixar de soar como pendência de pesquisa e passar a soar como trade-off assumido, com a fonte desta pesquisa citada.
2. **Não migrar para `Deferred` agora** continua a decisão certa (já estava em "O que deliberadamente NÃO fazer agora") — não há confirmação de urgência real, e a arquitetura já isola o ponto de troca. Mas vale adicionar uma frase citando que `Deferred` é o que a própria Roblox recomenda para projetos novos, para que quem ler o desenho no futuro entenda que essa é uma dívida técnica consciente, não uma escolha neutra.
3. **`WaitForChild` por rename continua como risco residual em aberto — não fechar a pendência.** Esta pesquisa não encontrou fonte primária que confirme ou refute o comportamento; a única coisa nova é uma inferência de engenharia (separação `ChildAdded` vs `Changed`) que sugere que a implementação atual provavelmente já está correta, mas "provavelmente" não é o padrão de evidência que o projeto exige (regra de invariante 1/2: fidelidade contra o dump/comportamento real, divergência sempre declarada). Recomendo manter a tarefa de fechar isso como validação empírica direta no Roblox Studio (não documental) antes de qualquer mudança de código, ou aceitar o risco residual como está, documentado exatamente como já está no arquivo do arquiteto, sem reescrever a redação como se fosse fato confirmado.
