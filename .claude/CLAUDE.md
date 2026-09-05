# LuauBench

Ambiente de desenvolvimento para Roblox que roda **por fora do Roblox Studio**. Pega um projeto Roblox (estrutura Rojo) e executa direto pelo terminal — `luaubench run` — sem precisar dar play/F5/F8 no Studio. Provê os Services do Roblox, o `game`/`workspace` e o resto da API global **simulados em formato de dados**, com tipagem Luau estrita, permitindo escrever e testar código (ProfileStore, data managers, state managers etc.) fora do editor.

Publicado no [Rokit](https://github.com/rojo-rbx/rokit): `rokit add victorcarmo2003/luaubench` → `rokit install` → `luaubench run`.

## Idioma

Responda sempre em **português (pt-BR)**. Código, identificadores, nomes de arquivo e commits em **inglês**. Comentários de código em português.

## Stack

| Camada | Tecnologia |
|---|---|
| Runtime | [Lune](https://github.com/lune-org/lune) — runtime Luau standalone (fs, net, process, task, serde), compila para executável standalone |
| Linguagem | Luau 100%, `--!strict` em todo módulo |
| Distribuição | [Rokit](https://github.com/rojo-rbx/rokit) — binário standalone (`lune build`) publicado em GitHub Releases |
| Integração de projeto | Formato de projeto [Rojo](https://rojo.space) (`.project.json` + sourcemap) — é como o LuauBench descobre a árvore de instâncias do projeto do usuário |
| Fonte de tipos/API | [Roblox API Dump](https://github.com/MaximumADHD/Roblox-Client-Tracker) oficial (`Full-API-Dump.json`) — classes, propriedades, eventos, herança |

## Por que essa arquitetura

- Lune já resolve fs/net/process/task/serde e compila executável standalone — não faz sentido reescrever um runtime Luau do zero só para ganhar isso.
- Rojo já é o formato de projeto padrão do ecossistema Roblox open-source — reaproveitar o `.project.json`/sourcemap evita inventar um formato novo que o usuário teria que aprender.
- Simular a partir do API Dump oficial (em vez de mapear serviço a serviço na mão) dá cobertura completa e atualizável por script — a superfície do Roblox é grande demais para mapear manualmente sem divergir da realidade.
- `game`/`workspace`/Services existem como **dados simulados em memória**, não como binding real ao Roblox — o objetivo é rodar lógica pura (data managers, state machines, ProfileStore) rápido, não renderizar nem substituir o Studio para tudo.

## Invariantes do projeto

Regras que nenhum agente pode violar sem autorização explícita do usuário:

1. **Toda classe/propriedade/evento simulado vem do Roblox API Dump oficial.** Nenhum agente inventa propriedade, evento ou comportamento de Instance que não esteja no dump ou explicitamente aprovado pelo usuário como extensão do LuauBench.
2. **Fidelidade de comportamento com o Roblox real é o objetivo — divergência é sempre declarada.** Se o LuauBench precisa se comportar diferente do Studio (ex: sem replicação client/server real, sem render), isso é documentado no código e no relatório do agente, nunca silencioso.
3. **Runtime é o Lune.** Nenhuma dependência de binário externo além do que o Lune já provê (fs, net, process, task, serde) entra sem essa decisão ser revisitada explicitamente com o usuário.
4. **Distribuição é via Rokit.** O build final é um executável standalone (`lune build`) publicado em GitHub Release, com `rokit.toml`/manifesto compatível com `rokit add victorcarmo2003/luaubench`. Nenhum outro canal de instalação sem decisão explícita.
5. **`--!strict` em todo módulo `.luau`, sem exceção.** Sem `any` — tipo genuinamente desconhecido usa `unknown` e é estreitado antes de usar.
6. **Local-first: nada do projeto do usuário sai da máquina dele.** O LuauBench não envia script, asset nem dado do projeto do usuário para nenhum serviço externo.
7. **Script do projeto do usuário é código arbitrário.** O runtime que o executa nunca assume que o script é confiável — acesso a filesystem/rede fora do que o Roblox real permitiria é limitado e explícito, nunca irrestrito por padrão.

Detalhamento em [.claude/rules/](rules/).

## Protocolo de orquestração

**O chat principal permanece livre.** Você (thread principal) é o orquestrador — não implementa, delega. Seu trabalho é: entender o pedido, escolher os agentes, disparar em paralelo, consolidar os relatórios e reportar ao usuário.

### Regras de delegação

- **Delegue sempre que houver mais de um arquivo ou mais de um domínio envolvido.** Só execute inline mudança trivial de uma linha.
- **Dispare em paralelo por padrão** — múltiplas chamadas de Agent na mesma mensagem. `coder-runtime`, `coder-services`, `coder-cli` e `coder-valuetypes` não compartilham arquivo e nunca conflitam entre si.
- **Rode em background** (`run_in_background: true`) salvo quando o próximo passo depende literalmente do resultado e nada mais pode avançar enquanto isso.
- **Todos reportam para você**, nunca direto ao usuário. Você consolida e entrega uma resposta única.
- **Nunca invente resultado de agente pendente.** Se o usuário perguntar antes da notificação chegar, diga que ainda está rodando.

### Fronteiras de paralelismo

| Agente | Território (não se sobrepõem) |
|---|---|
| `coder-runtime` | `src/runtime/` — DataModel, base de Instance, scheduler (task/coroutine), tipagem core |
| `coder-services` | `src/services/` — simulação dos Services do Roblox gerada a partir do API Dump |
| `coder-cli` | `src/cli/` — comando `luaubench run`, parsing de projeto Rojo, watch mode, empacotamento Rokit |
| `coder-valuetypes` | `src/valuetypes/` (+ `tools/generate-enums.luau`) — Value Types simulados (Vector3/CFrame/Color3/Enum/etc), ver `.claude/rules/06-valuetypes.md` |
| `testador` | `tests/scenarios/` — cenários práticos de uso, read-only em `src/**` e em `C:\Users\hakor\Documents\Roblox-Games` |

Revisores (`revisor-runtime`, `revisor-services`, `revisor-cli`, `revisor-valuetypes`) e o `testador` são todos read-only fora do próprio território — dispare quantos quiser em paralelo, sempre.

### Fluxo padrão

```
pedido do usuário
   │
   ├─ escopo claro e pequeno ──▶ coder(s) em paralelo ──▶ revisor(es) em paralelo ──▶ consolidar
   │
   └─ escopo grande ou novo ───▶ arquiteto ──▶ planejador (escreve tasks.json)
                                                    │
                                          coders em paralelo por território
                                                    │
                                          revisores em paralelo
                                                    │
                                                consolidar
```

`pesquisador` roda em paralelo com qualquer coisa sempre que houver formato externo desconhecido (Lune API, Rokit manifest, Roblox API Dump, formato de projeto/sourcemap do Rojo).

## Quadro de tarefas

`.claude/tasks.json` é a fonte da verdade. Cada tarefa tem um campo `agent` — é isso que permite despachar várias em paralelo sem colisão. Schema e regras em [.claude/skills/planejar/SKILL.md](skills/planejar/SKILL.md).

## Memória dos agentes

Relatórios longos vão para `.claude/agents-memory/{agente}-{assunto}-{data}.md`. O agente devolve para você um resumo curto e o caminho do arquivo — assim o contexto do chat principal não estoura.

## Skills

| Skill | Para quê |
|---|---|
| `/planejar` | Arquitetura + quebra em tarefas (arquiteto → planejador) |
| `/implementar` | Despacha tarefas do board em paralelo por território |
| `/revisar` | Revisão paralela dos territórios tocados |
| `/status` | Panorama: board de tarefas, o que já existe no repositório, estado do build/Rokit |

## Estado atual do projeto

Fase inicial — só a estrutura `.claude/` e as decisões de arquitetura de alto nível foram definidas nesta conversa: Lune como runtime, 3 territórios (`runtime`/`services`/`cli`), Roblox API Dump oficial como fonte de dados dos Services simulados. **Ainda não existe**: nenhum código-fonte, `rokit.toml`, `lune.toml`/config de build, repositório git inicializado.

Ordem de construção sugerida: `arquiteto` desenha o contrato entre `runtime`/`services`/`cli` (formato de Instance simulada, como o scheduler expõe `task.spawn`/`RunService`, como o dump do Roblox vira dado de service) → esqueleto do `runtime` (DataModel + Instance base) → gerador de `services` a partir do API Dump (começando pelos mais usados: `Workspace`, `Players`, `ReplicatedStorage`, `DataStoreService`, `RunService`, `TweenService`) → `cli` lendo `.project.json`/sourcemap do Rojo e populando a árvore simulada → `luaubench run` executando o script de entrada → watch mode → empacotamento para Rokit.
