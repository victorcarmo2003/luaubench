# Revisão `task-services-026` (SSRF em `HttpService`) — SEGUNDA RODADA

Data: 2026-09-06
Arquivos: `src/services/behavior/HttpService.luau`, `src/services/behavior/HttpService.spec.luau`, `src/services/Types.luau`, `src/services/Context.luau`
Território confirmado limpo: só esses 4 arquivos modificados em `src/services/` (`git status` verificado). Par coordenado (`task-cli-026`) toca `src/cli/*` — fora do meu escopo, não revisado aqui.

## Veredito

**REPROVADO** — novo bypass de SSRF encontrado (GRAVE), full end-to-end, confirmado com prova reproduzível independente do coder.

---

## O que foi verificado e está CORRETO

1. **62/62 `HttpService.spec.luau`** — rodei eu mesmo (`lune run src/services/behavior/HttpService.spec.luau`), bate exatamente com o alegado.
2. **29/29 arquivos de spec de `src/services/`** — rodei cada um individualmente (`find src/services -name "*.spec.luau"` → 29 arquivos), todos saíram com exit 0 e "N/N testes passaram" batendo consigo mesmos. Zero regressão.
3. Os **6 bypasses da rodada anterior** (decimal `2130706433`, octal `017700000001`, hex `0x7f000001`, abreviado `127.1`, IPv4-mapped IPv6 `::ffff:127.0.0.1` comprimido/expandido, `0.0.0.0`) — reproduzi com script independente meu (`net.serve` local próprio, sem depender do spec do coder): todos **RECUSADOS** sem `AllowHttpLocal`, mensagem `[LuauBench] refusing`. Confirmado.
4. Também testei variantes adicionais que o coder não cobriu explicitamente e todas se mostraram **corretamente bloqueadas** (nenhuma nova falha nessas):
   - Zero-padding decimal `127.000.000.001` → bloqueado (cai no parser octal, "000"→0, "001"→1, resultado idêntico).
   - IPv6 loopback totalmente expandido com colchetes `[0:0:0:0:0:0:0:1]` → bloqueado (bate a comparação literal existente).
   - IPv4 de 3 partes `127.0.1` → bloqueado (branch de 3 componentes do `tryParseIPv4`).
   - Notação mista `127.0.0x1` → bloqueado (colapsa para o branch de 3 componentes, resultado 127.0.0.1).
5. **`AllowHttpLocal=true` sem `AllowHttp=true`**: confirmado que `HttpEnabled` continua `false` e os 3 métodos erram "not enabled" antes de qualquer checagem de destino — sem regressão.
6. **`OnHttpRequest`**: testei com script independente —
   - Chamado 1x com `(method, host)` corretos numa requisição que **passa os gates mas falha depois** (host `.invalid` inexistente) — confirma que audita a TENTATIVA, não o sucesso, como pedido.
   - NÃO chamado quando recusado por `HttpEnabled=false` nem por destino privado sem `AllowHttpLocal` (spec do coder cobre isso, e minha leitura do fluxo de código confirma: `auditOutgoingRequest` só é chamado depois de `assertHttpEnabled`/`assertDestinationAllowed` passarem, nos 3 métodos).
7. `--!strict` presente nos 4 arquivos; sem `any` real no código de produção (`HttpService.luau`) — só ocorre como string literal dentro do nome/mensagem de um teste em `HttpService.spec.luau`, não como tipo.
8. Decisão de `0.0.0.0` bloqueado por padrão: razoável — comportamento realmente depende de SO (vários Linux tratam como loopback), lado seguro é o default aqui.

---

## GRAVE — Bypass novo, não coberto: confusão de host via BARRA INVERTIDA (`\`)

**Arquivo:** `src/services/behavior/HttpService.luau:412-441` (função `extractHost`), especificamente a linha 420:
```lua
local beforeSlash = string.match(afterScheme, "^([^/]*)") or afterScheme
```

