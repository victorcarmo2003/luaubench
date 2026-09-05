# Revisão task-runtime-016 — Instance.SetClassMethods / ClassDescriptor.Methods (2026-09-04)

Escopo: `src/runtime/Instance.luau`, `src/runtime/Instance.spec.luau`, `src/runtime/ClassRegistry.luau`,
`src/runtime/ClassRegistry.spec.luau`. Read-only, nenhum arquivo editado.

Lido antes da revisão: `.claude/tasks.json` (task-runtime-016 completa), e
`arquiteto-runtime-2026-09-04.md`, seção "Revisão pós-integração 2026-09-04 (3) — acesso a
membro" (linhas 790-976) inteira.

## O que foi verificado ativamente (não só relato do coder)

1. **Rodei os quatro arquivos de teste eu mesmo** com o binário Lune de sempre (`lune 0.10.5`,
   `/c/Users/hakor/.rokit/bin/lune`):
   - `Instance.spec.luau`: **33/33** (confirmado, exit 0).
   - `ClassRegistry.spec.luau`: **17/17** (confirmado, exit 0).
   - Regressão: `Signal.spec.luau` 6/6, `Scheduler.spec.luau` 12/12, `Integration.spec.luau` 9/9,
     `Sandbox.spec.luau` 7/7 — todos exit 0.

2. **`table.freeze`/`table.isfrozen` no Lune 0.10.5**: testei fora do spec do coder, script
   isolado (`isfrozen` antes/depois de `freeze`, escrita numa tabela congelada via `pcall`) —
   `isfrozen` alterna corretamente `false`→`true`, escrita numa tabela congelada falha via pcall.
   Confirmado, não é suposição do relato.

3. **`luau-lsp analyze --platform=standard`** nos quatro arquivos do escopo: limpo, exit 0.
   `grep` por `\bany\b` nos quatro arquivos: zero ocorrências fora de comentários que
   explicitamente dizem "nunca usar any" — confirma "zero `any`" do relato.

4. **Ponto 1 — os 24/13 testes originais realmente não foram alterados.** O repositório é git
   mas **sem nenhum commit** (`git log` → "does not have any commits yet"), então diff/hash
   contra uma versão anterior commitada é impossível. Usei evidência indireta, mas concreta:
   - `arquiteto-runtime-2026-09-04.md` (escrito **antes** deste patch, na fase de decisão)
     cita linhas exatas do `Instance.spec.luau` **pré-patch**: "Get/SetPropertyRaw
     (linhas 217-229)" e "pcall... (linhas 129-131, 244-255)".
   - No arquivo **atual**, esses mesmos testes (por conteúdo/nome) estão em 226-238, 138-140 e
     253-264 — um deslocamento **uniforme de +9 linhas** em todos os três pontos.
   - Esse deslocamento bate exatamente com o tamanho do bloco novo inserido no topo do arquivo
     (linhas 21-29 do arquivo atual: `type DynamicIndexable` + `asDynamic`, 9 linhas), inserido
     **antes** do primeiro teste. Nenhuma outra parte do arquivo precisaria mudar de tamanho
     para produzir esse deslocamento constante.
   - Mesma técnica em `ClassRegistry.spec.luau`: `revisor-runtime-classregistry-initialize-
     2026-09-04.md` (revisão da task-runtime-013, também pré-patch) cita "assert em
     `ClassRegistry.spec:183`" para o teste de IsA-dentro-do-Initialize. No arquivo atual, o
     assert equivalente está na linha 202 — deslocamento de **+19**, que bate exatamente com o
     tamanho do novo helper `makeDescriptorWithMethods` (linhas 64-81, 18 linhas + 1 linha em
     branco) inserido antes dos testes originais.
   - Word-for-word, os dois arquivos foram lidos por inteiro e o conteúdo de cada um dos 24 e
     13 testes bate com a descrição funcional das tarefas que os criaram (task-runtime-002/013).
   - Conclusão: evidência forte e convergente (dois pontos de referência independentes, dois
     arquivos, dois deslocamentos diferentes mas cada um exatamente do tamanho do bloco inserido)
     de que a mudança foi puramente aditiva (helpers no topo + testes no fim), sem edição dos
     testes originais. Não é uma prova byte-a-byte (impossível sem histórico de commit), mas é
     mais rigorosa que confiar no comentário "nenhum teste alterado" dentro do próprio arquivo.

5. **Ponto 2 — ordem de `__index`.** Lido o código (`Instance.luau:493-538`): fixos
   (ClassName/Name/Parent) → sinais → `Methods` (base) → `data.classMethods` → fallback
   `data.properties[key]`. Bate exatamente com a ordem final do arquiteto. Testei ao vivo (script
   próprio fora do spec): registrei `Raycast` em `classMethods` E uma propriedade raw chamada
   `Raycast` no mesmo instance (via `SetPropertyRaw`) — `instance.Raycast` resolveu para a
   função (classMethods), confirmando que `classMethods` é consultado antes do fallback de
   `properties`. `GetChildren` (método base) continua servido normalmente.

