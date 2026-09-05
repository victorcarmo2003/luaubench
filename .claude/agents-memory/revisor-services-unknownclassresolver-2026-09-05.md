# Revisão — task-services-011 (services injeta o resolvedor de classe desconhecida)

Data: 2026-09-05. Território revisado: `src/services/init.luau` + `src/services/init.spec.luau`. Read-only, tudo reproduzido pelo revisor (nenhum dado aceito por self-report do coder).

## Veredito

**APROVADO**

## O que foi verificado, com evidência reproduzida

### 1. Suite de testes rodada pelo revisor (não pelo coder)

Rodei `lune run` em cada um dos 17 arquivos de spec de `runtime`+`services` individualmente:

- `src/runtime/*.spec.luau` (8 arquivos): 29+16+63+9+20+16+7+6 = **166/166**
- `src/services/*.spec.luau` (9 arquivos, incluindo `behavior/*` e `tools/generate-services.spec.luau` não contado — território `services` puro): 9+3+9+14+5+4+8+11+3+22 = **88/88**
- `src/services/init.spec.luau` isolado: **22/22** (confirma "18+4" do coder — 18 pré-existentes + 4 novos deste task)

Total runtime+services: **254/254**, zero falha. Confirma a alegação do coder ("22/22 init.spec, regressão total 17 arquivos verde").

### 2. `resolveUnknownClass` — pureza e totalidade

Leitura do código (`src/services/init.luau:224-233`): é só `Manifest.Classes[className]` + dois `if`, sem `error()`, sem efeito colateral. Testei eu mesmo via script fora do repo (`lune run` com require relativo até `src/runtime`/`src/services`), cobrindo casos fora dos testes do coder:

- `""`, `" "` → `NotAClass` (erro família Roblox, sem crash)
- `"workspace"`, `"WORKSPACE"` (case errado) → `NotAClass` — confirma que o lookup é case-sensitive, sem normalização (fiel ao Roblox real, que não aceita alias)
- `"Teams "` / `" Teams"` (espaço extra) → `NotAClass`
- `"Fr@me!"`, `"日本語"` (unicode), string de 5000 caracteres `"AAA..."` → todos `NotAClass`, sem crash, sem exceção

Nenhum input quebrou a função — confirma total (responde para qualquer string) e pura (nenhum erro interno, decisão de errar/devolver nil é sempre de `DataModel:GetService`).

### 3. `unsimulatedClassMessage` — fonte única

Confirmado por leitura: `resolveUnknownClass` (caso `ServiceNotSimulated`) e `Services.new` (caso 3, linha ~445) chamam a MESMA função local `unsimulatedClassMessage(className)` (linhas 196-198). Testei o efeito ponta-a-ponta: `game:GetService("Teams")` devolveu exatamente `[LuauBench] Teams exists in the Roblox API Dump (0.737.0.7371584) but is not simulated by LuauBench yet` — mesma DumpVersion, mesma frase que `Services.new` produziria para uma classe não coberta. Uma edição na frase só pode acontecer num lugar; não há literal duplicado para divergir.

### 4. Posição de `Runtime.UnknownClassResolver.Set`

Lido o corpo de `Services.Register()` (linhas 260-278), não o comentário: `registered = true` na linha 264, `Runtime.UnknownClassResolver.Set(resolveUnknownClass)` na linha 271, laço `for className, generated in GeneratedIndex` começa na linha 273. Ordem exata pedida pelo desenho (guarda de idempotência → Set → laço).

### 5. Teste ponta-a-ponta pós-`Bootstrap`

Reproduzi eu mesmo (script fora do repo, sem tocar `src/`):
- `game:GetService("Teams")` → erro contendo `[LuauBench]` e a `DumpVersion` (`0.737.0.7371584`)
- `game:GetService("Frmae")` → erro `'Frmae' is not a valid Service name` (aspas simples, S maiúsculo, sem prefixo) — string vem de `DataModel.luau` (`task-runtime-030`), não deste território, mas o contrato bate
- `game:GetService("Frame")` → `nil`, sem erro

Nenhuma das três mensagens tem byte fora de ASCII.

**Avaliação do proxy "sem byte não-ASCII" pedida na tarefa:** é um proxy **fraco mas não incorreto aqui**. Ele detecta com certeza qualquer acento (ã, ç, õ...), mas não pegaria uma frase em português sem diacríticos (ex.: "nao instalado", "para", "que" são palavras portuguesas 100% ASCII) nem uma frase em inglês gramaticalmente errada. Isso NÃO é um bug atual — inspecionei os literais reais (`unsimulatedClassMessage` e a string em `DataModel.luau`) e ambos são inglês correto, batendo exatamente com o texto do desenho. É uma observação de qualidade de teste para o futuro (BAIXO, não bloqueante): o teste automatizado sozinho não seria suficiente para pegar uma regressão sutil (ex.: alguém trocar "is not simulated" por "nao esta simulado" sem acento) — só a inspeção manual do literal (feita aqui) fecha essa lacuna.

### 6. Idempotência

Chamei `Services.Bootstrap()` duas vezes seguidas + `Services.Register()` uma terceira vez direto, no mesmo processo — sem erro, sem duplicar registro, e `GetService` continuou funcionando normalmente nos três vereditos depois das 3 chamadas. `Set` sobrescreve silenciosamente (mesma função, efeito nulo) — comportamento correto e documentado.

