# Revisão — task-runtime-021 (resolução de filho por nome em `__index`)

Data: 2026-09-05. Arquivos revisados: `src/runtime/Instance.luau`, `src/runtime/Instance.spec.luau`. Escopo confirmado via `git status --short src/runtime/` — nenhum outro arquivo do território foi tocado.

## Achado mais importante: pesquisa `task-services-006` terminou DURANTE esta revisão

`.claude/agents-memory/pesquisa-member-vs-child-2026-09-05.md` **não existia** no início desta revisão (`task-services-006` estava `in-progress`) e apareceu no meio do trabalho. Lido na íntegra assim que detectado.

**Veredito da pesquisa sobre a pergunta que importa para `task-runtime-021`:**

> "Membro vence filho em colisão? **SIM, confirmado por fonte oficial.**"

Citação literal da doc oficial (`Roblox/creator-docs`, `content/en-us/reference/engine/classes/Instance.yaml`, seção `FindFirstChild`):
> "Sometimes the `Name` of an object is the same as that of a property of its `Parent`. When using the dot operator, properties take precedence over children if they share a name."

Isso **CONFIRMA**, não contradiz, a hipótese implementada em `Instance.luau` (`propertyValue` checado antes de `FindFirstChild`, campos fixos/sinais/métodos checados antes disso ainda). A ordem que o coder implementou (passos 1-4, 6, 7, fallback leniente do 8, conforme a Decisão 4 do arquiteto) está **factualmente correta**, não apenas plausível. Não há achado GRAVE/ALTO aqui — o cenário que o usuário pediu para vigiar (hipótese contradita) **não se materializou**.

Nota BAIXA não-bloqueante para quem pegar `task-runtime-018` a seguir: o comentário de hipótese em `Instance.luau:568-585` ainda diz "HIPÓTESE NÃO CONFIRMADA... NÃO tinha respondido no momento em que este código foi escrito" — isso ficou desatualizado agora que a pesquisa existe e confirma. Não bloqueia esta aprovação (o comentário estava correto no momento em que foi escrito, é exatamente o protocolo pedido), mas `task-runtime-018` deveria trocar esse comentário por uma citação da confirmação em vez de deixá-lo dizendo "não confirmado" para sempre.

**Achados da mesma pesquisa que NÃO dizem respeito a este território (`Instance.luau`) mas são relevantes para o board:**
- 4a: a premissa do desenho de que `Script.Source` é bloqueada por `PluginSecurity` está factualmente errada — o dump mostra `Security: None`, o bloqueio real é via `Capabilities: PluginOrOpenCloud`. A conclusão prática (fora do schema) continua certa, só a justificativa erra. Mais grave: a Decisão 3 do gerador (services) não verifica `Capabilities` nenhuma — lacuna real que pode vazar propriedades indevidas no schema de `task-services-002`.
- 4b: `RunService.RenderStepped` "existe e nunca dispara" (decisão do arquiteto) reproduz um **bug do Studio**, não o comportamento do servidor de produção real (que erra ao conectar). Recomendação da pesquisa: mudar a decisão ou declarar explicitamente que o LuauBench imita o Studio, não o RCC real.

Isso é território de `services`/arquiteto, fora do meu escopo de revisão (`src/runtime/`), mas repasso porque o usuário pediu vigilância ativa sobre essa pesquisa e o achado é real, só não incide sobre `task-runtime-021`.

## Verificação item a item (pedida explicitamente)

1. **34 testes originais intactos** — confirmado por `git diff -- src/runtime/Instance.spec.luau`: o único hunk começa no contexto da linha 576 (logo após o teste 34, "instância criada por NewBase direto..."); as primeiras ~575 linhas são byte-idênticas ao `HEAD` (`edacf7e`). `grep -c '^test('` bate 34 (HEAD) → 42 (working tree). Rodei os 8 arquivos de spec do runtime via `lune 0.10.5` real: `Instance.spec.luau` 42/42, `Signal.spec.luau` 7/7, `Scheduler.spec.luau` 16/16, `Integration.spec.luau` 9/9, `ClassRegistry.spec.luau` 17/17, `DataModel.spec.luau` 9/9, `Sandbox.spec.luau` 7/7, `init.spec.luau` 3/3. `git status --short src/runtime/` confirma que só `Instance.luau`/`Instance.spec.luau` estão modificados — os outros 7 módulos não foram tocados.

2. **`parent.Filho` em 2 e 3 níveis** — confirmado pelos testes do coder e por script de verificação independente que escrevi (`_revisor_check_021.luau`, removido depois): `rs.Modules == modules` (2 níveis) e `rs.Modules.Combat == combat` (3 níveis encadeados, um `__index` por vez).

3. **Ordem de precedência com colisão real ativa** — testei eu mesmo, além dos casos do coder: propriedade (via `SetPropertyRaw`) vence filho homônimo `"Combat"`; campo fixo `Name` vence filho homônimo `"Name"`; método base `Destroy` vence filho homônimo `"Destroy"`; **e um caso a mais que o coder não tinha testado**: método de classe concreta (via `SetClassMethods`) também vence filho homônimo `"Raycast"` — confirmado, o filho fica acessível só via `FindFirstChild` em todos os quatro casos. Nenhuma falha.

4. **`Parent = nil` remove da resolução por nome** — confirmado: antes de desparentar `parent.Temp == child`, depois de `child.Parent = nil`, `parent.Temp == nil`.

5. **Custo de performance aceito, registrado em comentário** — confirmado, presente no bloco de comentário logo antes do `return Methods.FindFirstChild(self, key)` em `Instance.luau` ("Custo de performance aceito nesta fase: esta busca é uma varredura LINEAR..."). Não é achado.

6. **Comentário de hipótese no lugar certo e claro** — confirmado: está imediatamente antes do `return Methods.FindFirstChild(self, key)` (o ponto exato de disparo), cita `task-services-006` pelo nome completo da tarefa, explica a ordem assumida (a) e o alcance da busca (b), e diz o que fazer se a pesquisa contradisser. Cumpre o protocolo pedido pela `task-runtime-021`. Ver nota BAIXA acima sobre atualização futura.

## Verificações adicionais

- `luau-lsp analyze --platform=standard` limpo (exit 0) em `Instance.luau` + `Instance.spec.luau`.
- Zero ocorrências de `any` fora de comentário (`grep -n '\bany\b'` só acha menções em texto de comentário, nunca em anotação de tipo).
- `__newindex` confirmado sem mudança de comportamento — só comentário novo adicionado no fallback (diff mostra isso explicitamente).

## Achados

Nenhum achado GRAVE/ALTO/MÉDIO. Um achado informativo:

```
[BAIXO] src/runtime/Instance.luau:568-585
Problema: comentário de "hipótese não confirmada" ficou desatualizado — a pesquisa que o cita (task-services-006) já terminou e CONFIRMA a hipótese por fonte oficial.
Cenário de falha: nenhum — é só documentação defasada, não afeta comportamento. Alguém lendo o código hoje pode achar que a ordem ainda é incerta quando já não é.
Correção: task-runtime-018 (próxima a tocar este trecho) deve trocar o texto por algo como "CONFIRMADO contra o Roblox real, ver pesquisa-member-vs-child-2026-09-05.md" em vez de deixar "não confirmado" apontando para uma pesquisa que já respondeu. Não bloqueia esta aprovação.
```

## Veredito
APROVADO