**Problema:** `extractHost` só trata `/` como separador entre `host:porta` e o resto da URL (path/query). O WHATWG URL Standard — que a stack de rede real por trás de `net.request` (crate `url`/reqwest do Rust) implementa — manda **normalizar `\` para `/` em esquemas especiais (http/https/ws/wss/ftp/file) ANTES de separar host de path**. Como `extractHost` não faz essa normalização, uma URL como

```
http://127.0.0.1:PORT\@evil-marker.invalid/
```

é interpretada de forma **diferente** pelo filtro e pela rede real:
- **Filtro (`extractHost`)**: não vê `/` antes do `@`, então trata a string inteira até o `@` final como "userinfo" e extrai `evil-marker.invalid` como host — um hostname público, não reconhecido como privado, então `assertDestinationAllowed` **deixa passar sem `AllowHttpLocal`**.
- **Rede real (`net.request`)**: normaliza `\` → `/`, chegando a `http://127.0.0.1:PORT/@evil-marker.invalid/` — ou seja, conecta em **`127.0.0.1:PORT`** de verdade, tratando `@evil-marker.invalid/` como PATH.

**Cenário de falha (reproduzido por mim, script independente, servidor canário `net.serve` próprio em `127.0.0.1`, nunca serviço externo):**
```
URL usada: http://127.0.0.1:47611\@evil-marker.invalid/
GetAsync(httpService, url, ...) com AllowHttp=true, SEM AllowHttpLocal
finished=true ok(GetAsync completou sem erro)=true
hitCount no canario 127.0.0.1:47611 = 1
auditedHost (via OnHttpRequest) = evil-marker.invalid   <- ERRADO, mascara o alvo real
body devolvido por GetAsync = canary-hit
```
`GetAsync` **completou com sucesso** contra `127.0.0.1` sem `AllowHttpLocal` — bypass total do endurecimento. Pior ainda: o canal de auditoria `OnHttpRequest` registrou o host **errado** (`evil-marker.invalid`), então mesmo com `--verbose` ligado no `cli`, o operador veria um log que não corresponde ao destino real — o SSRF fica invisível na auditoria também.

Como `assertDestinationAllowed`/`extractHost` são compartilhados por `GetAsync`/`PostAsync`/`RequestAsync` (mesma função, mesma ordem de chamada nos 3), o mesmo vetor se aplica aos três métodos — validado por leitura de código; reproduzido experimentalmente via `GetAsync`.

**Correção:** normalizar `\` para `/` (ou tratar `\` como delimitador equivalente a `/`) em `extractHost` antes de cortar path/userinfo — no mínimo no cálculo de `beforeSlash` (linha 420); idealmente revisar a função inteira contra o algoritmo de host-parsing do WHATWG URL Standard, já que parsers "feitos à mão" divergindo do parser real é exatamente a classe de bug que motivou a reprovação anterior.

---

## GRAVE (mesma política desta revisão) — IPv4-compatible IPv6 (RFC 4291, forma deprecada `::a.b.c.d`, SEM `ffff`) não é reconhecido

**Arquivo:** `src/services/behavior/HttpService.luau` — `extractIPv4MappedOctets`/`ipv4MappedFromCompressed`/`ipv4MappedFromExpanded` (linhas 628-699) só reconhecem a forma **IPv4-mapped** (`::ffff:a.b.c.d`), nunca a forma **IPv4-compatible** (`::a.b.c.d`, sem o grupo `ffff` — RFC 4291 §2.5.5.1, deprecada mas ainda uma sintaxe IPv6 válida e parseável).

**Reproduzido por mim:**
- `isLocalDestination` para `::127.0.0.1`/`::10.0.0.1`/`::192.168.1.1` (comprimidos) e `0:0:0:0:0:0:127.0.0.1` (expandido) → **NÃO reconhecidos como privados** (`extractIPv4MappedOctets` retorna `nil` porque exige literalmente `ffff:`; `isIPv4Private` também falha porque `splitByDot` quebra em componentes não-numéricos como `"::127"`).
- Confirmei que isso não é só teórico: chamando `net.request` **diretamente** (bypassando todo o `services`) contra `http://[::127.0.0.1]:PORT/`, `http://[::10.0.0.1]/`, `http://[::192.168.1.1]/` e `http://[0:0:0:0:0:0:127.0.0.1]/`, a stack de rede do Lune **parseia com sucesso e tenta abrir socket de verdade** (chega a tentar conectar — falha só com `os error 10051` "unreachable network", um comportamento de ROTEAMENTO do Windows para esse endereço IPv6 legado, não uma rejeição de sintaxe).
- Passando pelo `HttpService.GetAsync` real (`AllowHttp=true`, sem `AllowHttpLocal`): o gate **deixa passar** (não erra "[LuauBench] refusing"), só falha depois com a mensagem genérica de rede — ou seja, **o filtro não bloqueou**, quem impediu a conexão nesta máquina foi o Windows, não o LuauBench.