### 7. Módulos fora do escopo — intocados

`git diff --stat` mostra só `src/services/init.luau` (+84/-6) e `src/services/init.spec.luau` (+126) tocados neste território (mais `.claude/tasks.json`, que só mudou `column: todo -> in-progress` para `task-services-011` E `task-cli-017` — mudança de dispatcher/orquestrador, não do coder; a alegação "não tocou tasks.json" é consistente em espírito). Grep/leitura confirmam `Manifest`, `ClassBuilder`, `generated/**`, `behavior/**`, `tools/generate-services.luau`, `IsKnownClass`, `IsServiceClass`, `IsSimulatedClass`, `GetSimulatedServiceClasses` sem nenhuma linha alterada.

### 8. `--!strict` / sem `any`

Ambos arquivos começam com `--!strict`. `grep -n "\bany\b" src/services/init.luau` não retornou nada. Nenhum `any` novo.

### 9. Território

`git status`/`git diff --stat` completo confirma que os únicos arquivos de `src/cli/` alterados (`RunCommand.luau`, `TreeMaterializer.luau` + specs) são disjuntos dos de `services` — consistente com `task-cli-017` rodando em paralelo, território `src/cli/` intocado por este coder. Único `require` de `runtime` em `init.luau` continua sendo o agregador (`require("./runtime")`, linha 178 — pré-existente, não `../runtime` por causa do gotcha de `require` "estilo diretório" já documentado no cabeçalho do próprio arquivo; não é uma violação, é a mesma convenção usada em todo o arquivo antes desta tarefa).

### 10. "Buraco" hipotético — resolver chamado para classe já `IsService=true` E `Covered=true`

Testei empiricamente: das 24 classes com `Covered == true` no manifesto, **todas as 24** aparecem como `Services.IsSimulatedClass(...) == true` depois do `Bootstrap` (0 mismatches) — ou seja, todas estão de fato registradas em `ClassRegistry`. Das classes que são Service E cobertas (11, via `GetSimulatedServiceClasses()`), todas resolveram via `game:GetService(...)` sem erro, sem cair no resolvedor.

Isso confirma estruturalmente por que o "buraco" é inalcançável: `runtime` (`DataModel:GetService`) só chama `UnknownClassResolver.Resolve` quando `ClassRegistry.Get(className) == nil`; e `Services.Register()` registra em `ClassRegistry` exatamente as classes de `GeneratedIndex`, que nascem de `Covered == true` no manifesto (mesma fonte, `tools/coverage.luau`, conforme comentário do próprio arquivo). Logo qualquer classe `Covered == true` sempre tem `ClassRegistry.Get(...) ~= nil`, e o resolvedor nunca é invocado para ela em produção. `resolveUnknownClass` não é exportado (confirmei `Services.resolveUnknownClass == nil` via cast `:: any` no meu script de teste), então também não há chamada direta possível por fora. Documentado no comentário do código (linhas 216-222) e agora confirmado empiricamente por este revisor — não é um buraco real, é uma invariante que se sustenta pela construção do próprio `Services.Register()`.

## Achados

Nenhum GRAVE/ALTO/MÉDIO. Um item BAIXO, não bloqueante:

```
[BAIXO] src/services/init.spec.luau:~475 (hasNonAsciiByte)
Problema: o proxy "sem byte não-ASCII" para "mensagem não está em português" não pega português sem diacríticos (ex.: "nao", "para", "que" são ASCII-válidos).
Cenário de falha: se um dia alguém reformular unsimulatedClassMessage/a string de DataModel.luau para uma frase em português sem acento, o teste continuaria verde.
Correção: opcional — não bloqueia esta tarefa, já que os literais atuais foram inspecionados manualmente e são inglês correto. Se quiser fechar a lacuna, complementar com uma lista de stopwords em português comuns sem acento, ou (mais simples) um teste de igualdade byte-a-byte contra a string exata esperada, que já existe em alguns dos testes novos (bom sinal — o teste de "Teams" já faz isso).
```

## O que verifiquei e não encontrei problema

- Fidelidade ao contrato de `task-runtime-030`: tipos `Runtime.UnknownClassVerdict`/`Runtime.UnknownClassResolver` consumidos exatamente como o agregador `src/runtime/init.luau` exporta.
- Nenhum módulo interno de `runtime` importado além do agregador `require("./runtime")`.
- Nenhuma função nova exportada por `Services` (só efeito colateral de `Register()` mudou).
- Cabeçalho do arquivo atualizado nos dois pontos certos (passo 5 da sequência de bootstrap + parágrafo de "superfície pública vista por cli").
- `Manifest.Covered` genuinamente não consultado em `resolveUnknownClass` (grep confirma).

## Conclusão

Implementação bate com o desenho do arquiteto byte a byte (mensagem, posição do `Set`, ordem dos vereditos, não-exportação). Toda alegação do coder foi reproduzida independentemente (contagem de testes, pureza/totalidade com inputs adicionais, posição exata do `Set`, mensagens pós-Bootstrap, idempotência, território). Nenhuma divergência entre o relatório do coder e o comportamento real observado.
