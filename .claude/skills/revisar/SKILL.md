---
name: revisar
description: Revisão paralela do LuauBench — dispara os revisores relevantes de uma vez sobre o que mudou. Use antes de commitar, ao fechar uma feature, ou quando o usuário pedir revisão.
argument-hint: "[caminho, feature, ou vazio para revisar o que mudou]"
---

# /revisar

Dispara os revisores relevantes **todos em paralelo**. São read-only — nunca conflitam entre si.

## 1. Determinar o escopo

- `$ARGUMENTS` vazio → o que mudou (`git status` / `git diff --name-only`; se não for repositório git, os arquivos tocados nesta sessão).
- `$ARGUMENTS` é caminho → aquele caminho.
- `$ARGUMENTS` é nome de feature → arquivos das tarefas dessa feature no board.

Se nada mudou e nada foi passado, pergunte o que revisar em vez de revisar o repositório inteiro.

## 2. Mapear arquivos para revisores

| Caminho tocado | Revisor |
|---|---|
| `src/runtime/` | `revisor-runtime` |
| `src/services/` | `revisor-services` |
| `src/cli/` | `revisor-cli` |

Se a mudança tocar mais de um território (ex: `runtime` mudou API pública consumida por `services`), dispare os dois revisores correspondentes — em paralelo, cada um no seu escopo.

## 3. Disparar tudo de uma vez

Todas as chamadas de Agent na **mesma mensagem**, `run_in_background: true`.

Cada prompt carrega:
- Lista exata de arquivos a revisar.
- O que a mudança pretendia fazer (para julgar se cumpre).
- Contexto relevante: tarefa do board, decisão do arquiteto, versão do API Dump em uso se aplicável.

## 4. Consolidar

Junte os achados de todos os revisores em **uma lista única**, ordenada por gravidade — não uma seção por revisor.

```
## Revisão: [escopo]

### GRAVE
- arquivo:linha — problema. → correção. [revisor]

### ALTO
- ...

### MÉDIO / BAIXO
- ... (agrupado, uma linha cada)

**Vereditos:** runtime APROVADO · services RESSALVAS · cli APROVADO
**Verificado sem achado:** [o que foi olhado e estava limpo]

Próximo passo: corrigir os GRAVE/ALTO? (despacha para os coders em paralelo)
```

Achado duplicado entre revisores aparece **uma vez**, com os dois créditos.

## 5. Corrigir, se o usuário quiser

Despache os coders dos territórios afetados **na mesma mensagem**, cada um com os achados do seu território. Depois rode `/revisar` de novo só nos arquivos alterados.

## Regras

- Não filtre achado GRAVE por achar exagero. Reporte e deixe o usuário decidir.
- Não repasse relatório bruto de revisor — consolide.
- Se um revisor não achou nada, diga o que ele verificou. Silêncio não é aprovação.
- Se dois revisores discordam, mostre os dois lados em vez de escolher em silêncio.
- Não corrija nada por conta própria dentro desta skill. Ela revisa; a correção é passo separado, com o usuário sabendo.
