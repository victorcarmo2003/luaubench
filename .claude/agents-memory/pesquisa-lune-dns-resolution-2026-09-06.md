# Pesquisa — resolução de DNS em `@lune/net` para endurecimento anti-SSRF (2026-09-06)

## Versão pinada (confirmado lendo o arquivo do projeto)

`D:\UserData\Documents\GitHub\luaubench\rokit.toml`:
```
[tools]
lune = "lune-org/lune@0.10.5"
```
**Lune 0.10.5, confirmado** — bate com o que já era usado em `pesquisa-http-messaging-2026-09-05.md` e no cabeçalho de `HttpService.luau`. Sem `.tool-versions`/`aftman.toml` no projeto — `rokit.toml` é a única fonte de pin.

## Fonte primária consultada

Repositório oficial `lune-org/lune`, tag `v0.10.5` (resolvida via `gh api repos/lune-org/lune/git/refs/tags/v0.10.5` → commit `e173211a3b529eb53624137931fc11f0a02ff867`). Arquivos lidos por inteiro nesse commit exato (não a doc "latest", não resumo de terceiros):

- `crates/lune-std-net/types.d.luau` (definição completa da API pública de `@lune/net`, 425 linhas — lida por inteiro)
- `crates/lune-std-net/src/client/fetch.rs`, `.../client/send.rs`, `.../client/mod.rs`, `.../client/rustls.rs`, `.../client/stream.rs`, `.../client/tcp.rs`, `.../shared/request.rs`, `.../shared/tcp.rs` — implementação Rust real por trás de `net.request`/`net.tcp.connect`
- `tests/net/tcp/info.luau` — teste oficial que exercita `net.tcp.connect` e confirma o formato de `remoteIp`
- `crates/lune-std-process/types.d.luau` — para a pergunta 3 (fallback via `process.exec`)

---

## 1) Existe função de resolução de DNS separada (`net.resolveHost`/`net.lookup`/etc.)?

**NÃO CONFIRMADO → na verdade, CONFIRMADA A AUSÊNCIA.** Não é omissão de busca: `types.d.luau` é a definição completa e exaustiva da API pública de `@lune/net` nesta versão (é o arquivo que o próprio Lune usa para gerar os typedefs do LSP/documentação) — API **completa** listada abaixo, não há nenhuma função de resolução de DNS pura:

```
net.request(config: string | FetchParams): FetchResponse
net.socket(url: string): WebSocket
net.serve(port: number, handlerOrConfig: ServeHttpHandler | ServeConfig): ServeHandle
net.urlEncode(s: string, binary: boolean?): string
net.urlDecode(s: string, binary: boolean?): string
net.tcp.connect(host: string, port: number, config: (true | TcpConfig)?): TcpStream
```

Nenhuma função `resolve`/`lookup`/`dns`/`getaddrinfo` existe em nenhum namespace de `@lune/net` na v0.10.5.

## 2) `net.request` aceita IP literal preservando o `Host` original?

**NÃO — confirmado lendo o código-fonte Rust (não inferência).** Em `crates/lune-std-net/src/client/send.rs` (o caminho real por trás do `net.request` exposto a Lua) e também em `client/fetch.rs`:

```rust
let (mut parts, body) = request.clone_inner().into_parts();
if let Some(host) = parts.uri.host() {
    let host = HeaderValue::from_str(host).unwrap();
    parts.headers.insert(HOST, host);   // <- HeaderMap::insert SUBSTITUI qualquer Host já presente
}
```

`HeaderMap::insert` (Hyper) **substitui** qualquer header `Host` que o script já tenha passado em `FetchParams.headers` — o valor enviado na conexão real é **sempre** derivado de `parts.uri.host()` (o host da própria URL usada para conectar), nunca de um header customizado. Ou seja: passar `url = "http://93.184.216.34/"` com `headers = {Host = "example.com"}` conecta no IP literal, mas o `Host` enviado no wire será `"93.184.216.34"`, não `"example.com"` — a técnica "resolver, validar o IP, montar a URL com o IP e preservar o Host original via header" **não funciona** em `net.request` nesta versão; o servidor de destino veria o Host errado (quebra qualquer vhost/roteamento por nome, e para HTTPS também quebra: `HttpStream::connect_url` usa `url.host()` — o mesmo host da URL — como SNI/`ServerName` da conexão TLS, então conectar por IP também tende a falhar a validação de certificado de qualquer domínio comum).

