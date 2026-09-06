-- Fixture end-to-end (task-cli-031): erro dentro de UM callback de `BindToClose` nunca derruba o
-- processo nem impede os DEMAIS callbacks de rodar -- semântica que `DataModel.
-- RunBindToCloseCallbacks` já garante (task-runtime-033, via `ThreadError` do Scheduler); este
-- fixture confirma a integração de ponta a ponta pelo `RunCommand`.
game:BindToClose(function()
	error("bindtoclose boom (proposital, teste task-cli-031)")
end)

game:BindToClose(function()
	print("bindtoclose: second callback still ran despite the first one erroring")
end)

print("main script ran")
