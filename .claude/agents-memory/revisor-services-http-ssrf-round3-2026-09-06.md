# Revisão `task-services-026` — 3ª rodada (revisor-services) — 2026-09-06

## Veredito: REPROVADO

Achado um **5º bypass de SSRF**, GRAVE, ainda sem correção — reproduzido empiricamente contra um
canário `net.serve` local em `127.0.0.1`, sem nenhuma notação exótica (nem backslash, nem
percent-encoding, nem tab/CR/LF): basta um `?` ou `#` literal seguido de `@host-qualquer` em
qualquer posição da URL, com o IP privado escrito na forma canônica mais simples (`127.0.0.1`).

## O bug

`extractHost` (`src/services/behavior/HttpService.luau:525-556`) calcula a região de
autoridade (`beforeSlash`) assim:

```lua
local beforeSlash = string.match(afterScheme, "^([^/]*)") or afterScheme
local hostPort = string.match(beforeSlash, "@([^@]*)$") or beforeSlash
```

Só reconhece **"/"** como terminador da autoridade. No WHATWG URL Standard (e, confirmado
empiricamente, no parser real por trás de `net.request`), a autoridade também termina em **"?"**
(início da query) e **"#"** (início do fragmento) — exatamente como termina em "/". O código não
sabe disso: tudo que vem depois de um "?" ou "#" (inclusive um "@" real que apareceria numa query
string comum) ainda é considerado parte da região onde a heurística "pega o texto depois do
ÚLTIMO @" procura host/userinfo.

Resultado: uma URL como `http://127.0.0.1:PORT?x@evil-marker.invalid/` faz `hostPort` virar
`"evil-marker.invalid"` (tudo antes do último "@", incluindo `"127.0.0.1:PORT?x"`, é descartado),
então `extractHost` devolve `"evil-marker.invalid"` — host público, não bloqueado — enquanto a
conexão real (query string não é reinterpretada como autoridade por NENHUM parser real) vai para
`127.0.0.1:PORT`.

Sem "@" nenhum o bug ainda existe, só que por um caminho diferente: `http://127.0.0.1?x/` (sem
porta) faz `host` virar o literal `"127.0.0.1?x"` (a query gruda no host por falta de terminador),
que `tryParseIPv4` rejeita (não é numérico puro) — tratado como hostname comum, não reconhecido
como privado.

## Reproduzido (empírico, script descartável, removido ao final — não versionado)

Canário `net.serve` real em `127.0.0.1:<porta>`, chamando o módulo real via `GetAsync` com
`AllowHttp=true` e **SEM** `AllowHttpLocal`:

```
url=http://127.0.0.1:47399?x@evil-marker.invalid/
SEM AllowHttpLocal -> ok=true canary_hits=1
  OnHttpRequest audited: method=GET host=evil-marker.invalid
```

- `ok=true`: a requisição **completou com sucesso**, sem `--allow-http-local`.
- `canary_hits=1`: a conexão real foi para `127.0.0.1` (o canário só responde lá).
- `OnHttpRequest` (canal de auditoria) registrou `"evil-marker.invalid"` — **o host errado** —
  então o bypass também envenena a auditoria, não só o gate.

Confirmadas as 4 variantes pedidas no prompt de revisão (todas com porta explícita, `AllowHttp=true`,
sem `AllowHttpLocal`, contra o canário real):

| URL | Resultado |
|---|---|
| `http://127.0.0.1:PORT?@evil-marker.invalid/` | bypass confirmado (hit no canário) |
| `http://127.0.0.1:PORT?x=1@evil-marker.invalid/` | bypass confirmado |
| `http://127.0.0.1:PORT#@evil-marker.invalid/` | bypass confirmado |
| `http://127.0.0.1:PORT#x@evil-marker.invalid/` | bypass confirmado |
| `http://127.0.0.1:PORT?x/` (sem "@") | **corretamente bloqueado** (o ":" antes do "?" ainda salva a extração quando não há "@" depois) |

A validação com `net.request` puro (sem nenhuma checagem do módulo no meio) confirma que a
premissa é real: as 4 URLs acima conectam de fato no canário local — não é uma peculiaridade da
extração, é o comportamento genuíno da stack de rede.

## Por que isto passou pelas 3 rodadas anteriores

