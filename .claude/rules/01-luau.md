# Regra 01 — Luau estrito

Vale para todo `.luau` do projeto, em todos os territórios.

## Strict mode, sempre

- `--!strict` na primeira linha de todo módulo. Sem exceção, inclusive script de teste.
- **Sem `any`.** Tipo genuinamente desconhecido é `unknown`, estreitado antes de usar.
- Toda função exportada tem assinatura tipada — parâmetros e retorno explícitos, mesmo quando a inferência do Luau acertaria sozinha.
- Tipo exportado (`export type`) para toda estrutura de dado pública de um módulo — quem consome não deve depender de inferência estrutural.

## Módulos

- Um módulo, uma responsabilidade. `local module = {}` no topo, `return module` no fim — sem export solto no meio do arquivo.
- Dependência circular entre módulos é erro de design — se `runtime` e `services` parecem precisar um do outro, o contrato está mal desenhado; volte para o `arquiteto`.
- Nome de arquivo em `PascalCase` para módulo que exporta uma classe/serviço (`Instance.luau`, `Workspace.luau`), `camelCase` para utilitário (`deepCopy.luau`).

## Erros

- Nunca `pcall` silencioso que engole erro sem logar ou repassar. Se um erro de script do usuário é esperado (é o caso comum aqui), ele é capturado e reportado formatado — não descartado.
- Mensagem de erro inclui contexto suficiente para debugar sem re-rodar com print: qual Instance, qual propriedade, qual linha do script do usuário quando disponível.

## Testes

- Teste na mesma tarefa da lógica que cobre, não como tarefa separada no fim.
- Teste o que for prático sem precisar de um `.project.json` real: parsing, construção de Instance simulada, transição de estado do scheduler. Teste de integração (CLI rodando um projeto de exemplo) fica marcado como tal.

## Performance

- `services` gerado a partir do API Dump não deve carregar/parsear o dump inteiro (potencialmente megabytes) a cada `luaubench run` sem necessidade — cachear/pré-processar é preferível a reparsear toda vez. Se a task não resolve isso, diga no relatório em vez de deixar silencioso.
