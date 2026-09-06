# Revisão `task-services-026` — 5ª e ÚLTIMA rodada de fix ativo (2026-09-06)

Escopo: `src/services/behavior/HttpService.luau`, `src/services/behavior/HttpService.spec.luau`. Read-only, nenhum arquivo do projeto editado. Dois scripts descartáveis criados na raiz do repo, rodados e removidos ao final: `.tmp-revisor-verify-http-unicode.luau`, `.tmp-revisor-homoglyph-probe.luau`. `git status` confirmado limpo (sem sobra) ao final.

Contexto: usuário decidiu explicitamente aceitar o risco residual de DNS rebinding e Unicode/IDNA além de 4 caracteres, e esta é a última rodada — não reabrir com uma 6ª rodada salvo classe estruturalmente nova e facilmente corrigível.

## Verificações e evidência reproduzida

1. **Suíte completa**: `lune run src/services/behavior/HttpService.spec.luau` → **101/101**, reproduzido diretamente. Suíte inteira de `src/services/`: enumerei 29 arquivos `.spec.luau` via `find` (bate com a alegação) e rodei cada um individualmente com `lune run` → **29/29 arquivos, 0 falha** (CollisionGroups 23/23, WorldRoot 12/12, Snapshot 37/37, Store 55/55, etc. — todos os territórios vizinhos/concorrentes intactos).

2. **Reprodução independente dos 4 separadores Unicode**, com script próprio (não reusa o spec do coder) chamando `Services.Register`/`Bootstrap` direto: fullwidth full stop U+FF0E, ideographic full stop U+3002, halfwidth ideographic full stop U+FF61, dígitos fullwidth U+FF11/FF17 — **todos RECUSADOS** (erro `[LuauBench] refusing...`) sem `AllowHttpLocal`, **todos ACEITOS** com `AllowHttpLocal=true` e completam round-trip real contra canário `net.serve` próprio (portas 47281/47282, não as do coder). 22/22 checagens próprias passaram.

3. **Host original nunca mascarado**: nos 4 casos acima, a mensagem de erro cita o host Unicode LITERAL da URL (nunca "127.0.0.1" ASCII). `OnHttpRequest` (canal de auditoria) recebeu `"127．0．0．1"` (com o caractere Unicode original), nunca o normalizado — confirmado por asserção de igualdade de string, não só "contém".

4. **Seção `RISCOS RESIDUAIS ACEITOS`** (linhas 631-672 do cabeçalho): li por completo. Honesta — não subestima (declara DNS rebinding como "risco ACEITO", não "resolvido"), cita fonte real e verificável (`.claude/agents-memory/pesquisa-lune-dns-resolution-2026-09-06.md`, que existe e cujo conteúdo (`HeaderMap::insert` sobrescrevendo `Host`, ausência de API de resolução separada em `@lune/net` 0.10.5) bate com o que a seção afirma). Não promete NFKC/IDNA completo — item 2 nomeia explicitamente "bidi override", "homoglifos" e cita por nome o caso "ｌｏｃａｌｈｏｓｔ" como "levantado, não confirmado empiricamente".

5. **Retest de regressão** (decimal `2130706433`, `\@`, `?@`) — todos os 3 continuam recusados sem `AllowHttpLocal`, sem regressão.

6. **Sondagem extra (opcional, feita)**: testei o caso que o próprio cabeçalho já cita como "não confirmado" — `"ｌｏｃａｌｈｏｓｔ"` (letras Latinas fullwidth) contra `net.request` PURO (sem passar por `HttpService.luau`). Resultado: **conecta de verdade no loopback** (`net.request` com `url = "http://ｌｏｃａｌｈｏｓｔ:PORT/"` completou contra canário em 127.0.0.1, status 200). Isto CONFIRMA empiricamente o que a seção de riscos já registrava como suspeita não verificada — não é uma classe nova (é exatamente "Unicode/IDNA além dos 4 caracteres cobertos", item 2 já aceito), só deixa de ser hipotético. Registrado abaixo como achado BAIXO/informativo, não bloqueante — dentro do escopo já aceito pelo usuário.

7. `--!strict` presente nas duas primeiras linhas dos dois arquivos. Nenhuma ocorrência do tipo `any` (grep `\ban y\b`), só a menção dentro do nome/asserção do próprio teste que verifica a ausência.

8. Território: `git status --porcelain` mostra só os 2 arquivos-alvo modificados; `git diff --stat` confirma (nenhum outro arquivo de `src/services/` tocado por esta tarefa). O arquivo solto `_ssrf_probe_standalone.luau` visto no status inicial da sessão já não existe mais (removido antes desta rodada).

## Achados

**[BAIXO]** `src/services/behavior/HttpService.luau:1063-1071` (docblock de `normalizeUnicodeHostLabels`)
Problema: o item "homoglifos" das RISCOS RESIDUAIS cita `"ｌｏｃａｌｈｏｓｔ"` como "não confirmado empiricamente" — confirmei nesta rodada que ele É explorável de verdade contra `net.request` puro (IDNA mapeia fullwidth Latin para ASCII antes de conectar).
Cenário de falha: script com `--allow-http` (sem `--allow-http-local`) chama `GetAsync("http://ｌｏｃａｌｈｏｓｔ:PORT/...")` e alcança loopback sem passar pelo gate — mesma classe já aceita (item 2, "Unicode/IDNA além dos 4 caracteres"), não uma classe nova.
Correção: não bloqueante nesta rodada (decisão do usuário já cobre esta classe). Sugestão de baixo custo para uma tarefa futura, se reaberta: trocar "não confirmado empiricamente" por "confirmado" no texto do cabeçalho, já que agora há evidência.

Nenhum outro achado. Não encontrei host inventado fora do dump, tipo simplificado indevidamente, cobertura não declarada, ou acesso a estrutura interna de `runtime` fora da API pública nestes dois arquivos.

## Veredito

**APROVADO COM RESSALVAS**

Ressalva única: item BAIXO acima (confirmação empírica de um risco já declarado como aceito, não uma pendência nova) — não bloqueia, registrar para referência futura caso o escopo seja reaberto.
