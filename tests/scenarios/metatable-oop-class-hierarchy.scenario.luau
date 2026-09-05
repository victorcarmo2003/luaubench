--!strict

-- Cenário: sistema de classe via metatable com herança encadeada (Animal -> Dog), o idioma de
-- OOP manual mais comum no ecossistema Roblox (setmetatable + __index apontando pra classe
-- base, sem nenhuma lib de terceiros) -- e depois várias instâncias desse sistema rodando como
-- "scripts de IA" concorrentes sob o Scheduler, pra garantir que o runtime não embaralha
-- estado entre coroutines (bug clássico: closure capturando a variável errada de um loop).
-- Origem: sintético (o idioma em si -- ver padrão real equivalente, mais elaborado, em
-- D:\UserData\Documents\Roblox-Games\Towers\src\server\Components\Player\VitalComponent.luau,
-- que usa Health/TakeDamage/Heal sobre um "self" com metatable, ainda que via o framework
-- Modux -- aqui reduzido ao idioma puro, sem depender do Modux nem de nenhuma API do
-- LuauBench ainda não implementada).
-- Superfície exercitada: Scheduler.new/Spawn/Wait/StepOnce (só pra rodar os "scripts de IA"
-- concorrentemente -- o sistema de classe em si não usa nada do LuauBench, de propósito, pra
-- isolar se ALGO do runtime atrapalha um padrão de OOP comum).
-- Status: passa hoje.

local process = require("@lune/process")
local Scheduler = require("../../src/runtime/Scheduler")

local passedCount = 0
local totalCount = 0

local function test(name: string, run: () -> ())
	totalCount += 1
	run()
	passedCount += 1
	print(`[PASS] {name}`)
end

-- ── Classe base ────────────────────────────────────────────────────────────────────────
type Animal = {
	Name: string,
	Health: number,
	TakeDamage: (self: Animal, amount: number) -> (),
	IsAlive: (self: Animal) -> boolean,
}

local Animal = {}
Animal.__index = Animal

local function newAnimal(name: string): Animal
	local self = setmetatable({}, Animal) :: Animal
	self.Name = name
	self.Health = 100
	return self
end

function Animal.TakeDamage(self: Animal, amount: number): ()
	self.Health = math.max(0, self.Health - amount)
end

function Animal.IsAlive(self: Animal): boolean
	return self.Health > 0
end

-- ── Subclasse: Dog herda de Animal via __index encadeado (Dog -> Animal) ────────────────
type Dog = Animal & {
	Breed: string,
	Bark: (self: Dog) -> string,
}

local Dog = setmetatable({}, { __index = Animal })
Dog.__index = Dog

local function newDog(name: string, breed: string): Dog
	local base = newAnimal(name)
	local self = setmetatable(base, Dog) :: Dog
	self.Breed = breed
	return self
end

function Dog.Bark(self: Dog): string
	return `{self.Name} ({self.Breed}) diz Au!`
end

test("Dog herda TakeDamage/IsAlive de Animal e adiciona Bark próprio, sem vazar estado entre instâncias", function()
	local rex = newDog("Rex", "Vira-lata")
	local fido = newDog("Fido", "Poodle")

	assert(rex.Bark ~= nil and fido.Bark ~= nil, "ambas as instâncias deveriam ter o método Bark herdado da classe Dog")
	assert(rex:Bark() == "Rex (Vira-lata) diz Au!", "Bark deveria usar o Name/Breed da própria instância")
	assert(fido:Bark() == "Fido (Poodle) diz Au!", "Bark de fido não deveria usar dados de rex")

	rex:TakeDamage(30)
	assert(rex.Health == 70, "TakeDamage herdado de Animal deveria alterar só a Health de rex")
	assert(fido.Health == 100, "TakeDamage em rex não deveria afetar fido (sem compartilhar tabela)")
	assert(rex:IsAlive() and fido:IsAlive(), "ambos deveriam continuar vivos")

	fido:TakeDamage(100)
	assert(not fido:IsAlive(), "IsAlive deveria refletir Health <= 0 depois de dano fatal")
	assert(rex:IsAlive(), "dano fatal em fido não deveria afetar rex")
end)

test("getmetatable encadeia Dog -> Animal corretamente (herança real, não achatada)", function()
	local rex = newDog("Rex", "Vira-lata")
	assert(getmetatable(rex) == Dog, "a metatable direta de uma instância Dog deveria ser a própria tabela Dog")
	assert(getmetatable(Dog).__index == Animal, "a metatable de Dog deveria apontar __index para Animal (herança encadeada)")
end)

test("N instâncias de Dog rodando como 'scripts de IA' concorrentes sob Scheduler mantêm estado independente", function()
	local scheduler = Scheduler.new()

	local dogs: { Dog } = {}
	for i = 1, 5 do
		table.insert(dogs, newDog(`Dog{i}`, "Vira-lata"))
	end

	-- Cada Dog roda um "script de IA" próprio: recebe `amount = índice * 10` de dano por
	-- tique, 3 tiques, via task.wait real do Scheduler -- exatamente o formato de bug clássico
	-- (closure de loop capturando a variável errada) que este cenário quer descartar.
	for i, dog in dogs do
		local amount = i * 10
		scheduler:Spawn(function()
			for _ = 1, 3 do
				scheduler:Wait(0.05)
				dog:TakeDamage(amount)
			end
		end)
	end

	for _ = 1, 4 do
		scheduler:StepOnce(0.05)
	end

	for i, dog in dogs do
		local expectedDamage = (i * 10) * 3
		local expectedHealth = math.max(0, 100 - expectedDamage)
		assert(
			dog.Health == expectedHealth,
			`Dog{i} deveria ter Health {expectedHealth} (recebeu dano de {i * 10} x3), tem {dog.Health}`
		)
	end
	assert(not scheduler:IsAlive(), "todos os 'scripts de IA' deveriam ter terminado (3 tiques cada, sem loop infinito)")
end)

print(`\n{passedCount}/{totalCount} testes passaram`)
process.exit(0)