6. **Ponto 3 — `__newindex` erra para método herdado E específico da classe.** Testei ao vivo:
   `instance.GetChildren = nil` → erro `"Unable to assign property GetChildren. GetChildren is a
   method of Foo2 and cannot be reassigned"`; `instance.Raycast = nil` (método de classe) → erro
   `"Unable to assign property Raycast. Raycast is a method of Foo2 and cannot be reassigned"`.
   As duas mensagens batem com a "aproximação de boa-fé" documentada (declarada como não
   confirmada contra o Roblox real, com citação da pesquisa no comentário do código).

7. **Ponto 4 — `SetClassMethods` rejeita as três condições.** Testei ao vivo, cada uma
   isoladamente: tabela não congelada → erro; valor não-função (`Foo = 42`) → erro; colisão
   (`Parent = function() end`) → erro. As três falharam como esperado (não confiei no relato).

8. **Ponto 5 — comentários de divergência.** Confirmados presentes nos dois fallbacks:
   `Instance.luau:531-537` (fallback de `__index`) e `Instance.luau:579-587` (fallback de
   `__newindex`) — ambos citam `task-runtime-018` explicitamente e descrevem a divergência
   corretamente (Roblox real erraria "X is not a valid member of Y"; LuauBench devolve nil /
   cria propriedade silenciosamente, por falta de schema de propriedades por classe).

9. **Ponto 6 — achatamento favorece a classe mais concreta.** Lido `ClassRegistry.luau:150-180`
   (`resolveClassMethods`): itera a cadeia `{Concreta, ..., Super, "Instance"}` **de trás para
   frente** (`for i = #chain, 1, -1`), mesclando `Instance`, depois superclasses, com a classe
   concreta mesclada **por último** — sobrescrevendo qualquer método de mesmo nome. Confirmado
   também pelo teste do coder rodado ao vivo ("classe mais concreta sobrescreve método de mesmo
   nome da superclasse no achatamento" → PASS, `child` venceu `parent`).

10. **Ponto 7 — `SetClassMethods` inacessível ao script do usuário.** Testei ao vivo:
    `getmetatable(instance)` devolve só `{__index, __newindex}` (duas funções), sem
    `SetClassMethods` nem nenhuma outra chave. `instance.SetClassMethods` via `__index` normal
    devolve `nil` (cai no fallback de properties, vazio). Confirmei também que
    `Sandbox.spec.luau` já teste que o script do usuário não alcança `require` (portanto não
    pode fazer `require("./Instance")` para chamar a função direto) — `Sandbox.luau` não requer
    `Instance.luau` nem referencia `SetClassMethods`/`ClassMethods` em nenhum ponto, então não há
    vazamento via `extraGlobals`. `src/runtime/init.luau` **ainda não existe** neste momento do
    projeto (nenhum arquivo `src/runtime/init.luau` no repositório) — logo não há reexportação
    hoje; a decisão de não reexportar quando o módulo existir já está registrada como
    "consequência para task-runtime-007" no próprio código e na memória do arquiteto, então não
    é uma lacuna desta tarefa.

## Verificação estrutural adicional

- Ordem de `ClassRegistry.new` (`resolveClassChain → NewBase → SetClassChain → SetClassMethods →
  Initialize`) lida em `ClassRegistry.luau:182-214` — bate exatamente com o corpo especificado
  pelo arquiteto.
- `FIXED_PROPERTY_KEYS` (`ClassName/Name/Parent`) + `SIGNAL_KEYS` (5 sinais) + `Methods` (base)
  são exatamente a superfície usada tanto pela checagem de colisão em `SetClassMethods`
  (`Instance.luau:667-676`) quanto pela ordem de resolução — sem divergência entre os dois
  pontos.
- Mensagens de erro internas (não relacionadas a `__index`/`__newindex`: `SetClassMethods` não
  congelada / valor não-função / colisão) permanecem em português, como manda o contrato
  ("erro de engenharia interna do LuauBench continua em português", distinto de "erro que o
  script pode observar", que vai em inglês). `setParent`/`getInternal` não foram tocados.
- `validatedClassMethodTables` (memoização por identidade, mapa fraco `__mode="k"`) só marca
  `true` **depois** de passar todas as validações — se qualquer `error()` disparar no meio do
  laço, nem a memoização nem `data.classMethods` são setados, então uma tabela inválida nunca
  fica "meio aceita".

## Achados

Nenhum. Patch corresponde ponto a ponto ao desenho do arquiteto (ordem de `__index`/`__newindex`,
mensagens de erro, comentários de divergência obrigatórios, achatamento com override correto,
memoização por identidade, superfície interna não vazada). Todas as 7 verificações críticas
pedidas pela thread principal foram reproduzidas ativamente (não só lidas no relato do coder) e
bateram.

## Veredito

APROVADO
