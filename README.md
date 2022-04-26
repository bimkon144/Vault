# Vault

* запуск локальной сетки ```npx hardhat node ```
* Запуск тестов  - ```npx hardhat test```
* запуск скрипта деплоя и методов ```npx hardhat run scripts/deployVault.js --network localhost```
* деплой на ринкибай npx hardhat run scripts/deployToTest.js --network rinkeby
* npx hardhat verify --contract "contracts/**.sol:**" --network rinkeby 0xc7d01C0EA02cc0276f80bE1d1BFed6696467E072 "100500"
* npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/qGjxzsFlzCxPTmcDhuHmqy24SI7yGcsu
* запуск форкнутой мейннет npx hardhat node --network hardhat
* запуск скрипта на форкнутой ноде npx hardhat run scripts/task.js --network localhost
* запуск ремикса онлайн cd .. => remixd -s Vault/