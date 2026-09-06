-- Fixture end-to-end (task-cli-035, fecha o achado de revisão de task-cli-032 -- ver
-- .claude/agents-memory/revisor-cli-task-cli-032-2026-09-06.md, "Verificação 5", cenário
-- reproduzido ao vivo pelo revisor): reproduz o cenário EXATO de sobreposição entre `--timeout` e
-- `BindToClose` que causava contagem dupla de erro -- um `BindToClose` que CEDE por mais tempo que
-- o timeout (abrindo uma janela longa) enquanto a thread do SCRIPT PRINCIPAL, ainda suspensa em
-- `task.wait` quando o timeout expira, é retomada pelo laço genérico interno de
-- `DataModel.RunBindToCloseCallbacks` (que drena TODAS as threads vivas do Scheduler, não só as de
-- BindToClose) e erra DENTRO dessa janela.
game:BindToClose(function()
	task.wait(0.5)
	print("bindtoclose-overlap: yielding callback finished")
end)

local n = 0
while true do
	n += 1
	task.wait(0.05)
	if n == 5 then
		error("leftover thread boom (double-count repro)")
	end
end
