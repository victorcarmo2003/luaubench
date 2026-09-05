# Regra 00 — Não-negociáveis do projeto

Valem para **todo agente**. Violação é motivo de rejeição em revisão.

## Fonte de verdade da simulação

A regra mais importante do projeto. O LuauBench só é útil se o comportamento simulado bater com o Roblox real — divergência não declarada é um bug silencioso que engana quem confia na ferramenta para debugar.

- Toda classe, propriedade, evento ou método de Instance simulado vem do Roblox API Dump oficial (`Full-API-Dump.json`, [MaximumADHD/Roblox-Client-Tracker](https://github.com/MaximumADHD/Roblox-Client-Tracker)). Nenhum agente inventa superfície de API que não esteja no dump.
- Extensão deliberada do LuauBench além do que o Roblox oferece (ex: helper de debug, comando exclusivo do CLI) é permitida, mas **nunca dentro do namespace simulado de uma classe real** — vive em módulo próprio do LuauBench, claramente distinto.
- Toda divergência de comportamento entre o LuauBench e o Roblox real (ex: sem replicação client/server, sem render 3D, timing de `RunService.Heartbeat` sem vsync real) é documentada explicitamente no código (`--` comentário) e no relatório do agente — nunca silenciosa.
- Dado dúvida sobre o comportamento real de uma classe/propriedade: **`pesquisador` confirma antes de implementar.** Não adivinhe.

## Execução de código arbitrário

Script do projeto do usuário é código arbitrário rodando dentro do processo do LuauBench.

- O runtime nunca concede acesso irrestrito a filesystem/rede/processo a um script simulado só porque o Lune permite tecnicamente — a superfície exposta ao script é a que o Roblox real exporia (não há `fs`/`net`/`process` cru dentro do sandbox do `game`), a menos que o próprio CLI do LuauBench precise disso para funcionar (fora do sandbox do script).
- Erro dentro de um script do usuário nunca derruba o processo do LuauBench inteiro sem uma mensagem estruturada — captura e reporta com stack trace e linha, do jeito mais parecido possível com o Output do Studio.

## Segurança operacional

- Nenhum dado do projeto do usuário (script, asset, path local) é enviado para serviço externo. O LuauBench é local-first.
- Token, chave de API ou credencial (ex: se o usuário integrar DataStore real, Open Cloud) nunca entra em código, log ou commit — vive em variável de ambiente, nunca hardcoded.

## Recursos

- Runtime é o Lune. Nenhuma dependência de binário externo além do que o Lune já provê entra sem essa decisão ser revisitada explicitamente com o usuário.
- Distribuição é via Rokit — executável standalone (`lune build`), publicado em GitHub Release. Nenhum outro canal sem decisão explícita.

## Idioma

- Resposta ao usuário: português (pt-BR).
- Código, identificadores, arquivos, commits: inglês.
- Comentários de código: português.
- Commits em Conventional Commits: `feat(services): add DataStoreService simulation`.
