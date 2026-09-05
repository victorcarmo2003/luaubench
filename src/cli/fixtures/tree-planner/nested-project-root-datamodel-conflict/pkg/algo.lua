-- fixture (task-cli-020, Decisao 16): raiz de um projeto ANINHADO com "$className": "DataModel"
-- explicito + "$path" que produz Source -- ao contrario da raiz do PLANO INTEIRO (fixture
-- "root-source-ignored"), aqui a excecao de "plan/root-source-ignored" NAO se aplica: um
-- DataModel so e uma classe legal na raiz do projeto MAIS EXTERNO. Deve continuar caindo em
-- "plan/class-name-conflict", como antes da task-cli-018 ter aberto a excecao larga demais.
return "should-never-be-loaded"
