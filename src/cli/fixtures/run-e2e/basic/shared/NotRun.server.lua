-- Fixture end-to-end (task-cli-006): Script fora de todo ServerScriptContainers (materializado
-- sob ReplicatedStorage) -- carregado mas nunca executado. Se esta linha aparecer no stdout de um
-- teste, o acceptance de "Script em ReplicatedStorage não executa" falhou.
print("THIS SHOULD NEVER RUN: Script outside ServerScriptContainers executed")
