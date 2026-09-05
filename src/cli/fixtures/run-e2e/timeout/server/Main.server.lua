-- Fixture end-to-end (task-cli-006): script que CEDE indefinidamente -- usado para testar
-- --timeout como rede de segurança (nunca um watchdog: só funciona porque este script CEDE via
-- task.wait, permitindo que o Scheduler consulte shouldContinue entre tiques).
while true do
	task.wait()
end
