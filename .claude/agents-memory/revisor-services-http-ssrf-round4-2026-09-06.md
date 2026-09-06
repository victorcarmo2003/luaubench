# Revisão `task-services-026` — 4ª rodada (gramática RFC 3986 em `extractHost`) — REPROVADO

Arquivos: `src/services/behavior/HttpService.luau`, `src/services/behavior/HttpService.spec.luau`.

## Veredito

**REPROVADO.** Achado GRAVE novo: bypass de SSRF via normalização IDNA/Unicode de separador de
domínio ("fullwidth dot" `U+FF0E`, "ideographic full stop" `U+3002`, dígitos "fullwidth"
`U+FF10`-`U+FF19`) que a stack de rede real (`@lune/net`, Rust `url`/`idna` crate, WHATWG URL
Standard) aplica ao host ANTES de resolver/conectar, mas que `extractHost`/`tryParseIPv4` deste
módulo não reproduzem — o host que a checagem audita/bloqueia diverge do host que a conexão REAL
usa, a MESMA classe de bug das 4 rodadas anteriores, desta vez na camada de normalização de
caractere dentro do label do host, não na segmentação de delimitadores estruturais (`/`, `?`, `#`,
`@`, `:`) que esta rodada corrigiu.

## O que foi verificado e CONFIRMOU o trabalho do coder (sem achado)

1. **`lune run` rodado pelo revisor, não assumido do relatório do coder.**
   - `lune run src/services/behavior/HttpService.spec.luau` → **93/93 testes passaram**.
   - Todos os 29 arquivos `*.spec.luau` de `src/services/` rodados individualmente pelo revisor →
     **29/29 passam**, nenhuma falha.

