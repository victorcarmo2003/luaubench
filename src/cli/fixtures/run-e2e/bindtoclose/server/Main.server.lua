-- Fixture end-to-end (task-cli-031): confirma que `game:BindToClose(fn)` de fato DISPARA e ESPERA
-- ao fim de `luaubench run` -- o gap que esta tarefa corrige (RunCommand nunca chamava
-- DataModel.RunBindToCloseCallbacks). Dois callbacks: um síncrono, outro que CEDE (task.wait) de
-- propósito -- o padrão real do ProfileStore aguardando jobs de save terminarem antes do processo
-- encerrar de verdade.
game:BindToClose(function()
	print("bindtoclose: simple callback ran")
end)

game:BindToClose(function()
	task.wait(0.05)
	print("bindtoclose: yielding callback finished")
end)

print("main script ran")