Conclusão: a estratégia "resolve → valida IP → conecta no IP validado preservando Host" **não é viável via `net.request`** nesta API — a biblioteca não dá esse grau de controle (não existe um "Agent"/hook de conexão customizável como em `http.Agent` do Node, nem parâmetro de `resolvedIp`/`servername` separado).

## 3) Outro módulo do Lune expõe DNS puro (getaddrinfo-like)? `process` como fallback via `nslookup`?

- **Nenhum outro módulo padrão do Lune 0.10.5 expõe resolução de DNS pura.** Só verificado diretamente `@lune/net` (não há) — não há indício de tal API em `@lune/process`/`@lune/fs`/`@lune/task`/`@lune/serde` pelos nomes de função em nenhuma pesquisa anterior do projeto nem nesta.
- `@lune/process` **tem** `process.exec(program: string, params: {string}?, options: ExecOptions?): ExecResult` (confirmado lendo `crates/lune-std-process/types.d.luau`, tag v0.10.5 — assinatura exata acima, `ExecResult = {ok, code, stdout, stderr}`). Tecnicamente **daria** para rodar `nslookup <host>` (Windows) / `getent hosts <host>` ou `dig +short <host>` (Linux) / `dscacheutil -q host -a name <host>` (macOS) e fazer parsing manual do `stdout`.
  **Documentado, não recomendado** (conforme pedido): isso (a) degrada portabilidade real — 3 comandos diferentes por SO, formatos de saída distintos e frágeis de parsear; (b) introduz dependência de um **binário externo ao Lune**, o que fere diretamente a Invariante 3 do projeto ("Nenhuma dependência de binário externo além do que o Lune já provê... entra sem essa decisão ser revisitada explicitamente com o usuário") — precisaria de aprovação explícita do usuário, não é uma decisão que `coder-services`/`arquiteto` podem tomar sozinhos.

## 4) Ausência confirmada — constatação central

**Confirmado, não é lacuna de busca:** Lune 0.10.5 não expõe nenhuma API de resolução de DNS isolada (`resolve`/`lookup`/`getaddrinfo`) em `@lune/net` nem em nenhum outro módulo padrão pesquisado. A única forma de obter um IP resolvido é como **efeito colateral de uma conexão TCP já estabelecida**, via `net.tcp.connect`.

### Achado que muda o quadro: `net.tcp.connect` faz resolução + conexão como UMA operação atômica, e expõe o IP resolvido

`crates/lune-std-net/types.d.luau` (v0.10.5) documenta uma API que a pesquisa anterior do projeto (`pesquisa-http-messaging-2026-09-05.md`) não cobriu — `net.tcp`, primitivas TCP de baixo nível:

```luau
export type TcpConfig = { tls: boolean?, ttl: number? }
export type TcpStream = {
    localIp: string?, localPort: number?,
    remoteIp: string?, remotePort: number?,
    close: (self: TcpStream) -> (),
    write: (self: TcpStream, data: string | buffer) -> (),
    read: (self: TcpStream, size: number?) -> string?,
}
function net.tcp.connect(host: string, port: number, config: (true | TcpConfig)?): TcpStream
```

Confirmado pelo teste oficial `tests/net/tcp/info.luau` (v0.10.5, roda de verdade contra `httpbingo.org:80`):
```luau
local stream = net.tcp.connect("httpbingo.org", 80)
assert(string.match(stream.remoteIp, "^%d+%.%d+%.%d+%.%d+$"), "remoteIp should be a valid IP address")
```

E confirmado lendo a implementação Rust (`client/mod.rs::connect_tcp` → `client/stream.rs::MaybeTlsStream::connect` → `async_net::TcpStream::connect((host, port))`, com TLS opcional via `ServerName::try_from(host)` quando `config.tls == true`): a resolução do hostname e a conexão TCP acontecem dentro de **uma única chamada Rust assíncrona**, sem nenhum ponto de retomada exposto a Lua entre "resolveu" e "conectou" — o script Luau só recebe o resultado depois que a conexão real já está estabelecida no endereço resolvido, e `remoteIp`/`remotePort` (`shared/tcp.rs`, via `stream.peer_addr()`) refletem o endereço **da conexão que já existe**, não uma resolução separada e potencialmente estale.

**Limitação importante, declarada:** `net.tcp` é explicitamente descrito no próprio `types.d.luau` como API de baixo nível ("*for all HTTP usage, please use the `request` and `serve` HTTP functions instead*"). Não faz parsing de HTTP/1.1 (status line, headers, chunked transfer-encoding), não decodifica corpo comprimido, não segue redirecionamento — tudo isso hoje é responsabilidade do Hyper por trás de `net.request`. Usar `net.tcp.connect` para SSRF-hardening implicaria **reimplementar manualmente** a camada HTTP que `RequestAsync`/`GetAsync`/`PostAsync` hoje delegam inteiramente a `net.request` (o próprio exemplo do `types.d.luau` mostra o desenvolvedor escrevendo a request line/Host header à mão: `conn:write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")`).