2. **Reprodução independente dos bypasses das rodadas 1-4** (script descartável próprio, cópia
   byte-a-byte das funções de `HttpService.luau`, canário `net.serve` local em `127.0.0.1`, dois
   canários distintos por porta para distinguir "conectou no host REAL" de "conectou no host
   DISFARÇADO" sem depender de DNS): confirmado que, tanto na cópia isolada quanto no módulo real
   via `Services.Bootstrap`, os seguintes casos continuam corretamente RECUSADOS sem
   `AllowHttpLocal` e ACEITOS com ela, indo para o host correto:
   - `\@` como separador de autoridade (achado GRAVE #1, 3ª rodada).
   - Percent-encoding do host, tab/LF/CR embutidos (achado GRAVE #4, 3ª rodada).
   - `?x@`/`?@`/`#x@`/`#@` terminando authority antes do `@` (achado da 4ª rodada, motivo desta
     rodada existir).
   - `\` reintroduzido IMEDIATAMENTE ANTES de `?`/`#` (`http://127.0.0.1\?x@evil/`) — a normalização
     (`normalizeUrlForParsing`, troca `\`→`/`) acontece ANTES da segmentação por `/?#`, então a URL
     já normalizada tem o "/" no lugar certo antes de `extractHost` rodar. Confirmado com canários
     de porta distinta (real vs. "evil"): a conexão E a extração concordam no host real em TODOS os
     casos testados (`\?x@`, múltiplos `?` seguidos, `#` seguido de `?` dentro do fragment, `?`
     seguido de `#` dentro da query).
   - Múltiplos `@` dentro da authority (`a@b@127.0.0.1`) — o ÚLTIMO vence dos dois lados, confirmado.
   - `%5C` (backslash percent-encoded) dentro da authority NÃO é reinterpretado como delimitador por
     nenhum dos dois lados — concordam no mesmo host (correto, teoricamente e na prática).
   - Colchete IPv6 assimétrico (só `[` ou só `]`) — `net.request` REAL rejeita ("invalid IPv6
     address"/"invalid international domain name") ANTES de qualquer conexão, em ambas as direções
     — não explorável, confirmado rodando.
   - Host só espaço, espaço como separador tentando confundir com `+` — `net.request` REAL rejeita
     ("invalid IPv4 address"/"invalid international domain name") antes de conectar.
   - NUL byte (`\0`) embutido no host — `net.request` REAL rejeita ("invalid international domain
     name"), NÃO trunca a string no NUL (não é uma vulnerabilidade de mistura C-string/Rust-string
     aqui) — não explorável.
   - BOM (`\xEF\xBB\xBF`) antes de `http://` — ambos os lados falham (nosso `assertValidUrl` rejeita
     por não bater o regex de esquema; `net.request` puro rejeita com "relative URL without a
     base") — sem divergência, sem risco.
   - Porta com sufixo não numérico, ponto duplo no host, trailing dot no host — todos ou concordam
     entre os dois lados, ou `net.request` real rejeita antes de conectar. Nenhum bypass novo aqui.
   - Ordem de normalização confirmada LENDO o código: `assertValidUrl` chama
     `normalizeUrlForParsing` PRIMEIRO (antes até do regex de esquema) e todo o pipeline
     (`extractHost`, `assertDestinationAllowed`, `auditOutgoingRequest`, `performNetRequest`) usa
     exclusivamente o valor de RETORNO normalizado — nunca a `url` crua. `percentDecodeHost` só roda
     DEPOIS que authority/userinfo/porta já foram segmentados pelos bytes literais (nunca decodifica
     a URL inteira antes de segmentar). Nenhuma inversão de ordem encontrada.

## Achado GRAVE (novo, não coberto por nenhuma rodada anterior)

**`HttpService.luau:603-647` (`extractHost`) + `:671-697` (`parseNumericComponent`/`splitByDot`) +
`:966-979` (`isLocalDestination`)**

**Problema:** o parsing de host deste módulo opera em bytes ASCII crus (`splitByDot` separa por "."
literal via `string.gmatch(host, "[^.]+")`; `parseNumericComponent` usa `%d` do Lua, que só
reconhece dígitos ASCII 0-9). A stack de rede real por trás de `net.request` (Rust, WHATWG URL
Standard — a MESMA referência que o cabeçalho do arquivo já cita para justificar
`normalizeUrlForParsing`/`percentDecodeHost`) aplica processamento **IDNA/UTS46 ("domain to
ASCII")** ao host de um esquema especial ANTES de resolver/conectar — isso inclui mapear os quatro
"separadores de label" equivalentes ao ponto (`.` U+002E, `．` U+FF0E fullwidth full stop, `。`
U+3002 ideographic full stop, `｡` U+FF61 halfwidth ideographic full stop) para o ponto ASCII, e
mapear dígitos/letras de largura total (`０-９` U+FF10-FF19, etc.) para seus equivalentes ASCII —
processamento de compatibilidade Unicode padrão que QUALQUER biblioteca de URL que implemente o
WHATWG URL Standard corretamente aplica.

**Cenário de falha (reproduzido e confirmado RODANDO, três formas independentes):**

1. `HttpService:GetAsync("http://127．0．0．1/")` (fullwidth full stop `U+FF0E` em vez de `.`) —
   com `AllowHttp=true, AllowHttpLocal=false` (a postura padrão/segura), `assertDestinationAllowed`
   NÃO recusa (porque `extractHost` devolve o literal `"127．0．0．1"`, `splitByDot` não separa por
   um caractere que não é o ponto ASCII, `tryParseIPv4` devolve `nil`, `isLocalDestination` devolve
   `false`) — a requisição passa direto para `net.request`, que DE FATO conecta em `127.0.0.1`
   (confirmado com um canário `net.serve` real em loopback, via o módulo de produção completo —
   `Services.Bootstrap` + `game:GetService("HttpService"):GetAsync`, não só a lógica copiada —
   `ok=true`, corpo do canário devolvido, canário registrou 1 hit).
2. Mesma falha com `http://127。0。0。1/` (ideographic full stop `U+3002`) — confirmado com
   `net.request` puro + canário: conecta com sucesso.
3. Mesma falha com dígitos fullwidth `http://１２７.0.0.１/` (`U+FF11`/`U+FF12`/`U+FF17`, dígitos
   "1", "2", "7" em largura total, pontos ASCII normais) — confirmado com `net.request` puro +
   canário: conecta com sucesso.

Em TODOS os três casos, um script rodando sem `--allow-http-local` consegue alcançar
`127.0.0.1`/rede local — exatamente o destino que L2.2.4 e as 4 rodadas anteriores desta MESMA
tarefa existem para bloquear — só reescrevendo o IP com um caractere Unicode de aparência similar,
trivial de produzir (copiar/colar de um teclado IME, ou um `string.gsub` de uma linha
`:gsub("%.", "．")`).

**Correção:** a MESMA disciplina que o cabeçalho já usa para justificar `normalizeUrlForParsing`
("a URL passa pelas MESMAS transformações que o parser real faz ANTES de qualquer checagem de
host") precisa ser estendida à normalização de LABEL do host, não só aos delimitadores estruturais:
antes de `tryParseIPv4`/comparação de "localhost", os quatro separadores de label equivalentes ao
ponto (`.`, `U+FF0E`, `U+3002`, `U+FF61`) precisam ser normalizados para `.` ASCII, e dígitos/letras
de largura total precisam ser dobrados para seu equivalente ASCII (ou, alternativa mais robusta e
mais alinhada ao padrão real: aplicar uma normalização Unicode NFKC ao host — que resolve fullwidth
digits/dots e uma classe maior de confusáveis de uma vez — antes de qualquer parsing de IPv4/IPv6,
sempre preservando o host original, não normalizado, para exibição/mensagem de erro). Sem isso, o
padrão "mais uma forma nova a cada rodada" (que a 4ª rodada já tinha identificado como sintoma de
"parsing próprio sem garantia de bater com WHATWG") se repete — desta vez na camada de
caracteres do host, não na de delimitadores.

**Nota lateral (não testada empiricamente, mas mesma causa raiz — registrar, não afirmar como
confirmada):** a checagem `lowered == "localhost"` (`isLocalDestination`) usa `string.lower`, que só
rebaixa ASCII — um homóglifo Unicode de "localhost" (ex.: caracteres fullwidth "ｌｏｃａｌｈｏｓｔ")
provavelmente also escaparia dessa comparação literal pelo mesmo motivo (sem normalização Unicode
antes de comparar), mas isso não foi confirmado rodando contra `net.request` real nesta rodada —
verificar antes de reportar como bypass adicional confirmado.

## Testes/checagens adicionais pedidos, e resultado

- `--!strict` presente na linha 1; teste mecânico "SEM ANY" no próprio spec passou (varre o
  texto-fonte por `any` como palavra isolada) — sem `any` no arquivo, confirmado por leitura
  completa do arquivo também.
- `AllowHttpLocal=true` sem `AllowHttp=true`: `HttpEnabled` nasce `false` (só `AllowHttp` controla
  isso, via `Initialize`/`Context.IsHttpAllowed()`) — os 3 métodos de rede continuam errando "not
  enabled" ANTES de qualquer checagem de destino. Confirmado por leitura do código e teste existente
  já passando.
- `OnHttpRequest` audita o host REAL (nunca o disfarçado) em todos os bypasses de delimitador
  reproduzidos nesta rodada (a bug de IDNA acima não foi testada quanto à auditoria especificamente,
  mas segue o mesmo caminho de código de `extractHost`/`auditOutgoingRequest` — o host AUDITADO
  seria o mesmo host ERRADO, "127．0．0．1" com pontos fullwidth, não "127.0.0.1" — o mascaramento
  do achado GRAVE também se propaga para o log de auditoria, o que é ainda mais grave para
  `--verbose` do `cli`).
- Território limpo: nenhum arquivo deixado para trás pelo revisor (dois scripts de prova
  descartáveis criados e removidos ao final desta revisão).

## Recomendação

Não aprovar. O padrão histórico desta função (mais uma forma a cada rodada) se repete uma quinta
vez, desta vez numa camada inteiramente nova (normalização de caractere Unicode do host) que nenhuma
rodada anterior sequer considerou. Sugestão para a próxima rodada: em vez de continuar reagindo
achado-por-achado, considerar se vale a pena `arquiteto` avaliar uma dependência mínima (ou
implementação própria pequena e testada) de normalização IDNA/NFKC do host ANTES de qualquer
parsing de IP — a estratégia "seguir a gramática RFC 3986" desta rodada resolveu a classe de bug de
DELIMITADORES, mas o projeto ainda não tem uma resposta estrutural para a classe de bug de
CARACTERES (Unicode/IDNA), e as duas classes são igualmente exploráveis.