As rodadas 1-3 (decimal/octal/hex/abreviado, IPv4-mapped/compatible IPv6, `\@`, percent-encoding,
tab/CR/LF) atacaram todas o mesmo tipo de problema: "que NOTAÇÃO de IP o host pode assumir". A
mudança de estratégia desta rodada ("normalizar como a rede real normaliza") resolveu bem a
NORMALIZAÇÃO DE CARACTERES (`\`→`/`, remoção de tab/CR/LF, percent-decode do host) — mas
`extractHost` continua sendo um **segmentador próprio, escrito à mão**, que só reconhece "/" e "@"
como delimitadores estruturais. "?" e "#" nunca entraram na lista de delimitadores reconhecidos,
em NENHUMA das 3 rodadas — a normalização não ajuda aqui porque o problema não é uma variação de
caractere dentro do host, é a fronteira da autoridade sendo mal-computada.

## Resposta ao item 8 do pedido (estrutural: a abordagem é mais robusta?)

Não, pelo menos não integralmente. "Normalizar como a rede real normaliza" resolveu a classe de bug
das 3 primeiras rodadas (variação de notação/encoding DENTRO do que já era reconhecido como host),
mas a segmentação em si (onde a autoridade começa e termina) continua sendo reimplementada à mão,
com uma lista incompleta de delimitadores. Isso é a mesma fragilidade fundamental que a mudança de
estratégia pretendia eliminar — só que operando em um nível diferente (delimitadores estruturais em
vez de notação de IP). Enquanto `extractHost` não tratar "?"/"#" (e, por rigor, qualquer outro
terminador de autoridade do parser real) como fim de autoridade, cada rodada futura corre o risco de
achar mais uma forma de "o que termina a autoridade que o código ainda não sabe". Isto é achado
GRAVE concreto (não risco residual teórico) nesta rodada.

## Demais itens verificados (não bloqueiam a reprovação, registrados para o próximo ciclo)

- `lune run src/services/behavior/HttpService.spec.luau` → **80/80 passaram**, confirmado rodando
  (bate com o alegado). Contagem de arquivos `*.spec.luau` em `src/services/` → **29**, bate com o
  "29/29" alegado (não rodei a suíte completa, dado o REPROVADO já certo pelo achado acima).
- Bypasses das rodadas 1-3 (decimal/octal/hex/abreviado, `0.0.0.0`, IPv4-mapped/compatible IPv6 com
  e sem `ffff:`, `\@`, percent-encoding total e parcial, tab/LF/CR embutido) — todos continuam
  RECUSADOS sem `AllowHttpLocal`, confirmado pela suíte passando e por leitura do código; não
  reproduzi cada um de novo à mão (a suíte já os exercita com round-trip real contra o canário).
- `AllowHttpLocal=true` sem `AllowHttp=true` continua sem abrir rede (`Initialize` só liga
  `HttpEnabled` via `Context.IsHttpAllowed()`; `AllowHttpLocal` só é consultado depois — código
  lido, teste dedicado passando).
- `percentDecodeHost` decodifica só o token de host — não testei um payload dedicado de
  percent-encoding no PATH para confirmar que ele não vaza para lá, mas por leitura de código
  `percentDecodeHost` só é chamado sobre o resultado já segmentado por `extractHost` (nunca sobre a
  URL inteira), então estruturalmente não deveria afetar o path. Não voltei a isto depois de achar
  o bypass acima — priorizei reportar o achado GRAVE.
- `--!strict` presente na linha 1 de ambos os arquivos; grep por `\bany\b` em `HttpService.luau` não
  encontrou nada; o teste mecânico do próprio spec ("SEM ANY") também passou.
- Território limpo: `git status` mostra só `HttpService.luau`/`HttpService.spec.luau` alterados
  dentro de `src/services/behavior/` (mais `Context.luau`/`Types.luau`, que são o contrato
  coordenado com `task-cli-026`, já documentado no cabeçalho do módulo — não avaliei essas duas
  peça por peça a fundo, dado o REPROVADO já certo).

## Correção sugerida (não implementada — sou read-only)

`extractHost` precisa tratar "?" e "#" como terminadores de autoridade, no MESMO nível que "/" já
é tratado — ou seja, cortar `afterScheme` no primeiro caractere dentre `/`, `?`, `#` (o que vier
primeiro), e só then aplicar a lógica de "@"/porta/colchetes sobre esse pedaço. Isso fecha tanto a
variante com "@" quanto a variante sem "@" (host+query grudados) na mesma correção.