---

## Pergunta secundária — DNS rebinding: é possível garantir resolução+conexão atômicas?

**SIM, via `net.tcp.connect` — CONFIRMADO pela leitura do código-fonte, não é só design teórico.**

O padrão ficaria:
1. Chamar `net.tcp.connect(originalHostname, port, {tls = (scheme == "https")})` passando o **hostname original** (nunca um IP pré-resolvido à parte) — a resolução e a conexão são a MESMA chamada, então não existe uma segunda janela de resolução para um DNS malicioso explorar.
2. Inspecionar `stream.remoteIp` (o IP da conexão **já estabelecida**, vindo de `peer_addr()` do socket real, não de uma consulta DNS textual separada).
3. Se privado/loopback/bloqueado sem `AllowHttpLocal`: `stream:close()` **sem nunca ter escrito um byte** — nenhum dado sai, nenhuma requisição HTTP chega ao destino; o TCP handshake sozinho não vaza nada sensível (SSRF clássico exige que o destino receba dado controlado pelo atacante ou devolva algo explorável — nenhum dos dois acontece antes do `write`).
4. Se permitido: escrever a requisição HTTP manualmente (`write`) e fazer parsing manual da resposta (`read`).

Isso elimina estruturalmente a classe de DNS rebinding (validar contra uma resolução A, conectar de fato via uma resolução B feita depois) porque não há duas resoluções — há uma só, e ela É a conexão.

**O que isso NÃO resolve de graça:** o preço é abrir mão de toda a camada HTTP que `net.request` dá de graça (redirecionamento, `Content-Encoding`, `Transfer-Encoding: chunked`, timeouts, etc. — mesmas lacunas já documentadas no cabeçalho de `HttpService.luau` para `net.request` puro, mas agora TODAS caindo sobre este módulo para implementar à mão em vez de delegar ao Hyper). Não confirmei se o parser HTTP/1.1 que teria que ser escrito à mão é trivial o bastante para não introduzir sua própria classe de bugs — **não tentei implementar/testar isso nesta pesquisa**, é constatação de viabilidade de API, não uma prova de que a reimplementação sai correta de primeira.

---

## Recomendação direta para o arquiteto

A estratégia original pedida ("resolver DNS e checar o IP real via uma função de resolução separada, depois conectar via `net.request` no IP validado preservando o Host") **é inviável como formulada** — não existe função de resolução separada em `@lune/net` 0.10.5, e mesmo que houvesse, `net.request` **sempre sobrescreve o header `Host` com o host da própria URL de conexão** (confirmado no código-fonte), então não dá para "conectar no IP, mas falar o hostname original" por essa via.

Duas alternativas reais, nenhuma sem custo:

1. **Manter a validação textual atual (`extractHost` + normalização RFC 3986 + notações de IP), aceitando o risco residual de DNS rebinding documentado no cabeçalho de `HttpService.luau`** — é a opção de menor esforço, já implementada e testada em 4 rodadas de revisão; a lacuna (hostname que resolve para IP privado só no momento da conexão) fica como divergência declarada (regra 00), não escondida. Como o LuauBench nunca reintroduziu risco pior que o Roblox real de forma silenciosa até agora, isto é uma opção defensável a curto prazo.
2. **Reescrever a MÁSCARA de rede de `HttpService` sobre `net.tcp.connect`** (resolver+conectar+validar `remoteIp` antes de qualquer `write`, depois falar HTTP/1.1 manualmente) — fecha a classe de rebinding de verdade, mas é uma tarefa de escopo grande: perde toda a camada HTTP que hoje vem de graça de `net.request` (redirects, decompressão, parsing de resposta) e precisa ser reimplementada e testada com o mesmo rigor de segurança que `extractHost` já passou (4 rodadas). Isto é uma decisão de arquitetura — não algo para `coder-services` decidir sozinho numa tarefa isolada; envolve reabrir o desenho de `HttpService` (`arquiteto-services-2026-09-05.md`, seção L2.2) e provavelmente uma tarefa dedicada de porte considerável, com sua própria bateria de revisão de segurança.

Não há meio-termo limpo dentro de `net.request` — a única API do Lune que combina "resolver e conectar como uma coisa só" com "eu vejo o IP resolvido" é `net.tcp`, e ela não fala HTTP sozinha.
