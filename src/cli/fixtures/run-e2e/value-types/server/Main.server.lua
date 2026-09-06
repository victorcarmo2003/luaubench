-- Fixture end-to-end (task-cli-025): prova que RunCommand liga Runtime.TypeNameResolver ao
-- território valuetypes de ponta a ponta -- typeof() de um value type real precisa devolver o
-- nome Roblox real ("Vector3"), nunca o "userdata" cru do Luau (Decisao 4 do desenho de
-- valuetypes; RunCommand.luau, item e).
local position = Vector3.new(1, 2, 3)
assert(typeof(position) == "Vector3", "typeof(Vector3.new(...)) deveria ser 'Vector3', recebeu " .. typeof(position))
assert(tostring(position) == "1, 2, 3", "tostring(Vector3.new(1, 2, 3)) deveria ser '1, 2, 3', recebeu " .. tostring(position))

print("value types ok: " .. tostring(position))