Isto é irmão exato do caso que o coder já tratou (`::ffff:a.b.c.d`) — mesma técnica de "endereço IPv4 embutido em IPv6", só que sem o prefixo `ffff:`. Em outra plataforma (ou versão futura da stack de rede do Lune) que rotule esse endereço como roteável, isto conecta de verdade — não há garantia de que "unreachable network" do Windows é uma proteção, é só um acidente de implementação de socket, do mesmo jeito que o coder já documentou para `0.0.0.0`/IPv4-mapped ("comportamento depende do SO").

**Correção:** estender `extractIPv4MappedOctets` (ou uma função irmã) para também reconhecer `::a.b.c.d`/`0:0:0:0:0:0:a.b.c.d` (sem `ffff`) — mesma técnica já usada, só sem exigir o grupo `ffff`.

---

## BAIXO (nota de robustez, não bloqueante) — zone ID IPv6 (`%eth0`/`%25eth0`) não é normalizado

`isIPv6Loopback` faz comparação EXATA de string (`loweredHost == "::1"`) — um host escrito como `::1%eth0` ou `::1%25eth0` (RFC 4007 scope zone) não bate a comparação e passa pelo filtro. **Testei diretamente contra `net.request`** (sem o gate): ambas as formas falham com `"bad argument #1: invalid IPv6 address"` — a stack de rede do Lune **rejeita zone ID nesta versão**, então este caminho específico **não é explorável hoje** através de `net.request`. Reporto mesmo assim porque é um gap real de normalização e a correção é trivial (cortar tudo a partir de `%` antes de comparar) — se uma versão futura do Lune/da lib de rede aceitar zone ID, o buraco already existe no filtro.

---

## Não investigado a fundo (fora do orçamento desta rodada, mas relevante)

- **DNS rebinding** (host que resolve para IP privado): já é **LIMITAÇÃO DECLARADA** explicitamente no cabeçalho do arquivo (`net.request` resolve e conecta como operação só, sem hook de inspeção do IP resolvido) — não é um achado novo, é lacuna conhecida e documentada, coerente com o que testei (tentei contra um domínio público real que resolve para `127.0.0.1`; sem rede externa neste ambiente para confirmar round-trip completo, mas a limitação já está corretamente declarada e não escondida).
- IDN/homograph: não é uma classe de bypass distinta da resolução de DNS acima (dependeria do MESMO mecanismo não implementado) — não persegui separadamente.

---

## Recomendação

Não aprovar até:
1. Corrigir a normalização de `\`→`/` em `extractHost` (GRAVE, bypass confirmado fim-a-fim).
2. Cobrir a forma IPv4-compatible IPv6 (`::a.b.c.d` sem `ffff`) em `extractIPv4MappedOctets` (GRAVE pela política desta rodada, mesmo com o Windows atenuando o impacto local).
3. Opcionalmente, cortar zone ID (`%...`) antes de comparar em `isIPv6Loopback` (BAIXO, não bloqueante, mas barato de corrigir).

Depois da correção, reteste OBRIGATORIAMENTE com os dois casos GRAVE acima (script `\@`/backslash e `::a.b.c.d`), não só os 6 bypasses da primeira rodada — este padrão de "corrigir só a lista literal reportada e não a classe geral do bug" foi exatamente o que já causou a primeira reprovação.
