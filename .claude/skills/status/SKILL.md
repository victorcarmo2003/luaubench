---
name: status
description: Panorama do LuauBench — board de tarefas, o que já está implementado em src/runtime/, src/services/, src/cli/, e o que falta configurar (versão do API Dump fixada, empacotamento Rokit). Use para saber onde o projeto está antes de decidir o próximo passo.
---

# /status

Panorama rápido. **Só leitura** — não muda nada.

## 1. Board

Leia `.claude/tasks.json`: quantas em `todo`, `in-progress`, `review`, `done`. Qual é a próxima leva e quantas tarefas tem.

Tarefa presa em `in-progress` sem agente rodando é sinal de sessão interrompida — sinalize.

## 2. O que existe no repositório

Verifique se `src/runtime/`, `src/services/` e `src/cli/` existem e o que contêm. Não assuma pelo board — confira o disco.

Se `src/services/` existir, liste quais classes de Service já têm módulo (nome do arquivo é o nome da classe) — isso é o indicador mais direto de cobertura do API Dump.

Se não existir nada ainda, diga isso em uma linha em vez de tentar preencher o resto — o projeto está em fase de fundação, é esperado.

## 3. Configuração externa

Isso não dá para checar só olhando código — confirme contra o disco/conversa:

- Versão do Roblox API Dump fixada e referenciada em algum lugar do repositório (`.claude/agents-memory/` ou arquivo de config)?
- `rokit.toml`/manifesto de distribuição presente e coerente com o último build?
- `lune.toml`/config de build presente?

## 4. Build

Se já houve build/empacotamento:

```bash
lune build
```

Reporta se o executável standalone é gerado sem erro, e se há release publicada no GitHub correspondente.

## Formato

```
## LuauBench — [data]

**Board:** N todo · M in-progress · K review · L done
Próxima leva: N (X tarefas)

**Repositório:** runtime [existe/não existe] · services [existe/não existe, N classes] · cli [existe/não existe]

**Configuração externa:** [o que está confirmado, o que falta — em uma linha cada]

**Build/Rokit:** [status do último build, ou "nunca buildado"]

**Atenção:** [só o que exige ação — senão omita a seção]
```

## Regras

- Só leitura. Não corrija nada, não crie tarefa, não dispare agente.
- Não invente número nem estado. Se não deu para confirmar, diga que não deu.
- Priorize o que exige ação: tarefa travada, versão do API Dump não fixada, manifesto Rokit desatualizado.
